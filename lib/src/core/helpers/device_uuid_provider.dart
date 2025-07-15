import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class DeviceUUIDProvider {
  DeviceUUIDProvider(
    this._deviceInfo,
  );

  final DeviceInfoPlugin _deviceInfo;

  Future<String?> getDeviceUUID() async {
    if (Platform.isIOS) {
      final IosDeviceInfo iosDeviceInfo = await _deviceInfo.iosInfo;
      return iosDeviceInfo.identifierForVendor;
    } else {
      final AndroidDeviceInfo androidDeviceInfo = await _deviceInfo.androidInfo;
      return androidDeviceInfo.id;
    }
  }
}
