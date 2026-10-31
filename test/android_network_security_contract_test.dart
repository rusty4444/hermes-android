import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android trusts explicitly installed user CAs for private gateways',
    () async {
      final manifest = await File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsString();
      final networkSecurityConfig = await File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsString();

      expect(
        manifest,
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
      expect(networkSecurityConfig, contains('<certificates src="system" />'));
      expect(networkSecurityConfig, contains('<certificates src="user" />'));
      expect(
        networkSecurityConfig,
        contains('cleartextTrafficPermitted="true"'),
      );
    },
  );
}
