import 'dart:async';
import 'package:flutter/material.dart';
import 'partner_access_controller.dart';
import 'partner_api_client.dart';
import 'partner_pages.dart';

class PartnerShell extends StatefulWidget {
  const PartnerShell({super.key, required this.access});
  final PartnerAccessController access;
  @override
  State<PartnerShell> createState() => _PartnerShellState();
}

class _PartnerShellState extends State<PartnerShell> {
  PartnerStore? _store;
  PartnerStore? _previousStore;
  int _tab = 0;
  int _storeGeneration = 0;
  bool _leaving = false;
  bool _closing = false;
  final _pageKey = GlobalKey<PartnerPageState>();
  static const labels = ['홈', '매장', '혜택', '콘텐츠', '리포트', '플랜'];
  @override
  void initState() {
    super.initState();
    if (widget.access.stores.length == 1) _store = widget.access.stores.single;
    widget.access.addListener(_accessChanged);
  }

  void _accessChanged() {
    if (!mounted) return;
    final access = widget.access;
    if ([
      PartnerAccess.nonOwner,
      PartnerAccess.signedOut,
      PartnerAccess.unavailable
    ].contains(access.state)) {
      if (_closing) return;
      setState(() => _closing = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final own = ModalRoute.of(context);
        Navigator.of(context).popUntil((route) => route == own);
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    if (access.isOwner &&
        _store != null &&
        !access.stores.any((s) => s.id == _store!.id)) {
      _store = null;
      _storeGeneration++;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.access.removeListener(_accessChanged);
    super.dispose();
  }

  Future<void> _back() async {
    final previous = _previousStore;
    if (_store == null &&
        previous != null &&
        widget.access.isOwner &&
        widget.access.stores.any((s) => s.id == previous.id)) {
      setState(() {
        _store = previous;
        _previousStore = null;
        _tab = 0;
        _storeGeneration++;
      });
      return;
    }
    await _leave();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final ok =
        await (_pageKey.currentState?.confirmDiscard() ?? Future.value(true));
    _leaving = false;
    if (ok && mounted) {
      setState(() => _closing = true);
      Navigator.of(context).pop();
    }
  }

  Future<void> _choose(PartnerStore store) async {
    final ok =
        await (_pageKey.currentState?.confirmDiscard() ?? Future.value(true));
    if (!ok || !await widget.access.check() || !mounted) return;
    if (!widget.access.stores.any((s) => s.id == store.id)) return;
    setState(() {
      _store = store;
      _previousStore = null;
      _tab = 0;
      _storeGeneration++;
    });
  }

  Future<Map<String, dynamic>> _request(String route,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final store = _store;
    final generation = _storeGeneration;
    final user = widget.access.userId;
    final accessGeneration = widget.access.generation;
    if (store == null || !widget.access.isOwner) {
      throw Exception('권한을 확인하고 있습니다.');
    }
    try {
      final result = await PartnerApiClient()
          .request(route, restaurantId: store.id, method: method, body: body);
      if (!mounted ||
          generation != _storeGeneration ||
          user != widget.access.userId ||
          accessGeneration != widget.access.generation ||
          !widget.access.isOwner) {
        throw Exception('매장 정보가 변경되었습니다.');
      }
      return result;
    } on PartnerApiException catch (e) {
      if (e.status == 403) {
        final valid = await widget.access.check();
        if (valid && widget.access.stores.any((s) => s.id == store.id)) {
          widget.access.clear();
        }
      } else if (e.code == 'owner_mode_disabled' ||
          e.code == 'store_context_mismatch') {
        widget.access.clear();
        unawaited(widget.access.check());
      }
      rethrow;
    }
  }

  Future<void> _selectTab(int tab) async {
    if (tab == _tab) return;
    if (!await (_pageKey.currentState?.confirmDiscard() ??
            Future.value(true)) ||
        !mounted) {
      return;
    }
    setState(() {
      _tab = tab;
      _storeGeneration++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = widget.access;
    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 56 +
              (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 40) *
                  2,
          leadingWidth: 124,
          leading: TextButton.icon(
              onPressed: _leave,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('일반 모드로')),
          title: Text(_store?.name ?? '내 매장 선택',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17)),
          actions: [
            if (_store != null && access.stores.length > 1)
              IconButton(
                  tooltip: '매장 변경',
                  icon: const Icon(Icons.storefront),
                  onPressed: () async {
                    if (!await (_pageKey.currentState?.confirmDiscard() ??
                            Future.value(true)) ||
                        !mounted) {
                      return;
                    }
                    setState(() {
                      _previousStore = _store;
                      _store = null;
                      _storeGeneration++;
                    });
                  })
          ],
        ),
        body: Stack(children: [
          ExcludeSemantics(
              excluding: !access.isOwner,
              child: IgnorePointer(
                ignoring: !access.isOwner,
                child: _store == null
                    ? ListView(children: [
                        const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('관리할 매장을 선택해 주세요.')),
                        ...access.stores.map((s) => ListTile(
                            title: Text(s.name),
                            subtitle: Text('매장 ${s.id}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _choose(s)))
                      ])
                    : PartnerPage(
                        key: _pageKey,
                        tab: _tab,
                        scope:
                            '${access.userId}:${_store!.id}:$_storeGeneration',
                        request: _request,
                        access: access),
              )),
          if (!access.isOwner)
            const Positioned.fill(
                child: ColoredBox(
                    color: Colors.white,
                    child: Center(child: CircularProgressIndicator()))),
        ]),
        bottomNavigationBar: _store == null
            ? null
            : SafeArea(
                top: false,
                child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                        children: List.generate(
                            labels.length,
                            (i) => TextButton(
                                  onPressed: access.isOwner
                                      ? () => _selectTab(i)
                                      : null,
                                  style: TextButton.styleFrom(
                                      foregroundColor: i == _tab
                                          ? const Color(0xFF312E81)
                                          : Colors.grey),
                                  child: Text(labels[i]),
                                ))))),
      ),
    );
  }
}
