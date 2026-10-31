# Provider subscription usage

Usage separates provider-reported subscription limits from Hermes recorded session, token and cost analytics. OpenAI API billing is not Codex subscription allowance.

- Codex (`openai-codex`) reports `Session` as a **5-hour session** window and `Weekly` as a weekly window.
- Claude (`anthropic`) reports `Current session` as a **5-hour session** window and `Current week` as a weekly window. Model-specific weekly labels, such as `Opus week`, retain their provider labels and scope.
- Only these exact provider/session-label pairs receive the five-hour display label. Unknown labels, including labels belonging to another provider, remain unchanged.
- Only reported windows are shown. A weekly-only response does not imply a session window. Missing percentages and reset timestamps remain unavailable; the app does not calculate a reset from the session duration.
- Accounts are shown separately, never averaged. A model-scoped limit does not mean the entire account is exhausted.

The app reads the existing selected-profile model inventory independently of recorded analytics. Refresh is explicit; there are no added model calls, polling or direct provider authentication. An initially empty inventory can populate on Refresh.

Regression coverage: `test/provider_account_usage_test.dart` and `test/provider_review_test.dart`, including exact labels, unknown labels, weekly-only and empty inventory, model scopes, reset availability, locale fallback, independent failures and identity/lifecycle boundaries.
