// The NextGen chat: Kyllene's transcript (markdown replies with collapsible
// thinking and tool rows), status line, inline approval/question panel and the
// pill composer (model chip, dictation, send/stop, steer or queue while busy).
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/attachment_draft.dart';
import '../../core/services/android_voice_composer_adapter.dart';
import '../../core/services/attachment_draft_service.dart';
import '../../core/services/voice_composer_adapter.dart';
import '../data/chat_controller.dart';
import '../data/nextgen_gateway.dart';
import '../theme/nextgen_theme.dart';
import 'model_sheet.dart';
import 'nextgen_scope.dart';
import 'widgets.dart';
import '../nextgen_l10n.dart';

class NgChatView extends StatefulWidget {
  const NgChatView({
    super.key,
    required this.chat,
    required this.onOpenSidebar,
    required this.onNewChat,
  });

  final NgChatController chat;
  final VoidCallback onOpenSidebar;
  final VoidCallback onNewChat;

  @override
  State<NgChatView> createState() => _NgChatViewState();
}

class _NgChatViewState extends State<NgChatView> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _ticker;

  /// Files picked for the next message.
  final List<AttachmentDraft> _drafts = [];
  bool _preparing = false;
  final _imagePicker = ImagePicker();

  VoiceComposerAdapter? _voice;
  bool _listening = false;
  String _beforeDictation = '';

  NgChatController get chat => widget.chat;

  @override
  void initState() {
    super.initState();
    chat.addListener(_onChat);
    _input.addListener(() => setState(() {}));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (chat.running && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant NgChatView old) {
    super.didUpdateWidget(old);
    if (old.chat != chat) {
      old.chat.removeListener(_onChat);
      chat.addListener(_onChat);
    }
  }

  void _onChat() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    chat.removeListener(_onChat);
    _ticker?.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    _voice?.dispose();
    // Unsent picks only live in the app cache.
    if (_drafts.isNotEmpty) {
      unawaited(chat.attachmentService.removeAll(List.of(_drafts)));
    }
    super.dispose();
  }

  int get _slotsLeft => maxRemoteAttachmentDrafts - _drafts.length;

  Future<void> _attach() async {
    final c = NgColors.of(context);
    final choice = await showNgSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: c.text2),
              title: Text(ngL.ng_photos),
              onTap: () => Navigator.pop(context, 'photos'),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: c.text2),
              title: Text(ngL.ng_camera),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: Icon(Icons.attach_file, color: c.text2),
              title: Text(ngL.ng_files),
              onTap: () => Navigator.pop(context, 'files'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (_slotsLeft <= 0) {
      ngToast(
        context,
        ngL.ng_you_can_attach_up_to_files(maxRemoteAttachmentDrafts),
      );
      return;
    }
    setState(() => _preparing = true);
    final errors = <String>[];
    try {
      switch (choice) {
        case 'photos' || 'camera':
          final images = choice == 'camera'
              ? [
                  ?await _imagePicker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 75,
                    maxWidth: 1600,
                    maxHeight: 1600,
                  ),
                ]
              : await _imagePicker.pickMultiImage(
                  imageQuality: 75,
                  maxWidth: 1600,
                  maxHeight: 1600,
                );
          for (final image in images.take(_slotsLeft)) {
            try {
              final draft = await chat.attachmentService.prepareImage(
                sourcePath: image.path,
                displayName: image.name,
                existingDrafts: _drafts,
                mode: AttachmentDraftMode.remoteGateway,
              );
              if (mounted) setState(() => _drafts.add(draft));
            } on AttachmentDraftException catch (e) {
              errors.add(e.message);
            }
          }
        case 'files':
          final result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: true,
            withData: false,
          );
          for (final file in (result?.files ?? const []).take(_slotsLeft)) {
            final path = file.path;
            if (path == null) {
              errors.add(ngL.ng_couldn_t_read(file.name));
              continue;
            }
            try {
              final draft = await chat.attachmentService.prepareGenericFile(
                sourcePath: path,
                displayName: file.name,
                existingDrafts: _drafts,
              );
              if (mounted) setState(() => _drafts.add(draft));
            } on AttachmentDraftException catch (e) {
              errors.add(e.message);
            }
          }
      }
    } catch (e) {
      errors.add(ngL.ng_couldn_t_prepare_that_file(e));
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
    if (errors.isNotEmpty && mounted) ngToast(context, errors.first);
  }

  Future<void> _removeDraft(AttachmentDraft draft) async {
    setState(() => _drafts.remove(draft));
    await chat.attachmentService.removeCachedFile(draft);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty && _drafts.isEmpty) return;
    if (_drafts.isNotEmpty && !chat.running) {
      final drafts = List.of(_drafts);
      _input.clear();
      setState(_drafts.clear);
      // A refused prompt keeps its files on the message for Retry.
      await chat.send(text, attachments: drafts);
      return;
    }
    if (text.isEmpty) return;
    if (chat.running) {
      final choice = await _busyChoice();
      if (choice == null) return;
      _input.clear();
      switch (choice) {
        case 'steer':
          await chat.steer(text);
        case 'queue':
          chat.enqueue(text);
        case 'stop':
          await chat.stopAndSend(text);
      }
      return;
    }
    _input.clear();
    await chat.send(text);
  }

  Future<String?> _busyChoice() {
    final c = NgColors.of(context);
    return showNgSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                ngL.ng_hermes_is_still_working,
                style: NgType.title.copyWith(color: c.text),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.alt_route),
              title: Text(ngL.ng_steer),
              subtitle: Text(ngL.ng_adds_this_to_the_running_turn),
              onTap: () => Navigator.pop(context, 'steer'),
            ),
            ListTile(
              leading: const Icon(Icons.queue),
              title: Text(ngL.ng_queue),
              subtitle: Text(ngL.ng_sends_it_when_the_turn_finishes),
              onTap: () => Navigator.pop(context, 'queue'),
            ),
            ListTile(
              leading: Icon(Icons.stop_circle_outlined, color: c.danger),
              title: Text(ngL.ng_stop_and_send),
              subtitle: Text(ngL.ng_stops_the_turn_then_sends_this),
              onTap: () => Navigator.pop(context, 'stop'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleDictation() async {
    if (_listening) {
      await _voice?.stop();
      setState(() => _listening = false);
      return;
    }
    final voice = _voice ??= createVoiceComposerAdapter();
    final ok = await voice.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _listening = false);
        ngToast(context, ngL.ng_dictation_stopped(message));
      },
    );
    if (!ok) {
      if (mounted) ngToast(context, ngL.ng_speech_recognition_isn_t_available);
      return;
    }
    _beforeDictation = _input.text.trim();
    setState(() => _listening = true);
    await voice.listen(
      onResult: ({required transcript, required isFinal}) {
        final joined = [
          if (_beforeDictation.isNotEmpty) _beforeDictation,
          transcript,
        ].join(' ');
        _input.value = TextEditingValue(
          text: joined,
          selection: TextSelection.collapsed(offset: joined.length),
        );
        if (isFinal && mounted) setState(() => _listening = false);
      },
    );
  }

  String _subtitle(NgConnectionState state) {
    if (!state.isConnected) return state.label;
    if (chat.running) {
      final started = chat.turnStartedAt;
      final secs = started == null
          ? 0
          : DateTime.now().difference(started).inSeconds;
      final step = chat.status?.trim();
      return [
        ngL.ng_working,
        if (step != null && step.isNotEmpty) step,
        if (secs > 0) '${secs}s',
      ].join(' · ');
    }
    return chat.model ?? ngL.ng_ready;
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final gateway = NgScope.of(context).gateway;
    return ListenableBuilder(
      listenable: gateway,
      builder: (context, _) {
        final state = gateway.state;
        return Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              tooltip: ngL.ng_chats,
              icon: const Icon(Icons.view_sidebar_outlined),
              onPressed: widget.onOpenSidebar,
            ),
            titleSpacing: 0,
            title: GestureDetector(
              onTap: chat.isNew ? null : _rename,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.title.isEmpty ? ngL.ng_new_chat : chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgType.heading.copyWith(color: c.text),
                  ),
                  Text(
                    _subtitle(state),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgType.caption.copyWith(
                      color: state.isConnected ? c.text3 : c.warning,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (chat.usage != null)
                IconButton(
                  tooltip: ngL.ng_usage,
                  icon: const Icon(Icons.data_usage),
                  onPressed: _showUsage,
                ),
              IconButton(
                tooltip: ngL.ng_new_chat,
                icon: const Icon(Icons.edit_square),
                onPressed: widget.onNewChat,
              ),
            ],
          ),
          body: Column(
            children: [
              if (!state.isConnected) _connectionBanner(c, gateway),
              Expanded(child: _transcript(c)),
              if (chat.error != null) _errorBar(c),
              if (chat.queued.isNotEmpty) _queue(c),
              if (chat.request != null)
                _InputPanel(chat: chat, request: chat.request!)
              else
                _composer(c, state),
            ],
          ),
        );
      },
    );
  }

  Future<void> _rename() async {
    final title = await ngPromptText(
      context,
      title: ngL.ng_rename_chat,
      initial: chat.title,
    );
    if (title == null || title.trim().isEmpty) return;
    try {
      await chat.rename(title);
    } catch (e) {
      if (mounted) ngToast(context, ngL.ng_couldn_t_rename(e));
    }
  }

  void _showUsage() {
    final u = chat.usage!;
    final c = NgColors.of(context);
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: NgType.label.copyWith(color: c.text2)),
          ),
          Text(v, style: NgType.label.copyWith(color: c.text)),
        ],
      ),
    );
    showNgSheet<void>(
      context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ngL.ng_this_chat,
                style: NgType.title.copyWith(color: c.text),
              ),
              const SizedBox(height: 12),
              row(ngL.ng_input_tokens, ngCompactNumber(u.input)),
              row(ngL.ng_output_tokens, ngCompactNumber(u.output)),
              if (u.reasoning > 0)
                row(ngL.ng_reasoning_tokens, ngCompactNumber(u.reasoning)),
              if (u.cacheRead > 0)
                row(ngL.ng_cache_reads, ngCompactNumber(u.cacheRead)),
              if (u.calls > 0) row(ngL.ng_api_calls, '${u.calls}'),
              if (u.cost != null)
                row(ngL.ng_cost, '\$${u.cost!.toStringAsFixed(4)}'),
              if (u.contextUsed != null &&
                  u.contextMax != null &&
                  u.contextMax! > 0) ...[
                row(
                  ngL.ng_context,
                  '${ngCompactNumber(u.contextUsed!)} / '
                  '${ngCompactNumber(u.contextMax!)}',
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (u.contextUsed! / u.contextMax!).clamp(0, 1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectionBanner(NgColors c, NextGenGateway gateway) {
    final state = gateway.state;
    final expired = state.phase == NgConnectionPhase.sessionExpired;
    final failed = state.phase == NgConnectionPhase.failed;
    return Container(
      width: double.infinity,
      color: (expired || failed ? c.dangerSoft : c.warningSoft),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              expired
                  ? ngL.ng_your_sign_in_expired
                  : state.reason == null
                  ? state.label
                  : '${state.label} ${state.reason}',
              style: NgType.bodySmall.copyWith(color: c.text),
            ),
          ),
          if (expired)
            TextButton(
              onPressed: NgScope.of(context).signInAgain,
              child: Text(ngL.ng_sign_in_2),
            )
          else
            TextButton(onPressed: gateway.retry, child: Text(ngL.ng_retry)),
        ],
      ),
    );
  }

  Widget _errorBar(NgColors c) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
    decoration: BoxDecoration(
      color: c.dangerSoft,
      borderRadius: BorderRadius.circular(NgRadii.md),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            chat.error!,
            style: NgType.bodySmall.copyWith(color: c.text),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => setState(() => chat.error = null),
        ),
      ],
    ),
  );

  Widget _queue(NgColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final q in chat.queued)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(NgRadii.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_send, size: 16, color: c.text3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      q.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NgType.bodySmall.copyWith(color: c.text2),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => chat.unqueue(q),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _transcript(NgColors c) {
    if (chat.loadingHistory && chat.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (chat.items.isEmpty) {
      return NgGlow(
        child: NgEmpty(
          icon: Icons.auto_awesome,
          title: chat.historyError ?? ngL.ng_what_should_we_work_on,
          body: chat.historyError == null
              ? ngL.ng_ask_hermes_anything_it_can_run
              : null,
        ),
      );
    }
    final items = chat.items;
    final lastUserIndex = items.lastIndexWhere((i) => i is NgUserItem);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      itemCount: items.length + (chat.running ? 1 : 0),
      itemBuilder: (context, index) {
        if (chat.running && index == 0) return _statusLine(c);
        final i = items.length - 1 - (index - (chat.running ? 1 : 0));
        final item = items[i];
        return switch (item) {
          NgUserItem() => _UserBubble(
            item: item,
            onRetry: i == lastUserIndex && !chat.running
                ? chat.retryLast
                : null,
          ),
          NgAssistantItem() => _AssistantBlock(
            item: item,
            last: i == items.length - 1,
            onRetry: i == items.length - 1 && !chat.running
                ? chat.retryLast
                : null,
          ),
          NgNoticeItem() => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              item.text,
              textAlign: TextAlign.center,
              style: NgType.caption.copyWith(
                color: item.error ? c.danger : c.text3,
              ),
            ),
          ),
        };
      },
    );
  }

  Widget _statusLine(NgColors c) {
    final frame = chat.thinkingFrame ?? chat.status;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: c.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              frame == null || frame.isEmpty
                  ? ngL.ng_working
                  : ngL.ng_working_2(frame),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NgType.bodySmall.copyWith(color: c.text3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer(NgColors c, NgConnectionState state) {
    final hasText = _input.text.trim().isNotEmpty;
    final canSend = hasText || (_drafts.isNotEmpty && !chat.running);
    final modelLabel = [
      chat.model == null ? ngL.ng_default_model : _shortModel(chat.model!),
      if (chat.reasoningEffort != null && chat.reasoningEffort!.isNotEmpty)
        ngEffortLabel(chat.reasoningEffort),
    ].join(' · ');
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: c.input,
            borderRadius: BorderRadius.circular(NgRadii.xl),
            border: Border.all(color: c.stroke),
          ),
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_drafts.isNotEmpty || _preparing)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                    children: [
                      for (final d in _drafts)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InputChip(
                            avatar: Icon(
                              d.kind == AttachmentDraftKind.image
                                  ? Icons.image_outlined
                                  : Icons.insert_drive_file_outlined,
                              size: 16,
                            ),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                d.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onDeleted: () => _removeDraft(d),
                          ),
                        ),
                      if (_preparing)
                        const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
              TextField(
                controller: _input,
                focusNode: _focus,
                minLines: 1,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                style: NgType.body.copyWith(color: c.text),
                decoration: InputDecoration(
                  hintText: _listening
                      ? ngL.ng_listening
                      : chat.running
                      ? ngL.ng_steer_or_queue_a_message
                      : ngL.ng_message_hermes,
                  hintStyle: NgType.body.copyWith(color: c.textMuted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: ngL.ng_attach,
                    icon: Icon(Icons.add_circle_outline, color: c.text2),
                    onPressed: _preparing ? null : _attach,
                  ),
                  Flexible(
                    child: NgPill(
                      modelLabel,
                      icon: Icons.auto_awesome,
                      onTap: () => showNgModelSheet(context, chat),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: _listening
                        ? ngL.ng_stop_dictation
                        : ngL.ng_dictate,
                    icon: Icon(
                      _listening ? Icons.mic : Icons.mic_none,
                      color: _listening ? c.accent : c.text2,
                    ),
                    onPressed: _toggleDictation,
                  ),
                  if (chat.running && !hasText)
                    IconButton.filled(
                      tooltip: ngL.ng_stop,
                      style: IconButton.styleFrom(
                        backgroundColor: c.inverse,
                        foregroundColor: c.onInverse,
                      ),
                      icon: const Icon(Icons.stop_rounded),
                      onPressed: chat.stop,
                    )
                  else
                    IconButton.filled(
                      tooltip: ngL.ng_send,
                      style: IconButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: c.onAccent,
                        disabledBackgroundColor: c.surface3,
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded),
                      onPressed: canSend ? _send : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _shortModel(String model) {
    final slash = model.lastIndexOf('/');
    return slash >= 0 ? model.substring(slash + 1) : model;
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.item, this.onRetry});
  final NgUserItem item;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4, left: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (item.steered)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 4),
              child: Text(
                ngL.ng_steered,
                style: NgType.caption.copyWith(color: c.text3),
              ),
            ),
          if (item.text.isNotEmpty)
            GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: item.text));
                ngToast(context, ngL.ng_copied);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: c.userBubble,
                  borderRadius: BorderRadius.circular(NgRadii.lg),
                ),
                child: SelectableText(
                  item.text,
                  style: NgType.body.copyWith(
                    color: c.onUserBubble.withValues(
                      alpha: item.pending ? 0.6 : 1,
                    ),
                  ),
                ),
              ),
            ),
          if (item.attachments.isEmpty && item.files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  for (final f in item.files)
                    NgPill(f, icon: Icons.attach_file),
                ],
              ),
            ),
          if (item.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  for (final a in item.attachments)
                    NgPill(
                      a.name,
                      icon: a.status == AttachmentDraftStatus.failed
                          ? Icons.error_outline
                          : a.kind == AttachmentDraftKind.image
                          ? Icons.image_outlined
                          : Icons.attach_file,
                      tone: a.status == AttachmentDraftStatus.failed
                          ? NgTone.danger
                          : NgTone.neutral,
                    ),
                ],
              ),
            ),
          if (item.failure != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      ngL.ng_not_sent(item.failure ?? ''),
                      style: NgType.caption.copyWith(color: c.danger),
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(onPressed: onRetry, child: Text(ngL.ng_retry)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AssistantBlock extends StatefulWidget {
  const _AssistantBlock({required this.item, required this.last, this.onRetry});
  final NgAssistantItem item;
  final bool last;
  final VoidCallback? onRetry;

  @override
  State<_AssistantBlock> createState() => _AssistantBlockState();
}

class _AssistantBlockState extends State<_AssistantBlock> {
  bool _showThinking = false;
  bool _showTools = false;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final item = widget.item;
    final tools = item.tools;
    final runningTool = tools.where((t) => t.running).lastOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.reasoning.trim().isNotEmpty)
            _Disclosure(
              icon: Icons.psychology_outlined,
              label: item.open && item.text.isEmpty
                  ? ngL.ng_thinking
                  : ngL.ng_thought,
              open: _showThinking,
              onTap: () => setState(() => _showThinking = !_showThinking),
              child: Text(
                item.reasoning.trim(),
                style: NgType.bodySmall.copyWith(color: c.text3),
              ),
            ),
          if (tools.isNotEmpty)
            _Disclosure(
              icon: Icons.build_outlined,
              label: runningTool != null
                  ? '${runningTool.name}${runningTool.detail == null ? '' : ' · ${runningTool.detail}'}'
                  : tools.length == 1
                  ? ngL.ng_used(tools.first.name)
                  : ngL.ng_used_tools(tools.length),
              busy: runningTool != null,
              open: _showTools,
              onTap: () => setState(() => _showTools = !_showTools),
              child: Column(
                children: [for (final t in tools) _ToolRow(tool: t)],
              ),
            ),
          if (item.text.isNotEmpty)
            MarkdownBody(
              data: item.text,
              selectable: true,
              onTapLink: (text, href, title) {
                final uri = href == null ? null : Uri.tryParse(href);
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: NgType.body.copyWith(color: c.text),
                    listBullet: NgType.body.copyWith(color: c.text),
                    h1: NgType.title.copyWith(color: c.text),
                    h2: NgType.heading.copyWith(color: c.text, fontSize: 18),
                    h3: NgType.heading.copyWith(color: c.text),
                    code: NgType.code.copyWith(
                      color: c.text,
                      backgroundColor: c.well,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: c.well,
                      borderRadius: BorderRadius.circular(NgRadii.md),
                      border: Border.all(color: c.stroke),
                    ),
                    codeblockPadding: const EdgeInsets.all(12),
                    blockquoteDecoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: c.strokeStrong, width: 3),
                      ),
                    ),
                    a: NgType.body.copyWith(color: c.accentText),
                    tableBorder: TableBorder.all(color: c.stroke),
                  ),
            ),
          if (!item.open && item.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  _ActionIcon(
                    icon: Icons.copy_rounded,
                    tooltip: ngL.ng_copy,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: item.text));
                      ngToast(context, ngL.ng_copied);
                    },
                  ),
                  if (widget.onRetry != null)
                    _ActionIcon(
                      icon: Icons.refresh_rounded,
                      tooltip: ngL.ng_retry,
                      onTap: widget.onRetry!,
                    ),
                  if (item.outputTokens != null && item.outputTokens! > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        '${ngCompactNumber(item.outputTokens!)} tokens',
                        style: NgType.caption.copyWith(color: c.textMuted),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 17,
      color: c.text3,
      icon: Icon(icon),
      onPressed: onTap,
    );
  }
}

class _Disclosure extends StatelessWidget {
  const _Disclosure({
    required this.icon,
    required this.label,
    required this.open,
    required this.onTap,
    required this.child,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final bool open;
  final bool busy;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(NgRadii.sm),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: c.accent,
                      ),
                    )
                  else
                    Icon(icon, size: 16, color: c.text3),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NgType.label.copyWith(color: c.text3),
                    ),
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: c.text3,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(NgRadii.md),
                border: Border.all(color: c.stroke),
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _ToolRow extends StatefulWidget {
  const _ToolRow({required this.tool});
  final NgTool tool;

  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final t = widget.tool;
    final detail = t.summary ?? t.detail;
    final hasBody =
        (t.input?.isNotEmpty ?? false) || (t.output?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasBody ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  t.running
                      ? Icons.more_horiz
                      : t.failed
                      ? Icons.error_outline
                      : Icons.check,
                  size: 15,
                  color: t.failed ? c.danger : c.text3,
                ),
                const SizedBox(width: 8),
                Text(t.name, style: NgType.label.copyWith(color: c.text2)),
                if (detail != null && detail.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NgType.caption.copyWith(color: c.text3),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (t.durationSeconds != null)
                  Text(
                    '${t.durationSeconds!.toStringAsFixed(1)}s',
                    style: NgType.caption.copyWith(color: c.textMuted),
                  ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          if (t.input?.isNotEmpty ?? false) _codeBlock(c, t.input!),
          if (t.output?.isNotEmpty ?? false) _codeBlock(c, t.output!),
        ],
      ],
    );
  }

  Widget _codeBlock(NgColors c, String text) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: c.well,
      borderRadius: BorderRadius.circular(NgRadii.sm),
    ),
    child: SelectableText(
      text.length > 4000 ? '${text.substring(0, 4000)}…' : text,
      style: NgType.code.copyWith(color: c.text2, fontSize: 11.5),
    ),
  );
}

/// What the agent is waiting on: approval, a question or a secret.
class _InputPanel extends StatefulWidget {
  const _InputPanel({required this.chat, required this.request});
  final NgChatController chat;
  final NgInputRequest request;

  @override
  State<_InputPanel> createState() => _InputPanelState();
}

class _InputPanelState extends State<_InputPanel> {
  final _text = TextEditingController();
  final _user = TextEditingController();
  late List<Set<String>> _picked;
  late List<TextEditingController> _answers;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant _InputPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) {
      for (final a in _answers) {
        a.dispose();
      }
      _text.clear();
      _user.clear();
      _reset();
    }
  }

  void _reset() {
    _picked = [for (final _ in widget.request.questions) <String>{}];
    _answers = [
      for (final _ in widget.request.questions) TextEditingController(),
    ];
  }

  @override
  void dispose() {
    _text.dispose();
    _user.dispose();
    for (final a in _answers) {
      a.dispose();
    }
    super.dispose();
  }

  void _done(bool ok) {
    if (!ok && mounted) {
      ngToast(context, ngL.ng_the_gateway_connection_dropped_try_again);
    }
  }

  static String _choiceLabel(String choice) => switch (choice) {
    'once' => ngL.ng_allow_once,
    'session' => ngL.ng_allow_for_this_chat,
    'always' => ngL.ng_always_allow,
    'deny' => ngL.ng_deny,
    _ => choice,
  };

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final r = widget.request;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(NgRadii.xl),
          border: Border.all(color: c.accent.withValues(alpha: 0.5)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.pan_tool_alt, size: 18, color: c.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.title,
                      style: NgType.heading.copyWith(color: c.text),
                    ),
                  ),
                ],
              ),
              if (r.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(r.body, style: NgType.bodySmall.copyWith(color: c.text2)),
              ],
              if (r.command != null && r.command!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.well,
                    borderRadius: BorderRadius.circular(NgRadii.sm),
                  ),
                  child: SelectableText(
                    r.command!,
                    style: NgType.code.copyWith(color: c.text),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              ..._body(c, r),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(NgColors c, NgInputRequest r) {
    switch (r.kind) {
      case NgRequestKind.approval:
        return [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in r.choices)
                choice == 'deny'
                    ? OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.danger,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () =>
                            _done(widget.chat.answerApproval(choice)),
                        child: Text(_choiceLabel(choice)),
                      )
                    : FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: choice == 'once'
                              ? c.accent
                              : c.surface3,
                          foregroundColor: choice == 'once'
                              ? c.onAccent
                              : c.text,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () =>
                            _done(widget.chat.answerApproval(choice)),
                        child: Text(_choiceLabel(choice)),
                      ),
            ],
          ),
        ];
      case NgRequestKind.clarify:
        return [
          for (var i = 0; i < r.questions.length; i++) ...[
            if (r.questions.length > 1 || r.questions[i].question.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  r.questions[i].question,
                  style: NgType.label.copyWith(color: c.text),
                ),
              ),
            if (r.questions[i].choices.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final choice in r.questions[i].choices)
                    FilterChip(
                      label: Text(choice),
                      selected: _picked[i].contains(choice),
                      onSelected: (on) => setState(() {
                        if (!r.questions[i].multiSelect) _picked[i].clear();
                        on ? _picked[i].add(choice) : _picked[i].remove(choice);
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            NgField(
              controller: _answers[i],
              hint: r.questions[i].choices.isEmpty
                  ? ngL.ng_your_answer
                  : ngL.ng_or_type_an_answer,
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              TextButton(
                onPressed: () => _done(widget.chat.cancelClarify()),
                child: Text(ngL.ng_skip),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  shape: const StadiumBorder(),
                ),
                onPressed: () => _done(
                  widget.chat.answerClarify([
                    for (var i = 0; i < r.questions.length; i++)
                      _answers[i].text.trim().isNotEmpty
                          ? [_answers[i].text.trim()]
                          : _picked[i].toList(),
                  ]),
                ),
                child: Text(ngL.ng_answer),
              ),
            ],
          ),
        ];
      case NgRequestKind.secret:
        return [
          NgField(controller: _text, obscure: r.masked, autofocus: true),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => _done(widget.chat.answerValue('')),
                child: Text(ngL.ng_cancel),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  shape: const StadiumBorder(),
                ),
                onPressed: () => _done(widget.chat.answerValue(_text.text)),
                child: Text(ngL.ng_send),
              ),
            ],
          ),
        ];
      case NgRequestKind.saveLogin:
        return [
          NgField(controller: _user, label: ngL.ng_username_or_email),
          const SizedBox(height: 10),
          NgField(controller: _text, label: ngL.ng_password, obscure: true),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => _done(widget.chat.answerSaveLogin('', '')),
                child: Text(ngL.ng_not_now),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  shape: const StadiumBorder(),
                ),
                onPressed: () => _done(
                  widget.chat.answerSaveLogin(_user.text.trim(), _text.text),
                ),
                child: Text(ngL.ng_save),
              ),
            ],
          ),
        ];
    }
  }
}
