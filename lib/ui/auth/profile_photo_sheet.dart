import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/util/app_toast.dart';
import '../../data/services/api_service.dart';

/// 프로필 사진 등록 — 카카오톡처럼 '고르고 → 원 안에 맞추고 → 저장'.
///
/// 크롭 패키지를 새로 넣지 않고 InteractiveViewer + RepaintBoundary 로 처리한다.
/// (패키지 추가는 iOS/안드로이드 네이티브 설정까지 건드려야 해서 이 기능엔 과하다)
///
/// 반환: 업로드된 URL('/api/uploads/...'), 기본이미지 선택 시 '', 취소면 null.
Future<String?> pickProfilePhoto(BuildContext context,
    {required bool hasPhoto}) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _SourceSheet(hasPhoto: hasPhoto),
  );
  if (source == null) return null;
  if (source == 'reset') return '';

  // 원본 그대로 다루면 큰 사진에서 메모리가 튄다 — 긴 변 1440 으로 먼저 줄인다.
  final XFile? picked = await ImagePicker().pickImage(
    source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1440,
    maxHeight: 1440,
    imageQuality: 92,
  );
  if (picked == null || !context.mounted) return null;

  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _CropScreen(file: File(picked.path)),
    ),
  );
}

/// 소스 선택 시트 — 앨범 / 카메라 / (사진 있으면) 기본 이미지로 변경.
class _SourceSheet extends StatelessWidget {
  final bool hasPhoto;
  const _SourceSheet({required this.hasPhoto});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF14161B) : Colors.white;
    final ink = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    Widget item(IconData icon, String label, String value, {Color? color}) =>
        InkWell(
          onTap: () => Navigator.of(context).pop(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(children: [
              Icon(icon, size: 21, color: color ?? ink),
              const SizedBox(width: 14),
              Text(label,
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: color ?? ink)),
            ]),
          ),
        );

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
            color: card, borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('프로필 사진',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: muted)),
            ),
          ),
          item(Icons.photo_library_rounded, '앨범에서 선택', 'gallery'),
          Divider(height: 1, color: muted.withValues(alpha: 0.15)),
          item(Icons.photo_camera_rounded, '카메라로 촬영', 'camera'),
          if (hasPhoto) ...[
            Divider(height: 1, color: muted.withValues(alpha: 0.15)),
            item(Icons.person_rounded, '기본 이미지로 변경', 'reset',
                color: const Color(0xFFDC2626)),
          ],
        ]),
      ),
    );
  }
}

/// 원형 크롭 — 사진을 옮기고 확대해서 원 안에 맞춘다.
class _CropScreen extends StatefulWidget {
  final File file;
  const _CropScreen({required this.file});

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  final _boundaryKey = GlobalKey();
  final _controller = TransformationController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final ctx = _boundaryKey.currentContext!;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final box = ctx.size!;
      // 결과는 512px 정사각 — 표시(최대 64dp)에 충분하고 업로드도 가볍다.
      final image = await boundary.toImage(pixelRatio: 512 / box.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw Exception('encode failed');

      final url = await ApiService()
          .uploadProfilePhotoBytes(data.buffer.asUint8List());
      if (!mounted) return;
      if (url == null) {
        setState(() => _saving = false);
        showAppToast(context, '사진 업로드에 실패했어요', isError: true);
        return;
      }
      Navigator.of(context).pop(url);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, '사진을 처리하지 못했어요', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.of(context).size.width - 48; // 원형 뷰포트 한 변

    return Scaffold(
      backgroundColor: const Color(0xFF0C0E13),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('프로필 사진',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
      body: Column(children: [
        const Spacer(),
        // 캡처 대상은 정사각 — 원형 마스크는 어디가 잘리는지 보여주는 안내다.
        Center(
          child: SizedBox(
            width: view,
            height: view,
            child: Stack(children: [
              RepaintBoundary(
                key: _boundaryKey,
                child: SizedBox(
                  width: view,
                  height: view,
                  child: InteractiveViewer(
                    transformationController: _controller,
                    minScale: 1,
                    maxScale: 5,
                    clipBehavior: Clip.hardEdge,
                    child: Image.file(widget.file,
                        width: view, height: view, fit: BoxFit.cover),
                  ),
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                    size: Size(view, view), painter: _CircleMaskPainter()),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        const Text('손가락으로 옮기고, 두 손가락으로 확대할 수 있어요',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8))),
        const Spacer(),
        Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.of(context).padding.bottom + 20),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('이 사진으로 설정',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 정사각 영역에서 원 밖만 어둡게 + 원 테두리.
class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final circle = Path()
      ..addOval(Rect.fromCircle(
          center: size.center(Offset.zero), radius: size.width / 2));
    final outside = Path.combine(PathOperation.difference,
        Path()..addRect(Offset.zero & size), circle);
    canvas.drawPath(
        outside, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawPath(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_CircleMaskPainter oldDelegate) => false;
}
