/// Only fallback fields from raw Dashboard config. Never retain the full config,
/// stringify this object, or surface parser/server errors: entries may hold keys.
class FallbackConfig {
  final List<FallbackEntry> entries;
  final List<FallbackEntry> legacyEntries;
  final bool _legacyPresent;
  final Object? _legacy;
  final Object? _primary;

  FallbackConfig._(
    this.entries,
    this.legacyEntries,
    this._legacyPresent,
    this._legacy,
    this._primary,
  );

  factory FallbackConfig.fromConfig(Map<String, dynamic> config) {
    return FallbackConfig._(
      _entries(config['fallback_providers']),
      _entries(config['fallback_model']),
      config.containsKey('fallback_model'),
      _freeze(config['fallback_model']),
      _freeze(config['fallback_providers']),
    );
  }

  /// The host appends legacy entries after this list (with route deduplication).
  /// Keep that representation untouched; this editor does not migrate legacy.
  bool confirms(List<FallbackEntry> expected, FallbackConfig before) =>
      // save_config may omit a default [] when this key was already absent.
      // Never permit this exception when clearing a previously persisted chain.
      (_equal(_primary, expected.map((e) => e.toJson()).toList()) ||
          (_primary == null && before._primary == null && expected.isEmpty)) &&
      _legacyPresent == before._legacyPresent &&
      _equal(_legacy, before._legacy);

  static List<FallbackEntry> _entries(Object? value) {
    if (value == null) return const [];
    final List candidates;
    if (value is Map<String, dynamic>) {
      candidates = [value];
    } else if (value is List) {
      candidates = value;
    } else {
      throw const FormatException('Invalid fallback configuration');
    }
    return List.unmodifiable(
      candidates.map((row) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid fallback configuration');
        }
        final entry = FallbackEntry(row);
        if (!entry.complete) {
          throw const FormatException('Incomplete fallback configuration');
        }
        return entry;
      }),
    );
  }
}

/// Immutable JSON entry, including opaque routing/credential metadata. Existing
/// values are never trimmed, resolved, normalised or reconstructed from discovery.
class FallbackEntry {
  final Map<String, dynamic> _data;
  FallbackEntry(Map<String, dynamic> data)
    : _data = _freeze(data) as Map<String, dynamic> {
    if (data['provider'] is! String || data['model'] is! String) {
      throw const FormatException('Invalid fallback selection');
    }
  }
  factory FallbackEntry.blank() => FallbackEntry({'provider': '', 'model': ''});
  String get provider => _data['provider'] as String;
  String get model => _data['model'] as String;
  bool get complete => provider.trim().isNotEmpty && model.trim().isNotEmpty;

  // Unknown fields can acquire routing semantics on newer hosts. Conservatively
  // lock their pair too, rather than reusing credentials/endpoints on a new route.
  bool get hasMetadata =>
      _data.keys.any((k) => k != 'provider' && k != 'model');
  FallbackEntry select(String provider, String model) =>
      FallbackEntry({..._data, 'provider': provider, 'model': model});
  Map<String, dynamic> toJson() => _data;
}

Object? _freeze(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(
      value.map((k, v) => MapEntry(k, _freeze(v))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw const FormatException('Invalid fallback metadata');
}

bool _equal(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => _equal(a[i], b[i]));
  }
  return a.runtimeType == b.runtimeType && a == b;
}
