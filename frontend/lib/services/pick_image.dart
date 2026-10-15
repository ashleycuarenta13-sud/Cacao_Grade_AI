import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'package:cacao/constants/app_constants.dart';

/// Activity 3, Part C's *Upload / Capture Bean Photo* screen.
///
/// The document names `image_picker` as the package behind its
/// `ImagePickerButton`, so both entry points the screen offers - taking a new
/// cut-test photo and choosing an existing one - come from the same API.

/// A photo the user chose or captured, after the client-side validation.
class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.fileName,
    required this.size,
  });

  final Uint8List bytes;
  final String fileName;
  final int size;
}

/// Raised when the chosen file is not something the system can grade.
///
/// Carries no status code: this never reached the network, so it is shown as a
/// plain error banner rather than queued for retry.
class ImagePickException implements Exception {
  const ImagePickException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lower-cased extension of [fileName], or null when it has none.
String? imageExtensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  return fileName.substring(dot + 1).toLowerCase();
}

/// Asks for a photo from [source] and validates it the way Part C describes.
///
/// Returns `null` when the user cancelled, which is not an error - nothing was
/// picked, so nothing should be reported as a failure.
///
/// Throws [ImagePickException] for a wrong file type or an oversized one. The
/// API enforces the same two rules again; this exists so a farmer is told
/// immediately instead of after a round-trip.
Future<PickedImage?> pickCacaoImage(ImageSource source) async {
  final XFile? file = await ImagePicker().pickImage(source: source);

  if (file == null) return null;

  final extension = imageExtensionOf(file.name);
  if (extension == null || !kAllowedImageExtensions.contains(extension)) {
    throw const ImagePickException('Only JPG and PNG images are allowed.');
  }

  final Uint8List bytes = await file.readAsBytes();

  if (bytes.isEmpty) {
    throw const ImagePickException('The selected image is empty.');
  }

  if (bytes.length > kMaxImageBytes) {
    throw const ImagePickException(
        'The image exceeds the 10 MB file-size limit.');
  }

  return PickedImage(
    bytes: bytes,
    fileName: file.name,
    size: bytes.length,
  );
}
