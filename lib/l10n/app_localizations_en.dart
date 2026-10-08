// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      'A one-off question. Archives itself after 72 hours; anything worth keeping is still remembered.';

  @override
  String get ai_full_text => 'AI + full-text';

  @override
  String get ai_search_model => 'AI search model';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'AI searched for: $aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'AI-assisted filing';

  @override
  String get api_key => 'API Key';

  @override
  String get api_server_key_from_hermes_env =>
      'API_SERVER_KEY from ~/.hermes/.env';

  @override
  String get active => 'Active';

  @override
  String get activity => 'Activity';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      'Activity reads the durable turn journal to know what Hermes is doing. Check that the gateway is reachable, then try again.';

  @override
  String get add => 'Add';

  @override
  String get add_connection => 'Add Connection';

  @override
  String get add_cron_job => 'Add Cron Job';

  @override
  String get add_gateway_connection => 'Add Gateway Connection';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      'Add and update connections from the backup, keep the rest.';

  @override
  String get add_attachment => 'Add attachment';

  @override
  String get add_new_cron_job => 'Add new cron job';

  @override
  String get add_to_chat => 'Add to chat';

  @override
  String get all_chats => 'All chats';

  @override
  String get all_stored_message_content => 'All stored message content';

  @override
  String get allow_for_this_session => 'Allow for this session';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      'Allow matching commands until this Hermes session ends.';

  @override
  String get allow_once => 'Allow once';

  @override
  String get always_allow => 'Always allow';

  @override
  String get apply_to_this_chat => 'Apply to this chat';

  @override
  String get approval_needed => 'Approval needed';

  @override
  String get archive => 'Archive';

  @override
  String get archive_project => 'Archive project';

  @override
  String archive_2(Object projectName) {
    return 'Archive $projectName?';
  }

  @override
  String archive_3(Object name) {
    return 'Archive $name?';
  }

  @override
  String get archived => 'Archived';

  @override
  String get archived_conversations_appear_here =>
      'Archived conversations appear here.';

  @override
  String get archived_quick_chats => 'Archived quick chats';

  @override
  String get artifacts_attachments_and_generated_media =>
      'Artifacts, attachments, and generated media';

  @override
  String get ask_ai_to_find_a_conversation => 'Ask AI to find a conversation';

  @override
  String get assets => 'Assets';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      'Assets need a server-authoritative Assets index in the Hermes Gateway before they can be shown per project.';

  @override
  String get assets_unavailable => 'Assets unavailable';

  @override
  String get attach_image_or_file => 'Attach image or file';

  @override
  String get attachment_drafts => 'Attachment drafts';

  @override
  String attachment_of(Object index, Object total) {
    return 'Attachment $index of $total';
  }

  @override
  String get auto_device_default => 'Auto (device default)';

  @override
  String get auto_archives_after_72_hours => 'Auto-archives after 72 hours';

  @override
  String get automation => 'Automation';

  @override
  String get autonomous_agents => 'Autonomous agents';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      'Background recovery unavailable — legacy transport';

  @override
  String get backup_restore => 'Backup & restore';

  @override
  String backup_exported(Object destination) {
    return 'Backup exported — $destination';
  }

  @override
  String get base_url => 'Base URL';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      'Binary preview is unavailable. Download the file to open it.';

  @override
  String get branch => 'Branch';

  @override
  String get branch_chat => 'Branch chat';

  @override
  String get branch_created_in_hermes_history =>
      'Branch created in Hermes history.';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      'Browse and manage your Hermes Agent sessions from your phone. Connects to a Hermes dashboard running on your local network.';

  @override
  String get browse_server_files => 'Browse server files';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      'Browse the miniserver folders behind your projects';

  @override
  String get cancel => 'Cancel';

  @override
  String get cancel_voice_input => 'Cancel voice input';

  @override
  String cannot_reach(Object host, Object port) {
    return 'Cannot reach $host:$port.';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return 'Cannot reach $host:$port. Check the host and port.';
  }

  @override
  String get change_ai_search_model => 'Change AI search model';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return 'Changes the default for $label. Use the selector in a chat to override only that conversation.';
  }

  @override
  String get chat_actions => 'Chat actions';

  @override
  String get chats => 'Chats';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      'Chats from this gateway are not grouped yet. Grouping stays on this phone until the gateway can host projects.';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      'Chats in this project will show their state and last activity here.';

  @override
  String get chats_that_are_not_assigned_to_a_project =>
      'Chats that are not assigned to a Project';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      'Chats you start in this project will appear here, on every device signed in to this Hermes.';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      'Check that the gateway is running and reachable, then try again.';

  @override
  String get check_the_dashboard_connection_and_try_again =>
      'Check the Dashboard connection and try again.';

  @override
  String get check_the_connection_and_try_again =>
      'Check the connection and try again.';

  @override
  String get choose_a_small_model_to_rewrite_queries =>
      'Choose a small model to rewrite queries';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      'Choose an AI search model before using AI search.';

  @override
  String get choose_an_active_project_next => 'Choose an active Project next';

  @override
  String get choose_chat_model => 'Choose chat model';

  @override
  String get choose_files => 'Choose files';

  @override
  String get choose_image => 'Choose image';

  @override
  String get choose_images => 'Choose images';

  @override
  String get choose_its_destination_space => 'Choose its destination space';

  @override
  String get clear_search => 'Clear search';

  @override
  String get close => 'Close';

  @override
  String get code_copied => 'Code copied';

  @override
  String get coming_next => 'Coming next';

  @override
  String get command => 'Command';

  @override
  String get command_line_chats => 'Command-line chats';

  @override
  String get compatibility_mode => 'Compatibility mode';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      'Configure a valid Desktop Gateway URL before attaching files.';

  @override
  String get confirm_always_allow => 'Confirm always allow';

  @override
  String get confirm_passphrase => 'Confirm passphrase';

  @override
  String connecting_to(Object baseUrl) {
    return 'Connecting to $baseUrl...';
  }

  @override
  String get connection_issue => 'Connection issue';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      'Connection switched — the running reply continues on the server and will reattach automatically.';

  @override
  String get connection_appearance_and_device_preferences =>
      'Connection, appearance, and device preferences';

  @override
  String context_tokens(Object effectiveContextLength) {
    return 'Context: $effectiveContextLength tokens';
  }

  @override
  String get continue_label => 'Continue';

  @override
  String get continue_working => 'Continue working';

  @override
  String get conversations_in_this_project => 'Conversations in this project';

  @override
  String get copy_code => 'Copy code';

  @override
  String get copy_message => 'Copy message';

  @override
  String could_not_branch_chat(Object error) {
    return 'Could not branch chat: $error';
  }

  @override
  String could_not_delete_session(Object error) {
    return 'Could not delete session: $error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return 'Could not deny the command: $error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return 'Could not load AI search models: $error';
  }

  @override
  String get could_not_load_conversations => 'Could not load conversations';

  @override
  String get could_not_load_files => 'Could not load files';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return 'Could not load models for this profile: $error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return 'Could not load more chats: $error';
  }

  @override
  String get could_not_open_the_hermes_dashboard =>
      'Could not open the Hermes dashboard.';

  @override
  String get could_not_open_this_project => 'Could not open this project';

  @override
  String get could_not_preview_file => 'Could not preview file';

  @override
  String get could_not_reach_hermes => 'Could not reach Hermes';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return 'Could not reach/authenticate the dashboard at $host:$dashboardPort. Check the port and credentials.';
  }

  @override
  String get could_not_read_activity => 'Could not read activity';

  @override
  String could_not_rename_chat(Object error) {
    return 'Could not rename chat: $error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return 'Could not send the approval: $error';
  }

  @override
  String get could_not_skip_the_hermes_question =>
      'Could not skip the Hermes question.';

  @override
  String could_not_the_project(Object action, Object error) {
    return 'Could not $action the project: $error';
  }

  @override
  String get couldn_t_delete_project => 'Couldn’t delete project';

  @override
  String couldn_t_load_runs(Object error) {
    return 'Couldn’t load runs: $error';
  }

  @override
  String get couldn_t_move_conversation => 'Couldn’t move conversation';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return 'Couldn’t move to $label: $reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files =>
      'Couldn’t prepare the shared files.';

  @override
  String get couldn_t_promote_conversation => 'Couldn’t promote conversation';

  @override
  String couldn_t_project(Object action) {
    return 'Couldn’t $action project';
  }

  @override
  String get create => 'Create';

  @override
  String get create_a_project => 'Create a project';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      'Create a project first, then chats can live inside it.';

  @override
  String get create_a_space_to_separate_related_conversations =>
      'Create a space to separate related conversations.';

  @override
  String get create_branch => 'Create branch';

  @override
  String get cron => 'Cron';

  @override
  String get cron_jobs => 'Cron Jobs';

  @override
  String get cron_job_added => 'Cron job added';

  @override
  String get cron_job_updated => 'Cron job updated';

  @override
  String get cron_run => 'Cron run';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      'Cross-device ordering and reversible bulk organization';

  @override
  String get current_profile_default => 'Current profile default';

  @override
  String get custom_proxy_and_dashboard_details =>
      'Custom proxy and dashboard details';

  @override
  String get dark => 'Dark';

  @override
  String get dashboard_proxy_settings => 'Dashboard / Proxy Settings';

  @override
  String get dashboard_password_optional => 'Dashboard Password (optional)';

  @override
  String get dashboard_port => 'Dashboard Port';

  @override
  String get dashboard_username_optional => 'Dashboard Username (optional)';

  @override
  String get dashboard_behind_proxy => 'Dashboard behind proxy';

  @override
  String get dashboard_path_prefix => 'Dashboard path prefix';

  @override
  String delegated_task(Object goal) {
    return 'Delegated task: $goal';
  }

  @override
  String get delete => 'Delete';

  @override
  String delete_2(Object name) {
    return 'Delete \"$name\"?';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return 'Delete \"$title\" from the remote Hermes history? This cannot be undone.';
  }

  @override
  String get delete_cron_job => 'Delete Cron Job';

  @override
  String get delete_connections_that_are_not_in_the_backup =>
      'Delete connections that are not in the backup.';

  @override
  String delete_failed(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String get delete_project => 'Delete project';

  @override
  String get delete_session => 'Delete session?';

  @override
  String delete_3(Object projectName) {
    return 'Delete $projectName?';
  }

  @override
  String deleted(Object name) {
    return 'Deleted \"$name\"';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      'Delivery is uncertain; recovering without resending…';

  @override
  String get desktop_gateway_url_optional => 'Desktop Gateway URL (optional)';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      'Desktop Gateway is not configured for this connection.';

  @override
  String get desktop_app => 'Desktop app';

  @override
  String get developer_tool_calls => 'Developer tool calls';

  @override
  String get discord_chats => 'Discord chats';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get do_not_run_this_command => 'Do not run this command.';

  @override
  String get documents_archives_audio_video_or_data =>
      'Documents, archives, audio, video, or data';

  @override
  String get download => 'Download';

  @override
  String download_failed(Object error) {
    return 'Download failed: $error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you =>
      'Durable facts Hermes keeps about you';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      'Durable work inside one of your projects, shared with Desktop.';

  @override
  String get edit => 'Edit';

  @override
  String get edit_connection => 'Edit Connection';

  @override
  String get edit_cron_job => 'Edit Cron Job';

  @override
  String get edit_gateway_connection => 'Edit Gateway Connection';

  @override
  String get edit_and_resend => 'Edit and resend';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      'Enables file attachments through the Desktop remote gateway.';

  @override
  String get enter_a_name => 'Enter a name';

  @override
  String get enter_a_passphrase => 'Enter a passphrase.';

  @override
  String get enter_the_passphrase_for_this_backup =>
      'Enter the passphrase for this backup.';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      'Every conversation is already assigned to a Project.';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      'Everything not yet native, in the authenticated web dashboard';

  @override
  String get explain_the_attached_content_clearly =>
      'Explain the attached content clearly.';

  @override
  String explain_this_content_clearly(Object text) {
    return 'Explain this content clearly:\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      'Explicit choices adjust Android accessibility text size; System leaves it unchanged.';

  @override
  String get export_label => 'Export';

  @override
  String get export_share => 'Export / share';

  @override
  String get external_api_clients => 'External API clients';

  @override
  String get extra_high => 'Extra High';

  @override
  String get extract_tasks => 'Extract tasks';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      'Extract the decisions, deadlines, owners, and actionable action items from the attached content.';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return 'Extract the decisions, deadlines, owners, and actionable action items from this content:\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return 'Failed to add job: $error';
  }

  @override
  String get failed_to_load_cron_jobs => 'Failed to load cron jobs';

  @override
  String get failed_to_load_memory => 'Failed to load memory';

  @override
  String get failed_to_load_messages => 'Failed to load messages';

  @override
  String get failed_to_load_settings => 'Failed to load settings';

  @override
  String get failed_to_load_skills => 'Failed to load skills';

  @override
  String failed_to_update_job(Object error) {
    return 'Failed to update job: $error';
  }

  @override
  String failed(Object error) {
    return 'Failed: $error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      'File attached; document catalog registration is pending.';

  @override
  String get file_reference_added_to_chat => 'File reference added to chat';

  @override
  String get files => 'Files';

  @override
  String get fill_from_document => 'Fill from document';

  @override
  String get folder_is_empty => 'Folder is empty';

  @override
  String get folders => 'Folders';

  @override
  String get full_text => 'Full-text';

  @override
  String get gateway_api_access => 'Gateway API access';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      'Gateway connected, but the dashboard could not be reached or authenticated. Check the dashboard details, or clear them to skip.';

  @override
  String get gateway_path_prefix => 'Gateway path prefix';

  @override
  String get go_to_end => 'Go to end';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Hermes Agent for Android';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'Hermes could not accept the answer. Please try again.';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      'Hermes could not load your saved connections';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'Hermes did not accept the response. Please try again.';

  @override
  String get hermes_is_responding => 'Hermes is responding…';

  @override
  String get hermes_is_waiting_for_input => 'Hermes is waiting for input…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'Hermes keeps Android accessibility text scaling active.';

  @override
  String get hermes_needs_your_input => 'Hermes needs your input';

  @override
  String get hermes_profile_optional => 'Hermes profile (optional)';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'Hermes profile must be a plain profile name such as \"sol\", not a path.';

  @override
  String get hermes_reasoning_details => 'Hermes reasoning details';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'Hermes recovery is unavailable: $error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'Hermes stopped recovery safely. No prompt was resent.';

  @override
  String get hide_passphrase => 'Hide passphrase';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      'Home needs your recent chats to know what deserves your attention. Check that the gateway is reachable, then try again.';

  @override
  String get host => 'Host';

  @override
  String get image_selection_was_interrupted_try_again =>
      'Image selection was interrupted. Try again.';

  @override
  String get import_label => 'Import';

  @override
  String get inbox => 'Inbox';

  @override
  String get inbox_is_clear => 'Inbox is clear';

  @override
  String get insert_a_remote_file_reference =>
      'Insert a remote @file reference';

  @override
  String get invalid_port_number => 'Invalid port number.';

  @override
  String get job_paused => 'Job paused';

  @override
  String get job_resumed => 'Job resumed';

  @override
  String get job_triggered => 'Job triggered';

  @override
  String get label => 'Label';

  @override
  String last_activity(Object day, Object month, Object year) {
    return 'Last activity $day/$month/$year';
  }

  @override
  String last(Object lastRun) {
    return 'Last: $lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      'Leave blank for default (8642; 443 with https)';

  @override
  String get leave_blank_for_default_9119 => 'Leave blank for default (9119)';

  @override
  String get light => 'Light';

  @override
  String listening(Object elapsed) {
    return 'Listening • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return 'Listening, elapsed $elapsed';
  }

  @override
  String get load_more => 'Load more…';

  @override
  String get loading => 'Loading';

  @override
  String get location => 'Location';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      'Make sure the Gateway API Server is running\n(hermes gateway status)';

  @override
  String matches(Object assigned, Object name) {
    return 'Matches $name · $assigned';
  }

  @override
  String get memory => 'Memory';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'Memory entries are cross-session facts the agent remembers.\nThey are configured in ~/.hermes/config.yaml';

  @override
  String get merge => 'Merge';

  @override
  String get message => 'Message';

  @override
  String get message_hermes => 'Message Hermes…';

  @override
  String get message_actions => 'Message actions';

  @override
  String get message_copied => 'Message copied';

  @override
  String get migrating => 'Migrating…';

  @override
  String get migration_complete => 'Migration complete';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      'Migration failed. Local Spaces were kept unchanged.';

  @override
  String get migration_incomplete => 'Migration incomplete';

  @override
  String get migration_preview => 'Migration preview';

  @override
  String get model => 'Model';

  @override
  String get model_and_thinking_for_this_chat =>
      'Model and thinking for this chat';

  @override
  String model_was_not_changed(Object error) {
    return 'Model was not changed: $error';
  }

  @override
  String get move_attachment_next => 'Move attachment next';

  @override
  String get move_attachment_previous => 'Move attachment previous';

  @override
  String get move_chat => 'Move chat';

  @override
  String get move_conversation => 'Move conversation';

  @override
  String get move_to_project => 'Move to project';

  @override
  String get move_to_space => 'Move to space';

  @override
  String get moved_to_a_project => 'Moved to a Project';

  @override
  String moved_to(Object label) {
    return 'Moved to $label';
  }

  @override
  String get name => 'Name';

  @override
  String get name_prompt_and_schedule_are_required =>
      'Name, prompt, and schedule are required';

  @override
  String get nav_activity => 'Activity';

  @override
  String get nav_projects => 'Projects';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Needs a correction-aware filing contract in the Hermes Gateway.';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      'Needs a reachable Hermes dashboard. Check the host, port, and credentials of this connection.';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Needs a server-authoritative Assets index in the Hermes Gateway.';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Needs durable pin ordering, batch mutation, and undo contracts in the Hermes Gateway.';

  @override
  String get needs_you => 'Needs you';

  @override
  String get new_label => 'New';

  @override
  String get new_chat => 'New Chat';

  @override
  String get new_chat_2 => 'New chat';

  @override
  String new_chat_3(Object projectName) {
    return 'New chat · $projectName';
  }

  @override
  String get new_project => 'New project';

  @override
  String get new_space => 'New space';

  @override
  String next(Object nextRun) {
    return 'Next: $nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'Nginx injects auth — app sends clean requests';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      'No TTS voices found.\nInstall Google Text-to-Speech and download voice data.';

  @override
  String get no_active_projects_on_this_gateway =>
      'No active Projects on this Gateway';

  @override
  String get no_activity_yet => 'No activity yet';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      'No chat is blocked, running, or waiting to be resumed. Start a new one whenever you are ready.';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return 'No chats in this project match “$searchQuery”.';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      'No chats in this space yet. Tap + to start one.';

  @override
  String get no_chats_yet => 'No chats yet';

  @override
  String get no_connections => 'No connections';

  @override
  String get no_conversation_matches_this_view =>
      'No conversation matches this view.';

  @override
  String get no_cron_jobs => 'No cron jobs';

  @override
  String get no_folders_yet => 'No folders yet';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      'No local spaces were found for this connection, so Projects are already the only organization in use here.';

  @override
  String get no_matches => 'No matches';

  @override
  String get no_memory_entries => 'No memory entries';

  @override
  String get no_message_content_matches => 'No message-content matches';

  @override
  String get no_new_messages => 'No new messages';

  @override
  String get no_projects_yet => 'No projects yet';

  @override
  String get no_runs_yet => 'No runs yet.';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return 'No server project matches this name · $assigned';
  }

  @override
  String get no_sessions_yet => 'No sessions yet';

  @override
  String get no_skills_found => 'No skills found';

  @override
  String get no_spaces_on_this_device => 'No spaces on this device';

  @override
  String get no_text_shared => 'No text shared';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      'No turn is blocked, in flight, or recently finished. Work you start will show up here.';

  @override
  String get no_turn_needs_your_input_or_has_failed =>
      'No turn needs your input or has failed.';

  @override
  String get no_unassigned_chats => 'No unassigned chats.';

  @override
  String get nothing_changed_in_the_last_seven_days =>
      'Nothing changed in the last seven days.';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      'Nothing has moved yet — this is only what a migration would do.';

  @override
  String get nothing_here => 'Nothing here';

  @override
  String get nothing_is_running => 'Nothing is running';

  @override
  String get nothing_needs_you => 'Nothing needs you';

  @override
  String get nothing_to_migrate => 'Nothing to migrate';

  @override
  String get off_no_thinking => 'Off (no thinking)';

  @override
  String get offline_showing_the_last_known_activity =>
      'Offline — showing the last known activity.';

  @override
  String get offline_showing_the_last_known_chats =>
      'Offline — showing the last known chats';

  @override
  String get offline_showing_the_last_known_projects =>
      'Offline — showing the last known projects.';

  @override
  String get on_this_device => 'On this device';

  @override
  String get on_device => 'On-device';

  @override
  String get open_inbox => 'Open inbox';

  @override
  String open_inbox_2(Object count) {
    return 'Open inbox ($count)';
  }

  @override
  String get open_the_hermes_dashboard => 'Open the Hermes dashboard';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      'Optional. For the Memory/Cron/Skills/Settings tabs. Leave blank to use the default dashboard port (9119) with no login.';

  @override
  String get organization => 'Organization';

  @override
  String get other_answer => 'Other answer';

  @override
  String get overview => 'Overview';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get password_optional => 'Password (optional)';

  @override
  String get phone_or_tablet => 'Phone or tablet';

  @override
  String get pin_batch_and_undo => 'Pin, batch and undo';

  @override
  String get port => 'Port';

  @override
  String get preparing_attachments => 'Preparing attachments…';

  @override
  String get preview_truncated => 'Preview truncated';

  @override
  String get preview_unavailable => 'Preview unavailable';

  @override
  String get profile => 'Profile';

  @override
  String get profile_default_model => 'Profile default model';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return 'Profile default set to $selectedModel. Chats with their own model keep that override.';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      'Profile this connection chats as when the dashboard serves several profiles. Leave blank for an isolated per-profile dashboard.';

  @override
  String get project => 'Project';

  @override
  String get project_actions => 'Project actions';

  @override
  String get project_chat => 'Project chat';

  @override
  String get project_chats_unavailable => 'Project chats unavailable';

  @override
  String get projects => 'Projects';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      'Projects group related chats, files, and activity, and stay in sync with Hermes on your computer.';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      'Projects need a Desktop Gateway connection. Add the Desktop Gateway URL to this connection to organize chats across your devices.';

  @override
  String get projects_unavailable => 'Projects unavailable';

  @override
  String get projects_activity_new_navigation =>
      'Projects, Activity — new navigation';

  @override
  String get promote_to_project => 'Promote to project';

  @override
  String get prompt => 'Prompt';

  @override
  String get protect_this_backup => 'Protect this backup';

  @override
  String get provider => 'Provider';

  @override
  String get proxy_injects_auth_app_sends_clean_requests =>
      'Proxy injects auth; app sends clean requests';

  @override
  String get quick_chat => 'Quick chat';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      'Quick chats appear here after their retention period.';

  @override
  String get read_aloud => 'Read aloud';

  @override
  String get read_aloud_is_unavailable_on_this_device =>
      'Read aloud is unavailable on this device';

  @override
  String get reading_response_aloud => 'Reading response aloud';

  @override
  String get ready_to_upload => 'Ready to upload';

  @override
  String get reasoning => 'Reasoning';

  @override
  String get recently_completed => 'Recently completed';

  @override
  String get recovering_hermes => 'Recovering Hermes…';

  @override
  String get refresh => 'Refresh';

  @override
  String get regenerate_response => 'Regenerate response';

  @override
  String get remove_attachment => 'Remove attachment';

  @override
  String get rename => 'Rename';

  @override
  String get rename_chat => 'Rename chat';

  @override
  String get rename_project => 'Rename project';

  @override
  String get rename_space => 'Rename space';

  @override
  String rename_2(Object projectName) {
    return 'Rename $projectName';
  }

  @override
  String rename_3(Object name) {
    return 'Rename $name';
  }

  @override
  String get replace => 'Replace';

  @override
  String get repositories => 'Repositories';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      'Research the attached content, verify the important claims, and cite sources.';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return 'Research this content, verify the important claims, and cite sources:\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return 'Reset failed: $retryError. The secure storage may need reinstall.';
  }

  @override
  String get reset_saved_connections => 'Reset saved connections';

  @override
  String get responding => 'Responding…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return 'Response closed locally; gateway stop failed: $error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      'Response closed locally; no active gateway turn was found.';

  @override
  String get response_ready => 'Response ready';

  @override
  String get response_stopped => 'Response stopped.';

  @override
  String get restore => 'Restore';

  @override
  String get restore_configuration => 'Restore configuration';

  @override
  String get restore_project => 'Restore project';

  @override
  String get retry => 'Retry';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return 'Retry failed for $name. The draft and prompt were kept.';
  }

  @override
  String get retry_upload => 'Retry upload';

  @override
  String retrying(Object name) {
    return 'Retrying $name…';
  }

  @override
  String get review_local_spaces => 'Review local spaces';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      'Review or promote quick chats past their retention period';

  @override
  String get review_the_attached_content => 'Review the attached content.';

  @override
  String get run_only_this_command => 'Run only this command.';

  @override
  String get running_now => 'Running now';

  @override
  String get save => 'Save';

  @override
  String get save_changes => 'Save Changes';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      'Save a permanent rule in the Hermes configuration.';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      'Save the durable facts from the attached content to memory, then confirm what was retained.';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return 'Save the durable facts from this content to memory, then confirm what was retained:\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      'Save your connections and settings to an encrypted file, then restore them after reinstalling or on another device.';

  @override
  String save_2(Object filename) {
    return 'Save $filename';
  }

  @override
  String get schedule => 'Schedule';

  @override
  String get scheduled_jobs_and_their_last_runs =>
      'Scheduled jobs and their last runs';

  @override
  String get scheduled_tasks => 'Scheduled tasks';

  @override
  String get script_only_no_agent => 'Script only (no agent)';

  @override
  String get scroll_horizontally => 'Scroll horizontally';

  @override
  String get search_all_chats => 'Search all chats';

  @override
  String get search_all_message_content => 'Search all message content';

  @override
  String get search_chats => 'Search chats';

  @override
  String get search_conversations => 'Search conversations';

  @override
  String get search_loaded_chats => 'Search loaded chats';

  @override
  String get search_mode => 'Search mode';

  @override
  String get select_one_option_or_enter_another_answer =>
      'Select one option, or enter another answer.';

  @override
  String get select_one_or_more_options_then_continue =>
      'Select one or more options, then continue.';

  @override
  String get select_text => 'Select text';

  @override
  String get send => 'Send';

  @override
  String send_failed(Object error) {
    return 'Send failed: $error';
  }

  @override
  String get send_message => 'Send message';

  @override
  String get session_sources => 'Session Sources';

  @override
  String get session_deleted_from_remote_hermes =>
      'Session deleted from remote Hermes.';

  @override
  String session_search_failed(Object error) {
    return 'Session search failed: $error';
  }

  @override
  String get set_profile_default => 'Set profile default';

  @override
  String get settings => 'Settings';

  @override
  String get share_to_hermes => 'Share to Hermes';

  @override
  String get show_passphrase => 'Show passphrase';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      'Show tool calls, thinking, and message metadata';

  @override
  String get signal_messages => 'Signal messages';

  @override
  String get skills => 'Skills';

  @override
  String skills_2(Object count) {
    return 'Skills ($count)';
  }

  @override
  String get skills_and_tools => 'Skills and tools';

  @override
  String get skip => 'Skip';

  @override
  String get slack_chats => 'Slack chats';

  @override
  String source(Object source) {
    return 'Source: $source';
  }

  @override
  String get space_actions => 'Space actions';

  @override
  String get spaces => 'Spaces';

  @override
  String get speak_to_hermes => 'Speak to Hermes';

  @override
  String get speech_recognition_is_unavailable =>
      'Speech recognition is unavailable';

  @override
  String get spoken_replies => 'Spoken replies';

  @override
  String get spoken_replies_off => 'Spoken replies off';

  @override
  String get spoken_replies_on => 'Spoken replies on';

  @override
  String get stalled_no_update_from_hermes => 'Stalled — no update from Hermes';

  @override
  String get start_something_new => 'Start something new';

  @override
  String get start_voice_input => 'Start voice input';

  @override
  String get starting_hermes => 'Starting Hermes…';

  @override
  String get steer_turn => 'Add to current response';

  @override
  String get steer_chip_label => 'STEER';

  @override
  String get steer_queued_for_next_turn =>
      'Turn is finishing — your note will be sent next';

  @override
  String get media_card_download => 'Download file';

  @override
  String get media_card_tap_to_download => 'Tap to download';

  @override
  String get still_loading_your_projects => 'Still loading your projects.';

  @override
  String get stop => 'Stop';

  @override
  String get stop_response => 'Stop response';

  @override
  String get stop_voice_input => 'Stop voice input';

  @override
  String get submitted_waiting_for_hermes => 'Submitted, waiting for Hermes';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      'Suggest Projects and learn from your corrections';

  @override
  String get summarize_the_attached_content =>
      'Summarize the attached content.';

  @override
  String summarize_this_content(Object text) {
    return 'Summarize this content:\n\n$text';
  }

  @override
  String get switch_profile => 'Switch profile';

  @override
  String get system => 'System';

  @override
  String get take_photo => 'Take photo';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      'Tap + to add a remote Hermes Gateway\n(API Server, port 8642)';

  @override
  String get tap_the_button_to_start_a_new_chat =>
      'Tap the + button to start a new chat';

  @override
  String get telegram_messages => 'Telegram messages';

  @override
  String get terminal_sessions => 'Terminal sessions';

  @override
  String get text_size => 'Text size';

  @override
  String get text_size_preview => 'Text size preview';

  @override
  String text_size_2(Object label) {
    return 'Text size: $label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely =>
      'The API key could not be stored securely.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      'The Project will move to Archived. Its chats and files stay intact, and you can restore it at any time.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      'The Project will move to Archived. Its chats and files stay intact, and you can restore it later.';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      'The active profile did not return any selectable models.';

  @override
  String get the_backup_could_not_be_exported =>
      'The backup could not be exported.';

  @override
  String get the_backup_could_not_be_restored =>
      'The backup could not be restored.';

  @override
  String get the_connection_could_not_be_deleted_safely =>
      'The connection could not be deleted safely.';

  @override
  String get the_connection_could_not_be_stored_securely =>
      'The connection could not be stored securely.';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      'The dashboard credentials could not be stored securely.';

  @override
  String get the_detached_reply_failed => 'The detached reply failed.';

  @override
  String the_detached_reply_failed_2(Object error) {
    return 'The detached reply failed: $error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      'The file contains your API keys and dashboard password, so it is encrypted. Without this passphrase the backup cannot be restored.';

  @override
  String get the_last_turn_failed => 'The last turn failed';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return 'The local connection store looks damaged ($errorType). You can reset the saved connections and start fresh. Chats on your gateway are not affected.';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      'The model only rewrites your question into a short full-text query. Hermes uses the provider credentials already configured on the host.';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      'The server has not reported folders for this project yet. Global Files stays available from More.';

  @override
  String get the_turn_failed => 'The turn failed';

  @override
  String get the_two_passphrases_do_not_match =>
      'The two passphrases do not match.';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      'The value is sent directly to the active Hermes gateway and is not saved by this Android app.';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      'There are no visible files in this server folder.';

  @override
  String get thinking_effort => 'Thinking effort';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      'This Hermes gateway does not support opening a project yet. Update Hermes on the server to browse a project from your phone.';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      'This Hermes gateway is older than server-side projects, so chats stay grouped on this device only. Update Hermes to share the same projects across your devices.';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      'This Project has no folder to open the chat in — it opened unassigned. Add a folder to the Project to group its chats.';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      'This chat has no messages available in the Desktop session yet.';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      'This creates a permanent rule in Hermes. Review the full command before confirming.';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      'This gateway does not host projects yet. Update the gateway to organize chats across your devices.';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      'This permanently deletes the Project. Chats will not be deleted; they’ll return to Unassigned.';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      'This server doesn\'t offer background recovery — chats run live';

  @override
  String get this_week => 'This week';

  @override
  String get titles_previews_and_models => 'Titles, previews, and models';

  @override
  String get tool_activity => 'Tool activity';

  @override
  String get trigger_now => 'Trigger now';

  @override
  String get turn_completed => 'Turn completed';

  @override
  String get turn_recovery_failed => 'Turn recovery failed';

  @override
  String get unable_to_prepare_this_file_try_another_one =>
      'Unable to prepare this file. Try another one.';

  @override
  String get unable_to_prepare_this_image_try_another_one =>
      'Unable to prepare this image. Try another one.';

  @override
  String unable_to_prepare(Object name) {
    return 'Unable to prepare $name.';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      'Unable to read the selected image. The selection was kept.';

  @override
  String get unassigned => 'Unassigned';

  @override
  String get unassigned_chats => 'Unassigned chats';

  @override
  String get untitled_chat => 'Untitled chat';

  @override
  String get untitled_session => 'Untitled session';

  @override
  String get update_api_key => 'Update API Key';

  @override
  String get upload_failed => 'Upload failed';

  @override
  String get upload_failed_tap_retry => 'Upload failed • tap retry';

  @override
  String uploading(Object index, Object name, Object total) {
    return 'Uploading $index/$total: $name';
  }

  @override
  String get use_as_is => 'Use as is';

  @override
  String get use_at_least_8_characters => 'Use at least 8 characters.';

  @override
  String get use_for_cron_jobs_backed_by_scripts =>
      'Use for cron jobs backed by scripts.';

  @override
  String get use_on_device => 'Use on-device';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      'Use the attached content to identify and fill the relevant document or form fields. Ask before submitting anything.';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return 'Use this content to identify and fill the relevant document or form fields. Ask before submitting anything:\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      'Used for hosted path prefixes and for the Settings, Memory, Skills and Cron tabs. Leave username/password blank for an open dashboard, or enable proxied mode when your reverse proxy injects dashboard auth.';

  @override
  String get username_optional => 'Username (optional)';

  @override
  String using(Object displayName) {
    return 'Using $displayName…';
  }

  @override
  String get verbose_mode => 'Verbose Mode';

  @override
  String get voice => 'Voice';

  @override
  String voice_setup_failed(Object error) {
    return 'Voice setup failed: $error';
  }

  @override
  String get waiting_for_your_input => 'Waiting for your input';

  @override
  String get what_hermes_knows_how_to_do => 'What Hermes knows how to do';

  @override
  String get what_should_the_agent_do => 'What should the agent do?';

  @override
  String get whatsapp_messages => 'WhatsApp messages';

  @override
  String get which_project => 'Which project?';

  @override
  String get workspace => 'Workspace';

  @override
  String get wrap_lines => 'Wrap lines';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return 'You can attach up to $maxRemoteAttachmentDrafts items.';
  }

  @override
  String get your_answer => 'Your answer';

  @override
  String get e_g_dashboard => 'e.g. /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      'e.g. /dashboard (proxy path before /api/)';

  @override
  String get e_g_profile_peter => 'e.g. /profile/peter';

  @override
  String get e_g_sol => 'e.g. sol';

  @override
  String get e_g_0_9_or_every_2h => 'e.g., 0 9 * * * or every 2h';

  @override
  String get e_g_daily_backup => 'e.g., Daily backup';

  @override
  String downloaded(Object filename) {
    return '$filename downloaded';
  }

  @override
  String activity_name_status(Object displayName, Object statusLabel) {
    return '$displayName: $statusLabel';
  }

  @override
  String connection_status_label(Object connectionLabel, Object label) {
    return '$connectionLabel $label';
  }

  @override
  String get example_host_hint =>
      '192.168.1.50, 100.x.y.z, or hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      'e.g. /profile/peter (proxy path before /api/ and /v1/)';

  @override
  String and_more(Object count) {
    return 'and $count more';
  }

  @override
  String chats_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chats',
      one: '$count chat',
    );
    return '$_temp0';
  }

  @override
  String on_this_device_only(Object chats) {
    return '$chats · on this device only';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count spaces',
      one: '$count space',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => 'no new projects needed';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projects to create',
      one: '$count project to create',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return '$linkedSessions chats migrated · $createdProjects projects created';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '$unlinkedSessions chats stayed in local Spaces and can be retried safely.';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • Recommended: small and inexpensive';
  }

  @override
  String session_meta(Object count, Object model, Object time) {
    return '$count msgs • $model • $time';
  }

  @override
  String model_scope_label(Object model, Object scope) {
    return '$model • $scope';
  }

  @override
  String get this_chat => 'this chat';

  @override
  String get profile_default => 'profile default';

  @override
  String minutes_ago(Object count) {
    return '${count}m ago';
  }

  @override
  String hours_ago(Object count) {
    return '${count}h ago';
  }

  @override
  String days_ago(Object count) {
    return '${count}d ago';
  }

  @override
  String get now_label => 'now';

  @override
  String get latest_label => 'Latest';

  @override
  String new_count_indicator(Object count) {
    return '$count new';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new messages',
      one: '$count new message',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return '$failures failed • $total total';
  }

  @override
  String activity_completed_summary(Object count) {
    return '$count completed';
  }

  @override
  String get hermes_is_using_a_tool => 'Hermes is using a tool';

  @override
  String hermes_is_using_tools(Object count) {
    return 'Hermes is using $count tools';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return '$count delegated task(s) completed';
  }

  @override
  String delegated_tasks_active(Object count) {
    return '$count delegated task(s) active';
  }

  @override
  String branch_main(Object label) {
    return '$label · main';
  }

  @override
  String get you_heading => '## You';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => 'Action';

  @override
  String get destination_label => 'Destination';

  @override
  String get preview_label => 'Preview';

  @override
  String get share_action_summarize => 'Summarize';

  @override
  String get share_action_explain => 'Explain';

  @override
  String get share_action_research => 'Research';

  @override
  String get share_action_remember => 'Remember';

  @override
  String get text_size_small => 'Small';

  @override
  String get text_size_default => 'Default';

  @override
  String get text_size_large => 'Large';

  @override
  String get text_size_extra_large => 'Extra large';

  @override
  String get text_size_use_system_description =>
      'Use Android accessibility text size exactly.';

  @override
  String text_size_percent_description(Object percent) {
    return '$percent% of the Android text size.';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return '$count file(s) skipped: limit, size, unreadable, or sensitive filename.';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort now apply only to this chat.';
  }

  @override
  String get reasoning_minimal => 'Minimal';

  @override
  String get reasoning_low => 'Low';

  @override
  String get reasoning_medium => 'Medium';

  @override
  String get reasoning_high => 'High';

  @override
  String get reasoning_max => 'Max';

  @override
  String get reasoning_ultra => 'Ultra';

  @override
  String get status_running => 'Running';

  @override
  String get status_failed => 'Failed';

  @override
  String get status_done => 'Done';

  @override
  String get status_idle => 'Idle';

  @override
  String get upload_status_uploading => 'Uploading';

  @override
  String get upload_status_uploaded => 'Uploaded';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments',
      one: '$count attachment',
    );
    return '$_temp0';
  }

  @override
  String get action_create => 'create';

  @override
  String get action_rename => 'rename';

  @override
  String get action_archive => 'archive';

  @override
  String get action_restore => 'restore';

  @override
  String get action_delete => 'delete';

  @override
  String get migrate => 'Migrate';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count assigned chats',
      one: '$count assigned chat',
    );
    return '$_temp0';
  }

  @override
  String get date_today => 'Today';

  @override
  String get date_yesterday => 'Yesterday';

  @override
  String get date_earlier => 'Earlier';

  @override
  String get nav_home => 'Home';

  @override
  String get nav_more => 'More';

  @override
  String get status_completed => 'Completed';

  @override
  String get filter_all => 'All';

  @override
  String get filter_recent => 'Recent';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  Key: $status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model  \nvia `$provider`';
  }

  @override
  String get deny => 'Deny';

  @override
  String get connect => 'Connect';

  @override
  String get appearance => 'Appearance';

  @override
  String get connection_section => 'Connection';

  @override
  String get about => 'About';

  @override
  String version_label(Object version) {
    return 'Version $version';
  }

  @override
  String get matched => 'Matched';

  @override
  String get search => 'Search';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get reasoning_off => 'Off';

  @override
  String get hermes_response_ready => 'Hermes response ready';

  @override
  String get admin_password_needed => 'Administrator password needed';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      'Hermes needs a sudo password for the pending terminal command.';

  @override
  String get sudo_password => 'Sudo password';

  @override
  String get secret_needed => 'Secret needed';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      'Hermes needs a secret for the pending skill.';

  @override
  String get secret_value => 'Secret value';

  @override
  String get attached_file => 'Attached file';
}
