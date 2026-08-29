import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:meta/meta.dart';

/// Result of validating a profile photo.
class FaceCheckResult {
  const FaceCheckResult._(this.ok, this.message);

  const FaceCheckResult.valid() : this._(true, null);
  const FaceCheckResult.invalid(String message) : this._(false, message);

  final bool ok;
  final String? message;
}

/// Detects human faces in a profile photo using on-device ML Kit so
/// drivers cannot set joke images (landscapes, memes, group shots, ...).
class FaceDetectionService {
  FaceDetectionService._();

  /// A face must span at least 15% of the image's smaller dimension to
  /// count as "clearly visible" — rejects distant group photos.
  static const double _minFaceSizeRatio = 0.15;

  static final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: _minFaceSizeRatio,
    ),
  );

  /// Validates [bytes] (JPEG/PNG image data). Returns [FaceCheckResult].
  ///
  /// The bytes are staged into a temp file because ML Kit's
  /// `InputImage.fromFilePath` applies EXIF rotation natively.
  static Future<FaceCheckResult> validateProfilePhoto(
    List<int> bytes, {
    @visibleForTesting FaceDetector? detector,
  }) async {
    final activeDetector = detector ?? _detector;
    try {
      final tempFile = File(
        '${Directory.systemTemp.path}/vr_profile_check_'
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(bytes);
      try {
        final inputImage = InputImage.fromFilePath(tempFile.path);
        final faces = await activeDetector.processImage(inputImage);
        if (faces.isEmpty) {
          return const FaceCheckResult.invalid(
            'No face detected. Please upload a clear photo of your face.',
          );
        }
        if (faces.length > 1) {
          return const FaceCheckResult.invalid(
            'Multiple faces detected. Please upload a photo of only '
            'yourself.',
          );
        }
        return const FaceCheckResult.valid();
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
    } catch (_) {
      // A detection infrastructure failure must not hard-block the driver;
      // the photo still goes through KYC review by humans.
      return const FaceCheckResult.valid();
    }
  }
}
