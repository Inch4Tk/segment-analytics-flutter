import 'dart:io';
import 'dart:async';
import 'dart:convert' show utf8, base64, json, Encoding;
import 'package:connectivity/connectivity.dart';
import 'package:http/http.dart';
import 'package:device_info/device_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class Analytics {
  static bool enabled = true;
  static Analytics _singleton;
  static String endpoint = "https://api.segment.io/v1";
  static String writeKey;
  static AnalyticsClient client = AnalyticsClient(Client());

  static String _anonId;
  static String _userId;
  static Future<void> _loadingUser;

  // Screen tracking specials
  static bool _amplitudeScreenTracking;

  // Sessions
  static DateTime _lastAction;
  static List<String> _enableSessionsFor;
  static Duration sessionTimeout;
  static String sessionId;

  // Context infos
  static String osName;
  static String osVersion;
  static String deviceId;
  static String deviceManufacturer;
  static String deviceModel;
  static String deviceType;

  static String appName;
  static String appVersion;
  static String appBuild;
  static String screenWidth;
  static String screenHeight;
  static String locale;

  static Future<void> _loading;

  factory Analytics.load(
      {String apiKey,
      String appName,
      String appVersion,
      String appBuild,
      String screenWidth,
      String screenHeight,
      String locale,
      List<String> enableSessionsFor = const ["Amplitude"],
      Duration sessionTimeout = const Duration(minutes: 30),
      bool amplitudeScreenTracking = false}) {
    Analytics.appName = appName;
    Analytics.appVersion = appVersion;
    Analytics.appBuild = appBuild;
    Analytics.screenWidth = screenWidth;
    Analytics.screenHeight = screenHeight;
    Analytics.locale = locale;
    Analytics.sessionTimeout = sessionTimeout;
    Analytics._enableSessionsFor = enableSessionsFor;
    Analytics._amplitudeScreenTracking = amplitudeScreenTracking;
    _singleton = Analytics._internal(apiKey);
    return _singleton;
  }

  factory Analytics() {
    if (_singleton == null) {
      if (enabled) {
        print("Warning: Called Analytics without loading the library.");
      }
      _singleton = Analytics._internalNoWriteKey();
      return _singleton;
    } else {
      return _singleton;
    }
  }

  Analytics._internal(String segmentApiKey) {
    writeKey = "Basic ${base64.encode(utf8.encode(segmentApiKey)).toString()}";
    Analytics._loading = _loadDeviceInfos();
    Analytics._loadingUser = _loadUserId();
  }

  Analytics._internalNoWriteKey();

  Future<void> _loadDeviceInfos() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      osName = "Android";
      osVersion =
          "${androidInfo.version.release} (sdk: ${androidInfo.version.sdkInt})";
      deviceId = androidInfo.androidId;
      deviceManufacturer = androidInfo.manufacturer;
      deviceModel = androidInfo.model;
      deviceType = "Android";
    } else {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      osName = "iOS";
      osVersion = iosInfo.systemVersion;
      deviceId = iosInfo.identifierForVendor;
      deviceManufacturer = "Apple";
      deviceModel = iosInfo.model;
      deviceType = "iOS";
    }
  }

  Future<void> _loadUserId() async {
    final sharedPrefs = await SharedPreferences.getInstance();
    Analytics._userId = sharedPrefs.getString("SegmentAnalyticsUserId");
    Analytics._anonId = sharedPrefs.getString("SegmentAnalyticsAnonId");
    if (Analytics._anonId == null) {
      await _regenerateAnonId(sharedPrefs);
    }
  }

  Future<void> _regenerateAnonId(SharedPreferences sharedPrefs) async {
    if (sharedPrefs == null) {
      sharedPrefs = await SharedPreferences.getInstance();
    }
    final uuid = Uuid();
    Analytics._anonId = uuid.v4();
    sharedPrefs.setString("SegmentAnalyticsAnonId", Analytics._anonId);
  }

  Future<void> _storeUserId(String userId) async {
    Analytics._userId = userId;
    final sharedPrefs = await SharedPreferences.getInstance();
    sharedPrefs.setString("SegmentAnalyticsUserId", userId);
  }

  Future<void> reset() async {
    Analytics._userId = null;
    final sharedPrefs = await SharedPreferences.getInstance();
    sharedPrefs.remove("SegmentAnalyticsUserId");
    await _regenerateAnonId(sharedPrefs);
  }

  Future<void> identify(String userId, {Map traits}) async {
    if (!enabled) {
      return;
    }
    // Make sure everything is fully loaded;
    await Analytics._loading;
    await Analytics._loadingUser;

    if (traits == null) {
      traits = Map();
    }

    await _storeUserId(userId);

    Map payload = {
      "traits": traits,
      "userId": userId,
      "anonymousId": _anonId,
      "context": await defaultContext()
    };
    client.postSilentMicrotask("$endpoint/identify",
        body: json.encode(payload));
  }

  Future<void> group(String userId, String groupId, {Map traits}) async {
    if (!enabled) {
      return;
    }
    // Make sure everything is fully loaded;
    await Analytics._loading;
    await Analytics._loadingUser;

    if (traits == null) {
      traits = Map();
    }

    Map payload = {
      "traits": traits,
      "userId": userId,
      "groupId": groupId,
      "anonymousId": _anonId,
      "context": await defaultContext()
    };
    client.postSilentMicrotask("$endpoint/group", body: json.encode(payload));
  }

  Future<void> screen(String name,
      {Map properties, Map context, Map integrations}) async {
    if (!enabled) {
      return;
    }
    // Make sure everything is fully loaded;
    await Analytics._loading;
    await Analytics._loadingUser;

    if (properties == null) {
      properties = Map();
    }

    Map sendContext = await defaultContext();
    if (context != null) {
      sendContext.addAll(context);
    }

    Map sendIntegrations = defaultIntegrations();
    if (integrations != null) {
      sendIntegrations.addAll(integrations);
    }

    Map payload = {
      "userId": _userId,
      "anonymousId": _anonId,
      "context": Map.from(sendContext),
      "name": name,
      "properties": Map.from(properties),
      "integrations": sendIntegrations
    };
    payload.addAll(defaultIntegrations());
    client.postSilentMicrotask("$endpoint/screen", body: json.encode(payload));

    if (_amplitudeScreenTracking) {
      final stIntegrations = defaultIntegrations();
      // Currently when enabling this below, we don't send anything
      // and there doesnt seem to be a way to keep amplitude
      // enabled if we also want to send a sessionId
      // stIntegrations["All"] = false;
      if (!stIntegrations.containsKey("Amplitude")) {
        stIntegrations["Amplitude"] = true;
      }
      await track("Loaded Screen",
          properties: {"name": name}, integrations: stIntegrations);
    }
  }

  Future<void> track(String event,
      {Map properties, Map context, Map integrations}) async {
    if (!enabled) {
      return;
    }
    // Make sure everything is fully loaded;
    await Analytics._loading;
    await Analytics._loadingUser;

    if (properties == null) {
      properties = Map();
    }

    Map sendContext = await defaultContext();
    if (context != null) {
      sendContext.addAll(context);
    }

    Map sendIntegrations = defaultIntegrations();
    if (integrations != null) {
      sendIntegrations.addAll(integrations);
    }

    Map payload = {
      "userId": _userId,
      "anonymousId": _anonId,
      "context": Map.from(sendContext),
      "event": event,
      "properties": Map.from(properties),
      "integrations": sendIntegrations
    };
    client.postSilentMicrotask("$endpoint/track", body: json.encode(payload));
  }

  Future<Map> defaultContext() async {
    // Check connectivity
    final connectivity = await (Connectivity().checkConnectivity());
    bool mobile = false;
    bool wifi = false;
    if (connectivity == ConnectivityResult.mobile) {
      mobile = true;
    }
    if (connectivity == ConnectivityResult.wifi) {
      wifi = true;
    }
    final String timezone = DateTime.now().timeZoneName;

    return {
      "library": {"name": "analytics-flutter", "version": "1.0.0"},
      "app": {"name": appName, "version": appVersion, "build": appBuild},
      "device": {
        "id": deviceId,
        "manufacturer": deviceManufacturer,
        "model": deviceModel,
        "type": deviceType
      },
      "network": {"cellular": mobile, "wifi": wifi},
      "screen": {"height": screenHeight, "width": screenWidth},
      "os": {"name": osName, "version": osVersion},
      "ip": "0.0.0.0",
      "timezone": timezone,
      "locale": locale
    };
  }

  Map defaultIntegrations() {
    final Map<String, dynamic> integrations = Map();
    for (final String integration in _enableSessionsFor) {
      integrations[integration] = {"session_id": _getSessionId()};
    }
    return integrations;
  }

  String _getSessionId() {
    bool newSession = false;
    final now = DateTime.now();
    if (Analytics._lastAction == null ||
        now.difference(_lastAction) > sessionTimeout ||
        sessionId == null) {
      newSession = true;
    }

    if (newSession) {
      sessionId = now.microsecondsSinceEpoch.toString();
    }
    _lastAction = now;
    return sessionId;
  }
}

class AnalyticsClient extends BaseClient {
  String userAgent;
  Client _inner;

  AnalyticsClient(this._inner);

  Future<StreamedResponse> send(BaseRequest request) {
    request.headers['Content-Type'] = "application/json";
    request.headers["Authorization"] = Analytics.writeKey;
    return _inner.send(request);
  }

  postSilentMicrotask(url,
      {Map<String, String> headers, body, Encoding encoding}) async {
    if (Analytics.writeKey == null) {
      print("Warning: Library was not loaded or no write key was supplied.");
      return;
    }

    scheduleMicrotask(() async {
      await this.post(url, headers: headers, body: body, encoding: encoding);
    });
  }
}
