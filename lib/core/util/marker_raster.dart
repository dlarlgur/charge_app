import 'dart:convert' show utf8;
import 'dart:io' show Directory, File;
import 'dart:ui' show ImageByteFormat;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        PipelineOwner,
        RenderPositionedBox,
        RenderRepaintBoundary,
        RenderView,
        ViewConfiguration;
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;

/// NOverlayImage.fromWidget/fromByteArray 대체 (플러그인 1.4.4 결함 2개 우회):
/// 1) 플러그인 래스터는 toImage() 의 ui.Image 를 dispose 하지 않아 마커를 만들
///    때마다 네이티브 이미지가 누적된다 (지도 세션 PSS 1GB+ 팅김 근본 원인).
/// 2) 플러그인 ImageUtil 은 첫 저장 때 임시폴더를 lock 없이 초기화해, 동시
///    호출이 서로의 폴더를 지우는 레이스가 있다 (첫 실행에서 클러스터 원이
///    빈 채로 뜨던 증상 + 시작 직후 PathNotFoundException 2건, 2026-08-19).
/// 여기서는 dispose 를 보장하고, 파일도 우리 전용 폴더에 직접 저장해
/// NOverlayImage.fromFile 로 넘긴다 — 플러그인 ImageUtil 경로를 아예 안 탄다.
class MarkerRaster {
  MarkerRaster._();

  // Future 를 메모이즈해 동시 첫 호출도 초기화를 정확히 1번만 타게 한다
  // (플러그인 레이스의 원인이던 check-then-act 를 제거).
  static Future<Directory>? _dirFuture;

  static Future<Directory> _imageDir() =>
      _dirFuture ??= _initDir();

  static Future<Directory> _initDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/marker_raster');
    // 이전 세션 파일 제거 — 앱 업데이트로 배지 디자인이 바뀌어도 stale 이미지가
    // 재사용되지 않게 세션마다 새로 그린다. (단일 초기화라 삭제 레이스 없음)
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    return dir;
  }

  // 이번 세션에 이미 저장한 파일 키 — 파일 존재 확인 IO 없이 재사용 판단.
  static final Set<String> _written = {};

  /// 위젯을 래스터해 지도 오버레이 이미지로. 같은 [cacheKey] 는 같은 파일을
  /// 재사용한다(이번 세션 한정). cacheKey 가 없으면 PNG 바이트 해시로 중복 제거.
  static Future<NOverlayImage> overlayImage({
    required Widget widget,
    required Size size,
    required BuildContext context,
    String? cacheKey,
  }) async {
    final dir = await _imageDir();
    if (cacheKey != null) {
      final name = sha256.convert(utf8.encode(cacheKey)).toString();
      final file = File('${dir.path}/$name.png');
      if (_written.contains(name)) return NOverlayImage.fromFile(file);
      final bytes =
          await _widgetToPngBytes(widget, size: size, context: context);
      await file.writeAsBytes(bytes, flush: true);
      _written.add(name);
      return NOverlayImage.fromFile(file);
    }
    final bytes = await _widgetToPngBytes(widget, size: size, context: context);
    final name = sha256.convert(bytes).toString();
    final file = File('${dir.path}/$name.png');
    if (!_written.contains(name)) {
      await file.writeAsBytes(bytes, flush: true);
      _written.add(name);
    }
    return NOverlayImage.fromFile(file);
  }

  // 플러그인 WidgetToImageUtil.widgetToImageByte 와 동일 파이프라인 + image.dispose().
  static Future<Uint8List> _widgetToPngBytes(
    Widget widget, {
    required Size size,
    required BuildContext context,
  }) async {
    final renderBox = RenderRepaintBoundary();
    final view = View.of(context);

    final renderPositionedBox =
        RenderPositionedBox(alignment: Alignment.center, child: renderBox);
    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(size),
        devicePixelRatio: view.devicePixelRatio,
      ),
      child: renderPositionedBox,
    );

    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();

    final buildOwner = BuildOwner(focusManager: FocusManager());
    final rootElement = RenderObjectToWidgetAdapter(
      container: renderBox,
      child: MediaQuery(
        data: MediaQueryData.fromView(view),
        child: Theme(
          data: Theme.of(context),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
                width: size.width, height: size.height, child: widget),
          ),
        ),
      ),
    ).attachToRenderTree(buildOwner);
    buildOwner
      ..buildScope(rootElement)
      ..finalizeTree();

    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    try {
      final image = await renderBox.toImage(pixelRatio: view.devicePixelRatio);
      try {
        final byteData = await image.toByteData(format: ImageByteFormat.png);
        return byteData!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      final emptyRenderToWidgetAdapter =
          RenderObjectToWidgetAdapter(container: renderBox);
      rootElement.update(emptyRenderToWidgetAdapter); // renderbox child = null
      buildOwner.finalizeTree();
      renderView
        ..detach()
        ..dispose();
      rootElement
        ..detachRenderObject()
        // ignore: invalid_use_of_visible_for_overriding_member — 플러그인 원본과 동일한 offscreen 트리 해체 순서
        ..deactivate();
      buildOwner.finalizeTree();
    }
  }
}
