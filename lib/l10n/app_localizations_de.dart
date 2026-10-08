// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      'Eine einmalige Frage. Wird nach 72 Stunden automatisch archiviert; alles, was es wert ist, bleibt im Gedächtnis.';

  @override
  String get ai_full_text => 'KI + Volltext';

  @override
  String get ai_search_model => 'KI-Suchmodell';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'KI hat gesucht: $aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'KI-gestützte Ablage';

  @override
  String get api_key => 'API-Schlüssel';

  @override
  String get api_server_key_from_hermes_env =>
      'API_SERVER_KEY aus ~/.hermes/.env';

  @override
  String get active => 'Aktiv';

  @override
  String get activity => 'Aktivität';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      'Die Aktivität liest das dauerhafte Turn-Journal, um zu wissen, was Hermes gerade tut. Prüfe, ob das Gateway erreichbar ist, und versuche es dann erneut.';

  @override
  String get add => 'Hinzufügen';

  @override
  String get add_connection => 'Verbindung hinzufügen';

  @override
  String get add_cron_job => 'Cron-Job hinzufügen';

  @override
  String get add_gateway_connection => 'Gateway-Verbindung hinzufügen';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      'Verbindungen aus dem Backup hinzufügen und aktualisieren, den Rest beibehalten.';

  @override
  String get add_attachment => 'Anhang hinzufügen';

  @override
  String get add_new_cron_job => 'Neuen Cron-Job hinzufügen';

  @override
  String get add_to_chat => 'Zum Chat hinzufügen';

  @override
  String get all_chats => 'Alle Chats';

  @override
  String get all_stored_message_content =>
      'Gesamter gespeicherter Nachrichteninhalt';

  @override
  String get allow_for_this_session => 'Für diese Sitzung erlauben';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      'Passende Befehle bis zum Ende dieser Hermes-Sitzung erlauben.';

  @override
  String get allow_once => 'Einmal erlauben';

  @override
  String get always_allow => 'Immer erlauben';

  @override
  String get apply_to_this_chat => 'Auf diesen Chat anwenden';

  @override
  String get approval_needed => 'Genehmigung erforderlich';

  @override
  String get archive => 'Archivieren';

  @override
  String get archive_project => 'Projekt archivieren';

  @override
  String archive_2(Object projectName) {
    return '$projectName archivieren?';
  }

  @override
  String archive_3(Object name) {
    return '$name archivieren?';
  }

  @override
  String get archived => 'Archiviert';

  @override
  String get archived_conversations_appear_here =>
      'Archivierte Unterhaltungen erscheinen hier.';

  @override
  String get archived_quick_chats => 'Archivierte Schnellchats';

  @override
  String get artifacts_attachments_and_generated_media =>
      'Artefakte, Anhänge und generierte Medien';

  @override
  String get ask_ai_to_find_a_conversation =>
      'KI bitten, eine Unterhaltung zu finden';

  @override
  String get assets => 'Assets';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      'Assets benötigen einen serverautoritativen Index im Hermes-Gateway, bevor sie pro Projekt angezeigt werden können.';

  @override
  String get assets_unavailable => 'Assets nicht verfügbar';

  @override
  String get attach_image_or_file => 'Bild oder Datei anhängen';

  @override
  String get attachment_drafts => 'Anhangsentwürfe';

  @override
  String attachment_of(Object index, Object total) {
    return 'Anhang $index von $total';
  }

  @override
  String get auto_device_default => 'Automatisch (Gerätestandard)';

  @override
  String get auto_archives_after_72_hours =>
      'Automatische Archivierung nach 72 Stunden';

  @override
  String get automation => 'Automatisierung';

  @override
  String get autonomous_agents => 'Autonome Agenten';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      'Hintergrund-Wiederherstellung nicht verfügbar — Legacy-Transport';

  @override
  String get backup_restore => 'Backup und Wiederherstellung';

  @override
  String backup_exported(Object destination) {
    return 'Backup exportiert — $destination';
  }

  @override
  String get base_url => 'Basis-URL';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      'Binärvorschau ist nicht verfügbar. Lade die Datei herunter, um sie zu öffnen.';

  @override
  String get branch => 'Branch';

  @override
  String get branch_chat => 'Chat verzweigen';

  @override
  String get branch_created_in_hermes_history =>
      'Branch im Hermes-Verlauf erstellt.';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      'Durchsuche und verwalte deine Hermes-Agent-Sitzungen vom Telefon aus. Verbindet sich mit einem Hermes-Dashboard in deinem lokalen Netzwerk.';

  @override
  String get browse_server_files => 'Serverdateien durchsuchen';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      'Durchsuche die miniserver-Ordner hinter deinen Projekten';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get cancel_voice_input => 'Spracheingabe abbrechen';

  @override
  String cannot_reach(Object host, Object port) {
    return '$host:$port ist nicht erreichbar.';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return '$host:$port ist nicht erreichbar. Prüfe Host und Port.';
  }

  @override
  String get change_ai_search_model => 'KI-Suchmodell ändern';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return 'Ändert den Standard für $label. Nutze die Auswahl in einem Chat, um nur diese Unterhaltung zu überschreiben.';
  }

  @override
  String get chat_actions => 'Chat-Aktionen';

  @override
  String get chats => 'Chats';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      'Chats von diesem Gateway werden noch nicht gruppiert. Die Gruppierung bleibt auf diesem Telefon, bis das Gateway Projekte hosten kann.';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      'Chats in diesem Projekt zeigen hier ihren Status und ihre letzte Aktivität.';

  @override
  String get chats_that_are_not_assigned_to_a_project =>
      'Chats, die keinem Projekt zugewiesen sind';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      'Chats, die du in diesem Projekt startest, erscheinen hier — auf jedem Gerät, das bei diesem Hermes angemeldet ist.';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      'Prüfe, ob das Gateway läuft und erreichbar ist, und versuche es dann erneut.';

  @override
  String get check_the_dashboard_connection_and_try_again =>
      'Prüfe die Dashboard-Verbindung und versuche es erneut.';

  @override
  String get check_the_connection_and_try_again =>
      'Prüfe die Verbindung und versuche es erneut.';

  @override
  String get choose_a_small_model_to_rewrite_queries =>
      'Wähle ein kleines Modell zum Umschreiben von Anfragen';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      'Wähle ein KI-Suchmodell, bevor du die KI-Suche verwendest.';

  @override
  String get choose_an_active_project_next =>
      'Wähle als Nächstes ein aktives Projekt';

  @override
  String get choose_chat_model => 'Chat-Modell wählen';

  @override
  String get choose_files => 'Dateien wählen';

  @override
  String get choose_image => 'Bild wählen';

  @override
  String get choose_images => 'Bilder wählen';

  @override
  String get choose_its_destination_space => 'Wähle den Zielbereich';

  @override
  String get clear_search => 'Suche löschen';

  @override
  String get close => 'Schließen';

  @override
  String get code_copied => 'Code kopiert';

  @override
  String get coming_next => 'Demnächst';

  @override
  String get command => 'Befehl';

  @override
  String get command_line_chats => 'Kommandozeilen-Chats';

  @override
  String get compatibility_mode => 'Kompatibilitätsmodus';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      'Konfiguriere eine gültige Desktop-Gateway-URL, bevor du Dateien anhängst.';

  @override
  String get confirm_always_allow => '„Immer erlauben“ bestätigen';

  @override
  String get confirm_passphrase => 'Passphrase bestätigen';

  @override
  String connecting_to(Object baseUrl) {
    return 'Verbindung zu $baseUrl wird hergestellt...';
  }

  @override
  String get connection_issue => 'Verbindungsproblem';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      'Verbindung gewechselt — die laufende Antwort wird auf dem Server fortgesetzt und automatisch wieder angehängt.';

  @override
  String get connection_appearance_and_device_preferences =>
      'Verbindung, Darstellung und Geräteeinstellungen';

  @override
  String context_tokens(Object effectiveContextLength) {
    return 'Kontext: $effectiveContextLength Token';
  }

  @override
  String get continue_label => 'Weiter';

  @override
  String get continue_working => 'Weiterarbeiten';

  @override
  String get conversations_in_this_project =>
      'Unterhaltungen in diesem Projekt';

  @override
  String get copy_code => 'Code kopieren';

  @override
  String get copy_message => 'Nachricht kopieren';

  @override
  String could_not_branch_chat(Object error) {
    return 'Chat konnte nicht verzweigt werden: $error';
  }

  @override
  String could_not_delete_session(Object error) {
    return 'Sitzung konnte nicht gelöscht werden: $error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return 'Befehl konnte nicht abgelehnt werden: $error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return 'KI-Suchmodelle konnten nicht geladen werden: $error';
  }

  @override
  String get could_not_load_conversations =>
      'Unterhaltungen konnten nicht geladen werden';

  @override
  String get could_not_load_files => 'Dateien konnten nicht geladen werden';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return 'Modelle für dieses Profil konnten nicht geladen werden: $error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return 'Weitere Chats konnten nicht geladen werden: $error';
  }

  @override
  String get could_not_open_the_hermes_dashboard =>
      'Das Hermes-Dashboard konnte nicht geöffnet werden.';

  @override
  String get could_not_open_this_project =>
      'Dieses Projekt konnte nicht geöffnet werden';

  @override
  String get could_not_preview_file =>
      'Datei konnte nicht in der Vorschau angezeigt werden';

  @override
  String get could_not_reach_hermes => 'Hermes ist nicht erreichbar';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return 'Dashboard unter $host:$dashboardPort nicht erreichbar oder nicht authentifiziert. Prüfe Port und Zugangsdaten.';
  }

  @override
  String get could_not_read_activity => 'Aktivität konnte nicht gelesen werden';

  @override
  String could_not_rename_chat(Object error) {
    return 'Chat konnte nicht umbenannt werden: $error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return 'Genehmigung konnte nicht gesendet werden: $error';
  }

  @override
  String get could_not_skip_the_hermes_question =>
      'Die Frage von Hermes konnte nicht übersprungen werden.';

  @override
  String could_not_the_project(Object action, Object error) {
    return 'Projekt konnte nicht $action werden: $error';
  }

  @override
  String get couldn_t_delete_project => 'Projekt konnte nicht gelöscht werden';

  @override
  String couldn_t_load_runs(Object error) {
    return 'Ausführungen konnten nicht geladen werden: $error';
  }

  @override
  String get couldn_t_move_conversation =>
      'Unterhaltung konnte nicht verschoben werden';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return 'Verschieben nach $label fehlgeschlagen: $reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files =>
      'Die geteilten Dateien konnten nicht vorbereitet werden.';

  @override
  String get couldn_t_promote_conversation =>
      'Unterhaltung konnte nicht hochgestuft werden';

  @override
  String couldn_t_project(Object action) {
    return 'Projekt konnte nicht $action werden';
  }

  @override
  String get create => 'Erstellen';

  @override
  String get create_a_project => 'Projekt erstellen';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      'Erstelle zuerst ein Projekt; darin können dann Chats leben.';

  @override
  String get create_a_space_to_separate_related_conversations =>
      'Erstelle einen Bereich, um zusammengehörige Unterhaltungen zu trennen.';

  @override
  String get create_branch => 'Branch erstellen';

  @override
  String get cron => 'Cron';

  @override
  String get cron_jobs => 'Cron-Jobs';

  @override
  String get cron_job_added => 'Cron-Job hinzugefügt';

  @override
  String get cron_job_updated => 'Cron-Job aktualisiert';

  @override
  String get cron_run => 'Cron-Ausführung';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      'Geräteübergreifende Reihenfolge und umkehrbare Massenorganisation';

  @override
  String get current_profile_default => 'Aktueller Profilstandard';

  @override
  String get custom_proxy_and_dashboard_details =>
      'Benutzerdefinierte Proxy- und Dashboard-Details';

  @override
  String get dark => 'Dunkel';

  @override
  String get dashboard_proxy_settings => 'Dashboard- / Proxy-Einstellungen';

  @override
  String get dashboard_password_optional => 'Dashboard-Passwort (optional)';

  @override
  String get dashboard_port => 'Dashboard-Port';

  @override
  String get dashboard_username_optional => 'Dashboard-Benutzername (optional)';

  @override
  String get dashboard_behind_proxy => 'Dashboard hinter Proxy';

  @override
  String get dashboard_path_prefix => 'Dashboard-Pfadpräfix';

  @override
  String delegated_task(Object goal) {
    return 'Delegierte Aufgabe: $goal';
  }

  @override
  String get delete => 'Löschen';

  @override
  String delete_2(Object name) {
    return '„$name“ löschen?';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return '„$title“ aus dem entfernten Hermes-Verlauf löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get delete_cron_job => 'Cron-Job löschen';

  @override
  String get delete_connections_that_are_not_in_the_backup =>
      'Verbindungen löschen, die nicht im Backup enthalten sind.';

  @override
  String delete_failed(Object error) {
    return 'Löschen fehlgeschlagen: $error';
  }

  @override
  String get delete_project => 'Projekt löschen';

  @override
  String get delete_session => 'Sitzung löschen?';

  @override
  String delete_3(Object projectName) {
    return '$projectName löschen?';
  }

  @override
  String deleted(Object name) {
    return '„$name“ gelöscht';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      'Die Zustellung ist ungewiss; Wiederherstellung ohne erneutes Senden…';

  @override
  String get desktop_gateway_url_optional => 'Desktop-Gateway-URL (optional)';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      'Desktop Gateway ist für diese Verbindung nicht konfiguriert.';

  @override
  String get desktop_app => 'Desktop-App';

  @override
  String get developer_tool_calls => 'Entwickler-Tool-Aufrufe';

  @override
  String get discord_chats => 'Discord-Chats';

  @override
  String get dismiss => 'Ausblenden';

  @override
  String get do_not_run_this_command => 'Diesen Befehl nicht ausführen.';

  @override
  String get documents_archives_audio_video_or_data =>
      'Dokumente, Archive, Audio, Video oder Daten';

  @override
  String get download => 'Herunterladen';

  @override
  String download_failed(Object error) {
    return 'Download fehlgeschlagen: $error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you =>
      'Dauerhafte Fakten, die Hermes über dich speichert';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      'Dauerhafte Arbeit in einem deiner Projekte, geteilt mit Desktop.';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get edit_connection => 'Verbindung bearbeiten';

  @override
  String get edit_cron_job => 'Cron-Job bearbeiten';

  @override
  String get edit_gateway_connection => 'Gateway-Verbindung bearbeiten';

  @override
  String get edit_and_resend => 'Bearbeiten und erneut senden';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      'Aktiviert Dateianhänge über das Desktop-Remote-Gateway.';

  @override
  String get enter_a_name => 'Namen eingeben';

  @override
  String get enter_a_passphrase => 'Gib eine Passphrase ein.';

  @override
  String get enter_the_passphrase_for_this_backup =>
      'Gib die Passphrase für dieses Backup ein.';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      'Jede Unterhaltung ist bereits einem Projekt zugewiesen.';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      'Alles, was noch nicht nativ ist, im authentifizierten Web-Dashboard';

  @override
  String get explain_the_attached_content_clearly =>
      'Erkläre den angehängten Inhalt verständlich.';

  @override
  String explain_this_content_clearly(Object text) {
    return 'Erkläre diesen Inhalt verständlich:\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      'Explizite Auswahl passt die Android-Schriftgröße für Barrierefreiheit an; „System“ lässt sie unverändert.';

  @override
  String get export_label => 'Exportieren';

  @override
  String get export_share => 'Exportieren / teilen';

  @override
  String get external_api_clients => 'Externe API-Clients';

  @override
  String get extra_high => 'Sehr hoch';

  @override
  String get extract_tasks => 'Aufgaben extrahieren';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      'Extrahiere aus dem angehängten Inhalt Entscheidungen, Fristen, Verantwortliche und umsetzbare Aufgaben.';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return 'Extrahiere aus diesem Inhalt Entscheidungen, Fristen, Verantwortliche und umsetzbare Aufgaben:\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return 'Job konnte nicht hinzugefügt werden: $error';
  }

  @override
  String get failed_to_load_cron_jobs =>
      'Cron-Jobs konnten nicht geladen werden';

  @override
  String get failed_to_load_memory => 'Gedächtnis konnte nicht geladen werden';

  @override
  String get failed_to_load_messages =>
      'Nachrichten konnten nicht geladen werden';

  @override
  String get failed_to_load_settings =>
      'Einstellungen konnten nicht geladen werden';

  @override
  String get failed_to_load_skills =>
      'Fähigkeiten konnten nicht geladen werden';

  @override
  String failed_to_update_job(Object error) {
    return 'Job konnte nicht aktualisiert werden: $error';
  }

  @override
  String failed(Object error) {
    return 'Fehlgeschlagen: $error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      'Datei angehängt; die Registrierung im Dokumentkatalog steht noch aus.';

  @override
  String get file_reference_added_to_chat =>
      'Dateireferenz zum Chat hinzugefügt';

  @override
  String get files => 'Dateien';

  @override
  String get fill_from_document => 'Aus Dokument befüllen';

  @override
  String get folder_is_empty => 'Ordner ist leer';

  @override
  String get folders => 'Ordner';

  @override
  String get full_text => 'Volltext';

  @override
  String get gateway_api_access => 'Gateway-API-Zugriff';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      'Gateway verbunden, aber das Dashboard war nicht erreichbar oder nicht authentifiziert. Prüfe die Dashboard-Details oder lösche sie, um zu überspringen.';

  @override
  String get gateway_path_prefix => 'Gateway-Pfadpräfix';

  @override
  String get go_to_end => 'Zum Ende';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Hermes Agent für Android';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'Hermes konnte die Antwort nicht annehmen. Bitte versuche es erneut.';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      'Hermes konnte deine gespeicherten Verbindungen nicht laden';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'Hermes hat die Antwort nicht angenommen. Bitte versuche es erneut.';

  @override
  String get hermes_is_responding => 'Hermes antwortet…';

  @override
  String get hermes_is_waiting_for_input => 'Hermes wartet auf deine Eingabe…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'Hermes lässt die Android-Textskalierung für Barrierefreiheit aktiv.';

  @override
  String get hermes_needs_your_input => 'Hermes braucht deine Eingabe';

  @override
  String get hermes_profile_optional => 'Hermes-Profil (optional)';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'Das Hermes-Profil muss ein einfacher Profilname wie „sol“ sein, kein Pfad.';

  @override
  String get hermes_reasoning_details => 'Hermes-Reasoning-Details';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'Hermes-Wiederherstellung ist nicht verfügbar: $error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'Hermes hat die Wiederherstellung sicher gestoppt. Es wurde kein Prompt erneut gesendet.';

  @override
  String get hide_passphrase => 'Passphrase verbergen';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      'Start braucht deine letzten Chats, um zu wissen, was deine Aufmerksamkeit verdient. Prüfe, ob das Gateway erreichbar ist, und versuche es dann erneut.';

  @override
  String get host => 'Host';

  @override
  String get image_selection_was_interrupted_try_again =>
      'Bildauswahl wurde unterbrochen. Versuche es erneut.';

  @override
  String get import_label => 'Importieren';

  @override
  String get inbox => 'Posteingang';

  @override
  String get inbox_is_clear => 'Posteingang ist leer';

  @override
  String get insert_a_remote_file_reference =>
      'Entfernte @file-Referenz einfügen';

  @override
  String get invalid_port_number => 'Ungültige Portnummer.';

  @override
  String get job_paused => 'Job pausiert';

  @override
  String get job_resumed => 'Job fortgesetzt';

  @override
  String get job_triggered => 'Job ausgelöst';

  @override
  String get label => 'Bezeichnung';

  @override
  String last_activity(Object day, Object month, Object year) {
    return 'Letzte Aktivität $day.$month.$year';
  }

  @override
  String last(Object lastRun) {
    return 'Zuletzt: $lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      'Leer lassen für Standard (8642; 443 bei https)';

  @override
  String get leave_blank_for_default_9119 => 'Leer lassen für Standard (9119)';

  @override
  String get light => 'Hell';

  @override
  String listening(Object elapsed) {
    return 'Höre zu • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return 'Höre zu, verstrichen: $elapsed';
  }

  @override
  String get load_more => 'Mehr laden…';

  @override
  String get loading => 'Wird geladen';

  @override
  String get location => 'Standort';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      'Stelle sicher, dass der Gateway-API-Server läuft\n(hermes gateway status)';

  @override
  String matches(Object assigned, Object name) {
    return 'Passt zu $name · $assigned';
  }

  @override
  String get memory => 'Gedächtnis';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'Gedächtniseinträge sind sitzungsübergreifende Fakten, die sich der Agent merkt.\nSie werden in ~/.hermes/config.yaml konfiguriert';

  @override
  String get merge => 'Zusammenführen';

  @override
  String get message => 'Nachricht';

  @override
  String get message_hermes => 'Nachricht an Hermes…';

  @override
  String get message_actions => 'Nachrichtenaktionen';

  @override
  String get message_copied => 'Nachricht kopiert';

  @override
  String get migrating => 'Migration läuft…';

  @override
  String get migration_complete => 'Migration abgeschlossen';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      'Migration fehlgeschlagen. Lokale Bereiche wurden unverändert beibehalten.';

  @override
  String get migration_incomplete => 'Migration unvollständig';

  @override
  String get migration_preview => 'Migrationsvorschau';

  @override
  String get model => 'Modell';

  @override
  String get model_and_thinking_for_this_chat =>
      'Modell und Reasoning für diesen Chat';

  @override
  String model_was_not_changed(Object error) {
    return 'Modell wurde nicht geändert: $error';
  }

  @override
  String get move_attachment_next => 'Anhang nach hinten verschieben';

  @override
  String get move_attachment_previous => 'Anhang nach vorne verschieben';

  @override
  String get move_chat => 'Chat verschieben';

  @override
  String get move_conversation => 'Unterhaltung verschieben';

  @override
  String get move_to_project => 'In Projekt verschieben';

  @override
  String get move_to_space => 'In Bereich verschieben';

  @override
  String get moved_to_a_project => 'In ein Projekt verschoben';

  @override
  String moved_to(Object label) {
    return 'Nach $label verschoben';
  }

  @override
  String get name => 'Name';

  @override
  String get name_prompt_and_schedule_are_required =>
      'Name, Prompt und Zeitplan sind erforderlich';

  @override
  String get nav_activity => 'Aktivität';

  @override
  String get nav_projects => 'Projekte';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Erfordert einen korrekturfähigen Ablagevertrag im Hermes-Gateway.';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      'Erfordert ein erreichbares Hermes-Dashboard. Prüfe Host, Port und Zugangsdaten dieser Verbindung.';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Erfordert einen serverautoritativen Assets-Index im Hermes-Gateway.';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Erfordert dauerhafte Pin-Reihenfolge-, Batch-Mutations- und Undo-Verträge im Hermes-Gateway.';

  @override
  String get needs_you => 'Du wirst gebraucht';

  @override
  String get new_label => 'Neu';

  @override
  String get new_chat => 'Neuer Chat';

  @override
  String get new_chat_2 => 'Neuer Chat';

  @override
  String new_chat_3(Object projectName) {
    return 'Neuer Chat · $projectName';
  }

  @override
  String get new_project => 'Neues Projekt';

  @override
  String get new_space => 'Neuer Bereich';

  @override
  String next(Object nextRun) {
    return 'Nächste: $nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'Nginx injiziert die Authentifizierung — die App sendet saubere Anfragen';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      'Keine TTS-Stimmen gefunden.\nInstalliere Google Text-to-Speech und lade die Sprachdaten herunter.';

  @override
  String get no_active_projects_on_this_gateway =>
      'Keine aktiven Projekte auf diesem Gateway';

  @override
  String get no_activity_yet => 'Noch keine Aktivität';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      'Kein Chat ist blockiert, läuft oder wartet auf Fortsetzung. Starte jederzeit einen neuen.';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return 'Keine Chats in diesem Projekt passen zu „$searchQuery“.';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      'Noch keine Chats in diesem Bereich. Tippe auf +, um einen zu starten.';

  @override
  String get no_chats_yet => 'Noch keine Chats';

  @override
  String get no_connections => 'Keine Verbindungen';

  @override
  String get no_conversation_matches_this_view =>
      'Keine Unterhaltung passt zu dieser Ansicht.';

  @override
  String get no_cron_jobs => 'Keine Cron-Jobs';

  @override
  String get no_folders_yet => 'Noch keine Ordner';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      'Für diese Verbindung wurden keine lokalen Bereiche gefunden; Projekte sind hier also bereits die einzige verwendete Organisation.';

  @override
  String get no_matches => 'Keine Treffer';

  @override
  String get no_memory_entries => 'Keine Gedächtniseinträge';

  @override
  String get no_message_content_matches => 'Keine Treffer im Nachrichteninhalt';

  @override
  String get no_new_messages => 'Keine neuen Nachrichten';

  @override
  String get no_projects_yet => 'Noch keine Projekte';

  @override
  String get no_runs_yet => 'Noch keine Ausführungen.';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return 'Kein Serverprojekt passt zu diesem Namen · $assigned';
  }

  @override
  String get no_sessions_yet => 'Noch keine Sitzungen';

  @override
  String get no_skills_found => 'Keine Fähigkeiten gefunden';

  @override
  String get no_spaces_on_this_device => 'Keine Bereiche auf diesem Gerät';

  @override
  String get no_text_shared => 'Kein Text geteilt';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      'Kein Turn ist blockiert, läuft oder wurde kürzlich abgeschlossen. Gestartete Arbeit erscheint hier.';

  @override
  String get no_turn_needs_your_input_or_has_failed =>
      'Kein Turn braucht deine Eingabe oder ist fehlgeschlagen.';

  @override
  String get no_unassigned_chats => 'Keine nicht zugewiesenen Chats.';

  @override
  String get nothing_changed_in_the_last_seven_days =>
      'In den letzten sieben Tagen hat sich nichts geändert.';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      'Es wurde noch nichts verschoben — dies ist nur, was eine Migration tun würde.';

  @override
  String get nothing_here => 'Hier ist nichts';

  @override
  String get nothing_is_running => 'Nichts läuft';

  @override
  String get nothing_needs_you => 'Nichts braucht dich';

  @override
  String get nothing_to_migrate => 'Nichts zu migrieren';

  @override
  String get off_no_thinking => 'Aus (kein Reasoning)';

  @override
  String get offline_showing_the_last_known_activity =>
      'Offline — zeige die letzte bekannte Aktivität.';

  @override
  String get offline_showing_the_last_known_chats =>
      'Offline — zeige die letzten bekannten Chats';

  @override
  String get offline_showing_the_last_known_projects =>
      'Offline — zeige die letzten bekannten Projekte.';

  @override
  String get on_this_device => 'Auf diesem Gerät';

  @override
  String get on_device => 'Auf dem Gerät';

  @override
  String get open_inbox => 'Posteingang öffnen';

  @override
  String open_inbox_2(Object count) {
    return 'Posteingang öffnen ($count)';
  }

  @override
  String get open_the_hermes_dashboard => 'Hermes-Dashboard öffnen';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      'Optional. Für die Tabs Gedächtnis/Cron/Fähigkeiten/Einstellungen. Leer lassen, um den Standard-Dashboard-Port (9119) ohne Anmeldung zu verwenden.';

  @override
  String get organization => 'Organisation';

  @override
  String get other_answer => 'Andere Antwort';

  @override
  String get overview => 'Übersicht';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get password_optional => 'Passwort (optional)';

  @override
  String get phone_or_tablet => 'Telefon oder Tablet';

  @override
  String get pin_batch_and_undo =>
      'Anpinnen, Stapelverarbeitung und Rückgängig';

  @override
  String get port => 'Port';

  @override
  String get preparing_attachments => 'Anhänge werden vorbereitet…';

  @override
  String get preview_truncated => 'Vorschau gekürzt';

  @override
  String get preview_unavailable => 'Vorschau nicht verfügbar';

  @override
  String get profile => 'Profil';

  @override
  String get profile_default_model => 'Standardmodell des Profils';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return 'Profilstandard auf $selectedModel gesetzt. Chats mit eigenem Modell behalten diese Überschreibung.';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      'Profil, mit dem diese Verbindung chattet, wenn das Dashboard mehrere Profile bedient. Leer lassen für ein isoliertes Dashboard pro Profil.';

  @override
  String get project => 'Projekt';

  @override
  String get project_actions => 'Projektaktionen';

  @override
  String get project_chat => 'Projekt-Chat';

  @override
  String get project_chats_unavailable => 'Projekt-Chats nicht verfügbar';

  @override
  String get projects => 'Projekte';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      'Projekte gruppieren zugehörige Chats, Dateien und Aktivitäten und bleiben mit Hermes auf deinem Computer synchron.';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      'Projekte benötigen eine Desktop-Gateway-Verbindung. Füge die Desktop-Gateway-URL zu dieser Verbindung hinzu, um Chats geräteübergreifend zu organisieren.';

  @override
  String get projects_unavailable => 'Projekte nicht verfügbar';

  @override
  String get projects_activity_new_navigation =>
      'Projekte, Aktivität — neue Navigation';

  @override
  String get promote_to_project => 'Zu Projekt hochstufen';

  @override
  String get prompt => 'Prompt';

  @override
  String get protect_this_backup => 'Dieses Backup schützen';

  @override
  String get provider => 'Anbieter';

  @override
  String get proxy_injects_auth_app_sends_clean_requests =>
      'Proxy injiziert die Authentifizierung; die App sendet saubere Anfragen';

  @override
  String get quick_chat => 'Schnellchat';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      'Schnellchats erscheinen hier nach ihrer Aufbewahrungsfrist.';

  @override
  String get read_aloud => 'Vorlesen';

  @override
  String get read_aloud_is_unavailable_on_this_device =>
      'Vorlesen ist auf diesem Gerät nicht verfügbar';

  @override
  String get reading_response_aloud => 'Antwort wird vorgelesen';

  @override
  String get ready_to_upload => 'Bereit zum Hochladen';

  @override
  String get reasoning => 'Reasoning';

  @override
  String get recently_completed => 'Kürzlich abgeschlossen';

  @override
  String get recovering_hermes => 'Hermes wird wiederhergestellt…';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get regenerate_response => 'Antwort neu generieren';

  @override
  String get remove_attachment => 'Anhang entfernen';

  @override
  String get rename => 'Umbenennen';

  @override
  String get rename_chat => 'Chat umbenennen';

  @override
  String get rename_project => 'Projekt umbenennen';

  @override
  String get rename_space => 'Bereich umbenennen';

  @override
  String rename_2(Object projectName) {
    return '$projectName umbenennen';
  }

  @override
  String rename_3(Object name) {
    return '$name umbenennen';
  }

  @override
  String get replace => 'Ersetzen';

  @override
  String get repositories => 'Repositories';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      'Recherchiere den angehängten Inhalt, überprüfe die wichtigen Aussagen und gib Quellen an.';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return 'Recherchiere diesen Inhalt, überprüfe die wichtigen Aussagen und gib Quellen an:\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return 'Zurücksetzen fehlgeschlagen: $retryError. Der sichere Speicher muss möglicherweise neu installiert werden.';
  }

  @override
  String get reset_saved_connections =>
      'Gespeicherte Verbindungen zurücksetzen';

  @override
  String get responding => 'Antwortet…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return 'Antwort lokal geschlossen; Gateway-Stopp fehlgeschlagen: $error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      'Antwort lokal geschlossen; kein aktiver Gateway-Turn gefunden.';

  @override
  String get response_ready => 'Antwort bereit';

  @override
  String get response_stopped => 'Antwort gestoppt.';

  @override
  String get restore => 'Wiederherstellen';

  @override
  String get restore_configuration => 'Konfiguration wiederherstellen';

  @override
  String get restore_project => 'Projekt wiederherstellen';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return 'Erneuter Versuch für $name fehlgeschlagen. Entwurf und Prompt wurden beibehalten.';
  }

  @override
  String get retry_upload => 'Upload erneut versuchen';

  @override
  String retrying(Object name) {
    return '$name wird erneut versucht…';
  }

  @override
  String get review_local_spaces => 'Lokale Bereiche überprüfen';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      'Schnellchats nach ihrer Aufbewahrungsfrist überprüfen oder hochstufen';

  @override
  String get review_the_attached_content => 'Überprüfe den angehängten Inhalt.';

  @override
  String get run_only_this_command => 'Führe nur diesen Befehl aus.';

  @override
  String get running_now => 'Läuft gerade';

  @override
  String get save => 'Speichern';

  @override
  String get save_changes => 'Änderungen speichern';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      'Speichere eine dauerhafte Regel in der Hermes-Konfiguration.';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      'Speichere die dauerhaften Fakten aus dem angehängten Inhalt im Gedächtnis und bestätige, was behalten wurde.';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return 'Speichere die dauerhaften Fakten aus diesem Inhalt im Gedächtnis und bestätige, was behalten wurde:\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      'Speichere deine Verbindungen und Einstellungen in einer verschlüsselten Datei und stelle sie nach einer Neuinstallation oder auf einem anderen Gerät wieder her.';

  @override
  String save_2(Object filename) {
    return '$filename speichern';
  }

  @override
  String get schedule => 'Zeitplan';

  @override
  String get scheduled_jobs_and_their_last_runs =>
      'Geplante Jobs und ihre letzten Ausführungen';

  @override
  String get scheduled_tasks => 'Geplante Aufgaben';

  @override
  String get script_only_no_agent => 'Nur Skript (kein Agent)';

  @override
  String get scroll_horizontally => 'Horizontal scrollen';

  @override
  String get search_all_chats => 'Alle Chats durchsuchen';

  @override
  String get search_all_message_content =>
      'Gesamten Nachrichteninhalt durchsuchen';

  @override
  String get search_chats => 'Chats durchsuchen';

  @override
  String get search_conversations => 'Unterhaltungen durchsuchen';

  @override
  String get search_loaded_chats => 'Geladene Chats durchsuchen';

  @override
  String get search_mode => 'Suchmodus';

  @override
  String get select_one_option_or_enter_another_answer =>
      'Wähle eine Option oder gib eine andere Antwort ein.';

  @override
  String get select_one_or_more_options_then_continue =>
      'Wähle eine oder mehrere Optionen und fahre dann fort.';

  @override
  String get select_text => 'Text auswählen';

  @override
  String get send => 'Senden';

  @override
  String send_failed(Object error) {
    return 'Senden fehlgeschlagen: $error';
  }

  @override
  String get send_message => 'Nachricht senden';

  @override
  String get session_sources => 'Sitzungsquellen';

  @override
  String get session_deleted_from_remote_hermes =>
      'Sitzung aus dem entfernten Hermes gelöscht.';

  @override
  String session_search_failed(Object error) {
    return 'Sitzungssuche fehlgeschlagen: $error';
  }

  @override
  String get set_profile_default => 'Als Profilstandard festlegen';

  @override
  String get settings => 'Einstellungen';

  @override
  String get share_to_hermes => 'An Hermes teilen';

  @override
  String get show_passphrase => 'Passphrase anzeigen';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      'Tool-Aufrufe, Reasoning und Nachrichten-Metadaten anzeigen';

  @override
  String get signal_messages => 'Signal-Nachrichten';

  @override
  String get skills => 'Fähigkeiten';

  @override
  String skills_2(Object count) {
    return 'Fähigkeiten ($count)';
  }

  @override
  String get skills_and_tools => 'Fähigkeiten und Tools';

  @override
  String get skip => 'Überspringen';

  @override
  String get slack_chats => 'Slack-Chats';

  @override
  String source(Object source) {
    return 'Quelle: $source';
  }

  @override
  String get space_actions => 'Bereichsaktionen';

  @override
  String get spaces => 'Bereiche';

  @override
  String get speak_to_hermes => 'Sprich mit Hermes';

  @override
  String get speech_recognition_is_unavailable =>
      'Spracherkennung ist nicht verfügbar';

  @override
  String get spoken_replies => 'Gesprochene Antworten';

  @override
  String get spoken_replies_off => 'Gesprochene Antworten aus';

  @override
  String get spoken_replies_on => 'Gesprochene Antworten an';

  @override
  String get stalled_no_update_from_hermes =>
      'Ins Stocken geraten — kein Update von Hermes';

  @override
  String get start_something_new => 'Etwas Neues starten';

  @override
  String get start_voice_input => 'Spracheingabe starten';

  @override
  String get starting_hermes => 'Hermes wird gestartet…';

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
  String get still_loading_your_projects =>
      'Deine Projekte werden noch geladen.';

  @override
  String get stop => 'Stoppen';

  @override
  String get stop_response => 'Antwort stoppen';

  @override
  String get stop_voice_input => 'Spracheingabe stoppen';

  @override
  String get submitted_waiting_for_hermes => 'Gesendet, warte auf Hermes';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      'Projekte vorschlagen und aus deinen Korrekturen lernen';

  @override
  String get summarize_the_attached_content =>
      'Fasse den angehängten Inhalt zusammen.';

  @override
  String summarize_this_content(Object text) {
    return 'Fasse diesen Inhalt zusammen:\n\n$text';
  }

  @override
  String get switch_profile => 'Profil wechseln';

  @override
  String get system => 'System';

  @override
  String get take_photo => 'Foto aufnehmen';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      'Tippe auf +, um ein entferntes Hermes-Gateway hinzuzufügen\n(API-Server, Port 8642)';

  @override
  String get tap_the_button_to_start_a_new_chat =>
      'Tippe auf die +-Schaltfläche, um einen neuen Chat zu starten';

  @override
  String get telegram_messages => 'Telegram-Nachrichten';

  @override
  String get terminal_sessions => 'Terminal-Sitzungen';

  @override
  String get text_size => 'Textgröße';

  @override
  String get text_size_preview => 'Textgrößen-Vorschau';

  @override
  String text_size_2(Object label) {
    return 'Textgröße: $label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely =>
      'Der API-Schlüssel konnte nicht sicher gespeichert werden.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      'Das Projekt wird nach „Archiviert“ verschoben. Seine Chats und Dateien bleiben intakt, und du kannst es jederzeit wiederherstellen.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      'Das Projekt wird nach „Archiviert“ verschoben. Seine Chats und Dateien bleiben intakt, und du kannst es später wiederherstellen.';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      'Das aktive Profil hat keine auswählbaren Modelle zurückgegeben.';

  @override
  String get the_backup_could_not_be_exported =>
      'Das Backup konnte nicht exportiert werden.';

  @override
  String get the_backup_could_not_be_restored =>
      'Das Backup konnte nicht wiederhergestellt werden.';

  @override
  String get the_connection_could_not_be_deleted_safely =>
      'Die Verbindung konnte nicht sicher gelöscht werden.';

  @override
  String get the_connection_could_not_be_stored_securely =>
      'Die Verbindung konnte nicht sicher gespeichert werden.';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      'Die Dashboard-Zugangsdaten konnten nicht sicher gespeichert werden.';

  @override
  String get the_detached_reply_failed =>
      'Die abgekoppelte Antwort ist fehlgeschlagen.';

  @override
  String the_detached_reply_failed_2(Object error) {
    return 'Die abgekoppelte Antwort ist fehlgeschlagen: $error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      'Die Datei enthält deine API-Schlüssel und das Dashboard-Passwort und ist daher verschlüsselt. Ohne diese Passphrase kann das Backup nicht wiederhergestellt werden.';

  @override
  String get the_last_turn_failed => 'Der letzte Turn ist fehlgeschlagen';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return 'Der lokale Verbindungsspeicher scheint beschädigt zu sein ($errorType). Du kannst die gespeicherten Verbindungen zurücksetzen und neu beginnen. Chats auf deinem Gateway sind nicht betroffen.';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      'Das Modell schreibt deine Frage nur in eine kurze Volltextanfrage um. Hermes verwendet die bereits auf dem Host konfigurierten Anbieter-Zugangsdaten.';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      'Der Server hat für dieses Projekt noch keine Ordner gemeldet. Globale Dateien bleibt über Mehr verfügbar.';

  @override
  String get the_turn_failed => 'Der Turn ist fehlgeschlagen';

  @override
  String get the_two_passphrases_do_not_match =>
      'Die beiden Passphrasen stimmen nicht überein.';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      'Der Wert wird direkt an das aktive Hermes-Gateway gesendet und nicht von dieser Android-App gespeichert.';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      'In diesem Serverordner sind keine sichtbaren Dateien.';

  @override
  String get thinking_effort => 'Denkaufwand';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      'Dieses Hermes-Gateway unterstützt das Öffnen eines Projekts noch nicht. Aktualisiere Hermes auf dem Server, um ein Projekt vom Telefon aus zu durchsuchen.';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      'Dieses Hermes-Gateway ist älter als serverseitige Projekte, daher bleiben Chats nur auf diesem Gerät gruppiert. Aktualisiere Hermes, um dieselben Projekte geräteübergreifend zu teilen.';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      'Dieses Projekt hat keinen Ordner, in dem der Chat geöffnet werden kann — er wurde nicht zugewiesen geöffnet. Füge dem Projekt einen Ordner hinzu, um seine Chats zu gruppieren.';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      'Dieser Chat hat noch keine Nachrichten in der Desktop-Sitzung.';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      'Dies erstellt eine dauerhafte Regel in Hermes. Überprüfe den vollständigen Befehl, bevor du bestätigst.';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      'Dieses Gateway hostet noch keine Projekte. Aktualisiere das Gateway, um Chats geräteübergreifend zu organisieren.';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      'Dies löscht das Projekt dauerhaft. Chats werden nicht gelöscht; sie kehren zu „Nicht zugewiesen“ zurück.';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      'Dieser Server bietet keine Hintergrund-Wiederherstellung — Chats laufen live';

  @override
  String get this_week => 'Diese Woche';

  @override
  String get titles_previews_and_models => 'Titel, Vorschauen und Modelle';

  @override
  String get tool_activity => 'Tool-Aktivität';

  @override
  String get trigger_now => 'Jetzt auslösen';

  @override
  String get turn_completed => 'Turn abgeschlossen';

  @override
  String get turn_recovery_failed => 'Turn-Wiederherstellung fehlgeschlagen';

  @override
  String get unable_to_prepare_this_file_try_another_one =>
      'Diese Datei konnte nicht vorbereitet werden. Versuche es mit einer anderen.';

  @override
  String get unable_to_prepare_this_image_try_another_one =>
      'Dieses Bild konnte nicht vorbereitet werden. Versuche es mit einem anderen.';

  @override
  String unable_to_prepare(Object name) {
    return '$name konnte nicht vorbereitet werden.';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      'Das ausgewählte Bild konnte nicht gelesen werden. Die Auswahl wurde beibehalten.';

  @override
  String get unassigned => 'Nicht zugewiesen';

  @override
  String get unassigned_chats => 'Nicht zugewiesene Chats';

  @override
  String get untitled_chat => 'Unbenannter Chat';

  @override
  String get untitled_session => 'Unbenannte Sitzung';

  @override
  String get update_api_key => 'API-Schlüssel aktualisieren';

  @override
  String get upload_failed => 'Upload fehlgeschlagen';

  @override
  String get upload_failed_tap_retry =>
      'Upload fehlgeschlagen • zum Wiederholen tippen';

  @override
  String uploading(Object index, Object name, Object total) {
    return 'Lade $index/$total hoch: $name';
  }

  @override
  String get use_as_is => 'So verwenden';

  @override
  String get use_at_least_8_characters => 'Verwende mindestens 8 Zeichen.';

  @override
  String get use_for_cron_jobs_backed_by_scripts =>
      'Für skriptbasierte Cron-Jobs verwenden.';

  @override
  String get use_on_device => 'Auf dem Gerät verwenden';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      'Verwende den angehängten Inhalt, um die relevanten Dokument- oder Formularfelder zu identifizieren und auszufüllen. Frage nach, bevor du etwas absendest.';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return 'Verwende diesen Inhalt, um die relevanten Dokument- oder Formularfelder zu identifizieren und auszufüllen. Frage nach, bevor du etwas absendest:\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      'Wird für gehostete Pfadpräfixe und für die Tabs Einstellungen, Gedächtnis, Fähigkeiten und Cron verwendet. Lass Benutzername/Passwort leer für ein offenes Dashboard, oder aktiviere den Proxy-Modus, wenn dein Reverse-Proxy die Dashboard-Authentifizierung injiziert.';

  @override
  String get username_optional => 'Benutzername (optional)';

  @override
  String using(Object displayName) {
    return '$displayName wird verwendet…';
  }

  @override
  String get verbose_mode => 'Ausführlicher Modus';

  @override
  String get voice => 'Sprache';

  @override
  String voice_setup_failed(Object error) {
    return 'Spracheinrichtung fehlgeschlagen: $error';
  }

  @override
  String get waiting_for_your_input => 'Warte auf deine Eingabe';

  @override
  String get what_hermes_knows_how_to_do => 'Was Hermes kann';

  @override
  String get what_should_the_agent_do => 'Was soll der Agent tun?';

  @override
  String get whatsapp_messages => 'WhatsApp-Nachrichten';

  @override
  String get which_project => 'Welches Projekt?';

  @override
  String get workspace => 'Arbeitsbereich';

  @override
  String get wrap_lines => 'Zeilen umbrechen';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return 'Du kannst bis zu $maxRemoteAttachmentDrafts Elemente anhängen.';
  }

  @override
  String get your_answer => 'Deine Antwort';

  @override
  String get e_g_dashboard => 'z. B. /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      'z. B. /dashboard (Proxy-Pfad vor /api/)';

  @override
  String get e_g_profile_peter => 'z. B. /profile/peter';

  @override
  String get e_g_sol => 'z. B. sol';

  @override
  String get e_g_0_9_or_every_2h => 'z. B. 0 9 * * * oder every 2h';

  @override
  String get e_g_daily_backup => 'z. B. Tägliches Backup';

  @override
  String downloaded(Object filename) {
    return '$filename heruntergeladen';
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
      '192.168.1.50, 100.x.y.z oder hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      'z. B. /profile/peter (Proxy-Pfad vor /api/ und /v1/)';

  @override
  String and_more(Object count) {
    return 'und $count weitere';
  }

  @override
  String chats_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Chats',
      one: '$count Chat',
    );
    return '$_temp0';
  }

  @override
  String on_this_device_only(Object chats) {
    return '$chats · nur auf diesem Gerät';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bereiche',
      one: '$count Bereich',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => 'keine neuen Projekte nötig';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zu erstellende Projekte',
      one: '$count zu erstellendes Projekt',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return '$linkedSessions Chats migriert · $createdProjects Projekte erstellt';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '$unlinkedSessions Chats sind in lokalen Bereichen geblieben und können sicher erneut versucht werden.';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • Empfohlen: klein und günstig';
  }

  @override
  String session_meta(Object count, Object model, Object time) {
    return '$count Nachr. • $model • $time';
  }

  @override
  String model_scope_label(Object model, Object scope) {
    return '$model • $scope';
  }

  @override
  String get this_chat => 'dieser Chat';

  @override
  String get profile_default => 'Profilstandard';

  @override
  String minutes_ago(Object count) {
    return 'vor $count Min.';
  }

  @override
  String hours_ago(Object count) {
    return 'vor $count Std.';
  }

  @override
  String days_ago(Object count) {
    return 'vor $count T.';
  }

  @override
  String get now_label => 'jetzt';

  @override
  String get latest_label => 'Neueste';

  @override
  String new_count_indicator(Object count) {
    return '$count neu';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neue Nachrichten',
      one: '$count neue Nachricht',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return '$failures fehlgeschlagen • $total gesamt';
  }

  @override
  String activity_completed_summary(Object count) {
    return '$count abgeschlossen';
  }

  @override
  String get hermes_is_using_a_tool => 'Hermes verwendet ein Tool';

  @override
  String hermes_is_using_tools(Object count) {
    return 'Hermes verwendet $count Tools';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return '$count delegierte Aufgabe(n) abgeschlossen';
  }

  @override
  String delegated_tasks_active(Object count) {
    return '$count delegierte Aufgabe(n) aktiv';
  }

  @override
  String branch_main(Object label) {
    return '$label · main';
  }

  @override
  String get you_heading => '## Du';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => 'Aktion';

  @override
  String get destination_label => 'Ziel';

  @override
  String get preview_label => 'Vorschau';

  @override
  String get share_action_summarize => 'Zusammenfassen';

  @override
  String get share_action_explain => 'Erklären';

  @override
  String get share_action_research => 'Recherchieren';

  @override
  String get share_action_remember => 'Merken';

  @override
  String get text_size_small => 'Klein';

  @override
  String get text_size_default => 'Standard';

  @override
  String get text_size_large => 'Groß';

  @override
  String get text_size_extra_large => 'Sehr groß';

  @override
  String get text_size_use_system_description =>
      'Genau die Android-Schriftgröße für Barrierefreiheit verwenden.';

  @override
  String text_size_percent_description(Object percent) {
    return '$percent % der Android-Textgröße.';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return '$count Datei(en) übersprungen: Limit, Größe, nicht lesbar oder sensibler Dateiname.';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort gelten jetzt nur für diesen Chat.';
  }

  @override
  String get reasoning_minimal => 'Minimal';

  @override
  String get reasoning_low => 'Niedrig';

  @override
  String get reasoning_medium => 'Mittel';

  @override
  String get reasoning_high => 'Hoch';

  @override
  String get reasoning_max => 'Maximal';

  @override
  String get reasoning_ultra => 'Ultra';

  @override
  String get status_running => 'Läuft';

  @override
  String get status_failed => 'Fehlgeschlagen';

  @override
  String get status_done => 'Fertig';

  @override
  String get status_idle => 'Inaktiv';

  @override
  String get upload_status_uploading => 'Wird hochgeladen';

  @override
  String get upload_status_uploaded => 'Hochgeladen';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Anhänge',
      one: '$count Anhang',
    );
    return '$_temp0';
  }

  @override
  String get action_create => 'erstellt';

  @override
  String get action_rename => 'umbenannt';

  @override
  String get action_archive => 'archiviert';

  @override
  String get action_restore => 'wiederhergestellt';

  @override
  String get action_delete => 'gelöscht';

  @override
  String get migrate => 'Migrieren';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zugewiesene Chats',
      one: '$count zugewiesener Chat',
    );
    return '$_temp0';
  }

  @override
  String get date_today => 'Heute';

  @override
  String get date_yesterday => 'Gestern';

  @override
  String get date_earlier => 'Früher';

  @override
  String get nav_home => 'Start';

  @override
  String get nav_more => 'Mehr';

  @override
  String get status_completed => 'Abgeschlossen';

  @override
  String get filter_all => 'Alle';

  @override
  String get filter_recent => 'Kürzlich';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  Schlüssel: $status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model  \nvia `$provider`';
  }

  @override
  String get deny => 'Ablehnen';

  @override
  String get connect => 'Verbinden';

  @override
  String get appearance => 'Darstellung';

  @override
  String get connection_section => 'Verbindung';

  @override
  String get about => 'Über';

  @override
  String version_label(Object version) {
    return 'Version $version';
  }

  @override
  String get matched => 'Passt';

  @override
  String get search => 'Suchen';

  @override
  String get on => 'An';

  @override
  String get off => 'Aus';

  @override
  String get reasoning_off => 'Aus';

  @override
  String get hermes_response_ready => 'Hermes-Antwort bereit';

  @override
  String get admin_password_needed => 'Administratorpasswort erforderlich';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      'Hermes benötigt ein sudo-Passwort für den ausstehenden Terminal-Befehl.';

  @override
  String get sudo_password => 'sudo-Passwort';

  @override
  String get secret_needed => 'Secret erforderlich';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      'Hermes benötigt ein Secret für die ausstehende Fähigkeit.';

  @override
  String get secret_value => 'Secret-Wert';

  @override
  String get attached_file => 'Angehängte Datei';
}
