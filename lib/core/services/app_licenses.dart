import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Adds local application and third-party notices without reading assets yet.
void registerAppLicenses({AssetBundle? assetBundle}) {
  if (_registered) return;
  _registered = true;

  LicenseRegistry.addLicense(() async* {
    final bundle = assetBundle ?? rootBundle;
    const notices = <String, String>{
      'LICENSE': 'Hermes Android',
      'assets/fonts/OFL.txt': 'Cinzel',
      'third_party/embedded-push-notice.md': 'embedded-fcm-distributor (3.1.0)',
      'third_party/embedded-push-relink.md': 'embedded-fcm-distributor (3.1.0)',
      'third_party/licenses/embedded-fcm-distributor-LGPL-2.1.txt':
          'embedded-fcm-distributor (3.1.0)',
      'third_party/NOTICE.md': 'Third-party source/build materials (scope)',
      'third_party/licenses/graphify-MIT.txt':
          'Graphify viewer template (source material)',
      'third_party/licenses/hermes-agent-MIT.txt':
          'Hermes Agent message templates (source material)',
      'third_party/licenses/flutter-BSD-3-Clause.txt':
          'Flutter iOS scaffold (source material)',
      'third_party/licenses/Apache-2.0.txt':
          'Gradle wrapper (Library build material)',
      'third_party/licenses/gradle-NOTICE.txt':
          'Gradle wrapper (Library build material)',
    };
    for (final notice in notices.entries) {
      yield LicenseEntryWithLineBreaks([
        notice.value,
      ], await bundle.loadString(notice.key));
    }
  });
}
