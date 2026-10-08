import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('ja'),
    Locale('ko'),
    Locale('pt'),
    Locale('pt', 'BR'),
    Locale('ru'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ];

  /// No description provided for @a_one_off_question_archives_itself_after_72_hours_anything.
  ///
  /// In en, this message translates to:
  /// **'A one-off question. Archives itself after 72 hours; anything worth keeping is still remembered.'**
  String get a_one_off_question_archives_itself_after_72_hours_anything;

  /// No description provided for @ai_full_text.
  ///
  /// In en, this message translates to:
  /// **'AI + full-text'**
  String get ai_full_text;

  /// No description provided for @ai_search_model.
  ///
  /// In en, this message translates to:
  /// **'AI search model'**
  String get ai_search_model;

  /// No description provided for @ai_searched_for.
  ///
  /// In en, this message translates to:
  /// **'AI searched for: {aiRewrittenQuery}'**
  String ai_searched_for(Object aiRewrittenQuery);

  /// No description provided for @ai_assisted_filing.
  ///
  /// In en, this message translates to:
  /// **'AI-assisted filing'**
  String get ai_assisted_filing;

  /// No description provided for @api_key.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get api_key;

  /// No description provided for @api_server_key_from_hermes_env.
  ///
  /// In en, this message translates to:
  /// **'API_SERVER_KEY from ~/.hermes/.env'**
  String get api_server_key_from_hermes_env;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @activity_reads_the_durable_turn_journal_to_know_what_hermes.
  ///
  /// In en, this message translates to:
  /// **'Activity reads the durable turn journal to know what Hermes is doing. Check that the gateway is reachable, then try again.'**
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @add_connection.
  ///
  /// In en, this message translates to:
  /// **'Add Connection'**
  String get add_connection;

  /// No description provided for @add_cron_job.
  ///
  /// In en, this message translates to:
  /// **'Add Cron Job'**
  String get add_cron_job;

  /// No description provided for @add_gateway_connection.
  ///
  /// In en, this message translates to:
  /// **'Add Gateway Connection'**
  String get add_gateway_connection;

  /// No description provided for @add_and_update_connections_from_the_backup_keep_the_rest.
  ///
  /// In en, this message translates to:
  /// **'Add and update connections from the backup, keep the rest.'**
  String get add_and_update_connections_from_the_backup_keep_the_rest;

  /// No description provided for @add_attachment.
  ///
  /// In en, this message translates to:
  /// **'Add attachment'**
  String get add_attachment;

  /// No description provided for @add_new_cron_job.
  ///
  /// In en, this message translates to:
  /// **'Add new cron job'**
  String get add_new_cron_job;

  /// No description provided for @add_to_chat.
  ///
  /// In en, this message translates to:
  /// **'Add to chat'**
  String get add_to_chat;

  /// No description provided for @all_chats.
  ///
  /// In en, this message translates to:
  /// **'All chats'**
  String get all_chats;

  /// No description provided for @all_stored_message_content.
  ///
  /// In en, this message translates to:
  /// **'All stored message content'**
  String get all_stored_message_content;

  /// No description provided for @allow_for_this_session.
  ///
  /// In en, this message translates to:
  /// **'Allow for this session'**
  String get allow_for_this_session;

  /// No description provided for @allow_matching_commands_until_this_hermes_session_ends.
  ///
  /// In en, this message translates to:
  /// **'Allow matching commands until this Hermes session ends.'**
  String get allow_matching_commands_until_this_hermes_session_ends;

  /// No description provided for @allow_once.
  ///
  /// In en, this message translates to:
  /// **'Allow once'**
  String get allow_once;

  /// No description provided for @always_allow.
  ///
  /// In en, this message translates to:
  /// **'Always allow'**
  String get always_allow;

  /// No description provided for @apply_to_this_chat.
  ///
  /// In en, this message translates to:
  /// **'Apply to this chat'**
  String get apply_to_this_chat;

  /// No description provided for @approval_needed.
  ///
  /// In en, this message translates to:
  /// **'Approval needed'**
  String get approval_needed;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @archive_project.
  ///
  /// In en, this message translates to:
  /// **'Archive project'**
  String get archive_project;

  /// No description provided for @archive_2.
  ///
  /// In en, this message translates to:
  /// **'Archive {projectName}?'**
  String archive_2(Object projectName);

  /// No description provided for @archive_3.
  ///
  /// In en, this message translates to:
  /// **'Archive {name}?'**
  String archive_3(Object name);

  /// No description provided for @archived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archived;

  /// No description provided for @archived_conversations_appear_here.
  ///
  /// In en, this message translates to:
  /// **'Archived conversations appear here.'**
  String get archived_conversations_appear_here;

  /// No description provided for @archived_quick_chats.
  ///
  /// In en, this message translates to:
  /// **'Archived quick chats'**
  String get archived_quick_chats;

  /// No description provided for @artifacts_attachments_and_generated_media.
  ///
  /// In en, this message translates to:
  /// **'Artifacts, attachments, and generated media'**
  String get artifacts_attachments_and_generated_media;

  /// No description provided for @ask_ai_to_find_a_conversation.
  ///
  /// In en, this message translates to:
  /// **'Ask AI to find a conversation'**
  String get ask_ai_to_find_a_conversation;

  /// No description provided for @assets.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get assets;

  /// No description provided for @assets_need_a_server_authoritative_assets_index_in_the_hermes.
  ///
  /// In en, this message translates to:
  /// **'Assets need a server-authoritative Assets index in the Hermes Gateway before they can be shown per project.'**
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes;

  /// No description provided for @assets_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Assets unavailable'**
  String get assets_unavailable;

  /// No description provided for @attach_image_or_file.
  ///
  /// In en, this message translates to:
  /// **'Attach image or file'**
  String get attach_image_or_file;

  /// No description provided for @attachment_drafts.
  ///
  /// In en, this message translates to:
  /// **'Attachment drafts'**
  String get attachment_drafts;

  /// No description provided for @attachment_of.
  ///
  /// In en, this message translates to:
  /// **'Attachment {index} of {total}'**
  String attachment_of(Object index, Object total);

  /// No description provided for @auto_device_default.
  ///
  /// In en, this message translates to:
  /// **'Auto (device default)'**
  String get auto_device_default;

  /// No description provided for @auto_archives_after_72_hours.
  ///
  /// In en, this message translates to:
  /// **'Auto-archives after 72 hours'**
  String get auto_archives_after_72_hours;

  /// No description provided for @automation.
  ///
  /// In en, this message translates to:
  /// **'Automation'**
  String get automation;

  /// No description provided for @autonomous_agents.
  ///
  /// In en, this message translates to:
  /// **'Autonomous agents'**
  String get autonomous_agents;

  /// No description provided for @background_recovery_unavailable_legacy_transport.
  ///
  /// In en, this message translates to:
  /// **'Background recovery unavailable — legacy transport'**
  String get background_recovery_unavailable_legacy_transport;

  /// No description provided for @backup_restore.
  ///
  /// In en, this message translates to:
  /// **'Backup & restore'**
  String get backup_restore;

  /// No description provided for @backup_exported.
  ///
  /// In en, this message translates to:
  /// **'Backup exported — {destination}'**
  String backup_exported(Object destination);

  /// No description provided for @base_url.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get base_url;

  /// No description provided for @binary_preview_is_unavailable_download_the_file_to_open_it.
  ///
  /// In en, this message translates to:
  /// **'Binary preview is unavailable. Download the file to open it.'**
  String get binary_preview_is_unavailable_download_the_file_to_open_it;

  /// No description provided for @branch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get branch;

  /// No description provided for @branch_chat.
  ///
  /// In en, this message translates to:
  /// **'Branch chat'**
  String get branch_chat;

  /// No description provided for @branch_created_in_hermes_history.
  ///
  /// In en, this message translates to:
  /// **'Branch created in Hermes history.'**
  String get branch_created_in_hermes_history;

  /// No description provided for @browse_and_manage_your_hermes_agent_sessions_from_your_phone.
  ///
  /// In en, this message translates to:
  /// **'Browse and manage your Hermes Agent sessions from your phone. Connects to a Hermes dashboard running on your local network.'**
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone;

  /// No description provided for @browse_server_files.
  ///
  /// In en, this message translates to:
  /// **'Browse server files'**
  String get browse_server_files;

  /// No description provided for @browse_the_miniserver_folders_behind_your_projects.
  ///
  /// In en, this message translates to:
  /// **'Browse the miniserver folders behind your projects'**
  String get browse_the_miniserver_folders_behind_your_projects;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cancel_voice_input.
  ///
  /// In en, this message translates to:
  /// **'Cancel voice input'**
  String get cancel_voice_input;

  /// No description provided for @cannot_reach.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach {host}:{port}.'**
  String cannot_reach(Object host, Object port);

  /// No description provided for @cannot_reach_check_the_host_and_port.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach {host}:{port}. Check the host and port.'**
  String cannot_reach_check_the_host_and_port(Object host, Object port);

  /// No description provided for @change_ai_search_model.
  ///
  /// In en, this message translates to:
  /// **'Change AI search model'**
  String get change_ai_search_model;

  /// No description provided for @changes_the_default_for_use_the_selector_in_a_chat.
  ///
  /// In en, this message translates to:
  /// **'Changes the default for {label}. Use the selector in a chat to override only that conversation.'**
  String changes_the_default_for_use_the_selector_in_a_chat(Object label);

  /// No description provided for @chat_actions.
  ///
  /// In en, this message translates to:
  /// **'Chat actions'**
  String get chat_actions;

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @chats_from_this_gateway_are_not_grouped_yet_grouping_stays.
  ///
  /// In en, this message translates to:
  /// **'Chats from this gateway are not grouped yet. Grouping stays on this phone until the gateway can host projects.'**
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays;

  /// No description provided for @chats_in_this_project_will_show_their_state_and_last.
  ///
  /// In en, this message translates to:
  /// **'Chats in this project will show their state and last activity here.'**
  String get chats_in_this_project_will_show_their_state_and_last;

  /// No description provided for @chats_that_are_not_assigned_to_a_project.
  ///
  /// In en, this message translates to:
  /// **'Chats that are not assigned to a Project'**
  String get chats_that_are_not_assigned_to_a_project;

  /// No description provided for @chats_you_start_in_this_project_will_appear_here_on.
  ///
  /// In en, this message translates to:
  /// **'Chats you start in this project will appear here, on every device signed in to this Hermes.'**
  String get chats_you_start_in_this_project_will_appear_here_on;

  /// No description provided for @check_that_the_gateway_is_running_and_reachable_then_try.
  ///
  /// In en, this message translates to:
  /// **'Check that the gateway is running and reachable, then try again.'**
  String get check_that_the_gateway_is_running_and_reachable_then_try;

  /// No description provided for @check_the_dashboard_connection_and_try_again.
  ///
  /// In en, this message translates to:
  /// **'Check the Dashboard connection and try again.'**
  String get check_the_dashboard_connection_and_try_again;

  /// No description provided for @check_the_connection_and_try_again.
  ///
  /// In en, this message translates to:
  /// **'Check the connection and try again.'**
  String get check_the_connection_and_try_again;

  /// No description provided for @choose_a_small_model_to_rewrite_queries.
  ///
  /// In en, this message translates to:
  /// **'Choose a small model to rewrite queries'**
  String get choose_a_small_model_to_rewrite_queries;

  /// No description provided for @choose_an_ai_search_model_before_using_ai_search.
  ///
  /// In en, this message translates to:
  /// **'Choose an AI search model before using AI search.'**
  String get choose_an_ai_search_model_before_using_ai_search;

  /// No description provided for @choose_an_active_project_next.
  ///
  /// In en, this message translates to:
  /// **'Choose an active Project next'**
  String get choose_an_active_project_next;

  /// No description provided for @choose_chat_model.
  ///
  /// In en, this message translates to:
  /// **'Choose chat model'**
  String get choose_chat_model;

  /// No description provided for @choose_files.
  ///
  /// In en, this message translates to:
  /// **'Choose files'**
  String get choose_files;

  /// No description provided for @choose_image.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get choose_image;

  /// No description provided for @choose_images.
  ///
  /// In en, this message translates to:
  /// **'Choose images'**
  String get choose_images;

  /// No description provided for @choose_its_destination_space.
  ///
  /// In en, this message translates to:
  /// **'Choose its destination space'**
  String get choose_its_destination_space;

  /// No description provided for @clear_search.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clear_search;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @code_copied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get code_copied;

  /// No description provided for @coming_next.
  ///
  /// In en, this message translates to:
  /// **'Coming next'**
  String get coming_next;

  /// No description provided for @command.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get command;

  /// No description provided for @command_line_chats.
  ///
  /// In en, this message translates to:
  /// **'Command-line chats'**
  String get command_line_chats;

  /// No description provided for @compatibility_mode.
  ///
  /// In en, this message translates to:
  /// **'Compatibility mode'**
  String get compatibility_mode;

  /// No description provided for @configure_a_valid_desktop_gateway_url_before_attaching_files.
  ///
  /// In en, this message translates to:
  /// **'Configure a valid Desktop Gateway URL before attaching files.'**
  String get configure_a_valid_desktop_gateway_url_before_attaching_files;

  /// No description provided for @confirm_always_allow.
  ///
  /// In en, this message translates to:
  /// **'Confirm always allow'**
  String get confirm_always_allow;

  /// No description provided for @confirm_passphrase.
  ///
  /// In en, this message translates to:
  /// **'Confirm passphrase'**
  String get confirm_passphrase;

  /// No description provided for @connecting_to.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {baseUrl}...'**
  String connecting_to(Object baseUrl);

  /// No description provided for @connection_issue.
  ///
  /// In en, this message translates to:
  /// **'Connection issue'**
  String get connection_issue;

  /// No description provided for @connection_switched_the_running_reply_continues_on_the_server_and.
  ///
  /// In en, this message translates to:
  /// **'Connection switched — the running reply continues on the server and will reattach automatically.'**
  String get connection_switched_the_running_reply_continues_on_the_server_and;

  /// No description provided for @connection_appearance_and_device_preferences.
  ///
  /// In en, this message translates to:
  /// **'Connection, appearance, and device preferences'**
  String get connection_appearance_and_device_preferences;

  /// No description provided for @context_tokens.
  ///
  /// In en, this message translates to:
  /// **'Context: {effectiveContextLength} tokens'**
  String context_tokens(Object effectiveContextLength);

  /// No description provided for @continue_label.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continue_label;

  /// No description provided for @continue_working.
  ///
  /// In en, this message translates to:
  /// **'Continue working'**
  String get continue_working;

  /// No description provided for @conversations_in_this_project.
  ///
  /// In en, this message translates to:
  /// **'Conversations in this project'**
  String get conversations_in_this_project;

  /// No description provided for @copy_code.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copy_code;

  /// No description provided for @copy_message.
  ///
  /// In en, this message translates to:
  /// **'Copy message'**
  String get copy_message;

  /// No description provided for @could_not_branch_chat.
  ///
  /// In en, this message translates to:
  /// **'Could not branch chat: {error}'**
  String could_not_branch_chat(Object error);

  /// No description provided for @could_not_delete_session.
  ///
  /// In en, this message translates to:
  /// **'Could not delete session: {error}'**
  String could_not_delete_session(Object error);

  /// No description provided for @could_not_deny_the_command.
  ///
  /// In en, this message translates to:
  /// **'Could not deny the command: {error}'**
  String could_not_deny_the_command(Object error);

  /// No description provided for @could_not_load_ai_search_models.
  ///
  /// In en, this message translates to:
  /// **'Could not load AI search models: {error}'**
  String could_not_load_ai_search_models(Object error);

  /// No description provided for @could_not_load_conversations.
  ///
  /// In en, this message translates to:
  /// **'Could not load conversations'**
  String get could_not_load_conversations;

  /// No description provided for @could_not_load_files.
  ///
  /// In en, this message translates to:
  /// **'Could not load files'**
  String get could_not_load_files;

  /// No description provided for @could_not_load_models_for_this_profile.
  ///
  /// In en, this message translates to:
  /// **'Could not load models for this profile: {error}'**
  String could_not_load_models_for_this_profile(Object error);

  /// No description provided for @could_not_load_more_chats.
  ///
  /// In en, this message translates to:
  /// **'Could not load more chats: {error}'**
  String could_not_load_more_chats(Object error);

  /// No description provided for @could_not_open_the_hermes_dashboard.
  ///
  /// In en, this message translates to:
  /// **'Could not open the Hermes dashboard.'**
  String get could_not_open_the_hermes_dashboard;

  /// No description provided for @could_not_open_this_project.
  ///
  /// In en, this message translates to:
  /// **'Could not open this project'**
  String get could_not_open_this_project;

  /// No description provided for @could_not_preview_file.
  ///
  /// In en, this message translates to:
  /// **'Could not preview file'**
  String get could_not_preview_file;

  /// No description provided for @could_not_reach_hermes.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Hermes'**
  String get could_not_reach_hermes;

  /// No description provided for @could_not_reach_authenticate_the_dashboard_at_check_the_port.
  ///
  /// In en, this message translates to:
  /// **'Could not reach/authenticate the dashboard at {host}:{dashboardPort}. Check the port and credentials.'**
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  );

  /// No description provided for @could_not_read_activity.
  ///
  /// In en, this message translates to:
  /// **'Could not read activity'**
  String get could_not_read_activity;

  /// No description provided for @could_not_rename_chat.
  ///
  /// In en, this message translates to:
  /// **'Could not rename chat: {error}'**
  String could_not_rename_chat(Object error);

  /// No description provided for @could_not_send_the_approval.
  ///
  /// In en, this message translates to:
  /// **'Could not send the approval: {error}'**
  String could_not_send_the_approval(Object error);

  /// No description provided for @could_not_skip_the_hermes_question.
  ///
  /// In en, this message translates to:
  /// **'Could not skip the Hermes question.'**
  String get could_not_skip_the_hermes_question;

  /// No description provided for @could_not_the_project.
  ///
  /// In en, this message translates to:
  /// **'Could not {action} the project: {error}'**
  String could_not_the_project(Object action, Object error);

  /// No description provided for @couldn_t_delete_project.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t delete project'**
  String get couldn_t_delete_project;

  /// No description provided for @couldn_t_load_runs.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load runs: {error}'**
  String couldn_t_load_runs(Object error);

  /// No description provided for @couldn_t_move_conversation.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t move conversation'**
  String get couldn_t_move_conversation;

  /// No description provided for @couldn_t_move_to.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t move to {label}: {reason}'**
  String couldn_t_move_to(Object label, Object reason);

  /// No description provided for @couldn_t_prepare_the_shared_files.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t prepare the shared files.'**
  String get couldn_t_prepare_the_shared_files;

  /// No description provided for @couldn_t_promote_conversation.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t promote conversation'**
  String get couldn_t_promote_conversation;

  /// No description provided for @couldn_t_project.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t {action} project'**
  String couldn_t_project(Object action);

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @create_a_project.
  ///
  /// In en, this message translates to:
  /// **'Create a project'**
  String get create_a_project;

  /// No description provided for @create_a_project_first_then_chats_can_live_inside_it.
  ///
  /// In en, this message translates to:
  /// **'Create a project first, then chats can live inside it.'**
  String get create_a_project_first_then_chats_can_live_inside_it;

  /// No description provided for @create_a_space_to_separate_related_conversations.
  ///
  /// In en, this message translates to:
  /// **'Create a space to separate related conversations.'**
  String get create_a_space_to_separate_related_conversations;

  /// No description provided for @create_branch.
  ///
  /// In en, this message translates to:
  /// **'Create branch'**
  String get create_branch;

  /// No description provided for @cron.
  ///
  /// In en, this message translates to:
  /// **'Cron'**
  String get cron;

  /// No description provided for @cron_jobs.
  ///
  /// In en, this message translates to:
  /// **'Cron Jobs'**
  String get cron_jobs;

  /// No description provided for @cron_job_added.
  ///
  /// In en, this message translates to:
  /// **'Cron job added'**
  String get cron_job_added;

  /// No description provided for @cron_job_updated.
  ///
  /// In en, this message translates to:
  /// **'Cron job updated'**
  String get cron_job_updated;

  /// No description provided for @cron_run.
  ///
  /// In en, this message translates to:
  /// **'Cron run'**
  String get cron_run;

  /// No description provided for @cross_device_ordering_and_reversible_bulk_organization.
  ///
  /// In en, this message translates to:
  /// **'Cross-device ordering and reversible bulk organization'**
  String get cross_device_ordering_and_reversible_bulk_organization;

  /// No description provided for @current_profile_default.
  ///
  /// In en, this message translates to:
  /// **'Current profile default'**
  String get current_profile_default;

  /// No description provided for @custom_proxy_and_dashboard_details.
  ///
  /// In en, this message translates to:
  /// **'Custom proxy and dashboard details'**
  String get custom_proxy_and_dashboard_details;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @dashboard_proxy_settings.
  ///
  /// In en, this message translates to:
  /// **'Dashboard / Proxy Settings'**
  String get dashboard_proxy_settings;

  /// No description provided for @dashboard_password_optional.
  ///
  /// In en, this message translates to:
  /// **'Dashboard Password (optional)'**
  String get dashboard_password_optional;

  /// No description provided for @dashboard_port.
  ///
  /// In en, this message translates to:
  /// **'Dashboard Port'**
  String get dashboard_port;

  /// No description provided for @dashboard_username_optional.
  ///
  /// In en, this message translates to:
  /// **'Dashboard Username (optional)'**
  String get dashboard_username_optional;

  /// No description provided for @dashboard_behind_proxy.
  ///
  /// In en, this message translates to:
  /// **'Dashboard behind proxy'**
  String get dashboard_behind_proxy;

  /// No description provided for @dashboard_path_prefix.
  ///
  /// In en, this message translates to:
  /// **'Dashboard path prefix'**
  String get dashboard_path_prefix;

  /// No description provided for @delegated_task.
  ///
  /// In en, this message translates to:
  /// **'Delegated task: {goal}'**
  String delegated_task(Object goal);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @delete_2.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String delete_2(Object name);

  /// No description provided for @delete_from_the_remote_hermes_history_this_cannot_be_undone.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\" from the remote Hermes history? This cannot be undone.'**
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  );

  /// No description provided for @delete_cron_job.
  ///
  /// In en, this message translates to:
  /// **'Delete Cron Job'**
  String get delete_cron_job;

  /// No description provided for @delete_connections_that_are_not_in_the_backup.
  ///
  /// In en, this message translates to:
  /// **'Delete connections that are not in the backup.'**
  String get delete_connections_that_are_not_in_the_backup;

  /// No description provided for @delete_failed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String delete_failed(Object error);

  /// No description provided for @delete_project.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get delete_project;

  /// No description provided for @delete_session.
  ///
  /// In en, this message translates to:
  /// **'Delete session?'**
  String get delete_session;

  /// No description provided for @delete_3.
  ///
  /// In en, this message translates to:
  /// **'Delete {projectName}?'**
  String delete_3(Object projectName);

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{name}\"'**
  String deleted(Object name);

  /// No description provided for @delivery_is_uncertain_recovering_without_resending.
  ///
  /// In en, this message translates to:
  /// **'Delivery is uncertain; recovering without resending…'**
  String get delivery_is_uncertain_recovering_without_resending;

  /// No description provided for @desktop_gateway_url_optional.
  ///
  /// In en, this message translates to:
  /// **'Desktop Gateway URL (optional)'**
  String get desktop_gateway_url_optional;

  /// No description provided for @desktop_gateway_is_not_configured_for_this_connection.
  ///
  /// In en, this message translates to:
  /// **'Desktop Gateway is not configured for this connection.'**
  String get desktop_gateway_is_not_configured_for_this_connection;

  /// No description provided for @desktop_app.
  ///
  /// In en, this message translates to:
  /// **'Desktop app'**
  String get desktop_app;

  /// No description provided for @developer_tool_calls.
  ///
  /// In en, this message translates to:
  /// **'Developer tool calls'**
  String get developer_tool_calls;

  /// No description provided for @discord_chats.
  ///
  /// In en, this message translates to:
  /// **'Discord chats'**
  String get discord_chats;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @do_not_run_this_command.
  ///
  /// In en, this message translates to:
  /// **'Do not run this command.'**
  String get do_not_run_this_command;

  /// No description provided for @documents_archives_audio_video_or_data.
  ///
  /// In en, this message translates to:
  /// **'Documents, archives, audio, video, or data'**
  String get documents_archives_audio_video_or_data;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @download_failed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String download_failed(Object error);

  /// No description provided for @durable_facts_hermes_keeps_about_you.
  ///
  /// In en, this message translates to:
  /// **'Durable facts Hermes keeps about you'**
  String get durable_facts_hermes_keeps_about_you;

  /// No description provided for @durable_work_inside_one_of_your_projects_shared_with_desktop.
  ///
  /// In en, this message translates to:
  /// **'Durable work inside one of your projects, shared with Desktop.'**
  String get durable_work_inside_one_of_your_projects_shared_with_desktop;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @edit_connection.
  ///
  /// In en, this message translates to:
  /// **'Edit Connection'**
  String get edit_connection;

  /// No description provided for @edit_cron_job.
  ///
  /// In en, this message translates to:
  /// **'Edit Cron Job'**
  String get edit_cron_job;

  /// No description provided for @edit_gateway_connection.
  ///
  /// In en, this message translates to:
  /// **'Edit Gateway Connection'**
  String get edit_gateway_connection;

  /// No description provided for @edit_and_resend.
  ///
  /// In en, this message translates to:
  /// **'Edit and resend'**
  String get edit_and_resend;

  /// No description provided for @enables_file_attachments_through_the_desktop_remote_gateway.
  ///
  /// In en, this message translates to:
  /// **'Enables file attachments through the Desktop remote gateway.'**
  String get enables_file_attachments_through_the_desktop_remote_gateway;

  /// No description provided for @enter_a_name.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get enter_a_name;

  /// No description provided for @enter_a_passphrase.
  ///
  /// In en, this message translates to:
  /// **'Enter a passphrase.'**
  String get enter_a_passphrase;

  /// No description provided for @enter_the_passphrase_for_this_backup.
  ///
  /// In en, this message translates to:
  /// **'Enter the passphrase for this backup.'**
  String get enter_the_passphrase_for_this_backup;

  /// No description provided for @every_conversation_is_already_assigned_to_a_project.
  ///
  /// In en, this message translates to:
  /// **'Every conversation is already assigned to a Project.'**
  String get every_conversation_is_already_assigned_to_a_project;

  /// No description provided for @everything_not_yet_native_in_the_authenticated_web_dashboard.
  ///
  /// In en, this message translates to:
  /// **'Everything not yet native, in the authenticated web dashboard'**
  String get everything_not_yet_native_in_the_authenticated_web_dashboard;

  /// No description provided for @explain_the_attached_content_clearly.
  ///
  /// In en, this message translates to:
  /// **'Explain the attached content clearly.'**
  String get explain_the_attached_content_clearly;

  /// No description provided for @explain_this_content_clearly.
  ///
  /// In en, this message translates to:
  /// **'Explain this content clearly:\n\n{text}'**
  String explain_this_content_clearly(Object text);

  /// No description provided for @explicit_choices_adjust_android_accessibility_text_size_system_leaves_it.
  ///
  /// In en, this message translates to:
  /// **'Explicit choices adjust Android accessibility text size; System leaves it unchanged.'**
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it;

  /// No description provided for @export_label.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export_label;

  /// No description provided for @export_share.
  ///
  /// In en, this message translates to:
  /// **'Export / share'**
  String get export_share;

  /// No description provided for @external_api_clients.
  ///
  /// In en, this message translates to:
  /// **'External API clients'**
  String get external_api_clients;

  /// No description provided for @extra_high.
  ///
  /// In en, this message translates to:
  /// **'Extra High'**
  String get extra_high;

  /// No description provided for @extract_tasks.
  ///
  /// In en, this message translates to:
  /// **'Extract tasks'**
  String get extract_tasks;

  /// No description provided for @extract_the_decisions_deadlines_owners_and_actionable_action_items_from.
  ///
  /// In en, this message translates to:
  /// **'Extract the decisions, deadlines, owners, and actionable action items from the attached content.'**
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from;

  /// No description provided for @extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2.
  ///
  /// In en, this message translates to:
  /// **'Extract the decisions, deadlines, owners, and actionable action items from this content:\n\n{text}'**
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  );

  /// No description provided for @failed_to_add_job.
  ///
  /// In en, this message translates to:
  /// **'Failed to add job: {error}'**
  String failed_to_add_job(Object error);

  /// No description provided for @failed_to_load_cron_jobs.
  ///
  /// In en, this message translates to:
  /// **'Failed to load cron jobs'**
  String get failed_to_load_cron_jobs;

  /// No description provided for @failed_to_load_memory.
  ///
  /// In en, this message translates to:
  /// **'Failed to load memory'**
  String get failed_to_load_memory;

  /// No description provided for @failed_to_load_messages.
  ///
  /// In en, this message translates to:
  /// **'Failed to load messages'**
  String get failed_to_load_messages;

  /// No description provided for @failed_to_load_settings.
  ///
  /// In en, this message translates to:
  /// **'Failed to load settings'**
  String get failed_to_load_settings;

  /// No description provided for @failed_to_load_skills.
  ///
  /// In en, this message translates to:
  /// **'Failed to load skills'**
  String get failed_to_load_skills;

  /// No description provided for @failed_to_update_job.
  ///
  /// In en, this message translates to:
  /// **'Failed to update job: {error}'**
  String failed_to_update_job(Object error);

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String failed(Object error);

  /// No description provided for @file_attached_document_catalog_registration_is_pending.
  ///
  /// In en, this message translates to:
  /// **'File attached; document catalog registration is pending.'**
  String get file_attached_document_catalog_registration_is_pending;

  /// No description provided for @file_reference_added_to_chat.
  ///
  /// In en, this message translates to:
  /// **'File reference added to chat'**
  String get file_reference_added_to_chat;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// No description provided for @fill_from_document.
  ///
  /// In en, this message translates to:
  /// **'Fill from document'**
  String get fill_from_document;

  /// No description provided for @folder_is_empty.
  ///
  /// In en, this message translates to:
  /// **'Folder is empty'**
  String get folder_is_empty;

  /// No description provided for @folders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get folders;

  /// No description provided for @full_text.
  ///
  /// In en, this message translates to:
  /// **'Full-text'**
  String get full_text;

  /// No description provided for @gateway_api_access.
  ///
  /// In en, this message translates to:
  /// **'Gateway API access'**
  String get gateway_api_access;

  /// No description provided for @gateway_connected_but_the_dashboard_could_not_be_reached_or.
  ///
  /// In en, this message translates to:
  /// **'Gateway connected, but the dashboard could not be reached or authenticated. Check the dashboard details, or clear them to skip.'**
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or;

  /// No description provided for @gateway_path_prefix.
  ///
  /// In en, this message translates to:
  /// **'Gateway path prefix'**
  String get gateway_path_prefix;

  /// No description provided for @go_to_end.
  ///
  /// In en, this message translates to:
  /// **'Go to end'**
  String get go_to_end;

  /// No description provided for @hermes_agent.
  ///
  /// In en, this message translates to:
  /// **'Hermes Agent'**
  String get hermes_agent;

  /// No description provided for @hermes_agent_for_android.
  ///
  /// In en, this message translates to:
  /// **'Hermes Agent for Android'**
  String get hermes_agent_for_android;

  /// No description provided for @hermes_could_not_accept_the_answer_please_try_again.
  ///
  /// In en, this message translates to:
  /// **'Hermes could not accept the answer. Please try again.'**
  String get hermes_could_not_accept_the_answer_please_try_again;

  /// No description provided for @hermes_could_not_load_your_saved_connections.
  ///
  /// In en, this message translates to:
  /// **'Hermes could not load your saved connections'**
  String get hermes_could_not_load_your_saved_connections;

  /// No description provided for @hermes_did_not_accept_the_response_please_try_again.
  ///
  /// In en, this message translates to:
  /// **'Hermes did not accept the response. Please try again.'**
  String get hermes_did_not_accept_the_response_please_try_again;

  /// No description provided for @hermes_is_responding.
  ///
  /// In en, this message translates to:
  /// **'Hermes is responding…'**
  String get hermes_is_responding;

  /// No description provided for @hermes_is_waiting_for_input.
  ///
  /// In en, this message translates to:
  /// **'Hermes is waiting for input…'**
  String get hermes_is_waiting_for_input;

  /// No description provided for @hermes_keeps_android_accessibility_text_scaling_active.
  ///
  /// In en, this message translates to:
  /// **'Hermes keeps Android accessibility text scaling active.'**
  String get hermes_keeps_android_accessibility_text_scaling_active;

  /// No description provided for @hermes_needs_your_input.
  ///
  /// In en, this message translates to:
  /// **'Hermes needs your input'**
  String get hermes_needs_your_input;

  /// No description provided for @hermes_profile_optional.
  ///
  /// In en, this message translates to:
  /// **'Hermes profile (optional)'**
  String get hermes_profile_optional;

  /// No description provided for @hermes_profile_must_be_a_plain_profile_name_such_as.
  ///
  /// In en, this message translates to:
  /// **'Hermes profile must be a plain profile name such as \"sol\", not a path.'**
  String get hermes_profile_must_be_a_plain_profile_name_such_as;

  /// No description provided for @hermes_reasoning_details.
  ///
  /// In en, this message translates to:
  /// **'Hermes reasoning details'**
  String get hermes_reasoning_details;

  /// No description provided for @hermes_recovery_is_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Hermes recovery is unavailable: {error}'**
  String hermes_recovery_is_unavailable(Object error);

  /// No description provided for @hermes_stopped_recovery_safely_no_prompt_was_resent.
  ///
  /// In en, this message translates to:
  /// **'Hermes stopped recovery safely. No prompt was resent.'**
  String get hermes_stopped_recovery_safely_no_prompt_was_resent;

  /// No description provided for @hide_passphrase.
  ///
  /// In en, this message translates to:
  /// **'Hide passphrase'**
  String get hide_passphrase;

  /// No description provided for @home_needs_your_recent_chats_to_know_what_deserves_your.
  ///
  /// In en, this message translates to:
  /// **'Home needs your recent chats to know what deserves your attention. Check that the gateway is reachable, then try again.'**
  String get home_needs_your_recent_chats_to_know_what_deserves_your;

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @image_selection_was_interrupted_try_again.
  ///
  /// In en, this message translates to:
  /// **'Image selection was interrupted. Try again.'**
  String get image_selection_was_interrupted_try_again;

  /// No description provided for @import_label.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import_label;

  /// No description provided for @inbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inbox;

  /// No description provided for @inbox_is_clear.
  ///
  /// In en, this message translates to:
  /// **'Inbox is clear'**
  String get inbox_is_clear;

  /// No description provided for @insert_a_remote_file_reference.
  ///
  /// In en, this message translates to:
  /// **'Insert a remote @file reference'**
  String get insert_a_remote_file_reference;

  /// No description provided for @invalid_port_number.
  ///
  /// In en, this message translates to:
  /// **'Invalid port number.'**
  String get invalid_port_number;

  /// No description provided for @job_paused.
  ///
  /// In en, this message translates to:
  /// **'Job paused'**
  String get job_paused;

  /// No description provided for @job_resumed.
  ///
  /// In en, this message translates to:
  /// **'Job resumed'**
  String get job_resumed;

  /// No description provided for @job_triggered.
  ///
  /// In en, this message translates to:
  /// **'Job triggered'**
  String get job_triggered;

  /// No description provided for @label.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get label;

  /// No description provided for @last_activity.
  ///
  /// In en, this message translates to:
  /// **'Last activity {day}/{month}/{year}'**
  String last_activity(Object day, Object month, Object year);

  /// No description provided for @last.
  ///
  /// In en, this message translates to:
  /// **'Last: {lastRun}'**
  String last(Object lastRun);

  /// No description provided for @leave_blank_for_default_8642_443_with_https.
  ///
  /// In en, this message translates to:
  /// **'Leave blank for default (8642; 443 with https)'**
  String get leave_blank_for_default_8642_443_with_https;

  /// No description provided for @leave_blank_for_default_9119.
  ///
  /// In en, this message translates to:
  /// **'Leave blank for default (9119)'**
  String get leave_blank_for_default_9119;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening • {elapsed}'**
  String listening(Object elapsed);

  /// No description provided for @listening_elapsed.
  ///
  /// In en, this message translates to:
  /// **'Listening, elapsed {elapsed}'**
  String listening_elapsed(Object elapsed);

  /// No description provided for @load_more.
  ///
  /// In en, this message translates to:
  /// **'Load more…'**
  String get load_more;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @make_sure_the_gateway_api_server_is_running_hermes_gateway.
  ///
  /// In en, this message translates to:
  /// **'Make sure the Gateway API Server is running\n(hermes gateway status)'**
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway;

  /// No description provided for @matches.
  ///
  /// In en, this message translates to:
  /// **'Matches {name} · {assigned}'**
  String matches(Object assigned, Object name);

  /// No description provided for @memory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memory;

  /// No description provided for @memory_entries_are_cross_session_facts_the_agent_remembers_they.
  ///
  /// In en, this message translates to:
  /// **'Memory entries are cross-session facts the agent remembers.\nThey are configured in ~/.hermes/config.yaml'**
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they;

  /// No description provided for @merge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get merge;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @message_hermes.
  ///
  /// In en, this message translates to:
  /// **'Message Hermes…'**
  String get message_hermes;

  /// No description provided for @message_actions.
  ///
  /// In en, this message translates to:
  /// **'Message actions'**
  String get message_actions;

  /// No description provided for @message_copied.
  ///
  /// In en, this message translates to:
  /// **'Message copied'**
  String get message_copied;

  /// No description provided for @migrating.
  ///
  /// In en, this message translates to:
  /// **'Migrating…'**
  String get migrating;

  /// No description provided for @migration_complete.
  ///
  /// In en, this message translates to:
  /// **'Migration complete'**
  String get migration_complete;

  /// No description provided for @migration_failed_local_spaces_were_kept_unchanged.
  ///
  /// In en, this message translates to:
  /// **'Migration failed. Local Spaces were kept unchanged.'**
  String get migration_failed_local_spaces_were_kept_unchanged;

  /// No description provided for @migration_incomplete.
  ///
  /// In en, this message translates to:
  /// **'Migration incomplete'**
  String get migration_incomplete;

  /// No description provided for @migration_preview.
  ///
  /// In en, this message translates to:
  /// **'Migration preview'**
  String get migration_preview;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @model_and_thinking_for_this_chat.
  ///
  /// In en, this message translates to:
  /// **'Model and thinking for this chat'**
  String get model_and_thinking_for_this_chat;

  /// No description provided for @model_was_not_changed.
  ///
  /// In en, this message translates to:
  /// **'Model was not changed: {error}'**
  String model_was_not_changed(Object error);

  /// No description provided for @move_attachment_next.
  ///
  /// In en, this message translates to:
  /// **'Move attachment next'**
  String get move_attachment_next;

  /// No description provided for @move_attachment_previous.
  ///
  /// In en, this message translates to:
  /// **'Move attachment previous'**
  String get move_attachment_previous;

  /// No description provided for @move_chat.
  ///
  /// In en, this message translates to:
  /// **'Move chat'**
  String get move_chat;

  /// No description provided for @move_conversation.
  ///
  /// In en, this message translates to:
  /// **'Move conversation'**
  String get move_conversation;

  /// No description provided for @move_to_project.
  ///
  /// In en, this message translates to:
  /// **'Move to project'**
  String get move_to_project;

  /// No description provided for @move_to_space.
  ///
  /// In en, this message translates to:
  /// **'Move to space'**
  String get move_to_space;

  /// No description provided for @moved_to_a_project.
  ///
  /// In en, this message translates to:
  /// **'Moved to a Project'**
  String get moved_to_a_project;

  /// No description provided for @moved_to.
  ///
  /// In en, this message translates to:
  /// **'Moved to {label}'**
  String moved_to(Object label);

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @name_prompt_and_schedule_are_required.
  ///
  /// In en, this message translates to:
  /// **'Name, prompt, and schedule are required'**
  String get name_prompt_and_schedule_are_required;

  /// No description provided for @nav_activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get nav_activity;

  /// No description provided for @nav_projects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get nav_projects;

  /// No description provided for @needs_a_correction_aware_filing_contract_in_the_hermes_gateway.
  ///
  /// In en, this message translates to:
  /// **'Needs a correction-aware filing contract in the Hermes Gateway.'**
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway;

  /// No description provided for @needs_a_reachable_hermes_dashboard_check_the_host_port_and.
  ///
  /// In en, this message translates to:
  /// **'Needs a reachable Hermes dashboard. Check the host, port, and credentials of this connection.'**
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and;

  /// No description provided for @needs_a_server_authoritative_assets_index_in_the_hermes_gateway.
  ///
  /// In en, this message translates to:
  /// **'Needs a server-authoritative Assets index in the Hermes Gateway.'**
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway;

  /// No description provided for @needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in.
  ///
  /// In en, this message translates to:
  /// **'Needs durable pin ordering, batch mutation, and undo contracts in the Hermes Gateway.'**
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in;

  /// No description provided for @needs_you.
  ///
  /// In en, this message translates to:
  /// **'Needs you'**
  String get needs_you;

  /// No description provided for @new_label.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get new_label;

  /// No description provided for @new_chat.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get new_chat;

  /// No description provided for @new_chat_2.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get new_chat_2;

  /// No description provided for @new_chat_3.
  ///
  /// In en, this message translates to:
  /// **'New chat · {projectName}'**
  String new_chat_3(Object projectName);

  /// No description provided for @new_project.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get new_project;

  /// No description provided for @new_space.
  ///
  /// In en, this message translates to:
  /// **'New space'**
  String get new_space;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next: {nextRun}'**
  String next(Object nextRun);

  /// No description provided for @nginx_injects_auth_app_sends_clean_requests.
  ///
  /// In en, this message translates to:
  /// **'Nginx injects auth — app sends clean requests'**
  String get nginx_injects_auth_app_sends_clean_requests;

  /// No description provided for @no_tts_voices_found_ninstall_google_text_to_speech_and.
  ///
  /// In en, this message translates to:
  /// **'No TTS voices found.\nInstall Google Text-to-Speech and download voice data.'**
  String get no_tts_voices_found_ninstall_google_text_to_speech_and;

  /// No description provided for @no_active_projects_on_this_gateway.
  ///
  /// In en, this message translates to:
  /// **'No active Projects on this Gateway'**
  String get no_active_projects_on_this_gateway;

  /// No description provided for @no_activity_yet.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get no_activity_yet;

  /// No description provided for @no_chat_is_blocked_running_or_waiting_to_be_resumed.
  ///
  /// In en, this message translates to:
  /// **'No chat is blocked, running, or waiting to be resumed. Start a new one whenever you are ready.'**
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed;

  /// No description provided for @no_chats_in_this_project_match.
  ///
  /// In en, this message translates to:
  /// **'No chats in this project match “{searchQuery}”.'**
  String no_chats_in_this_project_match(Object searchQuery);

  /// No description provided for @no_chats_in_this_space_yet_tap_to_start_one.
  ///
  /// In en, this message translates to:
  /// **'No chats in this space yet. Tap + to start one.'**
  String get no_chats_in_this_space_yet_tap_to_start_one;

  /// No description provided for @no_chats_yet.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get no_chats_yet;

  /// No description provided for @no_connections.
  ///
  /// In en, this message translates to:
  /// **'No connections'**
  String get no_connections;

  /// No description provided for @no_conversation_matches_this_view.
  ///
  /// In en, this message translates to:
  /// **'No conversation matches this view.'**
  String get no_conversation_matches_this_view;

  /// No description provided for @no_cron_jobs.
  ///
  /// In en, this message translates to:
  /// **'No cron jobs'**
  String get no_cron_jobs;

  /// No description provided for @no_folders_yet.
  ///
  /// In en, this message translates to:
  /// **'No folders yet'**
  String get no_folders_yet;

  /// No description provided for @no_local_spaces_were_found_for_this_connection_so_projects.
  ///
  /// In en, this message translates to:
  /// **'No local spaces were found for this connection, so Projects are already the only organization in use here.'**
  String get no_local_spaces_were_found_for_this_connection_so_projects;

  /// No description provided for @no_matches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get no_matches;

  /// No description provided for @no_memory_entries.
  ///
  /// In en, this message translates to:
  /// **'No memory entries'**
  String get no_memory_entries;

  /// No description provided for @no_message_content_matches.
  ///
  /// In en, this message translates to:
  /// **'No message-content matches'**
  String get no_message_content_matches;

  /// No description provided for @no_new_messages.
  ///
  /// In en, this message translates to:
  /// **'No new messages'**
  String get no_new_messages;

  /// No description provided for @no_projects_yet.
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get no_projects_yet;

  /// No description provided for @no_runs_yet.
  ///
  /// In en, this message translates to:
  /// **'No runs yet.'**
  String get no_runs_yet;

  /// No description provided for @no_server_project_matches_this_name.
  ///
  /// In en, this message translates to:
  /// **'No server project matches this name · {assigned}'**
  String no_server_project_matches_this_name(Object assigned);

  /// No description provided for @no_sessions_yet.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet'**
  String get no_sessions_yet;

  /// No description provided for @no_skills_found.
  ///
  /// In en, this message translates to:
  /// **'No skills found'**
  String get no_skills_found;

  /// No description provided for @no_spaces_on_this_device.
  ///
  /// In en, this message translates to:
  /// **'No spaces on this device'**
  String get no_spaces_on_this_device;

  /// No description provided for @no_text_shared.
  ///
  /// In en, this message translates to:
  /// **'No text shared'**
  String get no_text_shared;

  /// No description provided for @no_turn_is_blocked_in_flight_or_recently_finished_work.
  ///
  /// In en, this message translates to:
  /// **'No turn is blocked, in flight, or recently finished. Work you start will show up here.'**
  String get no_turn_is_blocked_in_flight_or_recently_finished_work;

  /// No description provided for @no_turn_needs_your_input_or_has_failed.
  ///
  /// In en, this message translates to:
  /// **'No turn needs your input or has failed.'**
  String get no_turn_needs_your_input_or_has_failed;

  /// No description provided for @no_unassigned_chats.
  ///
  /// In en, this message translates to:
  /// **'No unassigned chats.'**
  String get no_unassigned_chats;

  /// No description provided for @nothing_changed_in_the_last_seven_days.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed in the last seven days.'**
  String get nothing_changed_in_the_last_seven_days;

  /// No description provided for @nothing_has_moved_yet_this_is_only_what_a_migration.
  ///
  /// In en, this message translates to:
  /// **'Nothing has moved yet — this is only what a migration would do.'**
  String get nothing_has_moved_yet_this_is_only_what_a_migration;

  /// No description provided for @nothing_here.
  ///
  /// In en, this message translates to:
  /// **'Nothing here'**
  String get nothing_here;

  /// No description provided for @nothing_is_running.
  ///
  /// In en, this message translates to:
  /// **'Nothing is running'**
  String get nothing_is_running;

  /// No description provided for @nothing_needs_you.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs you'**
  String get nothing_needs_you;

  /// No description provided for @nothing_to_migrate.
  ///
  /// In en, this message translates to:
  /// **'Nothing to migrate'**
  String get nothing_to_migrate;

  /// No description provided for @off_no_thinking.
  ///
  /// In en, this message translates to:
  /// **'Off (no thinking)'**
  String get off_no_thinking;

  /// No description provided for @offline_showing_the_last_known_activity.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing the last known activity.'**
  String get offline_showing_the_last_known_activity;

  /// No description provided for @offline_showing_the_last_known_chats.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing the last known chats'**
  String get offline_showing_the_last_known_chats;

  /// No description provided for @offline_showing_the_last_known_projects.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing the last known projects.'**
  String get offline_showing_the_last_known_projects;

  /// No description provided for @on_this_device.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get on_this_device;

  /// No description provided for @on_device.
  ///
  /// In en, this message translates to:
  /// **'On-device'**
  String get on_device;

  /// No description provided for @open_inbox.
  ///
  /// In en, this message translates to:
  /// **'Open inbox'**
  String get open_inbox;

  /// No description provided for @open_inbox_2.
  ///
  /// In en, this message translates to:
  /// **'Open inbox ({count})'**
  String open_inbox_2(Object count);

  /// No description provided for @open_the_hermes_dashboard.
  ///
  /// In en, this message translates to:
  /// **'Open the Hermes dashboard'**
  String get open_the_hermes_dashboard;

  /// No description provided for @optional_for_the_memory_cron_skills_settings_tabs_leave_blank.
  ///
  /// In en, this message translates to:
  /// **'Optional. For the Memory/Cron/Skills/Settings tabs. Leave blank to use the default dashboard port (9119) with no login.'**
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank;

  /// No description provided for @organization.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get organization;

  /// No description provided for @other_answer.
  ///
  /// In en, this message translates to:
  /// **'Other answer'**
  String get other_answer;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @passphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get passphrase;

  /// No description provided for @password_optional.
  ///
  /// In en, this message translates to:
  /// **'Password (optional)'**
  String get password_optional;

  /// No description provided for @phone_or_tablet.
  ///
  /// In en, this message translates to:
  /// **'Phone or tablet'**
  String get phone_or_tablet;

  /// No description provided for @pin_batch_and_undo.
  ///
  /// In en, this message translates to:
  /// **'Pin, batch and undo'**
  String get pin_batch_and_undo;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @preparing_attachments.
  ///
  /// In en, this message translates to:
  /// **'Preparing attachments…'**
  String get preparing_attachments;

  /// No description provided for @preview_truncated.
  ///
  /// In en, this message translates to:
  /// **'Preview truncated'**
  String get preview_truncated;

  /// No description provided for @preview_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Preview unavailable'**
  String get preview_unavailable;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @profile_default_model.
  ///
  /// In en, this message translates to:
  /// **'Profile default model'**
  String get profile_default_model;

  /// No description provided for @profile_default_set_to_chats_with_their_own_model_keep.
  ///
  /// In en, this message translates to:
  /// **'Profile default set to {selectedModel}. Chats with their own model keep that override.'**
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  );

  /// No description provided for @profile_this_connection_chats_as_when_the_dashboard_serves_several.
  ///
  /// In en, this message translates to:
  /// **'Profile this connection chats as when the dashboard serves several profiles. Leave blank for an isolated per-profile dashboard.'**
  String get profile_this_connection_chats_as_when_the_dashboard_serves_several;

  /// No description provided for @project.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get project;

  /// No description provided for @project_actions.
  ///
  /// In en, this message translates to:
  /// **'Project actions'**
  String get project_actions;

  /// No description provided for @project_chat.
  ///
  /// In en, this message translates to:
  /// **'Project chat'**
  String get project_chat;

  /// No description provided for @project_chats_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Project chats unavailable'**
  String get project_chats_unavailable;

  /// No description provided for @projects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projects;

  /// No description provided for @projects_group_related_chats_files_and_activity_and_stay_in.
  ///
  /// In en, this message translates to:
  /// **'Projects group related chats, files, and activity, and stay in sync with Hermes on your computer.'**
  String get projects_group_related_chats_files_and_activity_and_stay_in;

  /// No description provided for @projects_need_a_desktop_gateway_connection_add_the_desktop_gateway.
  ///
  /// In en, this message translates to:
  /// **'Projects need a Desktop Gateway connection. Add the Desktop Gateway URL to this connection to organize chats across your devices.'**
  String get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway;

  /// No description provided for @projects_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Projects unavailable'**
  String get projects_unavailable;

  /// No description provided for @projects_activity_new_navigation.
  ///
  /// In en, this message translates to:
  /// **'Projects, Activity — new navigation'**
  String get projects_activity_new_navigation;

  /// No description provided for @promote_to_project.
  ///
  /// In en, this message translates to:
  /// **'Promote to project'**
  String get promote_to_project;

  /// No description provided for @prompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get prompt;

  /// No description provided for @protect_this_backup.
  ///
  /// In en, this message translates to:
  /// **'Protect this backup'**
  String get protect_this_backup;

  /// No description provided for @provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get provider;

  /// No description provided for @proxy_injects_auth_app_sends_clean_requests.
  ///
  /// In en, this message translates to:
  /// **'Proxy injects auth; app sends clean requests'**
  String get proxy_injects_auth_app_sends_clean_requests;

  /// No description provided for @quick_chat.
  ///
  /// In en, this message translates to:
  /// **'Quick chat'**
  String get quick_chat;

  /// No description provided for @quick_chats_appear_here_after_their_retention_period.
  ///
  /// In en, this message translates to:
  /// **'Quick chats appear here after their retention period.'**
  String get quick_chats_appear_here_after_their_retention_period;

  /// No description provided for @read_aloud.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get read_aloud;

  /// No description provided for @read_aloud_is_unavailable_on_this_device.
  ///
  /// In en, this message translates to:
  /// **'Read aloud is unavailable on this device'**
  String get read_aloud_is_unavailable_on_this_device;

  /// No description provided for @reading_response_aloud.
  ///
  /// In en, this message translates to:
  /// **'Reading response aloud'**
  String get reading_response_aloud;

  /// No description provided for @ready_to_upload.
  ///
  /// In en, this message translates to:
  /// **'Ready to upload'**
  String get ready_to_upload;

  /// No description provided for @reasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get reasoning;

  /// No description provided for @recently_completed.
  ///
  /// In en, this message translates to:
  /// **'Recently completed'**
  String get recently_completed;

  /// No description provided for @recovering_hermes.
  ///
  /// In en, this message translates to:
  /// **'Recovering Hermes…'**
  String get recovering_hermes;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @regenerate_response.
  ///
  /// In en, this message translates to:
  /// **'Regenerate response'**
  String get regenerate_response;

  /// No description provided for @remove_attachment.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get remove_attachment;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @rename_chat.
  ///
  /// In en, this message translates to:
  /// **'Rename chat'**
  String get rename_chat;

  /// No description provided for @rename_project.
  ///
  /// In en, this message translates to:
  /// **'Rename project'**
  String get rename_project;

  /// No description provided for @rename_space.
  ///
  /// In en, this message translates to:
  /// **'Rename space'**
  String get rename_space;

  /// No description provided for @rename_2.
  ///
  /// In en, this message translates to:
  /// **'Rename {projectName}'**
  String rename_2(Object projectName);

  /// No description provided for @rename_3.
  ///
  /// In en, this message translates to:
  /// **'Rename {name}'**
  String rename_3(Object name);

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @repositories.
  ///
  /// In en, this message translates to:
  /// **'Repositories'**
  String get repositories;

  /// No description provided for @research_the_attached_content_verify_the_important_claims_and_cite.
  ///
  /// In en, this message translates to:
  /// **'Research the attached content, verify the important claims, and cite sources.'**
  String get research_the_attached_content_verify_the_important_claims_and_cite;

  /// No description provided for @research_this_content_verify_the_important_claims_and_cite_sources.
  ///
  /// In en, this message translates to:
  /// **'Research this content, verify the important claims, and cite sources:\n\n{text}'**
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  );

  /// No description provided for @reset_failed_the_secure_storage_may_need_reinstall.
  ///
  /// In en, this message translates to:
  /// **'Reset failed: {retryError}. The secure storage may need reinstall.'**
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError);

  /// No description provided for @reset_saved_connections.
  ///
  /// In en, this message translates to:
  /// **'Reset saved connections'**
  String get reset_saved_connections;

  /// No description provided for @responding.
  ///
  /// In en, this message translates to:
  /// **'Responding…'**
  String get responding;

  /// No description provided for @response_closed_locally_gateway_stop_failed.
  ///
  /// In en, this message translates to:
  /// **'Response closed locally; gateway stop failed: {error}'**
  String response_closed_locally_gateway_stop_failed(Object error);

  /// No description provided for @response_closed_locally_no_active_gateway_turn_was_found.
  ///
  /// In en, this message translates to:
  /// **'Response closed locally; no active gateway turn was found.'**
  String get response_closed_locally_no_active_gateway_turn_was_found;

  /// No description provided for @response_ready.
  ///
  /// In en, this message translates to:
  /// **'Response ready'**
  String get response_ready;

  /// No description provided for @response_stopped.
  ///
  /// In en, this message translates to:
  /// **'Response stopped.'**
  String get response_stopped;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @restore_configuration.
  ///
  /// In en, this message translates to:
  /// **'Restore configuration'**
  String get restore_configuration;

  /// No description provided for @restore_project.
  ///
  /// In en, this message translates to:
  /// **'Restore project'**
  String get restore_project;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @retry_failed_for_the_draft_and_prompt_were_kept.
  ///
  /// In en, this message translates to:
  /// **'Retry failed for {name}. The draft and prompt were kept.'**
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name);

  /// No description provided for @retry_upload.
  ///
  /// In en, this message translates to:
  /// **'Retry upload'**
  String get retry_upload;

  /// No description provided for @retrying.
  ///
  /// In en, this message translates to:
  /// **'Retrying {name}…'**
  String retrying(Object name);

  /// No description provided for @review_local_spaces.
  ///
  /// In en, this message translates to:
  /// **'Review local spaces'**
  String get review_local_spaces;

  /// No description provided for @review_or_promote_quick_chats_past_their_retention_period.
  ///
  /// In en, this message translates to:
  /// **'Review or promote quick chats past their retention period'**
  String get review_or_promote_quick_chats_past_their_retention_period;

  /// No description provided for @review_the_attached_content.
  ///
  /// In en, this message translates to:
  /// **'Review the attached content.'**
  String get review_the_attached_content;

  /// No description provided for @run_only_this_command.
  ///
  /// In en, this message translates to:
  /// **'Run only this command.'**
  String get run_only_this_command;

  /// No description provided for @running_now.
  ///
  /// In en, this message translates to:
  /// **'Running now'**
  String get running_now;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @save_changes.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get save_changes;

  /// No description provided for @save_a_permanent_rule_in_the_hermes_configuration.
  ///
  /// In en, this message translates to:
  /// **'Save a permanent rule in the Hermes configuration.'**
  String get save_a_permanent_rule_in_the_hermes_configuration;

  /// No description provided for @save_the_durable_facts_from_the_attached_content_to_memory.
  ///
  /// In en, this message translates to:
  /// **'Save the durable facts from the attached content to memory, then confirm what was retained.'**
  String get save_the_durable_facts_from_the_attached_content_to_memory;

  /// No description provided for @save_the_durable_facts_from_this_content_to_memory_then.
  ///
  /// In en, this message translates to:
  /// **'Save the durable facts from this content to memory, then confirm what was retained:\n\n{text}'**
  String save_the_durable_facts_from_this_content_to_memory_then(Object text);

  /// No description provided for @save_your_connections_and_settings_to_an_encrypted_file_then.
  ///
  /// In en, this message translates to:
  /// **'Save your connections and settings to an encrypted file, then restore them after reinstalling or on another device.'**
  String get save_your_connections_and_settings_to_an_encrypted_file_then;

  /// No description provided for @save_2.
  ///
  /// In en, this message translates to:
  /// **'Save {filename}'**
  String save_2(Object filename);

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @scheduled_jobs_and_their_last_runs.
  ///
  /// In en, this message translates to:
  /// **'Scheduled jobs and their last runs'**
  String get scheduled_jobs_and_their_last_runs;

  /// No description provided for @scheduled_tasks.
  ///
  /// In en, this message translates to:
  /// **'Scheduled tasks'**
  String get scheduled_tasks;

  /// No description provided for @script_only_no_agent.
  ///
  /// In en, this message translates to:
  /// **'Script only (no agent)'**
  String get script_only_no_agent;

  /// No description provided for @scroll_horizontally.
  ///
  /// In en, this message translates to:
  /// **'Scroll horizontally'**
  String get scroll_horizontally;

  /// No description provided for @search_all_chats.
  ///
  /// In en, this message translates to:
  /// **'Search all chats'**
  String get search_all_chats;

  /// No description provided for @search_all_message_content.
  ///
  /// In en, this message translates to:
  /// **'Search all message content'**
  String get search_all_message_content;

  /// No description provided for @search_chats.
  ///
  /// In en, this message translates to:
  /// **'Search chats'**
  String get search_chats;

  /// No description provided for @search_conversations.
  ///
  /// In en, this message translates to:
  /// **'Search conversations'**
  String get search_conversations;

  /// No description provided for @search_loaded_chats.
  ///
  /// In en, this message translates to:
  /// **'Search loaded chats'**
  String get search_loaded_chats;

  /// No description provided for @search_mode.
  ///
  /// In en, this message translates to:
  /// **'Search mode'**
  String get search_mode;

  /// No description provided for @select_one_option_or_enter_another_answer.
  ///
  /// In en, this message translates to:
  /// **'Select one option, or enter another answer.'**
  String get select_one_option_or_enter_another_answer;

  /// No description provided for @select_one_or_more_options_then_continue.
  ///
  /// In en, this message translates to:
  /// **'Select one or more options, then continue.'**
  String get select_one_or_more_options_then_continue;

  /// No description provided for @select_text.
  ///
  /// In en, this message translates to:
  /// **'Select text'**
  String get select_text;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @send_failed.
  ///
  /// In en, this message translates to:
  /// **'Send failed: {error}'**
  String send_failed(Object error);

  /// No description provided for @send_message.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get send_message;

  /// No description provided for @session_sources.
  ///
  /// In en, this message translates to:
  /// **'Session Sources'**
  String get session_sources;

  /// No description provided for @session_deleted_from_remote_hermes.
  ///
  /// In en, this message translates to:
  /// **'Session deleted from remote Hermes.'**
  String get session_deleted_from_remote_hermes;

  /// No description provided for @session_search_failed.
  ///
  /// In en, this message translates to:
  /// **'Session search failed: {error}'**
  String session_search_failed(Object error);

  /// No description provided for @set_profile_default.
  ///
  /// In en, this message translates to:
  /// **'Set profile default'**
  String get set_profile_default;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @share_to_hermes.
  ///
  /// In en, this message translates to:
  /// **'Share to Hermes'**
  String get share_to_hermes;

  /// No description provided for @show_passphrase.
  ///
  /// In en, this message translates to:
  /// **'Show passphrase'**
  String get show_passphrase;

  /// No description provided for @show_tool_calls_thinking_and_message_metadata.
  ///
  /// In en, this message translates to:
  /// **'Show tool calls, thinking, and message metadata'**
  String get show_tool_calls_thinking_and_message_metadata;

  /// No description provided for @signal_messages.
  ///
  /// In en, this message translates to:
  /// **'Signal messages'**
  String get signal_messages;

  /// No description provided for @skills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get skills;

  /// No description provided for @skills_2.
  ///
  /// In en, this message translates to:
  /// **'Skills ({count})'**
  String skills_2(Object count);

  /// No description provided for @skills_and_tools.
  ///
  /// In en, this message translates to:
  /// **'Skills and tools'**
  String get skills_and_tools;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @slack_chats.
  ///
  /// In en, this message translates to:
  /// **'Slack chats'**
  String get slack_chats;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String source(Object source);

  /// No description provided for @space_actions.
  ///
  /// In en, this message translates to:
  /// **'Space actions'**
  String get space_actions;

  /// No description provided for @spaces.
  ///
  /// In en, this message translates to:
  /// **'Spaces'**
  String get spaces;

  /// No description provided for @speak_to_hermes.
  ///
  /// In en, this message translates to:
  /// **'Speak to Hermes'**
  String get speak_to_hermes;

  /// No description provided for @speech_recognition_is_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition is unavailable'**
  String get speech_recognition_is_unavailable;

  /// No description provided for @spoken_replies.
  ///
  /// In en, this message translates to:
  /// **'Spoken replies'**
  String get spoken_replies;

  /// No description provided for @spoken_replies_off.
  ///
  /// In en, this message translates to:
  /// **'Spoken replies off'**
  String get spoken_replies_off;

  /// No description provided for @spoken_replies_on.
  ///
  /// In en, this message translates to:
  /// **'Spoken replies on'**
  String get spoken_replies_on;

  /// No description provided for @stalled_no_update_from_hermes.
  ///
  /// In en, this message translates to:
  /// **'Stalled — no update from Hermes'**
  String get stalled_no_update_from_hermes;

  /// No description provided for @start_something_new.
  ///
  /// In en, this message translates to:
  /// **'Start something new'**
  String get start_something_new;

  /// No description provided for @start_voice_input.
  ///
  /// In en, this message translates to:
  /// **'Start voice input'**
  String get start_voice_input;

  /// No description provided for @starting_hermes.
  ///
  /// In en, this message translates to:
  /// **'Starting Hermes…'**
  String get starting_hermes;

  /// No description provided for @steer_turn.
  ///
  /// In en, this message translates to:
  /// **'Add to current response'**
  String get steer_turn;

  /// No description provided for @steer_chip_label.
  ///
  /// In en, this message translates to:
  /// **'STEER'**
  String get steer_chip_label;

  /// No description provided for @steer_queued_for_next_turn.
  ///
  /// In en, this message translates to:
  /// **'Turn is finishing — your note will be sent next'**
  String get steer_queued_for_next_turn;

  /// No description provided for @media_card_download.
  ///
  /// In en, this message translates to:
  /// **'Download file'**
  String get media_card_download;

  /// No description provided for @media_card_tap_to_download.
  ///
  /// In en, this message translates to:
  /// **'Tap to download'**
  String get media_card_tap_to_download;

  /// No description provided for @still_loading_your_projects.
  ///
  /// In en, this message translates to:
  /// **'Still loading your projects.'**
  String get still_loading_your_projects;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @stop_response.
  ///
  /// In en, this message translates to:
  /// **'Stop response'**
  String get stop_response;

  /// No description provided for @stop_voice_input.
  ///
  /// In en, this message translates to:
  /// **'Stop voice input'**
  String get stop_voice_input;

  /// No description provided for @submitted_waiting_for_hermes.
  ///
  /// In en, this message translates to:
  /// **'Submitted, waiting for Hermes'**
  String get submitted_waiting_for_hermes;

  /// No description provided for @suggest_projects_and_learn_from_your_corrections.
  ///
  /// In en, this message translates to:
  /// **'Suggest Projects and learn from your corrections'**
  String get suggest_projects_and_learn_from_your_corrections;

  /// No description provided for @summarize_the_attached_content.
  ///
  /// In en, this message translates to:
  /// **'Summarize the attached content.'**
  String get summarize_the_attached_content;

  /// No description provided for @summarize_this_content.
  ///
  /// In en, this message translates to:
  /// **'Summarize this content:\n\n{text}'**
  String summarize_this_content(Object text);

  /// No description provided for @switch_profile.
  ///
  /// In en, this message translates to:
  /// **'Switch profile'**
  String get switch_profile;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @take_photo.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get take_photo;

  /// No description provided for @tap_to_add_a_remote_hermes_gateway_api_server_port.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add a remote Hermes Gateway\n(API Server, port 8642)'**
  String get tap_to_add_a_remote_hermes_gateway_api_server_port;

  /// No description provided for @tap_the_button_to_start_a_new_chat.
  ///
  /// In en, this message translates to:
  /// **'Tap the + button to start a new chat'**
  String get tap_the_button_to_start_a_new_chat;

  /// No description provided for @telegram_messages.
  ///
  /// In en, this message translates to:
  /// **'Telegram messages'**
  String get telegram_messages;

  /// No description provided for @terminal_sessions.
  ///
  /// In en, this message translates to:
  /// **'Terminal sessions'**
  String get terminal_sessions;

  /// No description provided for @text_size.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get text_size;

  /// No description provided for @text_size_preview.
  ///
  /// In en, this message translates to:
  /// **'Text size preview'**
  String get text_size_preview;

  /// No description provided for @text_size_2.
  ///
  /// In en, this message translates to:
  /// **'Text size: {label}'**
  String text_size_2(Object label);

  /// No description provided for @the_api_key_could_not_be_stored_securely.
  ///
  /// In en, this message translates to:
  /// **'The API key could not be stored securely.'**
  String get the_api_key_could_not_be_stored_securely;

  /// No description provided for @the_project_will_move_to_archived_its_chats_and_files.
  ///
  /// In en, this message translates to:
  /// **'The Project will move to Archived. Its chats and files stay intact, and you can restore it at any time.'**
  String get the_project_will_move_to_archived_its_chats_and_files;

  /// No description provided for @the_project_will_move_to_archived_its_chats_and_files_2.
  ///
  /// In en, this message translates to:
  /// **'The Project will move to Archived. Its chats and files stay intact, and you can restore it later.'**
  String get the_project_will_move_to_archived_its_chats_and_files_2;

  /// No description provided for @the_active_profile_did_not_return_any_selectable_models.
  ///
  /// In en, this message translates to:
  /// **'The active profile did not return any selectable models.'**
  String get the_active_profile_did_not_return_any_selectable_models;

  /// No description provided for @the_backup_could_not_be_exported.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be exported.'**
  String get the_backup_could_not_be_exported;

  /// No description provided for @the_backup_could_not_be_restored.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be restored.'**
  String get the_backup_could_not_be_restored;

  /// No description provided for @the_connection_could_not_be_deleted_safely.
  ///
  /// In en, this message translates to:
  /// **'The connection could not be deleted safely.'**
  String get the_connection_could_not_be_deleted_safely;

  /// No description provided for @the_connection_could_not_be_stored_securely.
  ///
  /// In en, this message translates to:
  /// **'The connection could not be stored securely.'**
  String get the_connection_could_not_be_stored_securely;

  /// No description provided for @the_dashboard_credentials_could_not_be_stored_securely.
  ///
  /// In en, this message translates to:
  /// **'The dashboard credentials could not be stored securely.'**
  String get the_dashboard_credentials_could_not_be_stored_securely;

  /// No description provided for @the_detached_reply_failed.
  ///
  /// In en, this message translates to:
  /// **'The detached reply failed.'**
  String get the_detached_reply_failed;

  /// No description provided for @the_detached_reply_failed_2.
  ///
  /// In en, this message translates to:
  /// **'The detached reply failed: {error}'**
  String the_detached_reply_failed_2(Object error);

  /// No description provided for @the_file_contains_your_api_keys_and_dashboard_password_so.
  ///
  /// In en, this message translates to:
  /// **'The file contains your API keys and dashboard password, so it is encrypted. Without this passphrase the backup cannot be restored.'**
  String get the_file_contains_your_api_keys_and_dashboard_password_so;

  /// No description provided for @the_last_turn_failed.
  ///
  /// In en, this message translates to:
  /// **'The last turn failed'**
  String get the_last_turn_failed;

  /// No description provided for @the_local_connection_store_looks_damaged_you_can_reset_the.
  ///
  /// In en, this message translates to:
  /// **'The local connection store looks damaged ({errorType}). You can reset the saved connections and start fresh. Chats on your gateway are not affected.'**
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  );

  /// No description provided for @the_model_only_rewrites_your_question_into_a_short_full.
  ///
  /// In en, this message translates to:
  /// **'The model only rewrites your question into a short full-text query. Hermes uses the provider credentials already configured on the host.'**
  String get the_model_only_rewrites_your_question_into_a_short_full;

  /// No description provided for @the_server_has_not_reported_folders_for_this_project_yet.
  ///
  /// In en, this message translates to:
  /// **'The server has not reported folders for this project yet. Global Files stays available from More.'**
  String get the_server_has_not_reported_folders_for_this_project_yet;

  /// No description provided for @the_turn_failed.
  ///
  /// In en, this message translates to:
  /// **'The turn failed'**
  String get the_turn_failed;

  /// No description provided for @the_two_passphrases_do_not_match.
  ///
  /// In en, this message translates to:
  /// **'The two passphrases do not match.'**
  String get the_two_passphrases_do_not_match;

  /// No description provided for @the_value_is_sent_directly_to_the_active_hermes_gateway.
  ///
  /// In en, this message translates to:
  /// **'The value is sent directly to the active Hermes gateway and is not saved by this Android app.'**
  String get the_value_is_sent_directly_to_the_active_hermes_gateway;

  /// No description provided for @there_are_no_visible_files_in_this_server_folder.
  ///
  /// In en, this message translates to:
  /// **'There are no visible files in this server folder.'**
  String get there_are_no_visible_files_in_this_server_folder;

  /// No description provided for @thinking_effort.
  ///
  /// In en, this message translates to:
  /// **'Thinking effort'**
  String get thinking_effort;

  /// No description provided for @this_hermes_gateway_does_not_support_opening_a_project_yet.
  ///
  /// In en, this message translates to:
  /// **'This Hermes gateway does not support opening a project yet. Update Hermes on the server to browse a project from your phone.'**
  String get this_hermes_gateway_does_not_support_opening_a_project_yet;

  /// No description provided for @this_hermes_gateway_is_older_than_server_side_projects_so.
  ///
  /// In en, this message translates to:
  /// **'This Hermes gateway is older than server-side projects, so chats stay grouped on this device only. Update Hermes to share the same projects across your devices.'**
  String get this_hermes_gateway_is_older_than_server_side_projects_so;

  /// No description provided for @this_project_has_no_folder_to_open_the_chat_in.
  ///
  /// In en, this message translates to:
  /// **'This Project has no folder to open the chat in — it opened unassigned. Add a folder to the Project to group its chats.'**
  String get this_project_has_no_folder_to_open_the_chat_in;

  /// No description provided for @this_chat_has_no_messages_available_in_the_desktop_session.
  ///
  /// In en, this message translates to:
  /// **'This chat has no messages available in the Desktop session yet.'**
  String get this_chat_has_no_messages_available_in_the_desktop_session;

  /// No description provided for @this_creates_a_permanent_rule_in_hermes_review_the_full.
  ///
  /// In en, this message translates to:
  /// **'This creates a permanent rule in Hermes. Review the full command before confirming.'**
  String get this_creates_a_permanent_rule_in_hermes_review_the_full;

  /// No description provided for @this_gateway_does_not_host_projects_yet_update_the_gateway.
  ///
  /// In en, this message translates to:
  /// **'This gateway does not host projects yet. Update the gateway to organize chats across your devices.'**
  String get this_gateway_does_not_host_projects_yet_update_the_gateway;

  /// No description provided for @this_permanently_deletes_the_project_chats_will_not_be_deleted.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes the Project. Chats will not be deleted; they’ll return to Unassigned.'**
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted;

  /// No description provided for @this_server_doesn_t_offer_background_recovery_chats_run_live.
  ///
  /// In en, this message translates to:
  /// **'This server doesn\'t offer background recovery — chats run live'**
  String get this_server_doesn_t_offer_background_recovery_chats_run_live;

  /// No description provided for @this_week.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get this_week;

  /// No description provided for @titles_previews_and_models.
  ///
  /// In en, this message translates to:
  /// **'Titles, previews, and models'**
  String get titles_previews_and_models;

  /// No description provided for @tool_activity.
  ///
  /// In en, this message translates to:
  /// **'Tool activity'**
  String get tool_activity;

  /// No description provided for @trigger_now.
  ///
  /// In en, this message translates to:
  /// **'Trigger now'**
  String get trigger_now;

  /// No description provided for @turn_completed.
  ///
  /// In en, this message translates to:
  /// **'Turn completed'**
  String get turn_completed;

  /// No description provided for @turn_recovery_failed.
  ///
  /// In en, this message translates to:
  /// **'Turn recovery failed'**
  String get turn_recovery_failed;

  /// No description provided for @unable_to_prepare_this_file_try_another_one.
  ///
  /// In en, this message translates to:
  /// **'Unable to prepare this file. Try another one.'**
  String get unable_to_prepare_this_file_try_another_one;

  /// No description provided for @unable_to_prepare_this_image_try_another_one.
  ///
  /// In en, this message translates to:
  /// **'Unable to prepare this image. Try another one.'**
  String get unable_to_prepare_this_image_try_another_one;

  /// No description provided for @unable_to_prepare.
  ///
  /// In en, this message translates to:
  /// **'Unable to prepare {name}.'**
  String unable_to_prepare(Object name);

  /// No description provided for @unable_to_read_the_selected_image_the_selection_was_kept.
  ///
  /// In en, this message translates to:
  /// **'Unable to read the selected image. The selection was kept.'**
  String get unable_to_read_the_selected_image_the_selection_was_kept;

  /// No description provided for @unassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get unassigned;

  /// No description provided for @unassigned_chats.
  ///
  /// In en, this message translates to:
  /// **'Unassigned chats'**
  String get unassigned_chats;

  /// No description provided for @untitled_chat.
  ///
  /// In en, this message translates to:
  /// **'Untitled chat'**
  String get untitled_chat;

  /// No description provided for @untitled_session.
  ///
  /// In en, this message translates to:
  /// **'Untitled session'**
  String get untitled_session;

  /// No description provided for @update_api_key.
  ///
  /// In en, this message translates to:
  /// **'Update API Key'**
  String get update_api_key;

  /// No description provided for @upload_failed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get upload_failed;

  /// No description provided for @upload_failed_tap_retry.
  ///
  /// In en, this message translates to:
  /// **'Upload failed • tap retry'**
  String get upload_failed_tap_retry;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading {index}/{total}: {name}'**
  String uploading(Object index, Object name, Object total);

  /// No description provided for @use_as_is.
  ///
  /// In en, this message translates to:
  /// **'Use as is'**
  String get use_as_is;

  /// No description provided for @use_at_least_8_characters.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters.'**
  String get use_at_least_8_characters;

  /// No description provided for @use_for_cron_jobs_backed_by_scripts.
  ///
  /// In en, this message translates to:
  /// **'Use for cron jobs backed by scripts.'**
  String get use_for_cron_jobs_backed_by_scripts;

  /// No description provided for @use_on_device.
  ///
  /// In en, this message translates to:
  /// **'Use on-device'**
  String get use_on_device;

  /// No description provided for @use_the_attached_content_to_identify_and_fill_the_relevant.
  ///
  /// In en, this message translates to:
  /// **'Use the attached content to identify and fill the relevant document or form fields. Ask before submitting anything.'**
  String get use_the_attached_content_to_identify_and_fill_the_relevant;

  /// No description provided for @use_this_content_to_identify_and_fill_the_relevant_document.
  ///
  /// In en, this message translates to:
  /// **'Use this content to identify and fill the relevant document or form fields. Ask before submitting anything:\n\n{text}'**
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  );

  /// No description provided for @used_for_hosted_path_prefixes_and_for_the_settings_memory.
  ///
  /// In en, this message translates to:
  /// **'Used for hosted path prefixes and for the Settings, Memory, Skills and Cron tabs. Leave username/password blank for an open dashboard, or enable proxied mode when your reverse proxy injects dashboard auth.'**
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory;

  /// No description provided for @username_optional.
  ///
  /// In en, this message translates to:
  /// **'Username (optional)'**
  String get username_optional;

  /// No description provided for @using.
  ///
  /// In en, this message translates to:
  /// **'Using {displayName}…'**
  String using(Object displayName);

  /// No description provided for @verbose_mode.
  ///
  /// In en, this message translates to:
  /// **'Verbose Mode'**
  String get verbose_mode;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @voice_setup_failed.
  ///
  /// In en, this message translates to:
  /// **'Voice setup failed: {error}'**
  String voice_setup_failed(Object error);

  /// No description provided for @waiting_for_your_input.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your input'**
  String get waiting_for_your_input;

  /// No description provided for @what_hermes_knows_how_to_do.
  ///
  /// In en, this message translates to:
  /// **'What Hermes knows how to do'**
  String get what_hermes_knows_how_to_do;

  /// No description provided for @what_should_the_agent_do.
  ///
  /// In en, this message translates to:
  /// **'What should the agent do?'**
  String get what_should_the_agent_do;

  /// No description provided for @whatsapp_messages.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp messages'**
  String get whatsapp_messages;

  /// No description provided for @which_project.
  ///
  /// In en, this message translates to:
  /// **'Which project?'**
  String get which_project;

  /// No description provided for @workspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get workspace;

  /// No description provided for @wrap_lines.
  ///
  /// In en, this message translates to:
  /// **'Wrap lines'**
  String get wrap_lines;

  /// No description provided for @you_can_attach_up_to_items.
  ///
  /// In en, this message translates to:
  /// **'You can attach up to {maxRemoteAttachmentDrafts} items.'**
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts);

  /// No description provided for @your_answer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get your_answer;

  /// No description provided for @e_g_dashboard.
  ///
  /// In en, this message translates to:
  /// **'e.g. /dashboard'**
  String get e_g_dashboard;

  /// No description provided for @e_g_dashboard_proxy_path_before_api.
  ///
  /// In en, this message translates to:
  /// **'e.g. /dashboard (proxy path before /api/)'**
  String get e_g_dashboard_proxy_path_before_api;

  /// No description provided for @e_g_profile_peter.
  ///
  /// In en, this message translates to:
  /// **'e.g. /profile/peter'**
  String get e_g_profile_peter;

  /// No description provided for @e_g_sol.
  ///
  /// In en, this message translates to:
  /// **'e.g. sol'**
  String get e_g_sol;

  /// No description provided for @e_g_0_9_or_every_2h.
  ///
  /// In en, this message translates to:
  /// **'e.g., 0 9 * * * or every 2h'**
  String get e_g_0_9_or_every_2h;

  /// No description provided for @e_g_daily_backup.
  ///
  /// In en, this message translates to:
  /// **'e.g., Daily backup'**
  String get e_g_daily_backup;

  /// No description provided for @downloaded.
  ///
  /// In en, this message translates to:
  /// **'{filename} downloaded'**
  String downloaded(Object filename);

  /// No description provided for @activity_name_status.
  ///
  /// In en, this message translates to:
  /// **'{displayName}: {statusLabel}'**
  String activity_name_status(Object displayName, Object statusLabel);

  /// No description provided for @connection_status_label.
  ///
  /// In en, this message translates to:
  /// **'{connectionLabel} {label}'**
  String connection_status_label(Object connectionLabel, Object label);

  /// No description provided for @example_host_hint.
  ///
  /// In en, this message translates to:
  /// **'192.168.1.50, 100.x.y.z, or hermes-machine.tailnet.ts.net'**
  String get example_host_hint;

  /// No description provided for @example_profile_prefix_hint_full.
  ///
  /// In en, this message translates to:
  /// **'e.g. /profile/peter (proxy path before /api/ and /v1/)'**
  String get example_profile_prefix_hint_full;

  /// No description provided for @and_more.
  ///
  /// In en, this message translates to:
  /// **'and {count} more'**
  String and_more(Object count);

  /// No description provided for @chats_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} chat} other{{count} chats}}'**
  String chats_count(num count);

  /// No description provided for @on_this_device_only.
  ///
  /// In en, this message translates to:
  /// **'{chats} · on this device only'**
  String on_this_device_only(Object chats);

  /// No description provided for @spaces_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} space} other{{count} spaces}}'**
  String spaces_count(num count);

  /// No description provided for @no_new_projects_needed.
  ///
  /// In en, this message translates to:
  /// **'no new projects needed'**
  String get no_new_projects_needed;

  /// No description provided for @projects_to_create.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} project to create} other{{count} projects to create}}'**
  String projects_to_create(num count);

  /// No description provided for @chats_migrated_projects_created.
  ///
  /// In en, this message translates to:
  /// **'{linkedSessions} chats migrated · {createdProjects} projects created'**
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  );

  /// No description provided for @chats_stayed_in_local_spaces.
  ///
  /// In en, this message translates to:
  /// **'{unlinkedSessions} chats stayed in local Spaces and can be retried safely.'**
  String chats_stayed_in_local_spaces(Object unlinkedSessions);

  /// No description provided for @model_recommended.
  ///
  /// In en, this message translates to:
  /// **'{provider} • Recommended: small and inexpensive'**
  String model_recommended(Object provider);

  /// No description provided for @session_meta.
  ///
  /// In en, this message translates to:
  /// **'{count} msgs • {model} • {time}'**
  String session_meta(Object count, Object model, Object time);

  /// No description provided for @model_scope_label.
  ///
  /// In en, this message translates to:
  /// **'{model} • {scope}'**
  String model_scope_label(Object model, Object scope);

  /// No description provided for @this_chat.
  ///
  /// In en, this message translates to:
  /// **'this chat'**
  String get this_chat;

  /// No description provided for @profile_default.
  ///
  /// In en, this message translates to:
  /// **'profile default'**
  String get profile_default;

  /// No description provided for @minutes_ago.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String minutes_ago(Object count);

  /// No description provided for @hours_ago.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String hours_ago(Object count);

  /// No description provided for @days_ago.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String days_ago(Object count);

  /// No description provided for @now_label.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get now_label;

  /// No description provided for @latest_label.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get latest_label;

  /// No description provided for @new_count_indicator.
  ///
  /// In en, this message translates to:
  /// **'{count} new'**
  String new_count_indicator(Object count);

  /// No description provided for @new_messages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} new message} other{{count} new messages}}'**
  String new_messages(num count);

  /// No description provided for @activity_failed_summary.
  ///
  /// In en, this message translates to:
  /// **'{failures} failed • {total} total'**
  String activity_failed_summary(Object failures, Object total);

  /// No description provided for @activity_completed_summary.
  ///
  /// In en, this message translates to:
  /// **'{count} completed'**
  String activity_completed_summary(Object count);

  /// No description provided for @hermes_is_using_a_tool.
  ///
  /// In en, this message translates to:
  /// **'Hermes is using a tool'**
  String get hermes_is_using_a_tool;

  /// No description provided for @hermes_is_using_tools.
  ///
  /// In en, this message translates to:
  /// **'Hermes is using {count} tools'**
  String hermes_is_using_tools(Object count);

  /// No description provided for @delegated_tasks_completed.
  ///
  /// In en, this message translates to:
  /// **'{count} delegated task(s) completed'**
  String delegated_tasks_completed(Object count);

  /// No description provided for @delegated_tasks_active.
  ///
  /// In en, this message translates to:
  /// **'{count} delegated task(s) active'**
  String delegated_tasks_active(Object count);

  /// No description provided for @branch_main.
  ///
  /// In en, this message translates to:
  /// **'{label} · main'**
  String branch_main(Object label);

  /// No description provided for @you_heading.
  ///
  /// In en, this message translates to:
  /// **'## You'**
  String get you_heading;

  /// No description provided for @hermes_heading.
  ///
  /// In en, this message translates to:
  /// **'## Hermes'**
  String get hermes_heading;

  /// No description provided for @action_label.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get action_label;

  /// No description provided for @destination_label.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get destination_label;

  /// No description provided for @preview_label.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview_label;

  /// No description provided for @share_action_summarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize'**
  String get share_action_summarize;

  /// No description provided for @share_action_explain.
  ///
  /// In en, this message translates to:
  /// **'Explain'**
  String get share_action_explain;

  /// No description provided for @share_action_research.
  ///
  /// In en, this message translates to:
  /// **'Research'**
  String get share_action_research;

  /// No description provided for @share_action_remember.
  ///
  /// In en, this message translates to:
  /// **'Remember'**
  String get share_action_remember;

  /// No description provided for @text_size_small.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get text_size_small;

  /// No description provided for @text_size_default.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get text_size_default;

  /// No description provided for @text_size_large.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get text_size_large;

  /// No description provided for @text_size_extra_large.
  ///
  /// In en, this message translates to:
  /// **'Extra large'**
  String get text_size_extra_large;

  /// No description provided for @text_size_use_system_description.
  ///
  /// In en, this message translates to:
  /// **'Use Android accessibility text size exactly.'**
  String get text_size_use_system_description;

  /// No description provided for @text_size_percent_description.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of the Android text size.'**
  String text_size_percent_description(Object percent);

  /// No description provided for @text_size_label_description.
  ///
  /// In en, this message translates to:
  /// **'{label} — {description}'**
  String text_size_label_description(Object description, Object label);

  /// No description provided for @files_skipped.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) skipped: limit, size, unreadable, or sensitive filename.'**
  String files_skipped(Object count);

  /// No description provided for @model_scope_applied.
  ///
  /// In en, this message translates to:
  /// **'{model} • {effort} now apply only to this chat.'**
  String model_scope_applied(Object effort, Object model);

  /// No description provided for @reasoning_minimal.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get reasoning_minimal;

  /// No description provided for @reasoning_low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get reasoning_low;

  /// No description provided for @reasoning_medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get reasoning_medium;

  /// No description provided for @reasoning_high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get reasoning_high;

  /// No description provided for @reasoning_max.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get reasoning_max;

  /// No description provided for @reasoning_ultra.
  ///
  /// In en, this message translates to:
  /// **'Ultra'**
  String get reasoning_ultra;

  /// No description provided for @status_running.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get status_running;

  /// No description provided for @status_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get status_failed;

  /// No description provided for @status_done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get status_done;

  /// No description provided for @status_idle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get status_idle;

  /// No description provided for @upload_status_uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get upload_status_uploading;

  /// No description provided for @upload_status_uploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get upload_status_uploaded;

  /// No description provided for @attachment_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} attachment} other{{count} attachments}}'**
  String attachment_count(num count);

  /// No description provided for @action_create.
  ///
  /// In en, this message translates to:
  /// **'create'**
  String get action_create;

  /// No description provided for @action_rename.
  ///
  /// In en, this message translates to:
  /// **'rename'**
  String get action_rename;

  /// No description provided for @action_archive.
  ///
  /// In en, this message translates to:
  /// **'archive'**
  String get action_archive;

  /// No description provided for @action_restore.
  ///
  /// In en, this message translates to:
  /// **'restore'**
  String get action_restore;

  /// No description provided for @action_delete.
  ///
  /// In en, this message translates to:
  /// **'delete'**
  String get action_delete;

  /// No description provided for @migrate.
  ///
  /// In en, this message translates to:
  /// **'Migrate'**
  String get migrate;

  /// No description provided for @assigned_chats.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} assigned chat} other{{count} assigned chats}}'**
  String assigned_chats(num count);

  /// No description provided for @date_today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get date_today;

  /// No description provided for @date_yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get date_yesterday;

  /// No description provided for @date_earlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get date_earlier;

  /// No description provided for @nav_home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get nav_home;

  /// No description provided for @nav_more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get nav_more;

  /// No description provided for @status_completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get status_completed;

  /// No description provided for @filter_all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filter_all;

  /// No description provided for @filter_recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get filter_recent;

  /// No description provided for @connection_address_key.
  ///
  /// In en, this message translates to:
  /// **'{address}  •  Key: {status}'**
  String connection_address_key(Object address, Object status);

  /// No description provided for @model_via_provider.
  ///
  /// In en, this message translates to:
  /// **'{model}  \nvia `{provider}`'**
  String model_via_provider(Object model, Object provider);

  /// No description provided for @deny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get deny;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @connection_section.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection_section;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version_label.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String version_label(Object version);

  /// No description provided for @matched.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get matched;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @reasoning_off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get reasoning_off;

  /// No description provided for @hermes_response_ready.
  ///
  /// In en, this message translates to:
  /// **'Hermes response ready'**
  String get hermes_response_ready;

  /// No description provided for @admin_password_needed.
  ///
  /// In en, this message translates to:
  /// **'Administrator password needed'**
  String get admin_password_needed;

  /// No description provided for @hermes_needs_a_sudo_password_for_the_pending_terminal_command.
  ///
  /// In en, this message translates to:
  /// **'Hermes needs a sudo password for the pending terminal command.'**
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command;

  /// No description provided for @sudo_password.
  ///
  /// In en, this message translates to:
  /// **'Sudo password'**
  String get sudo_password;

  /// No description provided for @secret_needed.
  ///
  /// In en, this message translates to:
  /// **'Secret needed'**
  String get secret_needed;

  /// No description provided for @hermes_needs_a_secret_for_the_pending_skill.
  ///
  /// In en, this message translates to:
  /// **'Hermes needs a secret for the pending skill.'**
  String get hermes_needs_a_secret_for_the_pending_skill;

  /// No description provided for @secret_value.
  ///
  /// In en, this message translates to:
  /// **'Secret value'**
  String get secret_value;

  /// No description provided for @attached_file.
  ///
  /// In en, this message translates to:
  /// **'Attached file'**
  String get attached_file;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'ja',
    'ko',
    'pt',
    'ru',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
        }
        break;
      }
  }

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
