// ═══════════════════════════════════════════════════════════════
// utils/camera_image_utils.dart — 카메라 영상 변환 도우미
// ═══════════════════════════════════════════════════════════════
// 담당: A   |   우선: P0
// 수업 원본: (없음, 🔴 신규) google_mlkit_commons 공식 예제
//
// [이 파일이 하는 일]
//   - CameraImage → InputImage (ML Kit 에 넣는 모양). Android(nv21) 먼저, iOS(bgra8888) 는 나중
//   - CameraImage → jpg (image 패키지) — 졸음 의심 때만 호출 (매 프레임 변환하면 느림)
//
// [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
//   - toInputImage(CameraImage image, CameraDescription camera) → InputImage?
//   - toJpg(CameraImage image, {rotation}) → Uint8List? (nv21 · yuv420 · bgra8888, 실패하면 null)
//
// [주의]
//   - 학생들이 가장 많이 막히는 곳 — 공식 예제 코드를 그대로 가져다 쓴다
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class CameraImageUtils {
  /// CameraImage -> ML Kit InputImage 변환 (Android NV21 / YUV420 대응)
  static InputImage? toInputImage(CameraImage image, CameraDescription camera) {
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    // Android 단일 평면(NV21)인 경우 바로 사용, 다중 평면(YUV_420_888)인 경우 NV21 바이트로 병합
    //   → drive_screen 은 CameraController(imageFormatGroup: ImageFormatGroup.nv21) 로 열기 (공식 예제, 변환 없음)
    final bool merged = Platform.isAndroid && image.planes.length > 1;
    final Uint8List bytes = merged ? _yuv420ToNv21(image) : image.planes.first.bytes;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: Platform.isAndroid
            ? InputImageFormat.nv21
            : (format ?? InputImageFormat.bgra8888),
        // 병합한 NV21 은 줄 사이 여백 없이 width 바이트씩 채웠으므로 width (원래 줄 간격을 쓰면 화면이 깨짐)
        bytesPerRow: merged ? image.width : image.planes.first.bytesPerRow,
      ),
    );
  }

  /// Android YUV_420_888 (3 planes) -> NV21 (단일 바이트 배열) 변환
  static Uint8List _yuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final Uint8List nv21 = Uint8List(width * height + (width * height ~/ 2));
    int index = 0;

    // Y 평면 복사
    for (int row = 0; row < height; row++) {
      final int rowStart = row * yPlane.bytesPerRow;
      nv21.setRange(index, index + width, yPlane.bytes, rowStart);
      index += width;
    }

    // VU 교차 복사 (NV21 포맷)
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;
    final int uvWidth = width ~/ 2;
    final int uvHeight = height ~/ 2;

    for (int row = 0; row < uvHeight; row++) {
      for (int col = 0; col < uvWidth; col++) {
        final int uvOffset = row * uvRowStride + col * uvPixelStride;
        nv21[index++] = vPlane.bytes[uvOffset];
        nv21[index++] = uPlane.bytes[uvOffset];
      }
    }
    return nv21;
  }

  /// 의심 순간에만 호출: CameraImage -> JPG Uint8List 변환 (전면 카메라 회전 보정 포함)
  static Uint8List? toJpg(CameraImage image, {int rotation = 270}) {
    try {
      img.Image? converted;
      if (image.format.group == ImageFormatGroup.nv21) {
        converted = _convertNV21ToImage(image);
      } else if (image.format.group == ImageFormatGroup.yuv420) {
        converted = _convertYUV420ToImage(image);
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        converted = img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: image.planes[0].bytes.buffer,
          order: img.ChannelOrder.bgra,
        );
      }
      if (converted == null) return null;

      if (rotation != 0) {
        converted = img.copyRotate(converted, angle: rotation);
      }
      return Uint8List.fromList(img.encodeJpg(converted, quality: 85));
    } catch (e) {
      return null;
    }
  }

  /// NV21 (평면 1개: Y 전체 → V · U 교차) -> RGB 이미지
  static img.Image _convertNV21ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final Uint8List bytes = image.planes.first.bytes;
    final int stride = image.planes.first.bytesPerRow;
    final int uvStart = stride * height;

    final outImg = img.Image(width: width, height: height);
    for (int y = 0; y < height; y++) {
      final int uvRow = uvStart + (y ~/ 2) * stride;
      for (int x = 0; x < width; x++) {
        final int yp = bytes[y * stride + x];
        final int uvIndex = uvRow + (x & ~1);
        final int vp = uvIndex + 1 < bytes.length ? bytes[uvIndex] : 128;
        final int up = uvIndex + 1 < bytes.length ? bytes[uvIndex + 1] : 128;
        outImg.setPixelRgb(x, y, _r(yp, vp), _g(yp, up, vp), _b(yp, up));
      }
    }
    return outImg;
  }

  static int _r(int y, int v) => (y + 1.402 * (v - 128)).round().clamp(0, 255);
  static int _g(int y, int u, int v) =>
      (y - 0.344136 * (u - 128) - 0.714136 * (v - 128)).round().clamp(0, 255);
  static int _b(int y, int u) => (y + 1.772 * (u - 128)).round().clamp(0, 255);

  static img.Image _convertYUV420ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes.length > 1 ? image.planes[1] : null;
    final vPlane = image.planes.length > 2 ? image.planes[2] : null;

    final outImg = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * yPlane.bytesPerRow + x;
        final int yp = yPlane.bytes[yIndex];

        int up = 128;
        int vp = 128;
        if (uPlane != null && vPlane != null) {
          final int uvPixelStride = uPlane.bytesPerPixel ?? 1;
          final int uvIndex =
              (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2) * uvPixelStride;
          up = uPlane.bytes[uvIndex];
          vp = vPlane.bytes[uvIndex];
        }

        outImg.setPixelRgb(x, y, _r(yp, vp), _g(yp, up, vp), _b(yp, up));
      }
    }
    return outImg;
  }
}