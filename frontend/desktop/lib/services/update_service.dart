import 'package:desktop_updater/updater_controller.dart';
import 'package:flutter/foundation.dart';

/// Where releases live. GitHub Pages, not a backend OpenLucid doesn't have:
/// .github/workflows/release.yml publishes the manifest and every version's
/// raw files there on each tagged release.
const releaseManifestUrl = 'https://emolionl.github.io/openlucid/releases/manifest.json';

/// Singleton access to [DesktopUpdaterController].
///
/// The controller automatically checks the manifest on init and sets
/// [needUpdate], [isMandatory], etc. when a newer version is found.
class UpdateService {
  UpdateService._();

  static DesktopUpdaterController? _controller;

  /// Get or create the controller. On first access it immediately
  /// fetches the manifest and checks for updates.
  static DesktopUpdaterController get controller {
    _controller ??= _createController();
    return _controller!;
  }

  static DesktopUpdaterController _createController() {
    debugPrint('[UPDATE] Manifest URL: $releaseManifestUrl');
    return DesktopUpdaterController(appArchiveUrl: Uri.parse(releaseManifestUrl));
  }
}
