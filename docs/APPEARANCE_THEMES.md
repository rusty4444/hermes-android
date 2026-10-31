# Appearance themes

Hermes Android has ten device-wide colour themes: **Gold, Purple, Orange, Green, Blue, Red, Teal, Pink, Indigo and Cyan**.

## Choosing a theme

- Open **More → Settings → Appearance → Colour theme**, or tap the palette icon on the connection screen.
- Choose a colour. Changes apply immediately across existing screens without closing chats or discarding composer drafts.
- Choose **System**, **Light** or **Dark** independently of the colour theme.
- Appearance controls work without a gateway connection and remain available if loading server settings fails.
- The selected colour and brightness mode survive app restarts and are included in configuration backups. A rejected settings write restores the prior selection and displays an error; appearance writes are serialised so a failed older choice cannot overwrite a newer one.

## Colour coverage

The palette supplies the complete Material colour scheme and Hermes design tokens, including tinted backgrounds and cards, app bars, navigation, buttons, switches, input fields, menus, sheets, dialogs, selection, chat bubbles, tool cards and code blocks. Markdown text and code syntax use foreground colours suited to their actual backgrounds. The Hermes wordmark retains its Cinzel font and follows the chosen accent.

Status colours retain their meaning: errors remain red, success remains green, and warnings remain amber. Their tones adapt to light/dark mode. Alternative-colour swatches and media content are not recoloured. Fullscreen image viewing deliberately retains a black canvas and a white close icon on a black button.

The Android launcher icon and native launch screen are branding assets, not Flutter theme surfaces. Once Flutter is visible, status icons follow the app's selected light/dark mode. Gesture navigation remains transparent over the themed app. Three-button navigation receives a palette-matched surface in the OS-compatible brightness, because some Android versions tint those system buttons from the OS mode even when the app requests otherwise. This narrow system-chrome exception keeps buttons readable when the app and OS use opposite modes; it does not alter the chosen app theme.

## Development and regression checks

- `lib/core/theme/hermes_theme.dart` owns palette seeds, semantic ramps, full colour schemes and component defaults.
- Read active colours through `HermesTokens.of(context)` or `Theme.of(context).colorScheme`. Do not instantiate default token sets inside presentation widgets; doing so ignores the selected palette.
- Use the paired `onAccent` and `onAccentContainer` foregrounds over their respective fills. Use `foregroundFor` for opaque semantic fills, not a fixed white/black assumption.
- `ThemePreferenceStore` persists enum names under `theme_palette`, independently of `theme_mode`. Unknown or incorrectly typed values fall back non-destructively to Gold.
- Save and rollback completion refresh the surviving app even if the Appearance sheet or picker has closed. Only picker-local state and error snackbars depend on the picker still being mounted.
- Code-block caches retain parser nodes, not theme-dependent text styles, so existing blocks recolour on same-brightness palette changes.
- Contrast tests cover every palette in light/dark mode, normal-size body/muted/accent text, semantic badges, selected surfaces, scheme pairs and component foregrounds with a minimum 4.5:1 text contrast.
- Widget tests cover live selection, navigation/draft retention, restart, backup restoration, offline Settings, and compact layouts with enlarged text.
- `test/theme_source_guard_test.dart` rejects fixed UI colours outside the design system, apart from narrow media exceptions.

Run Flutter validation serially in a checkout to avoid races in generated test assets:

```sh
flutter gen-l10n
flutter analyze --no-pub --fatal-infos
flutter test --no-pub
flutter build apk --debug --target-platform android-arm64 --no-pub
```
