# Ares privacy policy

**Effective: 14 November 2026**

Ares (formerly Hermes Android) is a free, open-source client for a Hermes Agent server chosen by you or your organisation. The app developer does not operate that server and does not receive your chats by default.

For privacy questions or requests, open an issue at <https://github.com/rusty4444/hermes-android/issues>. Do not post passwords, access tokens, private chats or other sensitive material in a public issue.

## Information stored on your device

Ares stores the settings and connection details needed to provide the app, including gateway addresses, usernames, display preferences, chat drafts and cached files. Passwords, tokens and private keys are stored using Android-backed secure storage where the platform supports it. Configuration backups can contain sensitive connection material and are encrypted with the passphrase you choose.

You can remove local app data by clearing the app's storage or uninstalling it. Removing the app does not delete data held by your Hermes server.

## Information sent to your Hermes server

When you use Ares, the app sends your chosen Hermes server the information needed to perform your requests. This can include:

- prompts, chat content and session identifiers;
- photos, documents and other files you attach or download;
- microphone audio when you explicitly use dictation or voice features;
- authentication details and client certificates needed to connect;
- model, approval, scheduled-job, project, memory and settings actions you choose.

The server operator controls that server's retention, logging, model providers and onward disclosures. Ares does not select or operate those model providers for you. Review your server operator's privacy arrangements.

## Distribution and update services

The GitHub APK build can check GitHub Releases for updates. That request discloses ordinary connection metadata such as your IP address and user agent to GitHub. An in-app APK download also retrieves the selected release from GitHub. GitHub's own privacy terms apply.

The Google Play build uses Play-managed updates and does not perform the GitHub update check. Google Play's operation is covered by Google's privacy terms.

## Optional notifications and push

Notifications can be disabled in Android or in the app. Optional push delivery requires the separately installed and authorised mobile-push server companion. Depending on your choices, the service may process session identifiers, registration tokens, endpoint addresses and encrypted challenge material. Notification text is kept minimal by design.

A compatible UnifiedPush distributor or Google Play Services may process registration and delivery data. The relevant provider's privacy terms apply. Background delivery is best-effort.

## Analytics, advertising and marketing

Ares contains no advertising SDK and no developer-operated analytics service. It does not sell personal information or use chat content for advertising.

## AI output reports

The **Report AI output** action opens a new public GitHub issue in your browser. Ares does not automatically attach the reply, chat history, credentials or attachment paths. You choose what to submit. Remove sensitive material before posting. Where possible, report safety concerns without publishing personal data.

## External links and user-selected services

Ares can open links in your browser and can share files only when you choose the relevant action. Those destinations are governed by their own privacy policies. A link or file is not sent to a third party by the app unless you request that action.

## Changes

Material changes to this policy will be committed to this repository with the app release that contains them. The effective date above will be updated.
