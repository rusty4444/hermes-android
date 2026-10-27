import 'dart:convert';

import '../utils/attachment_types.dart';
import '../utils/delivered_files.dart';
import '../utils/generated_media.dart';
import '../utils/media_tags.dart';
import 'session.dart';

enum ChatAssetKind { image, audio, video, document }

/// A file explicitly delivered in durable chat history or by a known producer.
///
/// This is a reference, not an inventory entry or evidence that the file still
/// exists. Resolve it through the source connection's remote files client.
class ChatAsset {
  final Session session;
  final MediaTagRef ref;

  /// The message's Unix timestamp, or zero when none was recorded.
  final double timestamp;

  const ChatAsset({
    required this.session,
    required this.ref,
    required this.timestamp,
  });

  /// Merge duplicates within one source without losing older producer metadata.
  /// The newest occurrence owns the timestamp, session and exact reference path.
  ChatAsset merge(ChatAsset other) {
    if (id != other.id) {
      throw ArgumentError(
        'Cannot merge assets with different session/path IDs',
      );
    }
    final newest = other.timestamp > timestamp ? other : this;
    final older = identical(newest, this) ? other : this;
    final suggestedFilename =
        newest.ref.suggestedFilename ?? older.ref.suggestedFilename;
    if (suggestedFilename == newest.ref.suggestedFilename) return newest;
    return ChatAsset(
      session: newest.session,
      ref: MediaTagRef(
        path: newest.ref.path,
        quoted: newest.ref.quoted,
        suggestedFilename: suggestedFilename,
      ),
      timestamp: newest.timestamp,
    );
  }

  /// Lossless tuple encoding: delimiters inside either value cannot collide.
  /// Assets are scoped to one connection/profile by their data source.
  String get id => jsonEncode([session.id, ref.path]);

  ChatAssetKind get kind {
    final extension = ref.extension;
    if (attachmentIsImageAsset(extension)) return ChatAssetKind.image;
    if (attachmentIsAudio(extension)) return ChatAssetKind.audio;
    if (attachmentIsVideo(extension)) return ChatAssetKind.video;
    return ChatAssetKind.document;
  }
}

/// Extract explicit assistant deliveries and successful, audited tool results.
/// Never infer deliveries from arbitrary tool paths, uploads or sidecars.
///
/// Uses the server's display projection when supplied rather than inspecting a
/// compaction carrier's model-only text. Compacted *real* rows remain eligible.
/// Duplicate paths within this session retain their newest message timestamp;
/// results are newest first. Neither messages nor paths are normalised/mutated.
List<ChatAsset> chatAssetsFromMessages(
  Session session,
  List<Map<String, dynamic>> messages,
) {
  final assets = <String, ChatAsset>{};
  final toolNamesById = generatedMediaToolCallNames(messages);
  for (final message in messages) {
    if (!isPublicDeliveryMessage(message)) continue;
    final List<MediaTagRef> refs;
    if (message['role'] == 'assistant' || message['role'] == 'agent') {
      refs = extractDeliveredFileRefs(publicDeliveryText(message));
    } else {
      refs = generatedMediaFromToolMessage(
        message,
        toolNamesById: toolNamesById,
      );
    }

    final rawTimestamp = message['timestamp'];
    final timestamp = rawTimestamp is num
        ? rawTimestamp.toDouble()
        : rawTimestamp is String
        ? double.tryParse(rawTimestamp)
        : null;
    final recordedTimestamp = timestamp != null && timestamp.isFinite
        ? timestamp
        : 0.0;
    for (final ref in refs) {
      final asset = ChatAsset(
        session: session,
        ref: ref,
        timestamp: recordedTimestamp,
      );
      final previous = assets[asset.id];
      assets[asset.id] = previous?.merge(asset) ?? asset;
    }
  }
  return assets.values.toList()..sort((left, right) {
    final byTime = right.timestamp.compareTo(left.timestamp);
    return byTime == 0 ? left.id.compareTo(right.id) : byTime;
  });
}
