import 'provider_usage_screen.dart';

class ProviderScreen extends ProviderUsageScreen {
  const ProviderScreen({
    required super.connection,
    required super.providerId,
    required super.title,
    super.dashboardClient,
    super.key,
  });
}
