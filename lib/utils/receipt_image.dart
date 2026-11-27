import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// A receipt picture ready to store in Firestore (a document is limited to
/// 1 MiB, so the picture is shrunk to stay well under that).
class PreparedImage {
  const PreparedImage(this.bytes, this.mimeType);

  final Uint8List bytes;
  final String mimeType;
}

/// Biggest picture kept in Firestore, in bytes.
const int maxStoredImageBytes = 700 * 1024;

/// Settings for the copy sent to the reading workflow: large and sharp, because
/// small print on long receipts needs the pixels (kept under about 1.2 MB so a small n8n instance can handle it).
const int readingLongestSide = 2200;
const int readingMaxBytes = 1200 * 1024;

/// Resizes and re-encodes a picture as JPEG, at most [maxStoredImageBytes].
/// PDFs and pictures that cannot be decoded are returned unchanged.
Future<PreparedImage> prepareReceiptImage(
  Uint8List bytes,
  String mimeType, {
  int longestSide = 1600,
  int maxBytes = maxStoredImageBytes,
  int quality = 78,
}) async {
  if (!mimeType.startsWith('image/')) return PreparedImage(bytes, mimeType);
  try {
    final out = await compute(_compress, _Job(bytes, longestSide, maxBytes, quality));
    if (out == null) return PreparedImage(bytes, mimeType);
    return PreparedImage(out, 'image/jpeg');
  } catch (_) {
    return PreparedImage(bytes, mimeType);
  }
}

/// A small JPEG (about 200 px) shown in the receipts list. Null if it fails.
Future<Uint8List?> makeThumbnail(Uint8List bytes) async {
  try {
    return await compute(_thumb, bytes);
  } catch (_) {
    return null;
  }
}

class _Job {
  const _Job(this.bytes, this.longestSide, this.maxBytes, this.quality);

  final Uint8List bytes;
  final int longestSide;
  final int maxBytes;
  final int quality;
}

Uint8List? _compress(_Job job) {
  final maxBytes = job.maxBytes;
  var image = img.decodeImage(job.bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  var longest = job.longestSide;
  var quality = job.quality;
  Uint8List? result;
  for (var attempt = 0; attempt < 6; attempt++) {
    final scale = math.max(image.width, image.height) > longest
        ? (image.width >= image.height
            ? img.copyResize(image, width: longest)
            : img.copyResize(image, height: longest))
        : image;
    result = Uint8List.fromList(img.encodeJpg(scale, quality: quality));
    if (result.length <= maxBytes) return result;
    longest = (longest * 0.8).round();
    quality = math.max(50, quality - 8);
  }
  return result != null && result.length <= maxBytes ? result : null;
}

Uint8List? _thumb(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  final small = image.width >= image.height
      ? img.copyResize(image, width: 200)
      : img.copyResize(image, height: 200);
  return Uint8List.fromList(img.encodeJpg(small, quality: 60));
}
