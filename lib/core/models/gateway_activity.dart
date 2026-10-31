import '../utils/generated_media.dart';
import '../utils/media_tags.dart';

enum GatewayToolActivityPhase {
  running,
  generating,
  progress,
  completed,
  failed,
}

/// Whether a tool time is a device-side observation or a durable result row.
enum GatewayToolTimeSource { observed, storedResult }

/// A late ID can identify the sole active anonymous call, never a new start or
/// one of several same-name calls. Both transports use the same correlation.
int toolActivityUpdateIndex(
  List<GatewayToolActivity> activities,
  GatewayToolActivity update,
  String eventType,
) {
  if (update.toolId == null) return -1;
  final known = activities.indexWhere((a) => a.toolId == update.toolId);
  if (known >= 0) return known;
  if (eventType == 'tool.start' ||
      update.phase == GatewayToolActivityPhase.running) {
    return -1;
  }
  final candidates = [
    for (var i = 0; i < activities.length; i++)
      if (!activities[i].isTerminal &&
          activities[i].name.toLowerCase() == update.name.toLowerCase())
        i,
  ];
  return candidates.length == 1 && activities[candidates.single].toolId == null
      ? candidates.single
      : -1;
}

/// Most recent evidenced time within a group, irrespective of row order.
GatewayToolActivity? latestKnownToolActivity(
  Iterable<GatewayToolActivity> activities,
) {
  GatewayToolActivity? latest;
  for (final activity in activities) {
    final at = activity.lastActivityAt;
    if (at != null &&
        (latest?.lastActivityAt == null ||
            !at.isBefore(latest!.lastActivityAt!))) {
      latest = activity;
    }
  }
  return latest;
}

class GatewayToolActivity {
  static const _maxNameLength = 120;
  static const _maxDetailLength = 500;
  static int _nextLocalIdentity = 0;

  final String? toolId;

  /// Stable across merge updates, even if the gateway supplies a tool id later.
  /// Stored tool rows can also anchor the projected group to their message id.
  /// Unanchored activities get a unique local id, not another run's name.
  final String identity;
  final String name;
  final GatewayToolActivityPhase phase;
  final String? detail;
  final double? durationSeconds;
  final String? emoji;

  /// Validated producer deliveries, not arbitrary tool/debug output. These
  /// references are projected independently of the verbose activity card.
  final List<MediaTagRef> deliveredFiles;
  final bool _deliveryFailed;

  /// Only set when a live start event was actually observed. A persisted tool
  /// result never establishes when the call started.
  final DateTime? startedAt;
  final DateTime? lastActivityAt;
  final GatewayToolTimeSource? lastActivityTimeSource;

  GatewayToolActivity({
    required this.name,
    required this.phase,
    this.toolId,
    String? identity,
    this.detail,
    this.durationSeconds,
    this.emoji,
    List<MediaTagRef> deliveredFiles = const [],
    bool deliveryFailed = false,
    this.startedAt,
    this.lastActivityAt,
    this.lastActivityTimeSource,
  }) : deliveredFiles =
           phase == GatewayToolActivityPhase.failed || deliveryFailed
           ? const []
           : List.unmodifiable(deliveredFiles),
       _deliveryFailed =
           deliveryFailed || phase == GatewayToolActivityPhase.failed,
       identity =
           identity ??
           (toolId != null && toolId.trim().isNotEmpty
               ? 'tool:$toolId'
               : 'local:${_nextLocalIdentity++}');

  bool get isTerminal =>
      phase == GatewayToolActivityPhase.completed ||
      phase == GatewayToolActivityPhase.failed;

  bool get isFailed => phase == GatewayToolActivityPhase.failed;

  /// Retains a definitive delivery failure even if a later compact snapshot
  /// omits its result, without changing existing lifecycle-phase semantics.
  bool get hasFailedDelivery => _deliveryFailed;

  String get displayName {
    final words = name.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (words.isEmpty) return 'Tool';
    return words[0].toUpperCase() + words.substring(1);
  }

  String get statusLabel {
    switch (phase) {
      case GatewayToolActivityPhase.running:
        return 'Running';
      case GatewayToolActivityPhase.generating:
        return 'Preparing';
      case GatewayToolActivityPhase.progress:
        return 'Working';
      case GatewayToolActivityPhase.completed:
        return durationSeconds == null
            ? 'Completed'
            : 'Completed in ${_formatDuration(durationSeconds!)}';
      case GatewayToolActivityPhase.failed:
        return durationSeconds == null
            ? 'Failed'
            : 'Failed after ${_formatDuration(durationSeconds!)}';
    }
  }

  static GatewayToolActivity? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data, {
    DateTime? observedAt,
  }) {
    if (!eventType.startsWith('tool.')) return null;

    final toolId = _firstText(data, const [
      'tool_id',
      'toolCallId',
      'tool_call_id',
      'id',
    ]);
    final rawName = _firstText(data, const ['name', 'tool', 'label']) ?? 'tool';
    final name = _normalizeText(rawName, _maxNameLength) ?? 'tool';
    final durationSeconds = _duration(data['duration_s']);
    final error = _normalizeText(
      _firstText(data, const ['error']),
      _maxDetailLength,
    );

    final phase = _phaseFor(eventType, data['status']?.toString(), error);
    final generated = eventType == 'tool.complete'
        ? generatedMediaFromToolResult(
            _firstText(data, const ['name', 'tool']) ?? '',
            data['result'],
          )
        : const GeneratedMediaResult();
    final detail = switch (phase) {
      GatewayToolActivityPhase.failed => error,
      GatewayToolActivityPhase.completed => _normalizeText(
        _firstText(data, const ['summary']),
        _maxDetailLength,
      ),
      GatewayToolActivityPhase.progress => _normalizeText(
        _firstText(data, const ['preview', 'detail', 'label']),
        _maxDetailLength,
      ),
      GatewayToolActivityPhase.generating => _normalizeText(
        _firstText(data, const ['preview', 'detail', 'label']),
        _maxDetailLength,
      ),
      GatewayToolActivityPhase.running => _normalizeText(
        _firstText(data, const ['context', 'detail', 'label']),
        _maxDetailLength,
      ),
    };

    return GatewayToolActivity(
      toolId: toolId,
      name: name,
      phase: phase,
      detail: detail,
      durationSeconds: durationSeconds,
      emoji: _normalizeText(_firstText(data, const ['emoji']), 8),
      deliveredFiles: generated.deliveredFiles,
      deliveryFailed:
          generated.isFailure ||
          data['status'] == 'failed' ||
          data['status'] == 'error',
      startedAt:
          eventType == 'tool.start' && phase == GatewayToolActivityPhase.running
          ? observedAt
          : null,
      lastActivityAt: observedAt,
      lastActivityTimeSource: observedAt == null
          ? null
          : GatewayToolTimeSource.observed,
    );
  }

  /// API message timestamps are Unix seconds (possibly fractional), not the
  /// time this device fetched the history. Missing/invalid values stay unknown.
  static DateTime? storedResultTime(dynamic timestamp) {
    if (timestamp is! num || !timestamp.isFinite || timestamp <= 0) {
      return null;
    }
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        (timestamp * 1000).round(),
        isUtc: true,
      );
    } on RangeError {
      return null;
    }
  }

  factory GatewayToolActivity.fromStoredResult({
    required String name,
    String? toolId,
    required dynamic timestamp,
    Object? result,
    DateTime? observedStart,
    DateTime? observedLastActivity,
  }) {
    final resultTime = storedResultTime(timestamp);
    final generated = generatedMediaFromToolResult(name, result);
    return GatewayToolActivity(
      name: name,
      toolId: toolId,
      phase: GatewayToolActivityPhase.completed,
      deliveredFiles: generated.deliveredFiles,
      deliveryFailed: generated.isFailure,
      startedAt: observedStart,
      lastActivityAt: resultTime ?? observedLastActivity,
      lastActivityTimeSource: resultTime != null
          ? GatewayToolTimeSource.storedResult
          : observedLastActivity != null
          ? GatewayToolTimeSource.observed
          : null,
    );
  }

  GatewayToolActivity merge(GatewayToolActivity update) {
    return GatewayToolActivity(
      toolId: update.toolId ?? toolId,
      identity: identity,
      name: update.name == 'tool' && name != 'tool' ? name : update.name,
      phase: isTerminal && !update.isTerminal ? phase : update.phase,
      detail: update.detail ?? detail,
      durationSeconds: update.durationSeconds ?? durationSeconds,
      emoji: update.emoji ?? emoji,
      deliveredFiles: update.deliveredFiles.isNotEmpty
          ? update.deliveredFiles
          : deliveredFiles,
      // Missing compact-resume results preserve known deliveries. Definitive
      // failures are sticky for deliveries without changing lifecycle phases.
      deliveryFailed: _deliveryFailed || update._deliveryFailed,
      startedAt: startedAt ?? update.startedAt,
      lastActivityAt: update.lastActivityAt ?? lastActivityAt,
      lastActivityTimeSource:
          update.lastActivityTimeSource ?? lastActivityTimeSource,
    );
  }

  static GatewayToolActivityPhase _phaseFor(
    String eventType,
    String? legacyStatus,
    String? error,
  ) {
    if (eventType == 'tool.complete') {
      return error == null
          ? GatewayToolActivityPhase.completed
          : GatewayToolActivityPhase.failed;
    }
    if (eventType == 'tool.generating') {
      return GatewayToolActivityPhase.generating;
    }
    if (eventType == 'tool.progress') {
      return GatewayToolActivityPhase.progress;
    }

    switch (legacyStatus?.trim().toLowerCase()) {
      case 'completed':
      case 'complete':
      case 'finished':
      case 'done':
        return GatewayToolActivityPhase.completed;
      case 'failed':
      case 'error':
        return GatewayToolActivityPhase.failed;
      case 'generating':
      case 'preparing':
        return GatewayToolActivityPhase.generating;
      case 'progress':
      case 'working':
        return GatewayToolActivityPhase.progress;
      default:
        return GatewayToolActivityPhase.running;
    }
  }

  static String? _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static String? _normalizeText(String? value, int maxLength) {
    if (value == null) return null;
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    return normalized.length <= maxLength
        ? normalized
        : '${normalized.substring(0, maxLength - 1)}…';
  }

  static double? _duration(dynamic value) {
    if (value is num && value.isFinite && value >= 0) {
      return value.toDouble();
    }
    return null;
  }

  static String _formatDuration(double value) {
    if (value < 1) return '${(value * 1000).round()} ms';
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} s';
  }
}

class GatewayTurnStatus {
  static const _maxTextLength = 240;

  final String kind;
  final String text;

  const GatewayTurnStatus({required this.kind, required this.text});

  /// The caller supplies only this turn's live activities, never saved tools.
  static GatewayTurnStatus? forRunningTool(
    Iterable<GatewayToolActivity> activities,
  ) {
    final tool = activities.where((tool) => !tool.isTerminal).lastOrNull;
    if (tool == null) return null;
    final detail = _normalize(tool.detail, _maxTextLength);
    return GatewayTurnStatus(
      kind: 'tool',
      text: _normalize(
        detail == null ? tool.displayName : '${tool.displayName}: $detail',
        _maxTextLength,
      )!,
    );
  }

  static GatewayTurnStatus? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    if (eventType != 'status.update' && eventType != 'thinking.delta') {
      return null;
    }

    final kind = eventType == 'thinking.delta'
        ? 'thinking'
        : _normalize(data['kind']?.toString(), 40) ?? 'status';
    final rawText = _normalize(data['text']?.toString(), _maxTextLength);
    final text = rawText ?? _fallbackText(kind);
    if (text == null) return null;
    return GatewayTurnStatus(kind: kind, text: text);
  }

  static String? _fallbackText(String kind) {
    switch (kind) {
      case 'compacting':
        return 'Compacting conversation context…';
      case 'compacted':
        return 'Conversation context compacted';
      default:
        return null;
    }
  }

  static String? _normalize(String? value, int maxLength) {
    if (value == null) return null;
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    return normalized.length <= maxLength
        ? normalized
        : '${normalized.substring(0, maxLength - 1)}…';
  }
}
