import 'dart:io';
import 'dart:async';
import 'dart:convert' show utf8, base64, json, Encoding;
import 'package:connectivity/connectivity.dart';
import 'package:http/http.dart';
import 'package:device_info/device_info.dart';

class Analytics {
  static bool enabled = true;
  static Analytics _singleton;
  static String endpoint = "https://api.segment.io/v1";
  static String writeKey;
  static AnalyticsClient client = new AnalyticsClient(new Client());

  // Context infos
  static String osName;
  static String osVersion;
  static String deviceId;
  static String deviceManufacturer;
  static String deviceModel;

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
      String locale}) {
    Analytics.appName = appName;
    Analytics.appVersion = appVersion;
    Analytics.appBuild = appBuild;
    Analytics.screenWidth = screenWidth;
    Analytics.screenHeight = screenHeight;
    Analytics.locale = locale;
    _singleton = new Analytics._internal(apiKey);
    return _singleton;
  }

  factory Analytics() {
    if (_singleton == null) {
      if (enabled) {
        print("Warning: Called Analytics without loading the library.");
      }
      _singleton = new Analytics._internalNoWriteKey();
      return _singleton;
    } else {
      return _singleton;
    }
  }

  Analytics._internal(String segmentApiKey) {
    writeKey = "Basic ${base64.encode(utf8.encode(segmentApiKey)).toString()}";
    Analytics._loading = _loadDeviceInfos();
  }

  Analytics._internalNoWriteKey();

  Future<void> _loadDeviceInfos() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      osName = androidInfo.version.baseOS;
      osVersion = androidInfo.version.release;
      deviceId = androidInfo.androidId;
      deviceManufacturer = androidInfo.manufacturer;
      deviceModel = androidInfo.model;
    } else {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      osName = iosInfo.systemName;
      osVersion = iosInfo.systemVersion;
      deviceId = iosInfo.identifierForVendor;
      deviceManufacturer = "Apple";
      deviceModel = iosInfo.model;
    }
  }

  void identify(String userID, {Map traits}) async {
    if (!enabled) {
      return;
    }
    if (traits == null) {
      traits = new Map();
    }

    Map payload = {
      "traits": traits,
      "userId": userID,
      "context": await defaultContext()
    };
    client.postSilentMicrotask("$endpoint/identify",
        body: json.encode(payload));
  }

  void group(String userID, String groupId, {Map traits}) async {
    if (!enabled) {
      return;
    }
    if (traits == null) {
      traits = new Map();
    }

    Map payload = {
      "traits": traits,
      "userId": userID,
      "groupId": groupId,
      "context": await defaultContext()
    };
    client.postSilentMicrotask("$endpoint/group", body: json.encode(payload));
  }

  Future<void> screen(String userId, String name,
      {Map properties, Map context}) async {
    if (!enabled) {
      return;
    }
    if (properties == null) {
      properties = new Map();
    }

    Map sendContext = await defaultContext();
    if (context != null) {
      sendContext.addAll(context);
    }

    Map payload = {
      "userId": userId,
      "context": new Map.from(context),
      "name": name,
      "properties": new Map.from(properties)
    };
    client.postSilentMicrotask("$endpoint/screen", body: json.encode(payload));
  }

  void track(String userId, String event, {Map properties, Map context}) async {
    if (!enabled) {
      return;
    }
    if (properties == null) {
      properties = new Map();
    }

    Map sendContext = await defaultContext();
    if (context != null) {
      sendContext.addAll(context);
    }

    Map payload = {
      "userId": userId,
      "context": new Map.from(context),
      "event": event,
      "properties": new Map.from(properties)
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
        "model": deviceModel
      },
      "network": {"cellular": mobile, "wifi": wifi},
      "screen": {"height": screenHeight, "width": screenWidth},
      "os": {"name": osName, "version": osVersion},
      "ip": "0.0.0.0",
      "timezone": timezone,
      "locale": locale
    };
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
    // Make sure everything is fully loaded;
    await Analytics._loading;

    scheduleMicrotask(() async {
      await this.post(url, headers: headers, body: body, encoding: encoding);
    });
  }
}
