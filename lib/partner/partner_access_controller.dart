import '../config/analytics_events.dart';
import '../utils/analytics_logger.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import '../services/app_session.dart';
import 'partner_api_client.dart';

enum PartnerAccess {
  signedOut,
  unknown,
  checking,
  nonOwner,
  owner,
  unavailable
}

class PartnerStore {
  const PartnerStore(this.id, this.name);
  final int id;
  final String name;
}

class PartnerAccessController extends ChangeNotifier
    with WidgetsBindingObserver {
  PartnerAccessController(
      {Future<Map<String, dynamic>> Function()? loadMe,
      Future<bool> Function()? loadEnabled,
      Future<int?> Function()? loadUser})
      : _loadMe = loadMe ?? _defaultMe,
        _loadEnabled = loadEnabled ??
            (() async =>
                (await PartnerApiClient().request('config'))['enabled'] ==
                true),
        _loadUser = loadUser ?? _defaultUser;
  final Future<Map<String, dynamic>> Function() _loadMe;
  final Future<bool> Function() _loadEnabled;
  final Future<int?> Function() _loadUser;
  PartnerAccess state = PartnerAccess.unknown;
  List<PartnerStore> stores = const [];
  int? userId;
  int _generation = 0;
  Future<bool>? _pending;
  Timer? _periodic;
  Timer? _expiry;
  bool _foreground = true;
  bool _disposed = false;
  bool get isOwner => state == PartnerAccess.owner;
  int get generation => _generation;

  static Future<int?> _defaultUser() async {
    final prefs = await SharedPreferences.getInstance();
    return await ApiClient.hasAccessToken() ? prefs.getInt('user_id') : null;
  }

  static Future<Map<String, dynamic>> _defaultMe() async {
    final r = await ApiClient.get('/api/partner/me/')
        .timeout(const Duration(seconds: 35));
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  void start() {
    WidgetsBinding.instance.addObserver(this);
    AppSession.revision.addListener(_sessionChanged);
    _startTimer();
    unawaited(check());
  }

  void _startTimer() {
    _periodic?.cancel();
    _periodic = Timer.periodic(
        const Duration(seconds: 25), (_) => unawaited(check(quiet: true)));
  }

  void _sessionChanged() {
    clear(PartnerAccess.signedOut);
    if (!AppSession.changing && _foreground) unawaited(check());
  }

  void clear([PartnerAccess next = PartnerAccess.unavailable]) {
    _generation++;
    _pending = null;
    _expiry?.cancel();
    state = next;
    stores = const [];
    userId = null;
    if (!_disposed) notifyListeners();
  }

  Future<bool> check({bool quiet = false}) {
    if (!_foreground || AppSession.changing || _disposed) {
      return Future.value(false);
    }
    if (_pending != null) return _pending!;
    if (!quiet || !isOwner) {
      state = PartnerAccess.checking;
      notifyListeners();
    }
    final generation = _generation;
    final revision = AppSession.revision.value;
    final work = _check(generation, revision);
    _pending = work;
    work.whenComplete(() {
      if (identical(_pending, work)) _pending = null;
    });
    return work;
  }

  Future<bool> _check(int generation, int revision) async {
    bool current() =>
        !_disposed &&
        _foreground &&
        generation == _generation &&
        revision == AppSession.revision.value &&
        !AppSession.changing;
    try {
      final id = await _loadUser();
      if (!current()) return false;
      if (id == null || id <= 0) {
        clear(PartnerAccess.signedOut);
        return false;
      }
      final me = await _loadMe();
      if (!current()) return false;
      if (me['is_partner'] is! bool || me['stores'] is! List) {
        throw const FormatException('권한 응답');
      }
      final parsed = <PartnerStore>[];
      for (final raw in me['stores'] as List) {
        if (raw is! Map ||
            raw['restaurant_id'] is! int ||
            (raw['restaurant_id'] as int) <= 0 ||
            raw['name'] is! String) {
          throw const FormatException('매장 응답');
        }
        parsed.add(
            PartnerStore(raw['restaurant_id'] as int, raw['name'] as String));
      }
      if (me['is_partner'] != true || parsed.isEmpty) {
        clear(PartnerAccess.nonOwner);
        return false;
      }
      final enabled = await _loadEnabled();
      if (!current()) return false;
      if (await _loadUser() != id || !current()) return false;
      if (!enabled) {
        clear();
        return false;
      }
      userId = id;
      stores = List.unmodifiable(parsed);
      state = PartnerAccess.owner;
      _expiry?.cancel();
      _expiry = Timer(const Duration(seconds: 30), () => clear());
      notifyListeners();
      return true;
    } catch (_) {
      if (current()) {
        AnalyticsLogger.logEvent(AnalyticsEvents.partnerAccessFailed);
        clear();
      }
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _startTimer();
      unawaited(check());
    } else {
      _foreground = false;
      _periodic?.cancel();
      _generation++;
      _pending = null;
      _expiry?.cancel();
      this.state = PartnerAccess.unknown;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _periodic?.cancel();
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AppSession.revision.removeListener(_sessionChanged);
    super.dispose();
  }
}
