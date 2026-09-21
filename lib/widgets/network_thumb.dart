import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 목록용 네트워크 썸네일.
///
/// 서버는 S3 원본 URL만 내려주고 리사이징·CDN이 없다. 그래서 그냥 [Image.network]로
/// 그리면 표시 크기가 86px여도 원본 해상도를 통째로 디코딩한다. 목록에서는 이
/// 디코딩 비용이 스크롤 버벅임의 주된 원인이라, 표시 크기에 맞춰 디코딩하도록
/// [cacheWidth]를 지정한다. 같은 URL은 Flutter 이미지 캐시가 재사용한다.
class NetworkThumb extends StatelessWidget {
  const NetworkThumb({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.borderRadius,
    this.fallbackIcon = Icons.storefront_rounded,
  });

  final String? url;

  /// 논리 픽셀 기준 표시 크기. 디코딩 해상도를 여기에 맞춘다.
  final double width;
  final double height;

  final BorderRadius? borderRadius;
  final IconData fallbackIcon;

  static const _placeholder = Color(0xFFF1F2F5);
  static const _iconColor = Color(0xFFAEB4C0);

  bool get _hasUrl {
    final v = url?.trim();
    if (v == null || v.isEmpty) return false;
    final uri = Uri.tryParse(v);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      width: width,
      height: height,
      child: _hasUrl ? _buildImage(context) : _buildFallback(),
    );
    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }

  Widget _buildImage(BuildContext context) {
    // 기기 배율까지 반영해야 레티나에서 뭉개지지 않는다.
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ??
        ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final decodeWidth = (width * ratio).round();

    return Image.network(
      url!.trim(),
      fit: BoxFit.cover,
      width: width,
      height: height,
      cacheWidth: decodeWidth > 0 ? decodeWidth : null,
      // 디코딩이 끝나기 전에는 회색 판을 보여준다. 카드마다 스피너가 돌면
      // 목록이 산만해지므로 스켈레톤 톤을 유지한다.
      frameBuilder: (context, child, frame, wasSyncLoaded) {
        if (wasSyncLoaded || frame != null) {
          return AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 160),
            child: child,
          );
        }
        return _buildSkeleton();
      },
      errorBuilder: (_, __, ___) => _buildFallback(),
    );
  }

  Widget _buildSkeleton() => const ColoredBox(color: _placeholder);

  Widget _buildFallback() => ColoredBox(
        color: _placeholder,
        child: Center(
          child: Icon(fallbackIcon, size: width * 0.35, color: _iconColor),
        ),
      );
}
