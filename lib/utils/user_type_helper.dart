import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kDefaultUserTypeCode = 'IYFW';
const String _typeUpdateUrl = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/update/type_code/';

Future<String> ensureUserTypeCode(
  SharedPreferences prefs, {
  String? uuid,
  bool forceDefault = false,
}) async {
  final stored = (prefs.getString('user_type') ?? '').trim();
  final normalized = stored.toUpperCase();
  final needsDefault = forceDefault || stored.isEmpty || normalized == 'FALLBACK';

  if (needsDefault) {
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

    return kDefaultUserTypeCode;
  }

  return stored;
}
