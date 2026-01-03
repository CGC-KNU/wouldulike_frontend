import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/user_service.dart';

const String kDefaultUserTypeCode = 'IYFW';
const String _typeUpdateUrl = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/update/type_code/';

Future<String> ensureUserTypeCode(
  SharedPreferences prefs, {
  String? uuid,
  bool forceDefault = false,
}) async {
  final stored = (prefs.getString('user_type') ?? '').trim();
  final normalizedStored = stored.toUpperCase();

  final bool isLoggedIn = (prefs.getBool('kakao_logged_in') ?? false) &&
      ((prefs.getString('jwt_access_token') ?? '').isNotEmpty);

  if (!forceDefault && uuid != null && uuid.trim().isNotEmpty) {
    try {
      final remoteType = await UserService.fetchGuestType(uuid);
      final normalizedRemote = remoteType?.trim().toUpperCase() ?? '';

      if (normalizedRemote.isNotEmpty) {
        if (normalizedRemote != normalizedStored) {
          await prefs.setString('user_type', normalizedRemote);
        }
        if (isLoggedIn) {
          await UserService.updateUserTypeCode(normalizedRemote);
        }
        return normalizedRemote;
      }
    } catch (e) {
      debugPrint('Failed to resolve guest type: ${e.toString()}');
    }
  }

  if (!forceDefault &&
      normalizedStored.isNotEmpty &&
      normalizedStored != 'FALLBACK') {
    return normalizedStored;
  }

  await prefs.setString('user_type', kDefaultUserTypeCode);

  if (uuid != null && uuid.trim().isNotEmpty) {
    try {
      final response = await http.post(
        Uri.parse(_typeUpdateUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'uuid': uuid, 'type_code': kDefaultUserTypeCode}),
      );

      if (response.statusCode != 200) {
        debugPrint('Failed to update user type remotely: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error updating user type remotely: ${e.toString()}');
    }
  }

  if (isLoggedIn) {
    await UserService.updateUserTypeCode(kDefaultUserTypeCode);
  }

  return kDefaultUserTypeCode;
}
