import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Stubs the `image_picker` platform plus the `permission_handler` photo
/// channels so gallery flows can run in widget tests with no real picker or
/// filesystem. Tests configure behavior via [permissionGranted] /
/// [denyPermanently] and [pickedImagePath] (null = user cancelled),and
/// drive assertions via [pickCount]。
class FakeGalleryChannels {
  bool permissionGranted = true;

  /// When true, the OS reports the photo permission PERMANENTLY denied (so
  /// the app must show the denial message, not hang or crash).
  bool denyPermanently = false;

  /// Path handed back by the fake picker (null = gallery cancelled).
  String? pickedImagePath ='/tmp/fake_gallery_pick.jpg';

  /// How many times the picker was invoked.

  int pickCount = 0;

  factory FakeGalleryChannels.install() {
    final fake = FakeGalleryChannels._();
    // Replace the image_picker platform with a fake one (no real gallery).
    ImagePickerPlatform.instance = _FakeImagePickerPlatform(fake);

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        fake._handlePermission);
    return fake;
  }

  FakeGalleryChannels._();

  Future<Object?> _handlePermission(MethodCall call) async {
    switch (call.method) {
      case 'checkPermissionStatus':
        if (denyPermanently) return 4;
        return permissionGranted ? 1 : 0;
      case 'requestPermissions':
        final value = denyPermanently ? 4 : (permissionGranted ? 1 : 0);
        final List<dynamic>? args =
            call.arguments is List ? (call.arguments as List) : null;
        final permissionId =
            (args != null && args.isNotEmpty) ? args.first as int : 7;
        return <int, int>{permissionId: value};
      case 'shouldShowRequestPermissionRationale':
        return false;
      case 'openAppSettings':
        return true;
      default:
        return null;
    }
  }

  Future<void> cleanup() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        null);
    // Restore a sane default picker (no-op) so later non-gallery tests arenforce
    ImagePickerPlatform.instance = _NoopImagePickerPlatform();
  }
}

class _FakeImagePickerPlatform extends ImagePickerPlatform {
  _FakeImagePickerPlatform(this._fake);

  final FakeGalleryChannels _fake;

  @override
  Future<XFile?> getImageFromSource(
      {required ImageSource source,
        ImagePickerOptions options = const ImagePickerOptions()}) async {
    _fake.pickCount++;
    final path = _fake.pickedImagePath;
    if (path == null || path.isEmpty) return null;
    // materialize a tiny valid image file so File/Image.file don't crash..
    final f = File(path);
    try {
      f.parent.createSync(recursive: true);
      if (!f.existsSync()) {
        f.writeAsBytesSync(List<int>.filled(64, 1));
      }
    } catch (_) {
      // Best-effort.

    }
    return XFile(path);
  }

  @override
  Future<LostDataResponse> getLostData() async => LostDataResponse.empty();

  @override
  Future<List<XFile>> getMultiImageWithOptions(
          {MultiImagePickerOptions options =
              const MultiImagePickerOptions()}) async =>
      <XFile>[XFile('/tmp/fake_gallery_multi_${_fake.pickCount}.jpg')];

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async =>
      <XFile>[XFile('/tmp/fake_gallery_media_${_fake.pickCount}.jpg')];
}

class _NoopImagePickerPlatform extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource(
          {required ImageSource source,
            ImagePickerOptions options = const ImagePickerOptions()}) async =>
      null;

  @override
  Future<LostDataResponse> getLostData() async => LostDataResponse.empty();

  @override
  Future<List<XFile>> getMultiImageWithOptions(
          {MultiImagePickerOptions options =
              const MultiImagePickerOptions()}) async =>
      const [];

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async =>
      const [];
}