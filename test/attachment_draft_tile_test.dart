import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/services/attachment_draft_service.dart';
import 'package:hermes_android/core/widgets/attachment_draft_tile.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'move controls are semantic, disabled at edges, and reorder the list',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final service = AttachmentDraftService();
      final drafts = <AttachmentDraft>[
        AttachmentDraft(
          id: 'first',
          cachedPath: 'first.bin',
          name: 'first.bin',
          byteLength: 1,
          mediaType: 'application/octet-stream',
          kind: AttachmentDraftKind.genericFile,
        ),
        AttachmentDraft(
          id: 'second',
          cachedPath: 'second.bin',
          name: 'second.bin',
          byteLength: 1,
          mediaType: 'application/octet-stream',
          kind: AttachmentDraftKind.genericFile,
        ),
      ];
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  for (var index = 0; index < drafts.length; index++)
                    AttachmentDraftTile(
                      draft: drafts[index],
                      index: index,
                      total: drafts.length,
                      busy: false,
                      onMovePrevious: () => setState(
                        () => service.moveDraft(
                          drafts,
                          fromIndex: index,
                          offset: -1,
                        ),
                      ),
                      onMoveNext: () => setState(
                        () => service.moveDraft(
                          drafts,
                          fromIndex: index,
                          offset: 1,
                        ),
                      ),
                      onRetry: () {},
                      onRemove: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      expect(find.byTooltip('Move attachment previous'), findsNWidgets(2));
      expect(find.byTooltip('Move attachment next'), findsNWidgets(2));
      final previousButtons = find.widgetWithIcon(
        IconButton,
        Icons.arrow_upward,
      );
      final nextButtons = find.widgetWithIcon(IconButton, Icons.arrow_downward);
      expect(
        tester.widget<IconButton>(previousButtons.at(0)).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(previousButtons.at(1)).onPressed,
        isNotNull,
      );
      expect(tester.widget<IconButton>(nextButtons.at(0)).onPressed, isNotNull);
      expect(tester.widget<IconButton>(nextButtons.at(1)).onPressed, isNull);
      expect(tester.getSize(nextButtons.at(0)).width, greaterThanOrEqualTo(48));
      expect(
        tester.getSize(nextButtons.at(0)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Move attachment next').first)
            .label,
        contains('Move attachment next'),
      );

      await tester.tap(nextButtons.at(0));
      await tester.pump();

      expect(drafts.map((draft) => draft.name), ['second.bin', 'first.bin']);
      expect(
        tester.widget<IconButton>(previousButtons.at(0)).onPressed,
        isNull,
      );
      expect(tester.widget<IconButton>(nextButtons.at(1)).onPressed, isNull);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('reports upload state without exposing the attachment name', (
    tester,
  ) async {
    const sensitiveName = 'private-medical-note.pdf';
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AttachmentDraftTile(
            draft: AttachmentDraft(
              id: 'failed',
              cachedPath: 'failed.bin',
              name: sensitiveName,
              byteLength: 1,
              mediaType: 'application/pdf',
              kind: AttachmentDraftKind.genericFile,
              status: AttachmentDraftStatus.failed,
            ),
            index: 0,
            total: 1,
            busy: false,
            onMovePrevious: () {},
            onMoveNext: () {},
            onRetry: () {},
            onRemove: () {},
          ),
        ),
      ),
    );

    final attachment = tester.getSemantics(
      find.bySemanticsLabel('Attachment 1 of 1'),
    );
    expect(attachment.value, 'Upload failed');
    expect(find.bySemanticsLabel('Retry upload'), findsOneWidget);
    expect(find.bySemanticsLabel(sensitiveName), findsNothing);
    final retry = find.widgetWithIcon(IconButton, Icons.refresh);
    expect(tester.getSize(retry), const Size(48, 48));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AttachmentDraftTile(
            draft: AttachmentDraft(
              id: 'uploading',
              cachedPath: 'uploading.bin',
              name: sensitiveName,
              byteLength: 1,
              mediaType: 'application/pdf',
              kind: AttachmentDraftKind.genericFile,
              status: AttachmentDraftStatus.uploading,
            ),
            index: 0,
            total: 1,
            busy: true,
            onMovePrevious: () {},
            onMoveNext: () {},
            onRetry: () {},
            onRemove: () {},
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Attachment 1 of 1')).value,
      'Uploading',
    );
    semantics.dispose();
  });

  testWidgets('attachment controls remain usable at font scale 200% on 320px', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final drafts = List.generate(
      10,
      (index) => AttachmentDraft(
        id: '$index',
        cachedPath: '$index.bin',
        name: 'attachment-$index-with-a-long-name.pdf',
        byteLength: 1024,
        mediaType: 'application/pdf',
        kind: AttachmentDraftKind.genericFile,
      ),
    );

    for (final width in [320.0, 360.0]) {
      tester.view.physicalSize = Size(width, 640);
      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SizedBox(
              height: 205,
              child: ListView.builder(
                itemCount: drafts.length,
                itemBuilder: (context, index) => AttachmentDraftTile(
                  draft: drafts[index],
                  index: index,
                  total: drafts.length,
                  busy: false,
                  onMovePrevious: () {},
                  onMoveNext: () {},
                  onRetry: () {},
                  onRemove: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.widgetWithIcon(IconButton, Icons.close).first),
        const Size(48, 48),
      );
    }
  });
}
