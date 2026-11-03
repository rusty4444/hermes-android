import '../utils/chat_display_items.dart';

typedef MessagePageFetcher =
    Future<List<Map<String, dynamic>>> Function(int offset);

/// A bounded latest-first scan of raw rows. Tool calls/results can consume an
/// entire page without producing a single conversation bubble.
class ChatHistoryPageBatch {
  const ChatHistoryPageBatch(this.rows, this.rawCount, this.hasOlder);

  final List<Map<String, dynamic>> rows;
  final int rawCount;
  final bool hasOlder;
}

class ChatHistoryWindow {
  static const pageSize = 50;
  // Covers ordinary long tool runs without transferring an unbounded transcript.
  // Work beyond this window remains reachable with Load more.
  static const initialPageBudget = 12;

  List<Map<String, dynamic>> rows = [];
  int _olderOffset = 0;
  bool hasOlder = false;
  bool _initialized = false;

  int get olderOffset => _olderOffset;

  static int? _rowId(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is int) return id;
    if (id is num && id.isFinite && id == id.truncate()) return id.toInt();
    return int.tryParse(id?.toString() ?? '');
  }

  /// Fetch at most twelve raw pages on a cold open, stopping as soon as both
  /// sides of the conversation are visible or the server reaches its end.
  /// Subsequent refreshes usually need only the first page. An explicit
  /// persistence receipt may request additional fresh context, within the same
  /// page budget; already retained rows are never fresh confirmation context.
  /// A failed additional page keeps the usable first page.
  Future<ChatHistoryPageBatch> fetchRecent(
    MessagePageFetcher fetch, {
    bool Function()? shouldContinue,
    bool forceColdScan = false,
    bool Function(List<Map<String, dynamic>> rows)? needsContext,
  }) async {
    final first = await fetch(0);
    final pages = <List<Map<String, dynamic>>>[first];
    var count = first.length;
    var hasMore = first.length == pageSize;
    // An owner seed can already offer a valid Load more cursor while the
    // route's first physical read still owes its bounded cold-open scan.
    if (!_initialized || forceColdScan || needsContext?.call(first) == true) {
      while (hasMore && pages.length < initialPageBudget) {
        if (shouldContinue != null && !shouldContinue()) break;
        final combined = pages.reversed.expand((page) => page).toList();
        final bubbles = buildChatDisplayItems(
          messages: combined,
        ).whereType<Map<String, dynamic>>();
        if (bubbles.any((row) => row['role'] == 'user') &&
            bubbles.any((row) => row['role'] == 'assistant') &&
            needsContext?.call(combined) != true) {
          break;
        }
        try {
          final older = await fetch(count);
          pages.add(older);
          count += older.length;
          hasMore = older.length == pageSize;
        } catch (_) {
          // A usable recent page must not become an error screen just because
          // older context failed. The Load more action can retry it.
          break;
        }
      }
    }
    return ChatHistoryPageBatch(
      pages.reversed.expand((page) => page).toList(),
      count,
      hasMore,
    );
  }

  /// Merge by durable row identity, never by text/role (repeated prompts are
  /// valid). The API returns each raw page in chronological order even with
  /// `order=latest`, so numeric row IDs restore order across sliding windows.
  void acceptRecent(ChatHistoryPageBatch batch) {
    final previousMax = rows
        .map(_rowId)
        .whereType<int>()
        .fold<int>(0, (maximum, id) => id > maximum ? id : maximum);
    if (!_initialized) {
      _olderOffset = batch.rawCount;
      hasOlder = batch.hasOlder;
      _initialized = true;
    } else {
      final previousIds = rows.map(_rowId).whereType<int>().toSet();
      final incomingIds = batch.rows.map(_rowId).whereType<int>().toSet();
      if (incomingIds.isNotEmpty &&
          previousIds.isNotEmpty &&
          incomingIds.intersection(previousIds).isEmpty) {
        // The latest page jumped past the previously loaded window. Restart
        // the older scan at this page's boundary so Load more can fill the
        // gap instead of skipping it with a stale OFFSET.
        _olderOffset = batch.rawCount;
      } else {
        _olderOffset += incomingIds.where((id) => id > previousMax).length;
      }
      if (batch.hasOlder) hasOlder = true;
    }
    rows = _merge(rows, batch.rows);
  }

  void acceptOlder(List<Map<String, dynamic>> older) {
    _olderOffset += older.length;
    hasOlder = older.length == pageSize;
    rows = _merge(older, rows);
  }

  /// An app-owner observation supplies usable rows, not a physical route page.
  /// In particular it must not reset/advance an in-flight older-page cursor or
  /// mark a cold route scan initialized. Physical batches retain that authority.
  void mergeObservedRows(List<Map<String, dynamic>> latest) {
    rows = _merge(rows, latest);
  }

  static List<Map<String, dynamic>> _merge(
    List<Map<String, dynamic>> older,
    List<Map<String, dynamic>> newer,
  ) {
    final byId = <int, Map<String, dynamic>>{};
    // Without a durable key, old latest-window rows cannot be reconciled.
    final withoutId = newer.where((row) => _rowId(row) == null).toList();
    for (final row in [...older, ...newer]) {
      final id = _rowId(row);
      if (id != null) {
        byId[id] = row;
      }
    }
    final ids = byId.keys.toList()..sort();
    // Legacy rows without IDs cannot be safely matched across refreshes.
    // Keep only the latest fetched set, never duplicate it by content.
    return [for (final id in ids) byId[id]!, ...withoutId];
  }
}
