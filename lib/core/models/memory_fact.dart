/// Built-in stores are distinct: USER.md describes the user; MEMORY.md holds
/// the agent's notes. External-provider recall is not part of this API.
enum MemoryFactSource {
  profile('USER.md'),
  memory('MEMORY.md');

  const MemoryFactSource(this.fileName);
  final String fileName;
}

/// A saved entry, not an LLM-generated summary or a memory configuration option.
class MemoryFact {
  final String id;
  final MemoryFactSource source;
  final String content;

  const MemoryFact({
    required this.id,
    required this.source,
    required this.content,
  });

  // The learning graph caps each body at 1,200 Python characters. Count Unicode
  // code points rather than Dart UTF-16 units, and offer the full-node read.
  bool get mayBeTruncated => content.runes.length >= 1200;

  // Positional IDs on older gateways can drift to a different entry, even when
  // both entries share the entire preview. Only fingerprints support expansion.
  bool get hasStableIdentity =>
      RegExp(
        r'^memory:(profile|memory):[0-9]+:[a-f0-9]{12}$',
      ).firstMatch(id)?.group(0) ==
      id;

  static List<MemoryFact> parseGraph(Map<String, dynamic> graph) {
    final cards = graph['memory'];
    final nodes = graph['nodes'];
    if (cards is! List || nodes is! List) {
      throw const FormatException('Expected a saved-memory learning graph');
    }
    final memoryNodes = nodes
        .whereType<Map>()
        .where((node) => node['kind'] == 'memory')
        .toList();
    if (memoryNodes.length != cards.length) {
      throw const FormatException('Memory cards and identities do not match');
    }
    return List.unmodifiable([
      for (var index = 0; index < cards.length; index++)
        _parseCard(cards[index], memoryNodes[index], index),
    ]);
  }

  static MemoryFact _parseCard(Object? raw, Map node, int index) {
    if (raw is! Map || raw['body'] is! String) {
      throw const FormatException('Invalid saved memory fact');
    }
    final source = switch (raw['source']) {
      'profile' => MemoryFactSource.profile,
      'memory' => MemoryFactSource.memory,
      _ => throw const FormatException('Unknown built-in memory source'),
    };
    final content = raw['body'] as String;
    final id = node['id'];
    // Use the server's identity verbatim, including its optional fingerprint;
    // never infer an identity from the title/body or repair a malformed id.
    final identity = RegExp(
      r'^memory:(profile|memory):([0-9]+)(?::[a-f0-9]{12})?$',
    ).firstMatch(id is String ? id : '');
    if (content.trim().isEmpty ||
        identity == null ||
        identity.group(0) != id ||
        identity.group(1) != raw['source'] ||
        identity.group(2) != '$index' ||
        node['memorySource'] != raw['source']) {
      throw const FormatException('Invalid saved memory identity or content');
    }
    return MemoryFact(id: id as String, source: source, content: content);
  }
}
