import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

enum InAppUpdateResult { started, notAvailable, unsupported, error }

class AppUpdater {
  AppUpdater._();

  static Future<InAppUpdateResult> tryImmediateUpdate() async {
    if (!Platform.isAndroid) return InAppUpdateResult.unsupported;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return InAppUpdateResult.notAvailable;
      }
      if (info.immediateUpdateAllowed != true) {
        return InAppUpdateResult.notAvailable;
      }
      await InAppUpdate.performImmediateUpdate();
      return InAppUpdateResult.started;
    } catch (e) {
      debugPrint('[AppUpdater] immediate 실패: $e');
      return InAppUpdateResult.error;
    }
  }

  static Future<InAppUpdateResult> tryFlexibleUpdate() async {
    if (!Platform.isAndroid) return InAppUpdateResult.unsupported;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return InAppUpdateResult.notAvailable;
      }
      if (info.flexibleUpdateAllowed != true) {
        return InAppUpdateResult.notAvailable;
      }
      await InAppUpdate.startFlexibleUpdate();
      InAppUpdate.completeFlexibleUpdate();
      return InAppUpdateResult.started;
    } catch (e) {
      debugPrint('[AppUpdater] flexible 실패: $e');
      return InAppUpdateResult.error;
    }
  }
}
