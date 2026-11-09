import '../config/analytics_events.dart';
import '../config/screen_ids.dart';
import '../utils/analytics_logger.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_session.dart';
import 'partner_access_controller.dart';
import 'partner_api_client.dart';
import 'partner_report_launcher.dart';
import 'partner_design.dart';

typedef PartnerRequest = Future<Map<String, dynamic>> Function(String route,
    {String method, Map<String, dynamic>? body});
Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
List<Map<String, dynamic>> _rows(dynamic v) => v is List
    ? v.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];
String _text(dynamic v, [String fallback = '—']) =>
    v == null || '$v'.isEmpty ? fallback : '$v';
String _won(dynamic v) => v == null
    ? '미확인'
    : '${v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';
const _fields = {
  'description': '매장 소개',
  'phone_number': '전화번호',
  'main_menu': '대표 메뉴',
  'url': '매장 링크',
  'address': '주소',
  'promotion_text': '홍보 문구'
};
const _states = {
  'published': '게시됨',
  'scheduled': '예정',
  'failed': '실패',
  'done': '완료',
  'active': '진행 중',
  'PENDING': '검토 중',
  'APPROVED': '승인됨',
  'REJECTED': '반려'
};

class PartnerPage extends StatefulWidget {
  const PartnerPage(
      {super.key,
      required this.tab,
      required this.scope,
      required this.request,
      required this.access});
  final int tab;
  final String scope;
  final PartnerRequest request;
  final PartnerAccessController access;
  @override
  State<PartnerPage> createState() => PartnerPageState();
}

class PartnerPageState extends State<PartnerPage> {
  Map<String, dynamic>? _data;
  Map<String, dynamic> _extra = {};
  String? _error;
  bool _busy = false;
  bool _dirty = false;
  bool _restaurantDirty = false;
  bool _pinDirty = false;
  bool _uncertainRequest = false;
  int _loadVersion = 0;
  String _category = '';
  List<String> _images = [];
  final _edit = {for (final key in _fields.keys) key: TextEditingController()};
  final _currentPin = TextEditingController();
  final _newPin = TextEditingController();
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  final _notes = TextEditingController();
  final _note = TextEditingController();
  String _action = 'EDIT';
  int? _benefitId;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PartnerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope || oldWidget.tab != widget.tab) {
      _data = null;
      _extra = {};
      _error = null;
      _busy = false;
      _dirty = false;
      _restaurantDirty = false;
      _pinDirty = false;
      _images = [];
      _category = '';
      _benefitId = null;
      _action = 'EDIT';
      _uncertainRequest = false;
      for (final c in [
        ..._edit.values,
        _currentPin,
        _newPin,
        _title,
        _subtitle,
        _notes,
        _note
      ]) {
        c.clear();
      }
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _loadVersion++;
    for (final c in [
      ..._edit.values,
      _currentPin,
      _newPin,
      _title,
      _subtitle,
      _notes,
      _note
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> confirmDiscard() async {
    if (!_dirty && !_busy) return true;
    return await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                  title: const Text('편집을 끝낼까요?'),
                  content: Text(_busy
                      ? '처리 중입니다. 화면을 닫아도 요청이 완료될 수 있습니다.'
                      : '저장하지 않은 변경 내용이 사라집니다.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('계속 편집')),
                    TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('나가기'))
                  ],
                )) ??
        false;
  }

  Future<void> _load({bool preserveDraft = false}) async {
    final version = ++_loadVersion;
    const screens = [
      ScreenIds.partnerHome,
      ScreenIds.partnerRestaurant,
      ScreenIds.partnerBenefits,
      ScreenIds.partnerContent,
      ScreenIds.partnerReports,
      ScreenIds.partnerPlan
    ];
    AnalyticsLogger.logScreen(screens[widget.tab]);
    try {
      final routes = [
        'home',
        'restaurant',
        'benefits',
        'home',
        'reports',
        'plan'
      ];
      final data = await widget.request(routes[widget.tab]);
      Map<String, dynamic> extra = {};
      if (widget.tab == 1) extra = await widget.request('categories');
      if (widget.tab == 2) {
        extra = await widget.request('benefit-requests');
        extra['stamp'] = await widget.request('stamp-rule');
      }
      if (widget.tab == 4) extra = await widget.request('home');
      if (!mounted || version != _loadVersion) return;
      if (widget.tab == 1 && !preserveDraft) {
        for (final e in _edit.entries) {
          e.value.text = _text(data[e.key], '');
        }
        _category = _text(data['category'], '');
        _images =
            (data['s3_image_urls'] as List? ?? []).map((e) => '$e').toList();
      }
      setState(() {
        _data = data;
        _extra = extra;
        _error = null;
      });
    } catch (e) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _error = '불러오지 못했습니다. 잠시 후 다시 확인해 주세요.';
          _data = null;
        });
      }
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _write(String route, Map<String, dynamic> body,
      {String method = 'POST'}) async {
    if (_busy) return;
    final scope = widget.scope;
    setState(() => _busy = true);
    try {
      await widget.request(route, method: method, body: body);
      if (!mounted || widget.scope != scope) return;
      if (route == 'restaurant') _restaurantDirty = false;
      if (route == 'pin/change') _pinDirty = false;
      _dirty = _restaurantDirty || _pinDirty;
      if (route == 'benefit-requests') {
        _uncertainRequest = false;
        _title.clear();
        _subtitle.clear();
        _notes.clear();
        _note.clear();
      }
      if (route == 'pin/change') {
        _currentPin.clear();
        _newPin.clear();
      }
      _message(
          route == 'benefit-requests' ? '신청을 접수했습니다. 검토 후 반영됩니다.' : '저장했습니다.');
      await _load(preserveDraft: route == 'pin/change' && _restaurantDirty);
    } catch (e) {
      if (!mounted || widget.scope != scope) return;
      if (route == 'benefit-requests' &&
          (e is! PartnerApiException || e.status >= 500)) {
        _uncertainRequest = true;
        _message('접수 여부를 확인하지 못했습니다. 신청 내역을 새로고침해 확인한 뒤 다시 신청해 주세요.');
      } else {
        _message(e is PartnerApiException
            ? e.message
            : '처리 결과를 확인하지 못했습니다. 새로고침해 확인해 주세요.');
      }
    } finally {
      if (mounted && widget.scope == scope) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto() async {
    if (_busy || _images.length >= 5) return;
    final scope = widget.scope;
    final session = AppSession.revision.value;
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
          requestFullMetadata: false);
      if (file == null ||
          !mounted ||
          widget.scope != scope ||
          session != AppSession.revision.value) {
        return;
      }
      // Native photo selection can background the app. Await fresh access before uploading.
      if (!await widget.access.check() || !mounted || widget.scope != scope) {
        return;
      }
      final bytes = await file.readAsBytes();
      final png = bytes.length > 4 && bytes[0] == 137 && bytes[1] == 80;
      final jpeg = bytes.length > 2 && bytes[0] == 255 && bytes[1] == 216;
      final webp = bytes.length > 12 &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
      if (!png && !jpeg && !webp) {
        throw Exception('JPEG, PNG, WebP 사진을 선택해 주세요.');
      }
      final type = png
          ? 'image/png'
          : jpeg
              ? 'image/jpeg'
              : 'image/webp';
      final ext = png
          ? 'png'
          : jpeg
              ? 'jpg'
              : 'webp';
      final signed = await widget.request('images/presign',
          method: 'POST',
          body: {'filename': 'store.$ext', 'content_type': type});
      if (!mounted || widget.scope != scope) return;
      final upload = Uri.parse(signed['upload_url'] as String);
      final publicUrl = Uri.parse(signed['public_url'] as String);
      if (upload.scheme != 'https' ||
          !upload.host.endsWith('.amazonaws.com') ||
          publicUrl.scheme != 'https') {
        throw Exception('사진 업로드 주소를 확인하지 못했습니다.');
      }
      final req = http.Request('PUT', upload)
        ..followRedirects = false
        ..headers['Content-Type'] = type
        ..bodyBytes = bytes;
      final client = http.Client();
      try {
        final result =
            await client.send(req).timeout(const Duration(seconds: 40));
        await result.stream.drain<void>();
        if (result.statusCode < 200 || result.statusCode >= 300) {
          throw Exception('사진을 업로드하지 못했습니다.');
        }
      } finally {
        client.close();
      }
      if (!mounted ||
          widget.scope != scope ||
          session != AppSession.revision.value) {
        return;
      }
      setState(() {
        _images.add(publicUrl.toString());
        _dirty = true;
        _restaurantDirty = true;
      });
      _message('사진을 올렸습니다. 매장 정보 저장을 눌러 반영해 주세요.');
    } catch (e) {
      if (mounted && widget.scope == scope) {
        _message('사진을 올리지 못했습니다. 형식과 연결을 확인해 주세요.');
      }
    } finally {
      if (mounted && widget.scope == scope) setState(() => _busy = false);
    }
  }

  Widget _card(String title, List<Widget> children,
          {Color color = Colors.white}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PartnerPanel(
              color: color,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    for (var i = 0; i < children.length; i++) ...[
                      children[i],
                      if (i < children.length - 1) const SizedBox(height: 10),
                    ],
                  ])));
  Widget _line(String label, dynamic value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(builder: (context, box) {
        final name = Text(label,
            style: const TextStyle(fontSize: 12, color: PartnerDesign.muted));
        final text = Text(_text(value),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500));
        if (box.maxWidth < 260 ||
            MediaQuery.textScalerOf(context).scale(13) > 19) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [name, const SizedBox(height: 3), text]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 2, child: name),
          const SizedBox(width: 12),
          Expanded(flex: 5, child: text),
        ]);
      }));

  Widget _status(dynamic state) {
    final color = switch (state) {
      'published' || 'APPROVED' => PartnerDesign.green,
      'failed' || 'REJECTED' => PartnerDesign.red,
      'active' || 'PENDING' => PartnerDesign.amber,
      'done' => PartnerDesign.muted,
      _ => PartnerDesign.navy,
    };
    return PartnerBadge(_states[state] ?? _text(state),
        color: color, background: color.withValues(alpha: .08));
  }

  List<Widget> _feed(Map<String, dynamic> data) {
    final rows = _rows(data['feed'])
        .where((f) =>
            widget.tab != 3 || f['kind'] == 'post' || f['kind'] == 'campaign')
        .toList();
    if (rows.isEmpty) {
      return [
        const PartnerEmpty('아직 기록이 없습니다.', icon: Icons.photo_library_outlined)
      ];
    }
    return rows
        .map((f) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                      color: PartnerDesign.tint,
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(
                      f['kind'] == 'campaign'
                          ? Icons.campaign_outlined
                          : Icons.photo_library_outlined,
                      size: 18,
                      color: PartnerDesign.periwinkle)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_text(f['title']),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(_text(f['date']),
                              style: const TextStyle(
                                  fontSize: 11.5, color: PartnerDesign.muted)),
                          _status(f['state']),
                        ]),
                  ])),
              if (_text(f['permalink'], '').isNotEmpty)
                IconButton(
                    tooltip: '인스타그램에서 보기',
                    icon: const Icon(Icons.open_in_new, size: 18),
                    onPressed: () => _openExternal('${f['permalink']}')),
            ])))
        .toList();
  }

  Future<void> _openExternal(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception();
      }
    } catch (_) {
      _message('링크를 열지 못했습니다.');
    }
  }

  Widget _reportState(Map<String, dynamic> status) {
    final texts = {
      'unknown_start': '계약 시작일이 아직 등록되지 않았습니다.',
      'collecting': '첫 월간 리포트까지 ${_text(status['days_until_first'])}일',
      'available': '받으신 리포트가 ${_text(status['available_count'])}건 있습니다.',
      'delayed': '아직 보내 드린 리포트가 없습니다. 담당자에게 문의해 주세요.',
      'preparing': '월간 리포트를 준비하고 있습니다.',
      'unavailable': '리포트 현황을 읽지 못했습니다. 다시 확인해 주세요.'
    };
    final remaining = num.tryParse('${status['days_until_first']}');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: PartnerDesign.tint, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.description_outlined,
            color: PartnerDesign.periwinkle, size: 22),
        const SizedBox(height: 10),
        Text(texts[status['state']] ?? '리포트 현황을 확인하고 있습니다.',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: PartnerDesign.navy)),
        if (status['state'] == 'collecting' && remaining != null) ...[
          const SizedBox(height: 8),
          const Text('30일치 데이터가 쌓이면 담당자가 정리해 보내 드립니다.',
              style: TextStyle(fontSize: 12, color: PartnerDesign.muted)),
          const SizedBox(height: 12),
          Semantics(
              label: '첫 리포트 준비',
              value: '${((30 - remaining).clamp(0, 30) / 30 * 100).round()}%',
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LayoutBuilder(
                      builder: (context, box) => Stack(children: [
                            Container(height: 7, color: PartnerDesign.border),
                            Container(
                                height: 7,
                                width: box.maxWidth *
                                    ((30 - remaining) / 30).clamp(0, 1),
                                decoration: const BoxDecoration(
                                    gradient: PartnerDesign.gradient)),
                          ])))),
        ],
      ]),
    );
  }

  String _tierName(dynamic tier) =>
      const {'FREE': 'Free', 'BOOST': 'Boost', 'CONTENT': 'Premium'}[tier] ??
      _text(tier, '플랜 미확인');

  Widget _metric(String label, dynamic value, String unit,
      {dynamic previous, bool enabled = true, bool loyal = false}) {
    final now = num.tryParse('$value'), prev = num.tryParse('$previous');
    String comparison = '전월 비교 미확인';
    Color color = PartnerDesign.muted;
    if (loyal) {
      comparison = '지금까지 3일 이상 오신 분';
    } else if (now != null && prev != null) {
      if (prev == 0) {
        comparison = now == 0 ? '지난달에도 없었습니다' : '지난달 같은 기간에는 없었습니다';
      } else if (now == prev) {
        comparison = '전월과 같음';
      } else {
        final diff = now - prev;
        comparison = '${diff > 0 ? '▲' : '▼'} 전월 ${diff > 0 ? '+' : ''}$diff';
        color = diff > 0 ? PartnerDesign.green : PartnerDesign.red;
      }
    }
    return PartnerPanel(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: PartnerDesign.muted)),
          const SizedBox(height: 7),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: enabled ? _text(value) : '—',
                style: const TextStyle(
                    fontSize: 26,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5)),
            if (enabled)
              TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                      fontSize: 12, color: PartnerDesign.muted)),
          ])),
          const SizedBox(height: 9),
          Text(enabled ? comparison : '스탬프를 쓰지 않는 매장입니다',
              style: TextStyle(fontSize: 11.5, height: 1.45, color: color)),
        ]));
  }

  Widget _metrics(Map<String, dynamic> data) {
    final stats = _map(data['stats']),
        now = _map(stats['this']),
        prev = _map(stats['prev']);
    final stamp = _map(data['store'])['stamp_enabled'] != false;
    final items = [
      _metric('쿠폰 사용', now['coupon_used'], '장', previous: prev['coupon_used']),
      _metric('스탬프 적립', now['stamp'], '개',
          previous: prev['stamp'], enabled: stamp),
      _metric('재방문', now['revisit'], '명',
          previous: prev['revisit'], enabled: stamp),
      _metric('단골 누적', stats['loyal_total'], '명', enabled: stamp, loyal: true),
    ];
    return LayoutBuilder(builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
      final columns = box.maxWidth >= 650 && scale < 1.5
          ? 4
          : box.maxWidth < 330 && scale > 1.5
              ? 1
              : 2;
      return Column(children: [
        for (var start = 0; start < items.length; start += columns)
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IntrinsicHeight(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    for (var i = start;
                        i < start + columns && i < items.length;
                        i++) ...[
                      if (i > start) const SizedBox(width: 10),
                      Expanded(child: items[i]),
                    ],
                  ]))),
      ]);
    });
  }

  Widget _pinCard(Map<String, dynamic> store) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PartnerPanel(child: LayoutBuilder(builder: (context, box) {
        const label =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('매장 PIN',
              style: TextStyle(fontSize: 12, color: PartnerDesign.muted)),
          SizedBox(height: 4),
          Text('손님 스탬프 적립·쿠폰 사용에 쓰는 번호입니다.',
              style: TextStyle(fontSize: 11.5, color: PartnerDesign.muted)),
        ]);
        final pin = Text(
            _text(
                store['pin'],
                store['pin_unreadable'] == true
                    ? '현재 읽을 수 없습니다. 매장 메뉴에서 변경해 주세요.'
                    : '미설정'),
            style: TextStyle(
                fontSize: store['pin'] == null ? 13 : 24,
                fontWeight: FontWeight.w700,
                letterSpacing: store['pin'] == null ? 0 : 4));
        if (box.maxWidth >= 320 &&
            MediaQuery.textScalerOf(context).scale(13) < 18 &&
            store['pin'] != null &&
            '${store['pin']}'.length <= 6) {
          return Row(children: [
            const Expanded(child: label),
            const SizedBox(width: 16),
            pin
          ]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [label, const SizedBox(height: 10), pin]);
      })));

  List<Widget> _home(Map<String, dynamic> data) {
    final store = _map(data['store']);
    final billing = _map(data['billing']),
        invoice = _map(billing['invoice']),
        manager = _map(data['manager']),
        promo = _map(data['promo']);
    return [
      Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 18),
          child: Row(children: [
            CircleAvatar(
                radius: 23,
                backgroundColor: PartnerDesign.tint,
                child: Text(_text(store['name'], '매').characters.first,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: PartnerDesign.navy))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(_text(store['name']),
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                        PartnerBadge(_tierName(store['tier']),
                            color: store['tier'] == 'FREE'
                                ? PartnerDesign.muted
                                : Colors.white,
                            background: store['tier'] == 'CONTENT'
                                ? PartnerDesign.periwinkle
                                : store['tier'] == 'BOOST'
                                    ? PartnerDesign.navy
                                    : PartnerDesign.tint),
                      ]),
                  const SizedBox(height: 5),
                  Text(
                      [
                        if (_text(store['campus'], '').isNotEmpty)
                          '${store['campus']}',
                        if (store['contract_started_on'] != null ||
                            store['contract_ends_on'] != null)
                          '이용기간 ${_text(store['contract_started_on'])} ~ ${_text(store['contract_ends_on'])}',
                      ].join(' · '),
                      style: const TextStyle(
                          fontSize: 11.5, color: PartnerDesign.muted)),
                ])),
          ])),
      _pinCard(store),
      Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Text('${_text(data['month'])} 이번 달 지표',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
      _metrics(data),
      const Padding(
          padding: EdgeInsets.only(bottom: 18),
          child: Text(
              '앞의 셋은 이번 달 1일부터 오늘까지, 전월 비교도 지난달 같은 기간 기준입니다. 앱에서 실제로 찍힌 것만 셉니다.',
              style: TextStyle(fontSize: 11.5, color: PartnerDesign.muted))),
      _card('최근에 있었던 일', _feed(data), color: PartnerDesign.tint),
      _card('월간 리포트', [_reportState(_map(data['report_status']))]),
      _card('내 매장', [
        _line(
            '업종 · 대표 메뉴',
            [store['category'], store['main_menu']]
                .where((v) => _text(v, '').isNotEmpty)
                .join(' · ')),
        if (_text(store['coupon_basic'], '').isNotEmpty)
          _line('기본 쿠폰', store['coupon_basic']),
        if (_text(store['coupon_limited'], '').isNotEmpty)
          _line('한정 쿠폰', store['coupon_limited']),
        if (store['stamp_count'] != null)
          _line('스탬프 카드', '${store['stamp_count']}개'),
        if (_text(store['stamp_reward'], '').isNotEmpty)
          _line('스탬프 보상', store['stamp_reward']),
      ]),
      _card('이용 요금', [
        _line('월 계약금액', _won(billing['monthly_fee'])),
        _line(
            '납부 주기',
            billing['pay_cycle'] == 'LUMP'
                ? '일시납'
                : billing['pay_cycle'] == 'MONTHLY'
                    ? '월납'
                    : billing['pay_cycle']),
        if (invoice.isEmpty)
          const Text('아직 계산서가 발행되지 않았습니다.',
              style: TextStyle(fontSize: 12, color: PartnerDesign.muted))
        else
          Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_won(invoice['total']),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                PartnerBadge(invoice['paid_at'] != null ? '입금 확인' : '입금 대기',
                    color: invoice['paid_at'] != null
                        ? PartnerDesign.green
                        : PartnerDesign.amber,
                    background: invoice['paid_at'] != null
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFFFBEB)),
              ]),
      ]),
      _card('담당자 · 홍보물', [
        Row(children: [
          CircleAvatar(
              radius: 18,
              backgroundColor: PartnerDesign.navy,
              child: Text(_text(manager['name'], '?').characters.first,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(_text(manager['name'], '담당자가 곧 배정됩니다.'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (manager.isNotEmpty)
                  Text(_text(manager['title'], '우주라이크'),
                      style: const TextStyle(
                          fontSize: 11.5, color: PartnerDesign.muted)),
              ])),
        ]),
        for (final e in {'poster_url': '포스터 열기', 'qr_url': 'QR 열기'}.entries)
          if (promo[e.key] is String && (promo[e.key] as String).isNotEmpty)
            OutlinedButton(
                onPressed: () => _openExternal(promo[e.key] as String),
                child: Text(e.value)),
        if ((data['partial_errors'] as List? ?? []).contains('promo'))
          const Text('홍보물을 읽지 못했습니다. 새로고침해 주세요.'),
      ]),
    ];
  }

  List<Widget> _restaurant(Map<String, dynamic> data) {
    final categories = (_extra['categories'] as List? ?? [])
        .where((v) => v is! Map || v['code'] != 'ALL')
        .map((v) => v is Map ? _text(v['label'], '') : '$v')
        .where((s) => s.isNotEmpty)
        .toSet();
    if (_category.isNotEmpty) categories.add(_category);
    return [
      _card('기본 정보 · ${_text(data['name'])}', [
        for (final e in _fields.entries)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _edit[e.key],
                enabled: !_busy,
                maxLength: e.key == 'description' ? 2000 : 500,
                maxLines: e.key == 'description' ? 3 : 1,
                decoration: InputDecoration(labelText: e.value),
                onChanged: (_) {
                  _dirty = true;
                  _restaurantDirty = true;
                },
              )),
        DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _category.isEmpty ? null : _category,
            decoration: const InputDecoration(labelText: '업종'),
            items: categories
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: _busy
                ? null
                : (v) => setState(() {
                      _category = v ?? '';
                      _dirty = true;
                      _restaurantDirty = true;
                    })),
        const SizedBox(height: 16),
        const Divider(),
        Text('매장 사진 ${_images.length}/5',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const Text('첫 사진이 대표 사진입니다.',
            style: TextStyle(fontSize: 12, color: PartnerDesign.muted)),
        if (_images.isEmpty)
          const PartnerEmpty('매장의 분위기가 담긴 사진을 올려 주세요.',
              icon: Icons.add_photo_alternate_outlined),
        for (var i = 0; i < _images.length; i++)
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(_images[i],
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image))),
              title: Text('사진 ${i + 1}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: '앞으로 이동',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _busy || i == 0
                        ? null
                        : () => setState(() {
                              final image = _images.removeAt(i);
                              _images.insert(i - 1, image);
                              _dirty = true;
                              _restaurantDirty = true;
                            })),
                IconButton(
                    tooltip: '사진 삭제',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _images.removeAt(i);
                              _dirty = true;
                              _restaurantDirty = true;
                            })),
              ])),
        OutlinedButton.icon(
            onPressed: _busy || _images.length >= 5 ? null : _addPhoto,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('사진 선택')),
        FilledButton(
            onPressed: _busy
                ? null
                : () => _write(
                    'restaurant',
                    {
                      for (final e in _edit.entries) e.key: e.value.text.trim(),
                      'category': _category,
                      's3_image_urls': _images
                    },
                    method: 'PATCH'),
            child: const Text('매장 정보 저장')),
      ]),
      _card('매장 PIN ${data['has_pin'] == true ? '변경' : '최초 설정'}', [
        _line(
            '현재 PIN',
            data['pin'] ??
                (data['pin_unreadable'] == true ? '읽을 수 없습니다.' : '미설정')),
        if (data['has_pin'] == true)
          TextField(
              controller: _currentPin,
              obscureText: true,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '현재 PIN'),
              onChanged: (_) {
                _dirty = true;
                _pinDirty = true;
              }),
        TextField(
            controller: _newPin,
            obscureText: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '새 PIN (숫자 4자리 이상)'),
            onChanged: (_) {
              _dirty = true;
              _pinDirty = true;
            }),
        FilledButton(
            onPressed: _busy
                ? null
                : () {
                    if (!RegExp(r'^\d{4,}$').hasMatch(_newPin.text)) {
                      _message('새 PIN은 숫자 4자리 이상으로 입력해 주세요.');
                      return;
                    }
                    _write('pin/change', {
                      'new_pin': _newPin.text,
                      if (data['has_pin'] == true)
                        'current_pin': _currentPin.text
                    });
                  },
            child: const Text('PIN 저장')),
      ]),
    ];
  }

  List<Widget> _benefits(Map<String, dynamic> data) {
    final choices = _rows(data['choices']);
    final requests = _rows(_extra['requests']);
    final stamp = _map(_extra['stamp']), config = _map(stamp['config_json']);
    return [
      _card(
          '현재 혜택',
          choices.isEmpty
              ? [
                  const PartnerEmpty('등록된 혜택이 없습니다.',
                      icon: Icons.card_giftcard_outlined)
                ]
              : choices
                  .map((b) => Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: PartnerDesign.tint,
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PartnerBadge(b['active'] == false ? '중단' : '운영 중',
                                color: b['active'] == false
                                    ? PartnerDesign.muted
                                    : PartnerDesign.green,
                                background: b['active'] == false
                                    ? const Color(0xFFF3F4F6)
                                    : const Color(0xFFECFDF5)),
                            const SizedBox(height: 8),
                            Text(_text(b['label']),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                          ])))
                  .toList()),
      _card('스탬프 규칙', [
        Text(stamp['exists'] == false
            ? '등록된 스탬프 규칙이 없습니다.'
            : stamp['active'] == false || config['stamp_enabled'] == false
                ? '스탬프를 사용하지 않습니다.'
                : '한 주기 ${_text(config['cycle_target'])}개'),
        if (stamp['exists'] != false &&
            stamp['active'] != false &&
            config['stamp_enabled'] != false &&
            config['cycle_target'] is int &&
            (config['cycle_target'] as int) > 0 &&
            (config['cycle_target'] as int) <= 40)
          Wrap(
              spacing: 7,
              runSpacing: 7,
              children: List.generate(config['cycle_target'] as int, (i) {
                final reward = _rows(config['thresholds'])
                    .any((t) => '${t['stamps']}' == '${i + 1}');
                return Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: reward
                            ? const Color(0xFFFBBF24)
                            : Colors.transparent,
                        border: Border.all(
                            color: reward
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFFCECEF4),
                            width: 1.5)),
                    child: ExcludeSemantics(
                        child: reward
                            ? const Icon(Icons.card_giftcard_outlined,
                                size: 16, color: PartnerDesign.amber)
                            : Text('${i + 1}',
                                textScaler: TextScaler.noScaling,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: PartnerDesign.periwinkle))));
              })),
        for (final t in _rows(config['thresholds']))
          _line(
              '${_text(t['stamps'])}개 보상',
              t['reward_text'] ??
                  choices
                      .where((b) => '${b['stamp_key']}' == '${t['stamps']}')
                      .firstOrNull?['title'] ??
                  t['coupon_type_code']),
      ]),
      _card(
          '신청 내역 · 검토 중 ${_text(_extra['pending'], '0')}건',
          requests.isEmpty
              ? [const PartnerEmpty('신청 내역이 없습니다.')]
              : requests
                  .map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _status(r['status']),
                                  Text(_text(r['created_at']),
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          color: PartnerDesign.muted)),
                                ]),
                            _line(_text(r['action_label']), r['benefit_label']),
                            _line('변경 전', r['before']),
                            _line('변경 후', r['after']),
                            if (_text(r['note'], '').isNotEmpty)
                              _line('요청 메모', r['note']),
                            if (_text(r['decision_note'], '').isNotEmpty)
                              _line('검토 메모', r['decision_note']),
                          ])))
                  .toList()),
      _card('혜택 변경 신청', [
        const Text('신청은 검토 후 반영됩니다. 현재 혜택은 바로 변경되지 않습니다.'),
        DropdownButtonFormField<String>(
            key: ValueKey('action:${widget.scope}:$_action'),
            decoration: const InputDecoration(labelText: '신청 종류'),
            isExpanded: true,
            initialValue: _action,
            items: const [
              DropdownMenuItem(value: 'EDIT', child: Text('문구 수정')),
              DropdownMenuItem(value: 'STOP', child: Text('중단')),
              DropdownMenuItem(value: 'RESUME', child: Text('재개')),
              DropdownMenuItem(value: 'OTHER', child: Text('기타 요청'))
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                      _action = v!;
                      _dirty = true;
                    })),
        if (_action != 'OTHER')
          DropdownButtonFormField<int>(
              key: ValueKey('benefit:${widget.scope}:$_benefitId'),
              initialValue: _benefitId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '변경할 혜택'),
              items: choices
                  .map((b) => DropdownMenuItem<int>(
                      value: b['id'] as int,
                      child: Text(_text(b['label']),
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                        _benefitId = v;
                        _dirty = true;
                      })),
        if (_action == 'EDIT') ...[
          TextField(
              controller: _title,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '새 혜택 제목'),
              onChanged: (_) => _dirty = true),
          TextField(
              controller: _subtitle,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '부제'),
              onChanged: (_) => _dirty = true),
          TextField(
              controller: _notes,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '이용 조건'),
              onChanged: (_) => _dirty = true),
        ],
        TextField(
            controller: _note,
            enabled: !_busy,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '요청 메모'),
            onChanged: (_) => _dirty = true),
        if (_uncertainRequest)
          TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await _load();
                      if (mounted && _data != null) {
                        setState(() => _uncertainRequest = false);
                      }
                    },
              child: const Text('재신청 전에 신청 내역 확인')),
        FilledButton(
            onPressed: _busy || _uncertainRequest
                ? null
                : () {
                    if ((_action != 'OTHER' && _benefitId == null) ||
                        (_action == 'EDIT' && _title.text.trim().isEmpty) ||
                        (_action == 'OTHER' && _note.text.trim().isEmpty)) {
                      _message('변경할 혜택과 내용을 입력해 주세요.');
                      return;
                    }
                    _write('benefit-requests', {
                      'action': _action,
                      if (_action != 'OTHER') 'benefit_id': _benefitId,
                      if (_action == 'EDIT') ...{
                        'title': _title.text.trim(),
                        'subtitle': _subtitle.text.trim(),
                        'notes': _notes.text.trim()
                      },
                      'note': _note.text.trim()
                    });
                  },
            child: const Text('변경 신청')),
      ]),
    ];
  }

  List<Widget> _reports(Map<String, dynamic> data) {
    final reports = _rows(data['reports']);
    return [
      _card('월간 리포트', [_reportState(_map(_extra['report_status']))]),
      _card(
          '받은 리포트',
          reports.isEmpty
              ? [
                  const PartnerEmpty('아직 공개된 리포트가 없습니다.',
                      icon: Icons.description_outlined)
                ]
              : reports
                  .map((r) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: PartnerDesign.tint,
                                borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.description_outlined,
                                size: 20, color: PartnerDesign.periwinkle)),
                        title: Text(_text(r['title'])),
                        subtitle: Text(
                            '${_text(r['sent_at'] ?? r['linked_at'] ?? r['created_at'])}\n${_text(r['summary'], '')}'),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: _busy
                            ? null
                            : () async {
                                final scope = widget.scope;
                                setState(() => _busy = true);
                                try {
                                  final opened = await widget
                                      .request('reports/${r['id']}/open');
                                  if (!mounted || widget.scope != scope) return;
                                  await PartnerReportLauncher.open(
                                      opened['url'] as String);
                                  await widget.access.check();
                                  if (mounted &&
                                      widget.scope == scope &&
                                      widget.access.isOwner) {
                                    await _load();
                                  }
                                } catch (_) {
                                  AnalyticsLogger.logEvent(
                                      AnalyticsEvents.partnerReportOpenFailed);
                                  _message('리포트를 열지 못했습니다. 목록을 새로고침해 주세요.');
                                } finally {
                                  if (mounted && widget.scope == scope) {
                                    setState(() => _busy = false);
                                  }
                                }
                              },
                      ))
                  .toList())
    ];
  }

  List<Widget> _plan(Map<String, dynamic> data) {
    final store = _map(data['store']), billing = _map(data['billing']);
    return [
      _card(
          '현재 계약',
          [
            Align(
                alignment: Alignment.centerLeft,
                child: PartnerBadge(_tierName(store['tier']))),
            _line('월 계약금액', _won(billing['monthly_fee'])),
            const Text('부가세 별도',
                style: TextStyle(fontSize: 11.5, color: PartnerDesign.muted)),
            _line('계약 종료일', store['contract_ends_on'])
          ],
          color: PartnerDesign.tint),
      ..._rows(data['plans']).map((p) {
        final current = p['id'] == store['tier'];
        final boost = p['id'] == 'BOOST', premium = p['id'] == 'CONTENT';
        final accent = premium
            ? PartnerDesign.periwinkle
            : boost
                ? const Color(0xFFD97706)
                : PartnerDesign.muted;
        return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: PartnerPanel(
              padding: const EdgeInsets.all(20),
              borderColor: current ? accent : accent.withValues(alpha: .18),
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: premium
                      ? const [Color(0xFFEEF2FF), Color(0xFFFAF5FF)]
                      : boost
                          ? const [Color(0xFFFFFBEB), Color(0xFFFFF7ED)]
                          : const [Color(0xFFF9FAFB), Color(0xFFF3F4F6)]),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: accent.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Icon(
                                  premium
                                      ? Icons.workspace_premium_outlined
                                      : boost
                                          ? Icons.bolt_outlined
                                          : Icons.eco_outlined,
                                  color: accent,
                                  size: 24)),
                          Text(_text(p['displayName']),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          if (current)
                            PartnerBadge('현재 이용 중',
                                color: Colors.white, background: accent),
                          if (boost)
                            const PartnerBadge('추천',
                                color: PartnerDesign.amber,
                                background: Color(0xFFFEF3C7)),
                        ]),
                    const SizedBox(height: 18),
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: _text(p['price']),
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w800)),
                      TextSpan(
                          text: ' ${_text(p['priceSub'], '')} · 기준 가격',
                          style: const TextStyle(
                              fontSize: 11.5, color: PartnerDesign.muted)),
                    ])),
                    Divider(color: accent.withValues(alpha: .18)),
                    ..._rows(p['features']).map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Icon(Icons.check,
                                      size: 16, color: accent)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(_text(f['text']),
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: f['bold'] == true
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: f['bold'] == true
                                              ? PartnerDesign.ink
                                              : PartnerDesign.muted))),
                            ]))),
                  ]),
            ));
      }),
      _card('플랜 변경 안내', [
        const Text('실제 계약금액은 현재 계약을 기준으로 합니다. 변경은 담당자에게 문의해 주세요.',
            style: TextStyle(fontSize: 12, color: PartnerDesign.muted))
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) =>
      Theme(data: PartnerDesign.theme, child: Builder(builder: _buildPage));

  Widget _buildPage(BuildContext context) {
    if (_data == null) {
      return ColoredBox(
          color: PartnerDesign.background,
          child: Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cloud_off_outlined,
                            size: 36, color: PartnerDesign.periwinkle),
                        const SizedBox(height: 14),
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _load();
                            },
                            child: const Text('다시 시도'))
                      ]))));
    }
    final data = _data!;
    final content = switch (widget.tab) {
      0 => _home(data),
      1 => _restaurant(data),
      2 => _benefits(data),
      3 => [_card('콘텐츠 · 운영 기록', _feed(data))],
      4 => _reports(data),
      _ => _plan(data)
    };
    const titles = ['', '식당 관리', '혜택 관리', '콘텐츠', '리포트', '이용 플랜'];
    const descriptions = [
      '',
      '손님에게 보이는 매장 정보와 사진을 관리해 주세요.',
      '쿠폰·스탬프 혜택을 확인하고 변경을 신청하세요.',
      '우리 매장을 위해 진행한 콘텐츠와 캠페인입니다.',
      '매달 한 장으로 정리한 우리 매장의 활동과 변화를 확인하세요.',
      '우리 매장에 맞는 플랜과 계약 정보를 확인하세요.'
    ];
    return ColoredBox(
        color: PartnerDesign.background,
        child: Column(children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
              child: RefreshIndicator(
            onRefresh: () async {
              if (!_busy && await confirmDiscard()) {
                _dirty = false;
                _restaurantDirty = false;
                _pinDirty = false;
                await _load();
              }
            },
            child: LayoutBuilder(
                builder: (context, box) => ListView(
                        padding: EdgeInsets.symmetric(
                            vertical: 20,
                            horizontal: box.maxWidth > 800
                                ? (box.maxWidth - 768) / 2
                                : 16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          if (widget.tab != 0)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(titles[widget.tab],
                                          style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              color: PartnerDesign.navy)),
                                      const SizedBox(height: 6),
                                      Text(descriptions[widget.tab],
                                          style: const TextStyle(
                                              fontSize: 12.5,
                                              color: PartnerDesign.muted)),
                                    ])),
                          ...content,
                        ])),
          ))
        ]));
  }
}
