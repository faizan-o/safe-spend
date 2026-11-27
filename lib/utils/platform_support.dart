import 'package:flutter/foundation.dart';

/// True on Android and iOS, where the camera can be used to take a receipt
/// photo. On desktop and the web, receipts can only be uploaded from a file.
bool get canUseCamera =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
