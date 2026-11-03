# Long pastes

In a Remote Gateway chat, pasting **more than 3,000 characters in one edit**
creates a `paste.txt` attachment instead of leaving the full text in the
composer. Further pastes use `paste-2.txt`, `paste-3.txt`, and so on when those
names are already in the draft. The threshold counts UTF-16 code units, matching
Hermes Desktop; exactly 3,000 characters and short multiline pastes stay inline.

Type your instructions before or after pasting. Only the inserted text becomes
the attachment. Pasting over a selection replaces that selection without
removing the rest of your instructions. Whitespace, Unicode and line endings
are preserved in the UTF-8 file.

The attachment uses the existing file controls: reorder or remove it before
sending. Nothing is uploaded until you tap **Send**. The app uploads each file
through `file.attach` and submits the gateway's returned reference with your
instructions, not a phone-local path or a second copy of the pasted text. No
new server method, plugin or configuration is required.

## Safety and compatibility

- Text remains in the composer until its local file has been prepared. If file
  creation or an attachment limit fails, the text stays inline and the app
  explains the fallback. The usual limits apply: 10 items, 16 MiB per text file
  and 64 MiB total per draft.
- Send is unavailable during local paste preparation, but the text remains
  editable. If you edit or clear it while preparation is pending, that newer
  edit wins and the unused temporary file is removed.
- Unsent pasted content is included in the existing text-draft checkpoint.
  Leaving and reopening a chat restores it **inline**, with the remaining
  instructions, rather than relying on a temporary attachment cache surviving.
  Explicitly removing a paste attachment also removes its recovery copy.
  Nonempty whitespace is preserved in text drafts; only clearing to an empty
  string removes a draft.
- Legacy REST connections cannot upload general files, so long pastes remain
  ordinary message text there. Pasting during an active response or send also
  leaves text inline and does not add files to an already admitted turn.
- Android keyboards can deliver clipboard text as a committed editing update
  rather than a separate Paste event. The app recognises a single paste-sized
  insertion or selection replacement. Ordinary typing, active IME composition,
  in-app dictation and programmatic draft restoration are not converted. A
  keyboard's committed snippet or dictation insertion is indistinguishable from
  a paste of the same size and can also become an attachment.

Phone keyboard and clipboard behaviour can vary. Automated tests exercise
Flutter's toolbar-paste path and Android-style editing updates; these are not a
substitute for testing on a physical phone.
