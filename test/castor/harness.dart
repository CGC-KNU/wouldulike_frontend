// Castor 화면 캡처용 테스트 하네스.
//
// - 네트워크: dart:io HttpOverrides 로 가짜 HttpClient 를 꽂는다. package:http(IOClient)와
//   Image.network 가 모두 이 클라이언트를 거치므로, API 는 [FakeBackend] 가 가짜 JSON 을,
//   이미지 주소는 테스트에서 그린 음식 사진(가짜)을 돌려준다. 실제 서버로는 아무것도 나가지 않는다.
// - 글꼴: Pretendard 전 굵기 + Material/Cupertino 아이콘을 실제 파일에서 읽어 글자가 네모로 안 나오게 한다.
// - 캡처: 앱 전체(다이얼로그 · 시트 포함)를 RepaintBoundary 로 감싸 PNG 로 쓴다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 캡처 크기 — iPhone 14/15 논리 크기 390x844. PNG 는 2배(780x1688)로 쓴다.
const Size kPhoneLogicalSize = Size(390, 844);
const double kCapturePixelRatio = 2.0;

/// PNG 가 쌓이는 폴더. CI 는 CASTOR_SHOTS_DIR 로 바꾼다.
String get castorShotsDir =>
    Platform.environment['CASTOR_SHOTS_DIR'] ?? 'build/castor_shots';

// ───────────────────────────── 글꼴 ─────────────────────────────

Future<void> loadCastorFonts() async {
  final pretendard = FontLoader('Pretendard');
  for (final w in const [
    'Thin',
    'ExtraLight',
    'Light',
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
    'Black',
  ]) {
    pretendard.addFont(_fileBytes('assets/fonts/Pretendard-$w.ttf'));
  }
  await pretendard.load();

  final alkatra = FontLoader('Alkatra');
  for (final w in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    alkatra.addFont(_fileBytes('assets/fonts/Alkatra-$w.ttf'));
  }
  await alkatra.load();

  // 테스트 기본 글꼴(Ahem)은 네모로 그린다. 글꼴을 따로 지정하지 않은 Text 도
  // 한글로 보이게 Roboto 자리에 Pretendard 를 한 번 더 올린다.
  for (final family in const ['Roboto', 'FlutterTest', 'Ahem', 'sans-serif', 'Arial', 'Helvetica', 'system-ui', '.SF UI Text', '.SF Pro Text', 'Noto Sans KR']) {
    final l = FontLoader(family)
      ..addFont(_fileBytes('assets/fonts/Pretendard-Regular.ttf'))
      ..addFont(_fileBytes('assets/fonts/Pretendard-Medium.ttf'))
      ..addFont(_fileBytes('assets/fonts/Pretendard-SemiBold.ttf'))
      ..addFont(_fileBytes('assets/fonts/Pretendard-Bold.ttf'));
    await l.load();
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final material = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (material.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(_fileBytes(material.path)))
          .load();
    }
  }
  // cupertino_icons 패키지 글꼴
  final cupertino = _findPackageFile('cupertino_icons', 'assets/CupertinoIcons.ttf');
  if (cupertino != null) {
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')
          ..addFont(_fileBytes(cupertino)))
        .load();
  }
}

Future<ByteData> _fileBytes(String path) async =>
    ByteData.sublistView(File(path).readAsBytesSync());

String? _findPackageFile(String package, String rel) {
  final cfg = File('.dart_tool/package_config.json');
  if (!cfg.existsSync()) return null;
  final json = jsonDecode(cfg.readAsStringSync()) as Map<String, dynamic>;
  for (final p in (json['packages'] as List).cast<Map<String, dynamic>>()) {
    if (p['name'] == package) {
      var root = p['rootUri'] as String;
      final uri = root.startsWith('file:')
          ? Uri.parse(root)
          : Uri.parse('file://${Directory('.dart_tool').absolute.path}/').resolve(root);
      final f = File('${uri.toFilePath()}/$rel'.replaceAll('//', '/'));
      if (f.existsSync()) return f.path;
    }
  }
  return null;
}

// ───────────────────────────── 가짜 사진 ─────────────────────────────

/// 가짜 음식 사진들(PNG 바이트). setUpAll 에서 한 번 만든다.
final List<Uint8List> fakePhotos = [];

Future<void> buildFakePhotos() async {
  if (fakePhotos.isNotEmpty) return;
  Future<ui.Image> decode(String path) async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    return (await codec.getNextFrame()).image;
  }

  const icons = [
    'korean', 'chinese', 'japanese', 'western', 'donkatsu', 'hamburger',
    'cafe', 'pub', 'snack', 'total',
  ];
  const bgs = [
    Color(0xFFFFE6CC), Color(0xFFE3F2E6), Color(0xFFE0EAFB), Color(0xFFFBE3E8),
    Color(0xFFF5EEDB), Color(0xFFEAE4F8), Color(0xFFFFF0D9), Color(0xFFDDF2F2),
    Color(0xFFF8E6DA), Color(0xFFEFEFEF),
  ];
  const w = 640.0, h = 480.0;
  final pizza = await decode('assets/images/food1.png');
  // 실제 사진(피자) 크롭 3장
  for (final src in const [
    Rect.fromLTWH(0, 0, 1280, 855),
    Rect.fromLTWH(300, 60, 880, 660),
    Rect.fromLTWH(40, 300, 860, 555),
  ]) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImageRect(pizza, src, const Rect.fromLTWH(0, 0, w, h),
        Paint()..filterQuality = FilterQuality.high);
    fakePhotos.add(await _toPng(rec, w, h));
  }
  // 음식 일러스트 + 접시
  for (var i = 0; i < icons.length; i++) {
    final icon = await decode('assets/images/${icons[i]}.png');
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final bg = bgs[i];
    c.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(w, h),
          [bg, Color.lerp(bg, Colors.black, 0.08)!],
        ),
    );
    for (var y = 0.0; y < h; y += 64) {
      c.drawRect(Rect.fromLTWH(0, y, w, 26),
          Paint()..color = Colors.white.withValues(alpha: 0.18));
    }
    c.drawCircle(const Offset(w / 2 + 6, h / 2 + 10), 172,
        Paint()..color = Colors.black.withValues(alpha: 0.06));
    c.drawCircle(const Offset(w / 2, h / 2), 170, Paint()..color = Colors.white);
    c.drawCircle(const Offset(w / 2, h / 2), 138,
        Paint()
          ..color = const Color(0xFFF2F2F2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    final s = 200 / math.max(icon.width, icon.height);
    final dw = icon.width * s, dh = icon.height * s;
    c.drawImageRect(
      icon,
      Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
      Rect.fromLTWH((w - dw) / 2, (h - dh) / 2, dw, dh),
      Paint()..filterQuality = FilterQuality.high,
    );
    fakePhotos.add(await _toPng(rec, w, h));
  }
}

Future<Uint8List> _toPng(ui.PictureRecorder rec, double w, double h) async {
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// 주소에 음식 종류 낱말(korean · pizza …)이 있으면 그 사진, 없으면 주소 해시로 고른다.
Uint8List photoFor(Uri url) {
  final s = url.toString();
  var hsh = 0;
  for (final c in s.codeUnits) {
    hsh = (hsh * 31 + c) & 0x7fffffff;
  }
  if (s.contains('pizza')) return fakePhotos[hsh % 3];
  const kinds = [
    'korean', 'chinese', 'japanese', 'western', 'donkatsu', 'hamburger',
    'cafe', 'pub', 'snack', 'total',
  ];
  for (var i = 0; i < kinds.length; i++) {
    if (s.contains(kinds[i])) return fakePhotos[3 + i];
  }
  return fakePhotos[hsh % fakePhotos.length];
}

// ───────────────────────────── 가짜 백엔드 ─────────────────────────────

class FakeResponse {
  FakeResponse(this.status, this.body, {this.contentType = 'application/json; charset=utf-8'});
  FakeResponse.json(Object? data, {int status = 200})
      : this(status, Uint8List.fromList(utf8.encode(jsonEncode(data))));
  /// 영원히 끝나지 않는 응답 — 로딩 화면(스플래시)을 고정할 때.
  FakeResponse.hang() : this(-1, Uint8List(0));
  bool get hangs => status == -1;
  final int status;
  final Uint8List body;
  final String contentType;
}

typedef FakeRoute = Object? Function(FakeRequestInfo req);

class FakeRequestInfo {
  FakeRequestInfo(this.method, this.uri, this.body);
  final String method;
  final Uri uri;
  final String body;
  Map<String, dynamic> get jsonBody {
    try {
      return (jsonDecode(body) as Map).cast<String, dynamic>();
    } catch (_) {
      return const {};
    }
  }
}

/// 경로(쿼리 제외) → 응답. 키는 정확한 경로 또는 RegExp.
/// 응답이 [FakeResponse] 면 그대로, 아니면 JSON 200 으로 보낸다.
class FakeBackend {
  static final Map<Pattern, FakeRoute> routes = {};
  static final List<String> log = [];
  static final Set<String> misses = {};

  static void reset() {
    routes.clear();
    log.clear();
    misses.clear();
  }

  static FakeResponse handle(String method, Uri uri, String body) {
    final path = uri.path;
    log.add('$method $path${uri.hasQuery ? '?${uri.query}' : ''}');
    if (_isImage(uri)) {
      return FakeResponse(200, photoFor(uri), contentType: 'image/png');
    }
    for (final e in routes.entries) {
      final k = e.key;
      final hit = k is String
          ? (k == path || '$method $path' == k)
          : (k as RegExp).hasMatch('$method $path');
      if (hit) {
        final r = e.value(FakeRequestInfo(method, uri, body));
        if (r is FakeResponse) return r;
        return FakeResponse.json(r);
      }
    }
    misses.add('$method $path');
    // 모르는 API 는 404 — 화면은 '빈 상태'로 그린다.
    return FakeResponse.json({'detail': 'not found (castor fake)'}, status: 404);
  }

  static bool _isImage(Uri uri) {
    final p = uri.path.toLowerCase();
    return p.endsWith('.png') ||
        p.endsWith('.jpg') ||
        p.endsWith('.jpeg') ||
        p.endsWith('.webp') ||
        p.endsWith('.gif') ||
        uri.host.contains('s3.') ||
        uri.host.contains('images') ||
        uri.host.contains('img');
  }
}

class CastorHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpRequest(method, url);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpRequest implements HttpClientRequest {
  _FakeHttpRequest(this.method, this.uri);
  @override
  final String method;
  @override
  final Uri uri;
  final _body = BytesBuilder();
  final _headers = _FakeHeaders();
  final _done = Completer<HttpClientResponse>();

  @override
  HttpHeaders get headers => _headers;
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  bool persistentConnection = true;
  @override
  bool bufferOutput = true;
  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => _body.add(data);
  @override
  void write(Object? object) => _body.add(utf8.encode('$object'));
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final c in stream) {
      _body.add(c);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    if (!_done.isCompleted) {
      final r = FakeBackend.handle(method, uri, utf8.decode(_body.toBytes(), allowMalformed: true));
      if (r.hangs) return Completer<HttpClientResponse>().future;
      _done.complete(_FakeHttpResponse(r));
    }
    return _done.future;
  }

  @override
  Future<HttpClientResponse> get done => _done.future;
  @override
  Future<void> flush() async {}
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeHttpResponse(this._r)
      : _headers = _FakeHeaders()..set(HttpHeaders.contentTypeHeader, _r.contentType);
  final FakeResponse _r;
  final _FakeHeaders _headers;

  @override
  int get statusCode => _r.status;
  @override
  String get reasonPhrase => _r.status == 200 ? 'OK' : 'ERR';
  @override
  int get contentLength => _r.body.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  HttpHeaders get headers => _headers;
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  bool get persistentConnection => false;
  @override
  List<Cookie> get cookies => const [];

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(_r.body).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  final Map<String, List<String>> _m = {};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _m[name.toLowerCase()] = ['$value'];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      (_m[name.toLowerCase()] ??= []).add('$value');
  @override
  String? value(String name) => _m[name.toLowerCase()]?.first;
  @override
  List<String>? operator [](String name) => _m[name.toLowerCase()];
  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _m.forEach(action);
  @override
  ContentType? get contentType {
    final v = value(HttpHeaders.contentTypeHeader);
    return v == null ? null : ContentType.parse(v);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ───────────────────────────── 화면 띄우기 · 캡처 ─────────────────────────────

final GlobalKey castorBoundaryKey = GlobalKey(debugLabel: 'castor-boundary');

void setPhone(WidgetTester tester) {
  tester.view.physicalSize = kPhoneLogicalSize * 3;
  tester.view.devicePixelRatio = 3;
  // iPhone 노치 · 홈 인디케이터 자리(논리 47 / 34pt)
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  tester.platformDispatcher.textScaleFactorTestValue = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

/// 앱과 같은 테마로 감싼다(lib/main.dart MaterialApp 과 맞춤).
Widget castorApp({
  Widget? home,
  Map<String, WidgetBuilder>? routes,
  String? initialRoute,
  ThemeData? theme,
  List<NavigatorObserver> observers = const [],
}) {
  return RepaintBoundary(
    key: castorBoundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ??
          ThemeData(
            fontFamily: 'Pretendard',
            scaffoldBackgroundColor: Colors.white,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF312E81)),
          ),
      home: home,
      routes: routes ?? const {},
      initialRoute: initialRoute,
      navigatorObservers: observers,
      locale: const Locale('ko', 'KR'),
    ),
  );
}

/// 이미지(에셋 · 네트워크)를 실제로 디코딩시킨 뒤 몇 프레임 흘린다.
Future<void> settleImages(WidgetTester tester, {int rounds = 3}) async {
  for (var r = 0; r < rounds; r++) {
    final providers = <ImageProvider>{};
    for (final e in find.byType(Image, skipOffstage: false).evaluate()) {
      providers.add((e.widget as Image).image);
    }
    for (final e in find.byType(DecoratedBox, skipOffstage: false).evaluate()) {
      final d = (e.widget as DecoratedBox).decoration;
      if (d is BoxDecoration && d.image != null) providers.add(d.image!.image);
    }
    for (final e in find.byType(Container, skipOffstage: false).evaluate()) {
      final d = (e.widget as Container).decoration;
      if (d is BoxDecoration && d.image != null) providers.add(d.image!.image);
    }
    for (final e in find.byType(CircleAvatar, skipOffstage: false).evaluate()) {
      final w = e.widget as CircleAvatar;
      if (w.backgroundImage != null) providers.add(w.backgroundImage!);
    }
    if (providers.isEmpty) return;
    final ctx = tester.element(find.byKey(castorBoundaryKey));
    await tester.runAsync(() async {
      for (final p in providers) {
        try {
          await precacheImage(p, ctx, onError: (_, __) {})
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
    });
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// [pumps] 만큼 시간을 흘리며 로딩을 끝낸다(무한 애니메이션이 있어 pumpAndSettle 을 쓰지 않는다).
Future<void> letItLoad(WidgetTester tester,
    {Duration total = const Duration(seconds: 3), int steps = 12}) async {
  final step = Duration(microseconds: total.inMicroseconds ~/ steps);
  for (var i = 0; i < steps; i++) {
    await tester.pump(step);
  }
  // 실제 비동기(파일 · 디코딩)가 끼어 있으면 한 번 풀어 준다.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(milliseconds: 100));
}

/// 앱 전체를 PNG 로 쓴다 — 파일 이름 = Castor 화면 ID.
Future<File> captureScreen(WidgetTester tester, String screenId) async {
  await settleImages(tester);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(castorBoundaryKey));
  final dir = Directory(castorShotsDir)..createSync(recursive: true);
  final file = File('${dir.path}/$screenId.png');
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: kCapturePixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  return file;
}
