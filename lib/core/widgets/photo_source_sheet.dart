import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';

/// Source chosen by the driver for a photo/document upload.
enum PhotoSource { camera, gallery, files }

/// Bottom sheet letting the driver pick between the phone camera and the
/// gallery. [allowFiles] adds a generic file-browser option (used by
/// document uploads that also accept PDFs).
Future<PhotoSource?> showPhotoSourceSheet(
  BuildContext context, {
  bool allowFiles = false,
}) {
  return showModalBottomSheet<PhotoSource>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Select source',
            style: Theme.of(sheetContext).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take Photo'),
            onTap: () => Navigator.pop(sheetContext, PhotoSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(sheetContext, PhotoSource.gallery),
          ),
          if (allowFiles)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Browse Files (PDF)'),
              onTap: () => Navigator.pop(sheetContext, PhotoSource.files),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Picks a JPEG image from [source], downscaled so uploads stay well
/// under the API's 2MB limit and face detection stays fast. When
/// [preferFrontCamera] is true and the camera is used, the front
/// (selfie) camera opens by default.
Future<XFile?> pickImageFrom(
  PhotoSource source, {
  bool preferFrontCamera = false,
}) {
  return ImagePicker().pickImage(
    source: source == PhotoSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    preferredCameraDevice:
        preferFrontCamera ? CameraDevice.front : CameraDevice.rear,
    imageQuality: 85,
    maxWidth: 1600,
  );
}
