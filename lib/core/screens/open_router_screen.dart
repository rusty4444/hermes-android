import 'provider_usage_screen.dart';

class OpenRouterScreen extends ProviderUsageScreen {
  const OpenRouterScreen({
    required super.connection,
    super.dashboardClient,
    super.key,
  }) : super(providerId: 'openrouter', title: 'OpenRouter');
}
