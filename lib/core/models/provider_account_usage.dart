/// Provider-reported subscription windows, never inferred from token analytics.
library;

/// OpenAI API billing and Codex subscriptions are distinct provider identities.
String? subscriptionUsageProvider(String providerId) => switch (providerId) {
  'openai' || 'openai-codex' => 'openai-codex',
  'anthropic' => 'anthropic',
  _ => null,
};

class ProviderUsageWindow {
  final String label;
  final String? scope;
  final double? usedPercent;
  final DateTime? resetsAt;

  const ProviderUsageWindow({
    required this.label,
    this.scope,
    this.usedPercent,
    this.resetsAt,
  });

  double? get remainingPercent =>
      usedPercent == null ? null : 100 - usedPercent!;

  static ProviderUsageWindow? parse(dynamic value) {
    if (value is! Map) return null;
    final label = _text(value['label']);
    if (label == null) return null;
    final percent = value['used_percent'];
    return ProviderUsageWindow(
      label: label,
      scope: _text(value['scope']),
      usedPercent: percent is num && percent.isFinite
          ? percent.toDouble().clamp(0, 100)
          : null,
      resetsAt: _reset(value['resets_at']),
    );
  }
}

class ProviderAccountUsage {
  final String? id;
  final String? label;

  /// This is provider state, not derived from model-scoped exhaustion.
  final String? state;
  final DateTime? resetsAt;
  final List<ProviderUsageWindow> windows;

  const ProviderAccountUsage({
    this.id,
    this.label,
    this.state,
    this.resetsAt,
    this.windows = const [],
  });

  static ProviderAccountUsage? parse(dynamic value) {
    if (value is! Map) return null;
    return ProviderAccountUsage(
      id: _text(value['id']),
      label: _text(value['label']),
      state: _text(value['state']),
      resetsAt: _reset(value['resets_at']),
      windows: _windows(value['windows']),
    );
  }
}

class ProviderSubscriptionUsage {
  final String provider;
  final List<ProviderAccountUsage> accounts;
  final List<ProviderUsageWindow> windows;
  final bool hasAccounts;

  const ProviderSubscriptionUsage({
    required this.provider,
    this.accounts = const [],
    this.windows = const [],
    this.hasAccounts = false,
  });

  /// Only the exact subscription slug is authoritative. In particular, an
  /// `openai` API row must never supply Codex subscription allowance.
  static ProviderSubscriptionUsage? fromModelOptions(
    Map<String, dynamic> options,
    String providerId,
  ) {
    final slug = subscriptionUsageProvider(providerId);
    final providers = options['providers'];
    if (slug == null || providers is! List) return null;
    for (final provider in providers) {
      if (provider is! Map || provider['slug'] != slug) continue;
      final usage = provider['usage'];
      if (usage is! Map) return null;
      // An accounts field, even empty or malformed, must not fall through to
      // a synthetic pool average or legacy outer windows.
      if (usage.containsKey('accounts')) {
        final raw = usage['accounts'];
        return ProviderSubscriptionUsage(
          provider: slug,
          hasAccounts: true,
          accounts: raw is List
              ? List.unmodifiable(raw.map(ProviderAccountUsage.parse).nonNulls)
              : const [],
        );
      }
      return ProviderSubscriptionUsage(
        provider: slug,
        windows: _windows(usage['windows']),
      );
    }
    return null;
  }
}

String? _text(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value : null;

DateTime? _reset(dynamic value) {
  if (value is! String) return null;
  // A reset must be an ISO timestamp, not a numeric epoch or date-only value.
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?$',
  ).firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year ||
      date.month != month ||
      date.day != day ||
      int.parse(match[4]!) > 23 ||
      int.parse(match[5]!) > 59 ||
      int.parse(match[6] ?? '0') > 59) {
    return null;
  }
  final offset = RegExp(r'[+-](\d{2}):?(\d{2})$').firstMatch(value);
  if (offset != null &&
      (int.parse(offset[1]!) > 23 || int.parse(offset[2]!) > 59)) {
    return null;
  }
  return DateTime.tryParse(value);
}

List<ProviderUsageWindow> _windows(dynamic value) => value is List
    ? List.unmodifiable(value.map(ProviderUsageWindow.parse).nonNulls)
    : const [];
