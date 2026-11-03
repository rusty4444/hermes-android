import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';

/// POLICY A: qualify a real lazy cell by source without changing inner keys.
Finder inChatSource(Finder finder, ChatDisplaySource source) => find.descendant(
  of: find.byWidgetPredicate((widget) {
    final key = widget.key;
    if (widget is! KeyedSubtree || key is! ValueKey) return false;
    final value = key.value;
    return value is (ChatDisplaySource, Object) && value.$1 == source;
  }),
  matching: finder,
);

/// Existing delegate-inspection oracles still exercise the production builder.
/// Unwrap only the new provenance cell; never project a replacement transcript.
Widget unwrapChatSourceCell(Widget widget) {
  if (widget is! KeyedSubtree) return widget;
  final child = widget.child;
  return child is Column ? child.children.last : child;
}
