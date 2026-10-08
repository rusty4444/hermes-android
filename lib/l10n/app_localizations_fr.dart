// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      'Une question ponctuelle. S\'archive automatiquement après 72 heures ; tout ce qui mérite d\'être conservé reste en mémoire.';

  @override
  String get ai_full_text => 'IA + texte intégral';

  @override
  String get ai_search_model => 'Modèle de recherche IA';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'L\'IA a recherché : $aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'Classement assisté par IA';

  @override
  String get api_key => 'Clé API';

  @override
  String get api_server_key_from_hermes_env =>
      'API_SERVER_KEY depuis ~/.hermes/.env';

  @override
  String get active => 'Actif';

  @override
  String get activity => 'Activité';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      'L\'activité lit le journal durable des tours pour savoir ce que fait Hermes. Vérifiez que la passerelle est accessible, puis réessayez.';

  @override
  String get add => 'Ajouter';

  @override
  String get add_connection => 'Ajouter une connexion';

  @override
  String get add_cron_job => 'Ajouter une tâche Cron';

  @override
  String get add_gateway_connection => 'Ajouter une connexion passerelle';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      'Ajouter et mettre à jour les connexions depuis la sauvegarde, conserver les autres.';

  @override
  String get add_attachment => 'Ajouter une pièce jointe';

  @override
  String get add_new_cron_job => 'Ajouter une nouvelle tâche Cron';

  @override
  String get add_to_chat => 'Ajouter à la discussion';

  @override
  String get all_chats => 'Toutes les discussions';

  @override
  String get all_stored_message_content =>
      'Tout le contenu des messages stocké';

  @override
  String get allow_for_this_session => 'Autoriser pour cette session';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      'Autoriser les commandes correspondantes jusqu\'à la fin de cette session Hermes.';

  @override
  String get allow_once => 'Autoriser une fois';

  @override
  String get always_allow => 'Toujours autoriser';

  @override
  String get apply_to_this_chat => 'Appliquer à cette discussion';

  @override
  String get approval_needed => 'Approbation requise';

  @override
  String get archive => 'Archiver';

  @override
  String get archive_project => 'Archiver le projet';

  @override
  String archive_2(Object projectName) {
    return 'Archiver $projectName ?';
  }

  @override
  String archive_3(Object name) {
    return 'Archiver $name ?';
  }

  @override
  String get archived => 'Archivé';

  @override
  String get archived_conversations_appear_here =>
      'Les discussions archivées apparaissent ici.';

  @override
  String get archived_quick_chats => 'Discussions rapides archivées';

  @override
  String get artifacts_attachments_and_generated_media =>
      'Artefacts, pièces jointes et médias générés';

  @override
  String get ask_ai_to_find_a_conversation =>
      'Demander à l\'IA de trouver une discussion';

  @override
  String get assets => 'Ressources';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      'Les ressources nécessitent un index faisant autorité côté serveur dans la passerelle Hermes avant de pouvoir être affichées par projet.';

  @override
  String get assets_unavailable => 'Ressources indisponibles';

  @override
  String get attach_image_or_file => 'Joindre une image ou un fichier';

  @override
  String get attachment_drafts => 'Brouillons de pièces jointes';

  @override
  String attachment_of(Object index, Object total) {
    return 'Pièce jointe $index sur $total';
  }

  @override
  String get auto_device_default => 'Automatique (par défaut de l\'appareil)';

  @override
  String get auto_archives_after_72_hours =>
      'Archivage automatique après 72 heures';

  @override
  String get automation => 'Automatisation';

  @override
  String get autonomous_agents => 'Agents autonomes';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      'Récupération en arrière-plan indisponible — transport hérité';

  @override
  String get backup_restore => 'Sauvegarde et restauration';

  @override
  String backup_exported(Object destination) {
    return 'Sauvegarde exportée — $destination';
  }

  @override
  String get base_url => 'URL de base';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      'L\'aperçu binaire n\'est pas disponible. Téléchargez le fichier pour l\'ouvrir.';

  @override
  String get branch => 'Branche';

  @override
  String get branch_chat => 'Créer une branche de la discussion';

  @override
  String get branch_created_in_hermes_history =>
      'Branche créée dans l\'historique Hermes.';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      'Parcourez et gérez vos sessions Hermes Agent depuis votre téléphone. Se connecte à un tableau de bord Hermes exécuté sur votre réseau local.';

  @override
  String get browse_server_files => 'Parcourir les fichiers du serveur';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      'Parcourez les dossiers miniserver derrière vos projets';

  @override
  String get cancel => 'Annuler';

  @override
  String get cancel_voice_input => 'Annuler la saisie vocale';

  @override
  String cannot_reach(Object host, Object port) {
    return 'Impossible d\'atteindre $host:$port.';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return 'Impossible d\'atteindre $host:$port. Vérifiez l\'hôte et le port.';
  }

  @override
  String get change_ai_search_model => 'Changer le modèle de recherche IA';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return 'Modifie la valeur par défaut de $label. Utilisez le sélecteur dans une discussion pour ne remplacer que celle-ci.';
  }

  @override
  String get chat_actions => 'Actions de la discussion';

  @override
  String get chats => 'Discussions';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      'Les discussions de cette passerelle ne sont pas encore regroupées. Le regroupement reste sur ce téléphone tant que la passerelle ne peut pas héberger de projets.';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      'Les discussions de ce projet afficheront ici leur état et leur dernière activité.';

  @override
  String get chats_that_are_not_assigned_to_a_project =>
      'Discussions non affectées à un projet';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      'Les discussions que vous démarrez dans ce projet apparaîtront ici, sur tous les appareils connectés à ce Hermes.';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      'Vérifiez que la passerelle est en cours d\'exécution et accessible, puis réessayez.';

  @override
  String get check_the_dashboard_connection_and_try_again =>
      'Vérifiez la connexion au tableau de bord, puis réessayez.';

  @override
  String get check_the_connection_and_try_again =>
      'Vérifiez la connexion, puis réessayez.';

  @override
  String get choose_a_small_model_to_rewrite_queries =>
      'Choisissez un petit modèle pour reformuler les requêtes';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      'Choisissez un modèle de recherche IA avant d\'utiliser la recherche IA.';

  @override
  String get choose_an_active_project_next =>
      'Choisissez ensuite un projet actif';

  @override
  String get choose_chat_model => 'Choisir le modèle de discussion';

  @override
  String get choose_files => 'Choisir des fichiers';

  @override
  String get choose_image => 'Choisir une image';

  @override
  String get choose_images => 'Choisir des images';

  @override
  String get choose_its_destination_space =>
      'Choisissez son espace de destination';

  @override
  String get clear_search => 'Effacer la recherche';

  @override
  String get close => 'Fermer';

  @override
  String get code_copied => 'Code copié';

  @override
  String get coming_next => 'Bientôt disponible';

  @override
  String get command => 'Commande';

  @override
  String get command_line_chats => 'Discussions en ligne de commande';

  @override
  String get compatibility_mode => 'Mode de compatibilité';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      'Configurez une URL de Desktop Gateway valide avant de joindre des fichiers.';

  @override
  String get confirm_always_allow => 'Confirmer « Toujours autoriser »';

  @override
  String get confirm_passphrase => 'Confirmer la phrase de passe';

  @override
  String connecting_to(Object baseUrl) {
    return 'Connexion à $baseUrl...';
  }

  @override
  String get connection_issue => 'Problème de connexion';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      'Connexion basculée — la réponse en cours continue sur le serveur et se rattachera automatiquement.';

  @override
  String get connection_appearance_and_device_preferences =>
      'Connexion, apparence et préférences de l\'appareil';

  @override
  String context_tokens(Object effectiveContextLength) {
    return 'Contexte : $effectiveContextLength tokens';
  }

  @override
  String get continue_label => 'Continuer';

  @override
  String get continue_working => 'Continuer le travail';

  @override
  String get conversations_in_this_project => 'Discussions de ce projet';

  @override
  String get copy_code => 'Copier le code';

  @override
  String get copy_message => 'Copier le message';

  @override
  String could_not_branch_chat(Object error) {
    return 'Impossible de créer une branche de la discussion : $error';
  }

  @override
  String could_not_delete_session(Object error) {
    return 'Impossible de supprimer la session : $error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return 'Impossible de refuser la commande : $error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return 'Impossible de charger les modèles de recherche IA : $error';
  }

  @override
  String get could_not_load_conversations =>
      'Impossible de charger les discussions';

  @override
  String get could_not_load_files => 'Impossible de charger les fichiers';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return 'Impossible de charger les modèles de ce profil : $error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return 'Impossible de charger plus de discussions : $error';
  }

  @override
  String get could_not_open_the_hermes_dashboard =>
      'Impossible d\'ouvrir le tableau de bord Hermes.';

  @override
  String get could_not_open_this_project => 'Impossible d\'ouvrir ce projet';

  @override
  String get could_not_preview_file => 'Impossible de prévisualiser le fichier';

  @override
  String get could_not_reach_hermes => 'Impossible d\'atteindre Hermes';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return 'Impossible d\'atteindre ou d\'authentifier le tableau de bord sur $host:$dashboardPort. Vérifiez le port et les identifiants.';
  }

  @override
  String get could_not_read_activity => 'Impossible de lire l\'activité';

  @override
  String could_not_rename_chat(Object error) {
    return 'Impossible de renommer la discussion : $error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return 'Impossible d\'envoyer l\'approbation : $error';
  }

  @override
  String get could_not_skip_the_hermes_question =>
      'Impossible d\'ignorer la question de Hermes.';

  @override
  String could_not_the_project(Object action, Object error) {
    return 'Impossible de $action le projet : $error';
  }

  @override
  String get couldn_t_delete_project => 'Impossible de supprimer le projet';

  @override
  String couldn_t_load_runs(Object error) {
    return 'Impossible de charger les exécutions : $error';
  }

  @override
  String get couldn_t_move_conversation =>
      'Impossible de déplacer la discussion';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return 'Impossible de déplacer vers $label : $reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files =>
      'Impossible de préparer les fichiers partagés.';

  @override
  String get couldn_t_promote_conversation =>
      'Impossible de promouvoir la discussion';

  @override
  String couldn_t_project(Object action) {
    return 'Impossible de $action le projet';
  }

  @override
  String get create => 'Créer';

  @override
  String get create_a_project => 'Créer un projet';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      'Créez d\'abord un projet ; les discussions pourront y vivre.';

  @override
  String get create_a_space_to_separate_related_conversations =>
      'Créez un espace pour séparer les discussions liées.';

  @override
  String get create_branch => 'Créer une branche';

  @override
  String get cron => 'Cron';

  @override
  String get cron_jobs => 'Tâches Cron';

  @override
  String get cron_job_added => 'Tâche Cron ajoutée';

  @override
  String get cron_job_updated => 'Tâche Cron mise à jour';

  @override
  String get cron_run => 'Exécution Cron';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      'Ordre entre appareils et organisation en masse réversible';

  @override
  String get current_profile_default => 'Valeur par défaut du profil actuel';

  @override
  String get custom_proxy_and_dashboard_details =>
      'Détails personnalisés du proxy et du tableau de bord';

  @override
  String get dark => 'Sombre';

  @override
  String get dashboard_proxy_settings =>
      'Paramètres du tableau de bord / proxy';

  @override
  String get dashboard_password_optional =>
      'Mot de passe du tableau de bord (facultatif)';

  @override
  String get dashboard_port => 'Port du tableau de bord';

  @override
  String get dashboard_username_optional =>
      'Nom d\'utilisateur du tableau de bord (facultatif)';

  @override
  String get dashboard_behind_proxy => 'Tableau de bord derrière un proxy';

  @override
  String get dashboard_path_prefix => 'Préfixe de chemin du tableau de bord';

  @override
  String delegated_task(Object goal) {
    return 'Tâche déléguée : $goal';
  }

  @override
  String get delete => 'Supprimer';

  @override
  String delete_2(Object name) {
    return 'Supprimer « $name » ?';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return 'Supprimer « $title » de l\'historique Hermes distant ? Cette action est irréversible.';
  }

  @override
  String get delete_cron_job => 'Supprimer la tâche Cron';

  @override
  String get delete_connections_that_are_not_in_the_backup =>
      'Supprimer les connexions absentes de la sauvegarde.';

  @override
  String delete_failed(Object error) {
    return 'Échec de la suppression : $error';
  }

  @override
  String get delete_project => 'Supprimer le projet';

  @override
  String get delete_session => 'Supprimer la session ?';

  @override
  String delete_3(Object projectName) {
    return 'Supprimer $projectName ?';
  }

  @override
  String deleted(Object name) {
    return '« $name » supprimé';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      'La livraison est incertaine ; récupération sans renvoi…';

  @override
  String get desktop_gateway_url_optional =>
      'URL de Desktop Gateway (facultatif)';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      'Desktop Gateway n\'est pas configuré pour cette connexion.';

  @override
  String get desktop_app => 'Application de bureau';

  @override
  String get developer_tool_calls => 'Appels d\'outils du développeur';

  @override
  String get discord_chats => 'Discussions Discord';

  @override
  String get dismiss => 'Ignorer';

  @override
  String get do_not_run_this_command => 'N\'exécutez pas cette commande.';

  @override
  String get documents_archives_audio_video_or_data =>
      'Documents, archives, audio, vidéo ou données';

  @override
  String get download => 'Télécharger';

  @override
  String download_failed(Object error) {
    return 'Échec du téléchargement : $error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you =>
      'Faits durables que Hermes conserve à votre sujet';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      'Travail durable au sein de l\'un de vos projets, partagé avec Desktop.';

  @override
  String get edit => 'Modifier';

  @override
  String get edit_connection => 'Modifier la connexion';

  @override
  String get edit_cron_job => 'Modifier la tâche Cron';

  @override
  String get edit_gateway_connection => 'Modifier la connexion passerelle';

  @override
  String get edit_and_resend => 'Modifier et renvoyer';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      'Active les pièces jointes via la passerelle distante Desktop.';

  @override
  String get enter_a_name => 'Saisissez un nom';

  @override
  String get enter_a_passphrase => 'Saisissez une phrase de passe.';

  @override
  String get enter_the_passphrase_for_this_backup =>
      'Saisissez la phrase de passe de cette sauvegarde.';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      'Chaque discussion est déjà affectée à un projet.';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      'Tout ce qui n\'est pas encore natif, dans le tableau de bord web authentifié';

  @override
  String get explain_the_attached_content_clearly =>
      'Expliquez clairement le contenu joint.';

  @override
  String explain_this_content_clearly(Object text) {
    return 'Expliquez clairement ce contenu :\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      'Les choix explicites ajustent la taille de texte d\'accessibilité Android ; « Système » la laisse inchangée.';

  @override
  String get export_label => 'Exporter';

  @override
  String get export_share => 'Exporter / partager';

  @override
  String get external_api_clients => 'Clients API externes';

  @override
  String get extra_high => 'Très élevé';

  @override
  String get extract_tasks => 'Extraire les tâches';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      'Extrayez du contenu joint les décisions, les échéances, les responsables et les actions concrètes.';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return 'Extrayez de ce contenu les décisions, les échéances, les responsables et les actions concrètes :\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return 'Échec de l\'ajout de la tâche : $error';
  }

  @override
  String get failed_to_load_cron_jobs => 'Échec du chargement des tâches Cron';

  @override
  String get failed_to_load_memory => 'Échec du chargement de la mémoire';

  @override
  String get failed_to_load_messages => 'Échec du chargement des messages';

  @override
  String get failed_to_load_settings => 'Échec du chargement des paramètres';

  @override
  String get failed_to_load_skills => 'Échec du chargement des compétences';

  @override
  String failed_to_update_job(Object error) {
    return 'Échec de la mise à jour de la tâche : $error';
  }

  @override
  String failed(Object error) {
    return 'Échec : $error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      'Fichier joint ; l\'enregistrement au catalogue de documents est en attente.';

  @override
  String get file_reference_added_to_chat =>
      'Référence de fichier ajoutée à la discussion';

  @override
  String get files => 'Fichiers';

  @override
  String get fill_from_document => 'Remplir depuis le document';

  @override
  String get folder_is_empty => 'Le dossier est vide';

  @override
  String get folders => 'Dossiers';

  @override
  String get full_text => 'Texte intégral';

  @override
  String get gateway_api_access => 'Accès à l\'API de la passerelle';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      'Passerelle connectée, mais le tableau de bord est inaccessible ou non authentifié. Vérifiez les détails du tableau de bord, ou effacez-les pour ignorer.';

  @override
  String get gateway_path_prefix => 'Préfixe de chemin de la passerelle';

  @override
  String get go_to_end => 'Aller à la fin';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Hermes Agent pour Android';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'Hermes n\'a pas pu accepter la réponse. Veuillez réessayer.';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      'Hermes n\'a pas pu charger vos connexions enregistrées';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'Hermes n\'a pas accepté la réponse. Veuillez réessayer.';

  @override
  String get hermes_is_responding => 'Hermes répond…';

  @override
  String get hermes_is_waiting_for_input => 'Hermes attend votre saisie…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'Hermes maintient la mise à l\'échelle du texte d\'accessibilité Android active.';

  @override
  String get hermes_needs_your_input => 'Hermes a besoin de votre saisie';

  @override
  String get hermes_profile_optional => 'Profil Hermes (facultatif)';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'Le profil Hermes doit être un simple nom de profil tel que « sol », pas un chemin.';

  @override
  String get hermes_reasoning_details => 'Détails du raisonnement de Hermes';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'La récupération Hermes est indisponible : $error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'Hermes a arrêté la récupération en toute sécurité. Aucun prompt n\'a été renvoyé.';

  @override
  String get hide_passphrase => 'Masquer la phrase de passe';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      'L\'accueil a besoin de vos discussions récentes pour savoir ce qui mérite votre attention. Vérifiez que la passerelle est accessible, puis réessayez.';

  @override
  String get host => 'Hôte';

  @override
  String get image_selection_was_interrupted_try_again =>
      'La sélection d\'image a été interrompue. Réessayez.';

  @override
  String get import_label => 'Importer';

  @override
  String get inbox => 'Boîte de réception';

  @override
  String get inbox_is_clear => 'La boîte de réception est vide';

  @override
  String get insert_a_remote_file_reference =>
      'Insérer une référence @file distante';

  @override
  String get invalid_port_number => 'Numéro de port invalide.';

  @override
  String get job_paused => 'Tâche en pause';

  @override
  String get job_resumed => 'Tâche reprise';

  @override
  String get job_triggered => 'Tâche déclenchée';

  @override
  String get label => 'Libellé';

  @override
  String last_activity(Object day, Object month, Object year) {
    return 'Dernière activité $day/$month/$year';
  }

  @override
  String last(Object lastRun) {
    return 'Dernière : $lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      'Laissez vide pour la valeur par défaut (8642 ; 443 avec https)';

  @override
  String get leave_blank_for_default_9119 =>
      'Laissez vide pour la valeur par défaut (9119)';

  @override
  String get light => 'Clair';

  @override
  String listening(Object elapsed) {
    return 'Écoute • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return 'Écoute, écoulé : $elapsed';
  }

  @override
  String get load_more => 'Charger plus…';

  @override
  String get loading => 'Chargement';

  @override
  String get location => 'Emplacement';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      'Assurez-vous que le serveur API de la passerelle est en cours d\'exécution\n(hermes gateway status)';

  @override
  String matches(Object assigned, Object name) {
    return 'Correspond à $name · $assigned';
  }

  @override
  String get memory => 'Mémoire';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'Les entrées de mémoire sont des faits inter-sessions que l\'agent retient.\nElles se configurent dans ~/.hermes/config.yaml';

  @override
  String get merge => 'Fusionner';

  @override
  String get message => 'Message';

  @override
  String get message_hermes => 'Écrire à Hermes…';

  @override
  String get message_actions => 'Actions du message';

  @override
  String get message_copied => 'Message copié';

  @override
  String get migrating => 'Migration…';

  @override
  String get migration_complete => 'Migration terminée';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      'La migration a échoué. Les espaces locaux n\'ont pas été modifiés.';

  @override
  String get migration_incomplete => 'Migration incomplète';

  @override
  String get migration_preview => 'Aperçu de la migration';

  @override
  String get model => 'Modèle';

  @override
  String get model_and_thinking_for_this_chat =>
      'Modèle et raisonnement pour cette discussion';

  @override
  String model_was_not_changed(Object error) {
    return 'Le modèle n\'a pas été modifié : $error';
  }

  @override
  String get move_attachment_next =>
      'Déplacer la pièce jointe vers la suivante';

  @override
  String get move_attachment_previous =>
      'Déplacer la pièce jointe vers la précédente';

  @override
  String get move_chat => 'Déplacer la discussion';

  @override
  String get move_conversation => 'Déplacer la discussion';

  @override
  String get move_to_project => 'Déplacer vers un projet';

  @override
  String get move_to_space => 'Déplacer vers un espace';

  @override
  String get moved_to_a_project => 'Déplacé vers un projet';

  @override
  String moved_to(Object label) {
    return 'Déplacé vers $label';
  }

  @override
  String get name => 'Nom';

  @override
  String get name_prompt_and_schedule_are_required =>
      'Le nom, le prompt et la planification sont obligatoires';

  @override
  String get nav_activity => 'Activité';

  @override
  String get nav_projects => 'Projets';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Nécessite un contrat de classement tenant compte des corrections dans la passerelle Hermes.';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      'Nécessite un tableau de bord Hermes accessible. Vérifiez l\'hôte, le port et les identifiants de cette connexion.';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Nécessite un index de ressources faisant autorité côté serveur dans la passerelle Hermes.';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Nécessite des contrats d\'ordre d\'épinglage durable, de mutation par lots et d\'annulation dans la passerelle Hermes.';

  @override
  String get needs_you => 'Nécessite votre attention';

  @override
  String get new_label => 'Nouveau';

  @override
  String get new_chat => 'Nouvelle discussion';

  @override
  String get new_chat_2 => 'Nouvelle discussion';

  @override
  String new_chat_3(Object projectName) {
    return 'Nouvelle discussion · $projectName';
  }

  @override
  String get new_project => 'Nouveau projet';

  @override
  String get new_space => 'Nouvel espace';

  @override
  String next(Object nextRun) {
    return 'Prochaine : $nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'Nginx injecte l\'authentification — l\'application envoie des requêtes propres';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      'Aucune voix TTS trouvée.\nInstallez Google Text-to-Speech et téléchargez les données vocales.';

  @override
  String get no_active_projects_on_this_gateway =>
      'Aucun projet actif sur cette passerelle';

  @override
  String get no_activity_yet => 'Aucune activité pour l\'instant';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      'Aucune discussion bloquée, en cours ou en attente de reprise. Lancez-en une nouvelle quand vous voulez.';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return 'Aucune discussion de ce projet ne correspond à « $searchQuery ».';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      'Aucune discussion dans cet espace pour l\'instant. Touchez + pour en lancer une.';

  @override
  String get no_chats_yet => 'Aucune discussion pour l\'instant';

  @override
  String get no_connections => 'Aucune connexion';

  @override
  String get no_conversation_matches_this_view =>
      'Aucune discussion ne correspond à cette vue.';

  @override
  String get no_cron_jobs => 'Aucune tâche Cron';

  @override
  String get no_folders_yet => 'Aucun dossier pour l\'instant';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      'Aucun espace local n\'a été trouvé pour cette connexion ; les projets sont donc déjà la seule organisation utilisée ici.';

  @override
  String get no_matches => 'Aucune correspondance';

  @override
  String get no_memory_entries => 'Aucune entrée de mémoire';

  @override
  String get no_message_content_matches =>
      'Aucune correspondance dans le contenu des messages';

  @override
  String get no_new_messages => 'Aucun nouveau message';

  @override
  String get no_projects_yet => 'Aucun projet pour l\'instant';

  @override
  String get no_runs_yet => 'Aucune exécution pour l\'instant.';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return 'Aucun projet serveur ne correspond à ce nom · $assigned';
  }

  @override
  String get no_sessions_yet => 'Aucune session pour l\'instant';

  @override
  String get no_skills_found => 'Aucune compétence trouvée';

  @override
  String get no_spaces_on_this_device => 'Aucun espace sur cet appareil';

  @override
  String get no_text_shared => 'Aucun texte partagé';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      'Aucun tour bloqué, en cours ou récemment terminé. Le travail que vous lancez apparaîtra ici.';

  @override
  String get no_turn_needs_your_input_or_has_failed =>
      'Aucun tour n\'attend votre saisie ni n\'a échoué.';

  @override
  String get no_unassigned_chats => 'Aucune discussion non affectée.';

  @override
  String get nothing_changed_in_the_last_seven_days =>
      'Rien n\'a changé ces sept derniers jours.';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      'Rien n\'a encore été déplacé — ceci n\'est que ce que ferait une migration.';

  @override
  String get nothing_here => 'Rien ici';

  @override
  String get nothing_is_running => 'Rien en cours d\'exécution';

  @override
  String get nothing_needs_you => 'Rien ne nécessite votre attention';

  @override
  String get nothing_to_migrate => 'Rien à migrer';

  @override
  String get off_no_thinking => 'Désactivé (sans raisonnement)';

  @override
  String get offline_showing_the_last_known_activity =>
      'Hors ligne — affichage de la dernière activité connue.';

  @override
  String get offline_showing_the_last_known_chats =>
      'Hors ligne — affichage des dernières discussions connues';

  @override
  String get offline_showing_the_last_known_projects =>
      'Hors ligne — affichage des derniers projets connus.';

  @override
  String get on_this_device => 'Sur cet appareil';

  @override
  String get on_device => 'Sur l\'appareil';

  @override
  String get open_inbox => 'Ouvrir la boîte de réception';

  @override
  String open_inbox_2(Object count) {
    return 'Ouvrir la boîte de réception ($count)';
  }

  @override
  String get open_the_hermes_dashboard => 'Ouvrir le tableau de bord Hermes';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      'Facultatif. Pour les onglets Mémoire/Cron/Compétences/Paramètres. Laissez vide pour utiliser le port par défaut du tableau de bord (9119) sans connexion.';

  @override
  String get organization => 'Organisation';

  @override
  String get other_answer => 'Autre réponse';

  @override
  String get overview => 'Vue d\'ensemble';

  @override
  String get passphrase => 'Phrase de passe';

  @override
  String get password_optional => 'Mot de passe (facultatif)';

  @override
  String get phone_or_tablet => 'Téléphone ou tablette';

  @override
  String get pin_batch_and_undo => 'Épingler, par lots et annuler';

  @override
  String get port => 'Port';

  @override
  String get preparing_attachments => 'Préparation des pièces jointes…';

  @override
  String get preview_truncated => 'Aperçu tronqué';

  @override
  String get preview_unavailable => 'Aperçu indisponible';

  @override
  String get profile => 'Profil';

  @override
  String get profile_default_model => 'Modèle par défaut du profil';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return 'Valeur par défaut du profil définie sur $selectedModel. Les discussions avec leur propre modèle conservent ce remplacement.';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      'Profil avec lequel cette connexion discute lorsque le tableau de bord sert plusieurs profils. Laissez vide pour un tableau de bord isolé par profil.';

  @override
  String get project => 'Projet';

  @override
  String get project_actions => 'Actions du projet';

  @override
  String get project_chat => 'Discussion de projet';

  @override
  String get project_chats_unavailable => 'Discussions de projet indisponibles';

  @override
  String get projects => 'Projets';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      'Les projets regroupent les discussions, fichiers et activités liés, et restent synchronisés avec Hermes sur votre ordinateur.';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      'Les projets nécessitent une connexion Desktop Gateway. Ajoutez l\'URL de Desktop Gateway à cette connexion pour organiser les discussions sur tous vos appareils.';

  @override
  String get projects_unavailable => 'Projets indisponibles';

  @override
  String get projects_activity_new_navigation =>
      'Projets, Activité — nouvelle navigation';

  @override
  String get promote_to_project => 'Promouvoir en projet';

  @override
  String get prompt => 'Prompt';

  @override
  String get protect_this_backup => 'Protéger cette sauvegarde';

  @override
  String get provider => 'Fournisseur';

  @override
  String get proxy_injects_auth_app_sends_clean_requests =>
      'Le proxy injecte l\'authentification ; l\'application envoie des requêtes propres';

  @override
  String get quick_chat => 'Discussion rapide';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      'Les discussions rapides apparaissent ici après leur période de conservation.';

  @override
  String get read_aloud => 'Lire à voix haute';

  @override
  String get read_aloud_is_unavailable_on_this_device =>
      'La lecture à voix haute est indisponible sur cet appareil';

  @override
  String get reading_response_aloud => 'Lecture de la réponse à voix haute';

  @override
  String get ready_to_upload => 'Prêt à envoyer';

  @override
  String get reasoning => 'Raisonnement';

  @override
  String get recently_completed => 'Terminé récemment';

  @override
  String get recovering_hermes => 'Récupération de Hermes…';

  @override
  String get refresh => 'Actualiser';

  @override
  String get regenerate_response => 'Régénérer la réponse';

  @override
  String get remove_attachment => 'Retirer la pièce jointe';

  @override
  String get rename => 'Renommer';

  @override
  String get rename_chat => 'Renommer la discussion';

  @override
  String get rename_project => 'Renommer le projet';

  @override
  String get rename_space => 'Renommer l\'espace';

  @override
  String rename_2(Object projectName) {
    return 'Renommer $projectName';
  }

  @override
  String rename_3(Object name) {
    return 'Renommer $name';
  }

  @override
  String get replace => 'Remplacer';

  @override
  String get repositories => 'Dépôts';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      'Analysez le contenu joint, vérifiez les affirmations importantes et citez vos sources.';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return 'Analysez ce contenu, vérifiez les affirmations importantes et citez vos sources :\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return 'Échec de la réinitialisation : $retryError. Le stockage sécurisé devra peut-être être réinstallé.';
  }

  @override
  String get reset_saved_connections =>
      'Réinitialiser les connexions enregistrées';

  @override
  String get responding => 'Réponse en cours…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return 'Réponse fermée localement ; échec de l\'arrêt de la passerelle : $error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      'Réponse fermée localement ; aucun tour de passerelle actif trouvé.';

  @override
  String get response_ready => 'Réponse prête';

  @override
  String get response_stopped => 'Réponse arrêtée.';

  @override
  String get restore => 'Restaurer';

  @override
  String get restore_configuration => 'Restaurer la configuration';

  @override
  String get restore_project => 'Restaurer le projet';

  @override
  String get retry => 'Réessayer';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return 'Échec de la nouvelle tentative pour $name. Le brouillon et le prompt ont été conservés.';
  }

  @override
  String get retry_upload => 'Réessayer l\'envoi';

  @override
  String retrying(Object name) {
    return 'Nouvelle tentative pour $name…';
  }

  @override
  String get review_local_spaces => 'Examiner les espaces locaux';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      'Examiner ou promouvoir les discussions rapides au-delà de leur période de conservation';

  @override
  String get review_the_attached_content => 'Examinez le contenu joint.';

  @override
  String get run_only_this_command => 'N\'exécutez que cette commande.';

  @override
  String get running_now => 'En cours d\'exécution';

  @override
  String get save => 'Enregistrer';

  @override
  String get save_changes => 'Enregistrer les modifications';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      'Enregistrez une règle permanente dans la configuration Hermes.';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      'Enregistrez les faits durables du contenu joint en mémoire, puis confirmez ce qui a été conservé.';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return 'Enregistrez les faits durables de ce contenu en mémoire, puis confirmez ce qui a été conservé :\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      'Enregistrez vos connexions et paramètres dans un fichier chiffré, puis restaurez-les après une réinstallation ou sur un autre appareil.';

  @override
  String save_2(Object filename) {
    return 'Enregistrer $filename';
  }

  @override
  String get schedule => 'Planification';

  @override
  String get scheduled_jobs_and_their_last_runs =>
      'Tâches planifiées et leurs dernières exécutions';

  @override
  String get scheduled_tasks => 'Tâches planifiées';

  @override
  String get script_only_no_agent => 'Script uniquement (sans agent)';

  @override
  String get scroll_horizontally => 'Défiler horizontalement';

  @override
  String get search_all_chats => 'Rechercher dans toutes les discussions';

  @override
  String get search_all_message_content =>
      'Rechercher dans tout le contenu des messages';

  @override
  String get search_chats => 'Rechercher des discussions';

  @override
  String get search_conversations => 'Rechercher des discussions';

  @override
  String get search_loaded_chats => 'Rechercher dans les discussions chargées';

  @override
  String get search_mode => 'Mode de recherche';

  @override
  String get select_one_option_or_enter_another_answer =>
      'Sélectionnez une option ou saisissez une autre réponse.';

  @override
  String get select_one_or_more_options_then_continue =>
      'Sélectionnez une ou plusieurs options, puis continuez.';

  @override
  String get select_text => 'Sélectionner le texte';

  @override
  String get send => 'Envoyer';

  @override
  String send_failed(Object error) {
    return 'Échec de l\'envoi : $error';
  }

  @override
  String get send_message => 'Envoyer le message';

  @override
  String get session_sources => 'Sources des sessions';

  @override
  String get session_deleted_from_remote_hermes =>
      'Session supprimée du Hermes distant.';

  @override
  String session_search_failed(Object error) {
    return 'Échec de la recherche de sessions : $error';
  }

  @override
  String get set_profile_default => 'Définir par défaut du profil';

  @override
  String get settings => 'Paramètres';

  @override
  String get share_to_hermes => 'Partager avec Hermes';

  @override
  String get show_passphrase => 'Afficher la phrase de passe';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      'Afficher les appels d\'outils, le raisonnement et les métadonnées des messages';

  @override
  String get signal_messages => 'Messages Signal';

  @override
  String get skills => 'Compétences';

  @override
  String skills_2(Object count) {
    return 'Compétences ($count)';
  }

  @override
  String get skills_and_tools => 'Compétences et outils';

  @override
  String get skip => 'Ignorer';

  @override
  String get slack_chats => 'Discussions Slack';

  @override
  String source(Object source) {
    return 'Source : $source';
  }

  @override
  String get space_actions => 'Actions de l\'espace';

  @override
  String get spaces => 'Espaces';

  @override
  String get speak_to_hermes => 'Parler à Hermes';

  @override
  String get speech_recognition_is_unavailable =>
      'La reconnaissance vocale est indisponible';

  @override
  String get spoken_replies => 'Réponses vocales';

  @override
  String get spoken_replies_off => 'Réponses vocales désactivées';

  @override
  String get spoken_replies_on => 'Réponses vocales activées';

  @override
  String get stalled_no_update_from_hermes =>
      'Bloqué — aucune mise à jour de Hermes';

  @override
  String get start_something_new => 'Lancer quelque chose de nouveau';

  @override
  String get start_voice_input => 'Démarrer la saisie vocale';

  @override
  String get starting_hermes => 'Démarrage de Hermes…';

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
      'Chargement de vos projets en cours.';

  @override
  String get stop => 'Arrêter';

  @override
  String get stop_response => 'Arrêter la réponse';

  @override
  String get stop_voice_input => 'Arrêter la saisie vocale';

  @override
  String get submitted_waiting_for_hermes => 'Envoyé, en attente de Hermes';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      'Suggérer des projets et apprendre de vos corrections';

  @override
  String get summarize_the_attached_content => 'Résumez le contenu joint.';

  @override
  String summarize_this_content(Object text) {
    return 'Résumez ce contenu :\n\n$text';
  }

  @override
  String get switch_profile => 'Changer de profil';

  @override
  String get system => 'Système';

  @override
  String get take_photo => 'Prendre une photo';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      'Touchez + pour ajouter une passerelle Hermes distante\n(serveur API, port 8642)';

  @override
  String get tap_the_button_to_start_a_new_chat =>
      'Touchez le bouton + pour démarrer une nouvelle discussion';

  @override
  String get telegram_messages => 'Messages Telegram';

  @override
  String get terminal_sessions => 'Sessions de terminal';

  @override
  String get text_size => 'Taille du texte';

  @override
  String get text_size_preview => 'Aperçu de la taille du texte';

  @override
  String text_size_2(Object label) {
    return 'Taille du texte : $label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely =>
      'La clé API n\'a pas pu être stockée en toute sécurité.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      'Le projet passera dans « Archivé ». Ses discussions et fichiers restent intacts, et vous pourrez le restaurer à tout moment.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      'Le projet passera dans « Archivé ». Ses discussions et fichiers restent intacts, et vous pourrez le restaurer plus tard.';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      'Le profil actif n\'a renvoyé aucun modèle sélectionnable.';

  @override
  String get the_backup_could_not_be_exported =>
      'La sauvegarde n\'a pas pu être exportée.';

  @override
  String get the_backup_could_not_be_restored =>
      'La sauvegarde n\'a pas pu être restaurée.';

  @override
  String get the_connection_could_not_be_deleted_safely =>
      'La connexion n\'a pas pu être supprimée en toute sécurité.';

  @override
  String get the_connection_could_not_be_stored_securely =>
      'La connexion n\'a pas pu être stockée en toute sécurité.';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      'Les identifiants du tableau de bord n\'ont pas pu être stockés en toute sécurité.';

  @override
  String get the_detached_reply_failed => 'La réponse détachée a échoué.';

  @override
  String the_detached_reply_failed_2(Object error) {
    return 'La réponse détachée a échoué : $error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      'Le fichier contient vos clés API et le mot de passe du tableau de bord ; il est donc chiffré. Sans cette phrase de passe, la sauvegarde ne peut pas être restaurée.';

  @override
  String get the_last_turn_failed => 'Le dernier tour a échoué';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return 'Le stockage local des connexions semble endommagé ($errorType). Vous pouvez réinitialiser les connexions enregistrées et repartir de zéro. Les discussions de votre passerelle ne sont pas affectées.';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      'Le modèle ne fait que reformuler votre question en une courte requête de texte intégral. Hermes utilise les identifiants du fournisseur déjà configurés sur l\'hôte.';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      'Le serveur n\'a pas encore signalé de dossiers pour ce projet. Fichiers globaux reste disponible depuis Plus.';

  @override
  String get the_turn_failed => 'Le tour a échoué';

  @override
  String get the_two_passphrases_do_not_match =>
      'Les deux phrases de passe ne correspondent pas.';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      'La valeur est envoyée directement à la passerelle Hermes active et n\'est pas enregistrée par cette application Android.';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      'Aucun fichier visible dans ce dossier du serveur.';

  @override
  String get thinking_effort => 'Effort de raisonnement';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      'Cette passerelle Hermes ne prend pas encore en charge l\'ouverture d\'un projet. Mettez à jour Hermes sur le serveur pour parcourir un projet depuis votre téléphone.';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      'Cette passerelle Hermes est antérieure aux projets côté serveur ; les discussions ne sont donc regroupées que sur cet appareil. Mettez à jour Hermes pour partager les mêmes projets entre vos appareils.';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      'Ce projet n\'a pas de dossier dans lequel ouvrir la discussion — elle s\'est ouverte sans affectation. Ajoutez un dossier au projet pour regrouper ses discussions.';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      'Cette discussion n\'a pas encore de messages disponibles dans la session Desktop.';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      'Cela crée une règle permanente dans Hermes. Examinez la commande complète avant de confirmer.';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      'Cette passerelle n\'héberge pas encore de projets. Mettez à jour la passerelle pour organiser les discussions sur tous vos appareils.';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      'Cela supprime définitivement le projet. Les discussions ne seront pas supprimées ; elles reviendront dans « Non affecté ».';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      'Ce serveur n\'offre pas de récupération en arrière-plan — les discussions s\'exécutent en direct';

  @override
  String get this_week => 'Cette semaine';

  @override
  String get titles_previews_and_models => 'Titres, aperçus et modèles';

  @override
  String get tool_activity => 'Activité des outils';

  @override
  String get trigger_now => 'Déclencher maintenant';

  @override
  String get turn_completed => 'Tour terminé';

  @override
  String get turn_recovery_failed => 'Échec de la récupération du tour';

  @override
  String get unable_to_prepare_this_file_try_another_one =>
      'Impossible de préparer ce fichier. Essayez-en un autre.';

  @override
  String get unable_to_prepare_this_image_try_another_one =>
      'Impossible de préparer cette image. Essayez-en une autre.';

  @override
  String unable_to_prepare(Object name) {
    return 'Impossible de préparer $name.';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      'Impossible de lire l\'image sélectionnée. La sélection a été conservée.';

  @override
  String get unassigned => 'Non affecté';

  @override
  String get unassigned_chats => 'Discussions non affectées';

  @override
  String get untitled_chat => 'Discussion sans titre';

  @override
  String get untitled_session => 'Session sans titre';

  @override
  String get update_api_key => 'Mettre à jour la clé API';

  @override
  String get upload_failed => 'Échec de l\'envoi';

  @override
  String get upload_failed_tap_retry =>
      'Échec de l\'envoi • touchez pour réessayer';

  @override
  String uploading(Object index, Object name, Object total) {
    return 'Envoi de $index/$total : $name';
  }

  @override
  String get use_as_is => 'Utiliser tel quel';

  @override
  String get use_at_least_8_characters => 'Utilisez au moins 8 caractères.';

  @override
  String get use_for_cron_jobs_backed_by_scripts =>
      'À utiliser pour les tâches Cron basées sur des scripts.';

  @override
  String get use_on_device => 'Utiliser sur l\'appareil';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      'Utilisez le contenu joint pour identifier et remplir les champs pertinents du document ou du formulaire. Demandez avant d\'envoyer quoi que ce soit.';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return 'Utilisez ce contenu pour identifier et remplir les champs pertinents du document ou du formulaire. Demandez avant d\'envoyer quoi que ce soit :\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      'Utilisé pour les préfixes de chemins hébergés et pour les onglets Paramètres, Mémoire, Compétences et Cron. Laissez le nom d\'utilisateur et le mot de passe vides pour un tableau de bord ouvert, ou activez le mode proxy lorsque votre reverse proxy injecte l\'authentification du tableau de bord.';

  @override
  String get username_optional => 'Nom d\'utilisateur (facultatif)';

  @override
  String using(Object displayName) {
    return 'Utilisation de $displayName…';
  }

  @override
  String get verbose_mode => 'Mode détaillé';

  @override
  String get voice => 'Voix';

  @override
  String voice_setup_failed(Object error) {
    return 'Échec de la configuration vocale : $error';
  }

  @override
  String get waiting_for_your_input => 'En attente de votre saisie';

  @override
  String get what_hermes_knows_how_to_do => 'Ce que Hermes sait faire';

  @override
  String get what_should_the_agent_do => 'Que doit faire l\'agent ?';

  @override
  String get whatsapp_messages => 'Messages WhatsApp';

  @override
  String get which_project => 'Quel projet ?';

  @override
  String get workspace => 'Espace de travail';

  @override
  String get wrap_lines => 'Renvoi à la ligne';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return 'Vous pouvez joindre jusqu\'à $maxRemoteAttachmentDrafts éléments.';
  }

  @override
  String get your_answer => 'Votre réponse';

  @override
  String get e_g_dashboard => 'p. ex. /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      'p. ex. /dashboard (chemin proxy avant /api/)';

  @override
  String get e_g_profile_peter => 'p. ex. /profile/peter';

  @override
  String get e_g_sol => 'p. ex. sol';

  @override
  String get e_g_0_9_or_every_2h => 'p. ex. 0 9 * * * ou every 2h';

  @override
  String get e_g_daily_backup => 'p. ex. Sauvegarde quotidienne';

  @override
  String downloaded(Object filename) {
    return '$filename téléchargé';
  }

  @override
  String activity_name_status(Object displayName, Object statusLabel) {
    return '$displayName : $statusLabel';
  }

  @override
  String connection_status_label(Object connectionLabel, Object label) {
    return '$connectionLabel $label';
  }

  @override
  String get example_host_hint =>
      '192.168.1.50, 100.x.y.z ou hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      'p. ex. /profile/peter (chemin proxy avant /api/ et /v1/)';

  @override
  String and_more(Object count) {
    return 'et $count de plus';
  }

  @override
  String chats_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count discussions',
      one: '$count discussion',
    );
    return '$_temp0';
  }

  @override
  String on_this_device_only(Object chats) {
    return '$chats · sur cet appareil uniquement';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count espaces',
      one: '$count espace',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => 'aucun nouveau projet nécessaire';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projets à créer',
      one: '$count projet à créer',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return '$linkedSessions discussions migrées · $createdProjects projets créés';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '$unlinkedSessions discussions sont restées dans les espaces locaux et peuvent être réessayées sans risque.';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • Recommandé : petit et économique';
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
  String get this_chat => 'cette discussion';

  @override
  String get profile_default => 'par défaut du profil';

  @override
  String minutes_ago(Object count) {
    return 'il y a $count min';
  }

  @override
  String hours_ago(Object count) {
    return 'il y a $count h';
  }

  @override
  String days_ago(Object count) {
    return 'il y a $count j';
  }

  @override
  String get now_label => 'maintenant';

  @override
  String get latest_label => 'Dernier';

  @override
  String new_count_indicator(Object count) {
    return '$count nouveaux';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouveaux messages',
      one: '$count nouveau message',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return '$failures échoués • $total au total';
  }

  @override
  String activity_completed_summary(Object count) {
    return '$count terminés';
  }

  @override
  String get hermes_is_using_a_tool => 'Hermes utilise un outil';

  @override
  String hermes_is_using_tools(Object count) {
    return 'Hermes utilise $count outils';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return '$count tâche(s) déléguée(s) terminée(s)';
  }

  @override
  String delegated_tasks_active(Object count) {
    return '$count tâche(s) déléguée(s) active(s)';
  }

  @override
  String branch_main(Object label) {
    return '$label · main';
  }

  @override
  String get you_heading => '## Vous';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => 'Action';

  @override
  String get destination_label => 'Destination';

  @override
  String get preview_label => 'Aperçu';

  @override
  String get share_action_summarize => 'Résumer';

  @override
  String get share_action_explain => 'Expliquer';

  @override
  String get share_action_research => 'Rechercher';

  @override
  String get share_action_remember => 'Mémoriser';

  @override
  String get text_size_small => 'Petit';

  @override
  String get text_size_default => 'Par défaut';

  @override
  String get text_size_large => 'Grand';

  @override
  String get text_size_extra_large => 'Très grand';

  @override
  String get text_size_use_system_description =>
      'Utiliser exactement la taille de texte d\'accessibilité Android.';

  @override
  String text_size_percent_description(Object percent) {
    return '$percent % de la taille de texte Android.';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return '$count fichier(s) ignoré(s) : limite, taille, illisible ou nom de fichier sensible.';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort ne s\'appliquent désormais qu\'à cette discussion.';
  }

  @override
  String get reasoning_minimal => 'Minimal';

  @override
  String get reasoning_low => 'Faible';

  @override
  String get reasoning_medium => 'Moyen';

  @override
  String get reasoning_high => 'Élevé';

  @override
  String get reasoning_max => 'Maximal';

  @override
  String get reasoning_ultra => 'Ultra';

  @override
  String get status_running => 'En cours';

  @override
  String get status_failed => 'Échec';

  @override
  String get status_done => 'Terminé';

  @override
  String get status_idle => 'Inactif';

  @override
  String get upload_status_uploading => 'Envoi en cours';

  @override
  String get upload_status_uploaded => 'Envoyé';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pièces jointes',
      one: '$count pièce jointe',
    );
    return '$_temp0';
  }

  @override
  String get action_create => 'créer';

  @override
  String get action_rename => 'renommer';

  @override
  String get action_archive => 'archiver';

  @override
  String get action_restore => 'restaurer';

  @override
  String get action_delete => 'supprimer';

  @override
  String get migrate => 'Migrer';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count discussions affectées',
      one: '$count discussion affectée',
    );
    return '$_temp0';
  }

  @override
  String get date_today => 'Aujourd\'hui';

  @override
  String get date_yesterday => 'Hier';

  @override
  String get date_earlier => 'Plus tôt';

  @override
  String get nav_home => 'Accueil';

  @override
  String get nav_more => 'Plus';

  @override
  String get status_completed => 'Terminé';

  @override
  String get filter_all => 'Tout';

  @override
  String get filter_recent => 'Récent';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  Clé : $status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model  \nvia `$provider`';
  }

  @override
  String get deny => 'Refuser';

  @override
  String get connect => 'Se connecter';

  @override
  String get appearance => 'Apparence';

  @override
  String get connection_section => 'Connexion';

  @override
  String get about => 'À propos';

  @override
  String version_label(Object version) {
    return 'Version $version';
  }

  @override
  String get matched => 'Correspondance';

  @override
  String get search => 'Rechercher';

  @override
  String get on => 'Activé';

  @override
  String get off => 'Désactivé';

  @override
  String get reasoning_off => 'Désactivé';

  @override
  String get hermes_response_ready => 'Réponse de Hermes prête';

  @override
  String get admin_password_needed => 'Mot de passe administrateur requis';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      'Hermes a besoin d\'un mot de passe sudo pour la commande de terminal en attente.';

  @override
  String get sudo_password => 'Mot de passe sudo';

  @override
  String get secret_needed => 'Secret requis';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      'Hermes a besoin d\'un secret pour la compétence en attente.';

  @override
  String get secret_value => 'Valeur du secret';

  @override
  String get attached_file => 'Fichier joint';
}
