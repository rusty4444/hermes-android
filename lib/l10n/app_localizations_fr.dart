// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get fallback_title => 'Modèles de secours';

  @override
  String get fallback_notice =>
      'Essayés dans cet ordre si le modèle principal est indisponible. Les modifications concernent uniquement ce profil ; enregistrez explicitement la liste complète.';

  @override
  String get fallback_unavailable =>
      'La configuration de secours est indisponible ou invalide. Vérifiez la connexion, le profil sélectionné et la version de l’hôte, puis réessayez.';

  @override
  String get fallback_discovery_unavailable =>
      'La liste des fournisseurs est indisponible. Les entrées existantes sont conservées ; réessayez pour choisir fournisseurs et modèles.';

  @override
  String get fallback_empty => 'Aucune entrée dans cette liste de secours.';

  @override
  String get fallback_incomplete =>
      'Choisissez un fournisseur et un modèle pour chaque entrée, ou supprimez les entrées incomplètes avant d’enregistrer.';

  @override
  String get fallback_add => 'Ajouter un secours';

  @override
  String get fallback_save => 'Enregistrer la liste de secours';

  @override
  String get fallback_save_failed =>
      'Impossible de vérifier la liste enregistrée. Votre brouillon est conservé. Réessayez d’enregistrer ou actualisez les paramètres de l’hôte.';

  @override
  String get fallback_saved => 'Liste de secours enregistrée et vérifiée.';

  @override
  String get fallback_legacy_title => 'Anciens secours (lecture seule)';

  @override
  String get fallback_legacy_notice =>
      'L’hôte utilise aussi fallback_model après cette liste, en ignorant les routes en double. Ces anciennes entrées sont conservées même si la liste ci-dessus est vide. Modifiez-les sur l’hôte.';

  @override
  String fallback_priority(String position) {
    return 'Priorité $position';
  }

  @override
  String get fallback_move_up => 'Monter';

  @override
  String get fallback_move_down => 'Descendre';

  @override
  String get fallback_routing_read_only =>
      'Les détails de routage ou un fournisseur non répertorié sont conservés. Modifiez ce fournisseur/modèle sur l’hôte ; vous pouvez toujours déplacer ou supprimer l’entrée ici.';

  @override
  String get cron_model_default => 'Suivre le réglage par défaut';

  @override
  String get cron_model_notice =>
      'S’applique uniquement à cette tâche cron. Sans modèle fixé, Hermes utilise le modèle cron par défaut, puis le modèle principal. Gérez les modèles personnalisés sur l’hôte.';

  @override
  String get model_management_unavailable =>
      'Impossible de charger ou d’enregistrer les paramètres du modèle. Actualisez et réessayez.';

  @override
  String get model_management_subtitle =>
      'Modèles principal, de secours et auxiliaires de ce profil';

  @override
  String get usage => 'Utilisation';

  @override
  String get nous_portal => 'Nous Portal';

  @override
  String get portal_menu_subtitle =>
      'État de la passerelle et utilisation enregistrée';

  @override
  String get portal_read_only =>
      'Données en lecture seule de la passerelle. Gérez l’authentification Nous sur l’hôte Hermes. Ces points d’accès ne fournissent ni solde d’abonnement ni crédits.';

  @override
  String get portal_status => 'État du Portal sur la passerelle';

  @override
  String get portal_free_tier => 'Accès gratuit (sans compte connecté)';

  @override
  String get portal_signed_in => 'Connecté';

  @override
  String get portal_signed_out => 'Non connecté';

  @override
  String get portal_account_tier => 'Niveau du compte';

  @override
  String get portal_recorded_usage => 'Utilisation enregistrée';

  @override
  String get portal_all_providers =>
      'Tous les fournisseurs du profil de passerelle sélectionné. Un coût enregistré nul ne signifie pas que le modèle est gratuit.';

  @override
  String portal_period(String days) {
    return '$days derniers jours';
  }

  @override
  String get portal_sessions => 'Sessions';

  @override
  String get portal_input => 'Tokens d’entrée';

  @override
  String get portal_output => 'Tokens de sortie';

  @override
  String get portal_estimated => 'Coût estimé enregistré';

  @override
  String get portal_actual => 'Coût réel enregistré';

  @override
  String get portal_recorded_models => 'Modèles enregistrés';

  @override
  String get portal_no_models => 'Aucun modèle enregistré.';

  @override
  String get portal_unavailable =>
      'Indisponible. Vérifiez la connexion, le profil sélectionné et la version de la passerelle, puis réessayez.';

  @override
  String get paste_attachment_failed_text_kept =>
      'Impossible de joindre le texte collé. Il a été conservé dans le message.';

  @override
  String get background_task_report => 'Tâche en arrière-plan';

  @override
  String get background_process_report => 'Processus en arrière-plan';

  @override
  String get background_report_issues =>
      'Des problèmes ont été signalés — développez pour les détails.';

  @override
  String get background_report_expand => 'Développer le rapport';

  @override
  String get background_report_collapse => 'Réduire le rapport';

  @override
  String get hands_free_title => 'Mains libres';

  @override
  String get hands_free_start => 'Démarrer mains libres';

  @override
  String get hands_free_stop => 'Arrêter mains libres';

  @override
  String get hands_free_preparing => 'Préparation vocale — patientez';

  @override
  String get hands_free_listening => 'Dites Hey Hermes';

  @override
  String get hands_free_recording => 'Prêt — parlez maintenant';

  @override
  String get hands_free_waiting => 'En attente de Hermes';

  @override
  String get hands_free_speaking => 'Lecture — microphone coupé';

  @override
  String hands_free_followup(int seconds) {
    return 'Écouter jusqu’à $seconds secondes';
  }

  @override
  String get hands_free_error => 'Mains libres arrêté';

  @override
  String get hands_free_setup => 'Configurer mains libres';

  @override
  String hands_free_preview(String transcript) {
    return 'Aperçu vocal : $transcript';
  }

  @override
  String get hands_free_short_disclosure =>
      'Uniquement avec ce chat ouvert au premier plan. Activation hors ligne ; la voix peut utiliser le réseau. Consomme la batterie.';

  @override
  String get hands_free_error_action =>
      'Vérifiez le microphone, le service vocal, la voix et la connexion, puis Arrêter et Démarrer. Aucun renvoi automatique.';

  @override
  String get hands_free_disclosure =>
      'La détection fonctionne hors ligne sur le processeur. La reconnaissance Android, la voix choisie et la passerelle peuvent utiliser des réseaux. L’écoute consomme la batterie et peut se déclencher à tort. Elle s’arrête si le chat est couvert, fermé ou quitte le premier plan, sans reprise automatique. La dictée manuelle reste un brouillon modifiable.';

  @override
  String get hands_free_ready_cue =>
      'Dites « Hey Hermes », attendez « Prêt », puis parlez. Pas de capture d’un seul souffle ni d’audio préalable. Après une autorisation qui quitte l’app, appuyez à nouveau sur Démarrer.';

  @override
  String get hands_free_settings_title => 'Voix mains libres';

  @override
  String get hands_free_settings_subtitle =>
      'Affiche la commande de démarrage « Hey Hermes » dans les discussions. La désactiver arrête toute session mains libres en cours.';

  @override
  String get hands_free_timing_limit =>
      'La fenêtre de suivi est une durée maximale, non minimale. Android peut s’arrêter plus tôt. Le silence ramène à l’activation locale sans redémarrages répétés de reconnaissance.';

  @override
  String get hands_free_followup_off =>
      'Suivi désactivé — dites Hey Hermes pour chaque message';

  @override
  String get hands_free_start_blocked =>
      'Brouillon vide, aucun fichier joint, chat connecté au repos et réponses vocales activées requis. Terminez d’abord les actions vocales manuelles.';

  @override
  String get hands_free_setup_complete =>
      'Configuration du microphone terminée. Appuyez à nouveau sur Démarrer.';

  @override
  String message_time_recorded(String time) {
    return 'Recorded by server: $time (local time)';
  }

  @override
  String message_time_sent(String time) {
    return 'Send observed on this device: $time (local time)';
  }

  @override
  String message_time_received(String time) {
    return 'First received on this device: $time (local time)';
  }

  @override
  String get stop_and_send => 'Arrêter et envoyer';

  @override
  String get message_queued_for_running_turn =>
      'Message mis en attente pour l’exécution en cours.';

  @override
  String get running_message_not_accepted =>
      'Hermes n’a pas pu accepter ce message. Votre brouillon est conservé ; arrêtez la réponse ou attendez, puis renvoyez-le.';

  @override
  String get running_message_delivery_unknown =>
      'L’envoi n’a pas pu être confirmé. Votre brouillon est conservé. Vérifiez la conversation avant de réessayer.';

  @override
  String get attachment_tap_to_preview => 'Appuyer pour afficher un aperçu';

  @override
  String get attachment_save => 'Enregistrer';

  @override
  String get attachment_share => 'Partager';

  @override
  String get attachment_saved => 'Fichier enregistré';

  @override
  String get attachment_save_cancelled => 'Enregistrement annulé';

  @override
  String get attachment_save_failed =>
      'Impossible d’enregistrer ce fichier. Veuillez réessayer.';

  @override
  String get attachment_share_failed =>
      'Impossible de partager ce fichier. Veuillez réessayer.';

  @override
  String get attachment_download_failed =>
      'Impossible de charger ce fichier. Vérifiez la connexion et réessayez.';

  @override
  String get attachment_no_inline_preview =>
      'Aucun aperçu n’est disponible pour ce type de fichier. Enregistrez ou partagez le fichier original pour l’ouvrir dans une autre application.';

  @override
  String get attachment_image_failed =>
      'Impossible de décoder cette image. Vous pouvez toujours enregistrer ou partager le fichier original.';

  @override
  String get attachment_text_truncated =>
      'Aperçu raccourci. Enregistrez ou partagez le fichier pour le lire en entier.';

  @override
  String get attachment_text_unavailable =>
      'Impossible d’afficher ce fichier sous forme de texte. Enregistrez ou partagez le fichier original.';

  @override
  String get attachment_pdf_failed =>
      'Impossible d’afficher un aperçu de ce PDF. Enregistrez ou partagez le fichier original.';

  @override
  String get attachment_pdf_unavailable =>
      'Les aperçus PDF sont disponibles sur Android. Vous pouvez toujours enregistrer ou partager ce fichier.';

  @override
  String attachment_pdf_page(int page, int total) {
    return 'Page $page sur $total';
  }

  @override
  String get attachment_previous_page => 'Page précédente';

  @override
  String get attachment_next_page => 'Page suivante';

  @override
  String get attachment_loading => 'Chargement de l’aperçu…';

  @override
  String get attachment_document_text_notice =>
      'Aperçu du texte. La mise en page, les images et la mise en forme peuvent différer de l’original.';

  @override
  String get attachment_document_failed =>
      'Impossible d’afficher un aperçu de ce document. Enregistrez ou partagez le fichier original.';

  @override
  String get attachment_document_empty =>
      'Aucun texte lisible n’a été trouvé dans ce document.';

  @override
  String get attachment_video_failed =>
      'Impossible de lire cette vidéo. Son format ou son codec n’est peut-être pas pris en charge. Enregistrez ou partagez le fichier original.';

  @override
  String get attachment_video_play => 'Lire';

  @override
  String get attachment_video_pause => 'Pause';

  @override
  String get attachment_video_mute => 'Couper le son';

  @override
  String get attachment_video_unmute => 'Activer le son';

  @override
  String get attachment_video_seek => 'Position de la vidéo';

  @override
  String get attachment_close => 'Fermer l’aperçu';

  @override
  String get attachment_retry => 'Réessayer';

  @override
  String get saved_history_heading => 'Saved history';

  @override
  String get received_output_heading =>
      'Received output — match to saved history unconfirmed';

  @override
  String get received_output_details => 'About received output';

  @override
  String get received_output_explanation =>
      'This may also appear in saved history. The app cannot confirm a match.';

  @override
  String get local_prompt_context => 'Local prompt context';

  @override
  String get received_output_badge => 'Received · match unconfirmed';

  @override
  String get received_output_lifetime =>
      'Received output is kept temporarily in this app session and may be shortened or removed as limits are reached. It may not be available after the app or connection is closed.';

  @override
  String get theme_palette => 'Thème de couleur';

  @override
  String get theme_palette_gold => 'Or';

  @override
  String get theme_palette_purple => 'Violet';

  @override
  String get theme_palette_orange => 'Orange';

  @override
  String get theme_palette_green => 'Vert';

  @override
  String get theme_palette_blue => 'Bleu';

  @override
  String get theme_palette_red => 'Rouge';

  @override
  String get theme_palette_teal => 'Bleu sarcelle';

  @override
  String get theme_palette_pink => 'Rose';

  @override
  String get theme_palette_indigo => 'Indigo';

  @override
  String get theme_palette_cyan => 'Cyan';

  @override
  String get assets_recent_subtitle =>
      'Retrouvez les fichiers partagés par Hermes dans les discussions enregistrées';

  @override
  String get assets_scope_notice =>
      'Fichiers générés explicitement partagés par Hermes dans les réponses enregistrées. Il s’agit d’une vue partielle de l’historique des discussions, et non d’un catalogue complet des fichiers ou pièces jointes. Les fichiers référencés peuvent ne plus exister.';

  @override
  String get assets_download_limit =>
      'Les fichiers ne sont chargés que lorsque vous appuyez dessus. Les aperçus et les téléchargements sont limités à 25 MiB par fichier ; utilisez le tableau de bord pour les fichiers plus volumineux.';

  @override
  String get assets_search_hint =>
      'Rechercher parmi les fichiers trouvés ou les discussions d’origine';

  @override
  String get assets_all => 'Tous';

  @override
  String get assets_images => 'Images';

  @override
  String get assets_audio => 'Audio';

  @override
  String get assets_video => 'Vidéo';

  @override
  String get assets_documents => 'Documents et autres fichiers';

  @override
  String get assets_empty =>
      'Aucune ressource trouvée dans les messages analysés';

  @override
  String get assets_empty_detail =>
      'Analysez davantage de discussions ou des messages plus anciens pour remonter plus loin dans l’historique. Les pièces jointes ordinaires et les fichiers sans lien ne sont pas indexés ici.';

  @override
  String get assets_no_matches => 'Aucune ressource correspondante';

  @override
  String get assets_load_more_chats => 'Analyser plus de discussions';

  @override
  String get assets_load_older_messages => 'Analyser les messages plus anciens';

  @override
  String get assets_load_failed =>
      'Une partie de l’historique n’a pas pu être lue. Les résultats sont incomplets. Vérifiez la connexion au tableau de bord, puis réessayez.';

  @override
  String get assets_retry_failed =>
      'Réessayer les lectures de l’historique qui ont échoué';

  @override
  String get assets_partial =>
      'Le serveur a signalé un historique incomplet. Vérifiez le tableau de bord, puis actualisez.';

  @override
  String assets_scan_summary(int files, int chats) {
    return 'Références de fichiers trouvées : $files · Discussions analysées : $chats';
  }

  @override
  String assets_open_chat(String title) {
    return 'Ouvrir la discussion : $title';
  }

  @override
  String get assets_file_too_large =>
      'Ce fichier dépasse la limite de téléchargement. Ouvrez le tableau de bord pour le télécharger.';

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      'Une question ponctuelle. S\'archive automatiquement après 72 heures ; tout ce qui mérite d\'être conservé reste en mémoire.';

  @override
  String get archive_chat => 'Archiver la discussion';

  @override
  String get unarchive_chat => 'Désarchiver la discussion';

  @override
  String get chat_archived => 'Discussion archivée';

  @override
  String get chat_unarchived => 'Discussion désarchivée';

  @override
  String could_not_update_chat_archive(Object error) {
    return 'Impossible de modifier l’archivage de la discussion : $error';
  }

  @override
  String get quick_chat_description => 'Une question ponctuelle.';

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
  String get approval_needed_description =>
      'Une commande attend votre approbation ou votre refus.';

  @override
  String get approve => 'Approuver';

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
      'Seules les discussions archivées apparaissent ici. Les anciennes restent dans Toutes les discussions.';

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
  String get agent => 'Agent';

  @override
  String get autonomous_agents => 'Agents autonomes';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      'Récupération en arrière-plan indisponible — transport hérité';

  @override
  String get background_task_completed => 'Tâche en arrière-plan terminée';

  @override
  String get background_task_completed_description =>
      'Une commande de terminal en arrière-plan est terminée.';

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
  String get code_format => 'Code';

  @override
  String get coming_next => 'Bientôt disponible';

  @override
  String get command => 'Commande';

  @override
  String get command_palette => 'Command palette';

  @override
  String get command_palette_hint => 'Type a command';

  @override
  String get command_palette_no_results => 'No commands found';

  @override
  String get command_palette_new_chat => 'New chat';

  @override
  String get command_palette_search_chats => 'Search chats';

  @override
  String get command_palette_toggle_theme => 'Toggle theme';

  @override
  String get command_palette_copy_last_code => 'Copy last code block';

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
  String get could_not_open_link => 'Impossible d’ouvrir ce lien.';

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
  String get credit_notifications => 'Notifications de crédit';

  @override
  String get credit_notifications_description =>
      'L’utilisation du crédit a été arrêtée ou rétablie.';

  @override
  String get cron => 'Cron';

  @override
  String get crons => 'Crons';

  @override
  String get cron_conversations_empty =>
      'Conversations from scheduled jobs appear here, including older runs.';

  @override
  String get search_cron_conversations => 'Search cron conversations';

  @override
  String get cron_jobs => 'Tâches Cron';

  @override
  String cron_schedule_timezone(Object zone) {
    return 'Fuseau horaire de la planification : $zone';
  }

  @override
  String get crons_upcoming => 'À venir';

  @override
  String get crons_history => 'Historique';

  @override
  String cron_time_with_zone(Object time, Object zone) {
    return '$time ($zone)';
  }

  @override
  String cron_time_zone_unknown(Object time) {
    return '$time (fuseau horaire inconnu)';
  }

  @override
  String get cron_no_next_run => 'Aucune prochaine exécution planifiée';

  @override
  String get cron_status_scheduled => 'Planifiée';

  @override
  String get cron_status_paused => 'En pause';

  @override
  String cron_delivers_to(Object target) {
    return 'Livraison vers $target';
  }

  @override
  String get cron_upcoming_empty_title => 'Aucune tâche planifiée';

  @override
  String get cron_upcoming_empty_message =>
      'Rien n’est planifié. Créez une tâche dans Tâches Cron, ou demandez à l’agent d’en planifier une.';

  @override
  String get cron_upcoming_unavailable => 'Tâches planifiées indisponibles';

  @override
  String get cron_upcoming_needs_dashboard =>
      'Les tâches planifiées nécessitent une connexion au tableau de bord. Cette adresse n’expose pas la planification Cron. Vérifiez l’adresse du tableau de bord et la prise en charge par l’hôte.';

  @override
  String get cron_upcoming_needs_dashboard_auth =>
      'Les tâches planifiées nécessitent une authentification au tableau de bord. Ajoutez le nom d’utilisateur et le mot de passe du tableau de bord à cette connexion, ou activez le mode proxy.';

  @override
  String get cron_upcoming_dashboard_unreachable =>
      'Le tableau de bord est injoignable. Vérifiez l’hôte, le port du tableau de bord et le réseau, puis réessayez.';

  @override
  String get cron_upcoming_load_failed =>
      'Impossible de lire les tâches planifiées. Vérifiez la connexion au tableau de bord, puis réessayez.';

  @override
  String get cron_upcoming_refresh_failed =>
      'Impossible d’actualiser la planification. La dernière lecture réussie est affichée.';

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
  String get enable_notifications => 'Activer les notifications';

  @override
  String get enable_notifications_description =>
      'Désactiver ceci désactive toutes les notifications ci-dessous.';

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
  String get hermes_agent => 'Ares - formerly Hermes Android';

  @override
  String get hermes_agent_for_android => 'Ares - formerly Hermes Android';

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
      'Ares maintient la mise à l\'échelle du texte d\'accessibilité Android active.';

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
  String get input_needed => 'Réponse requise';

  @override
  String get input_needed_description =>
      'Hermes a posé une question ou a besoin d’un mot de passe ou d’un secret.';

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
  String get memory_about_you => 'À votre sujet';

  @override
  String get memory_agent_notes => 'Notes de l’agent';

  @override
  String get memory_builtin_scope =>
      'Faits enregistrés dans USER.md et MEMORY.md de ce profil. Les fournisseurs de mémoire externes (dont MemPalace) ne sont pas affichés ici.';

  @override
  String get memory_read_only =>
      'Lecture seule. Demandez à Hermes dans le chat de corriger ou d’oublier un fait.';

  @override
  String get memory_unavailable =>
      'Cette passerelle ou ce profil ne peut pas fournir les faits enregistrés. Vérifiez le profil sélectionné et mettez Hermes à jour si nécessaire.';

  @override
  String get memory_load_error =>
      'Vérifiez la connexion et l’authentification du tableau de bord, puis réessayez.';

  @override
  String get memory_read_full_fact => 'Lire le fait complet';

  @override
  String get memory_full_fact_requires_update =>
      'Les faits complets nécessitent une passerelle Hermes plus récente. Mettez Hermes à jour et actualisez la liste.';

  @override
  String get memory_fact_detail_error =>
      'Impossible de charger le fait complet. Il a peut-être changé ; actualisez la liste et réessayez.';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'Les faits enregistrés apparaîtront ici quand Hermes les aura mémorisés.';

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
  String get notifications => 'Notifications';

  @override
  String get notifications_permission_denied =>
      'Les notifications sont bloquées par le système. Activez-les pour cette application dans les réglages Android.';

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
  String get plugin_notifications => 'Notifications d’extensions';

  @override
  String get plugin_notifications_description =>
      'La passerelle a envoyé une notification pendant que l’application était en arrière-plan.';

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
  String get recently_active => 'Actif récemment';

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
  String get response_complete => 'Réponse terminée';

  @override
  String get response_complete_description =>
      'Un tour s’est terminé pendant que l’application était en arrière-plan.';

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
  String send_failed_api_only_permission_denied(Object error) {
    return 'Échec de l\'envoi : $error. Le serveur a refusé cette écriture pour le principal de la clé API. Si cette conversation appartient au Dashboard, renseigner le nom d\'utilisateur et le mot de passe Dashboard de cette connexion peut autoriser l\'envoi ; le serveur peut aussi refuser délibérément.';
  }

  @override
  String get send_message => 'Envoyer le message';

  @override
  String get send_test_notification => 'Envoyer une notification de test';

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
  String get test_notification_body =>
      'Si vous voyez ceci, les notifications fonctionnent.';

  @override
  String get test_notification_sent => 'Notification de test envoyée.';

  @override
  String get test_notification_title => 'Test des notifications Hermes';

  @override
  String get test_notification_unsupported =>
      'Impossible d’envoyer la notification — vérifiez que le système autorise les notifications.';

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
      'Ce projet a besoin d\'un dossier avant de pouvoir y démarrer une discussion. Ajoutez un dossier, puis réessayez.';

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
  String get received_outcome_unknown => 'Tour terminé — résultat non confirmé';

  @override
  String get turn_completed => 'Tour terminé';

  @override
  String get turn_failed => 'Échec du tour';

  @override
  String get turn_failed_description =>
      'Un tour en arrière-plan s’est terminé par une erreur.';

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
  String get message_metadata => 'Message details';

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
  String tool_start_observed(Object time) {
    return 'Début observé à $time (heure locale)';
  }

  @override
  String tool_last_observed(Object time) {
    return 'Dernière observation à $time (heure locale)';
  }

  @override
  String tool_result_recorded(Object time) {
    return 'Résultat enregistré à $time (heure locale)';
  }

  @override
  String get tool_time_unavailable => 'Heure indisponible';

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

  @override
  String get pin_chat => 'Épingler la discussion';

  @override
  String get unpin_chat => 'Désépingler la discussion';

  @override
  String get pinned_chats => 'Épinglées';

  @override
  String could_not_update_chat_pin(Object error) {
    return 'Impossible de modifier l’épinglage de la discussion : $error';
  }

  @override
  String get could_not_save_chat_spaces =>
      'Impossible d’enregistrer les espaces de discussion sur cet appareil';

  @override
  String get update_available => 'Mise à jour disponible';

  @override
  String get update_now => 'Update now';

  @override
  String get update_install => 'Install update';

  @override
  String get update_downloading => 'Downloading and verifying update…';

  @override
  String get update_allow_install =>
      'Allow Hermes to install this update, then return here and tap Install update.';

  @override
  String get update_failed =>
      'The update could not be downloaded, verified, or opened. Try again or view the release page.';

  @override
  String get a_newer_hermes_android_build_is_available_on_github =>
      'Une version plus récente de Ares est disponible sur GitHub.';

  @override
  String get release_notes => 'Notes de version';

  @override
  String get view_release => 'Voir la version';

  @override
  String get skip_this_version => 'Ignorer cette version';

  @override
  String get later => 'Plus tard';

  @override
  String get check_for_updates => 'Rechercher des mises à jour';

  @override
  String get check_for_updates_on_launch =>
      'Rechercher des mises à jour au démarrage';

  @override
  String get you_re_on_the_latest_version =>
      'Vous avez déjà la dernière version.';

  @override
  String get couldn_t_check_for_updates =>
      'Impossible de rechercher des mises à jour.';

  @override
  String get chat_density => 'Densité de la conversation';

  @override
  String chat_density_2(Object label) {
    return 'Densité de la conversation : $label';
  }

  @override
  String get chat_density_comfortable => 'Confortable';

  @override
  String get chat_density_compact => 'Compacte';

  @override
  String get chat_density_comfortable_description =>
      'Bulles plus spacieuses avec une étiquette d’expéditeur au-dessus de chaque message.';

  @override
  String get chat_density_compact_description =>
      'Bulles plus serrées et sans étiquette pour afficher plus de messages à l’écran.';

  @override
  String chat_density_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String
  get compact_removes_the_you_and_hermes_labels_and_trims_bubble_padding_spacing_and_side_margins =>
      'Le mode compacte supprime les étiquettes « You » et « Hermes » et réduit les marges internes, l’espacement et les marges latérales des bulles.';

  @override
  String get client_certificate_mtls => 'Client certificate (mTLS)';

  @override
  String get client_certificate_mtls_description =>
      'Present a certificate when an HTTPS proxy requires mutual TLS.';

  @override
  String get client_certificate_https_only =>
      'Client certificates are only used for HTTPS connections.';

  @override
  String get choose_certificate => 'Choose certificate';

  @override
  String get certificate_password => 'Certificate password';

  @override
  String get this_certificate_is_password_protected =>
      'This certificate is password-protected. It opens as you type.';

  @override
  String get enter_the_certificate_password_to_finish_loading_it =>
      'Enter the certificate password to finish loading the certificate you chose.';

  @override
  String get client_certificate_required =>
      'Load a client certificate or turn off the client certificate option.';

  @override
  String client_certificate_loaded(String label) {
    return 'Loaded: $label';
  }

  @override
  String get remove_certificate => 'Remove certificate';

  @override
  String get certificate_import_failed =>
      'That certificate could not be loaded.';

  @override
  String get background_work => 'Activité en arrière-plan';

  @override
  String get keep_chats_active_in_background =>
      'Garder les discussions actives en arrière-plan';

  @override
  String get background_work_description =>
      'Maintient la connexion des discussions lancées par vous lorsque cette app est en arrière-plan. Les connexions inactives peuvent être coupées. Consomme plus de batterie et de données. Désactiver cette option n’arrête pas le travail sur le serveur.';

  @override
  String get background_work_limits =>
      'Android peut malgré tout suspendre les connexions en mode Doze ou terminer le processus de l’app. Les notifications après la fin du processus nécessitent une configuration push séparée. L’arrêt forcé n’est pas pris en charge.';

  @override
  String get background_work_disclosure =>
      'Une notification de service obligatoire reste visible lorsque la protection en arrière-plan est active, même si les notifications de discussion facultatives sont désactivées.';

  @override
  String get battery_optimisation_settings =>
      'Paramètres d’optimisation de la batterie';

  @override
  String get battery_optimisation_description =>
      'Ouvre les paramètres Android pour consulter les restrictions de batterie. Aucune exemption n’est demandée automatiquement et modifier les paramètres ne garantit pas la réception.';

  @override
  String get battery_settings_unavailable =>
      'Impossible d’ouvrir les paramètres de batterie sur cet appareil.';

  @override
  String get background_work_save_failed =>
      'Impossible d’enregistrer le réglage d’activité en arrière-plan.';

  @override
  String get ongoing_chat_channel_name => 'Discussions actives';

  @override
  String get ongoing_chat_channel_description =>
      'Mises à jour silencieuses des discussions lancées par vous et non terminées';

  @override
  String get task_timeline => 'Task timeline';

  @override
  String get task_refresh_history => 'Refresh task history';

  @override
  String get task_live_preview => 'Live preview from parent events';

  @override
  String get task_preview_explanation =>
      'Latest exposed preview only; not a recorded transcript row.';

  @override
  String get task_preview => 'Preview';

  @override
  String get task_recorded_history => 'Recorded task history';

  @override
  String get task_loading_history => 'Loading task history…';

  @override
  String get task_empty_history =>
      'No recorded messages yet. The task may not have flushed its history; this does not mean it produced no work.';

  @override
  String get task_load_older => 'Load older';

  @override
  String get task_default_goal => 'Delegated task';

  @override
  String task_status(Object status) {
    return 'Status: $status';
  }

  @override
  String task_identity(Object id) {
    return 'Task: $id';
  }

  @override
  String task_stored_session(Object id) {
    return 'Stored session: $id';
  }

  @override
  String task_delegation(Object id) {
    return 'Delegation: $id';
  }

  @override
  String get task_read_only_notice =>
      'Read-only · recorded history may appear after the task flushes. Refresh to check again.';

  @override
  String task_row_label(Object id, Object role) {
    return '$role · row $id';
  }

  @override
  String get task_role_assistant => 'Assistant';

  @override
  String get task_role_user => 'User';

  @override
  String get task_role_tool => 'Tool';

  @override
  String task_tool_call(Object name) {
    return 'Tool call · $name';
  }

  @override
  String task_tool_result(Object name) {
    return 'Tool result · $name';
  }

  @override
  String task_call_details(Object arguments, Object id) {
    return 'Call ID: $id\nArguments\n$arguments';
  }

  @override
  String task_result_details(Object id, Object result) {
    return 'Call ID: $id\nResult\n$result';
  }

  @override
  String get task_not_supplied => 'Not supplied';

  @override
  String get task_missing_arguments => 'Arguments not retained by the server.';

  @override
  String get task_image_placeholder => '[image]';

  @override
  String get task_invalid_reference =>
      'Task transcript unavailable: invalid stored session reference.';

  @override
  String get task_auth_required =>
      'Task transcript unavailable: configure Dashboard authentication for this gateway. The API-server key cannot read task reasoning.';

  @override
  String get task_auth_rejected =>
      'Task transcript unavailable: Dashboard authentication was rejected. Check this gateway’s Dashboard settings.';

  @override
  String get task_incompatible_history =>
      'Task transcript unavailable: this Dashboard does not provide compatible bounded raw history for the selected profile.';

  @override
  String get task_identity_unproven =>
      'Task transcript unavailable: the Dashboard could not prove the exact stored session or its compression lineage. No transcript from another session is shown.';

  @override
  String get task_partial_compression =>
      'Partial history: this task continued after compression, but this gateway has not exposed a verifiable newer reference. The final reply may be missing. Automatic refresh is paused; use Refresh to retry.';

  @override
  String get task_partial_ancestors =>
      'Partial history: this gateway omits compression ancestors for this task. Earlier task segments may be missing. Known rows are retained; use Refresh to retry.';

  @override
  String get task_missing_reference =>
      'Task transcript unavailable: this server did not retain its session reference.';

  @override
  String get task_missing_row_identity =>
      'Task transcript unavailable: this server did not supply durable message row identities.';

  @override
  String get task_history_not_ready =>
      'Task history is not available yet (HTTP 404). The task may not have flushed, or this Dashboard may not support task history. Retry to check again.';

  @override
  String get task_refresh_failed =>
      'Could not refresh task history. Check the connection and retry.';

  @override
  String get task_status_interrupted => 'Interrupted';

  @override
  String get task_status_cancelled => 'Cancelled';

  @override
  String get task_status_requested => 'Requested';

  @override
  String get task_status_thinking => 'Thinking';

  @override
  String get task_status_tool => 'Using a tool';

  @override
  String get task_status_pending => 'Pending';

  @override
  String get task_status_dispatched => 'Dispatched';

  @override
  String task_status_unknown(Object status) {
    return 'Unknown status: $status';
  }

  @override
  String task_tasks_finished(Object count) {
    return '$count delegated task(s) finished';
  }

  @override
  String get activity_status_unconfirmed => 'Statut non confirmé';

  @override
  String get activity_recently_updated => 'Mis à jour récemment';

  @override
  String get activity_reconnecting =>
      'Reconnexion — vérification de l’état du tour';

  @override
  String get activity_outcome_unknown =>
      'Le résultat du tour n’a pas pu être confirmé. Ouvrez la discussion pour le vérifier.';

  @override
  String get activity_chat_updated_detail =>
      'Activité de la discussion enregistrée par la passerelle ; l’état du tour en temps réel n’est pas disponible.';

  @override
  String get activity_updated => 'Mis à jour';

  @override
  String get activity_empty_title => 'Aucune activité récente';

  @override
  String get activity_empty_detail =>
      'Les tours lancés dans cette application et les discussions de la passerelle mises à jour au cours des 7 derniers jours apparaissent ici.';

  @override
  String get activity_read_error =>
      'La vue Activité n’a pas pu lire ses enregistrements de tours ou les discussions de la passerelle. Vérifiez la connexion et réessayez.';

  @override
  String get activity_chat_unavailable =>
      'Cette discussion n’est plus disponible ou la passerelle n’a pas pu être jointe.';

  @override
  String get activity_partial_title => 'Activité partiellement chargée';

  @override
  String get activity_partial_detail =>
      'Une période limitée de l’activité de la passerelle est affichée. D’autres discussions peuvent exister ; tirez vers le bas pour actualiser.';

  @override
  String get provider_usage => 'Utilisation enregistrée';

  @override
  String get provider_usage_notice =>
      'Utilisation de Hermes sur 30 jours, pas le solde ni les tarifs. Configurez les identifiants sur le serveur Hermes ; cette application ne stocke aucune clé API de fournisseur.';

  @override
  String get provider_usage_failed =>
      'Impossible de charger l’utilisation enregistrée.';

  @override
  String get provider_usage_empty =>
      'Aucune utilisation enregistrée pour ce fournisseur.';

  @override
  String provider_usage_counts(String sessions, String input, String output) {
    return '$sessions sessions · Entrée : $input · Sortie : $output';
  }

  @override
  String provider_usage_costs(String estimated, String actual) {
    return 'Estimé : $estimated · Déclaré : $actual';
  }

  @override
  String get provider_quota_codex => 'Abonnement OpenAI Codex';

  @override
  String get provider_quota_claude => 'Abonnement Claude';

  @override
  String get provider_quota_openai_api =>
      'Utilisation enregistrée de l’API OpenAI';

  @override
  String get provider_quota_notice =>
      'Périodes de l’abonnement indiquées par le fournisseur, distinctes de l’utilisation enregistrée par Hermes et de la facturation de l’API. Les comptes sont affichés séparément ; les limites d’un modèle ne signifient pas que tout le quota du compte est épuisé.';

  @override
  String get provider_quota_windows_notice =>
      'Les abonnements Codex et Claude ont des limites par session de cinq heures et par semaine. Seules les périodes indiquées par le fournisseur sont affichées ; les limites et les heures de réinitialisation non communiquées restent indisponibles. Les limites hebdomadaires peuvent s’appliquer au compte ou à certains modèles.';

  @override
  String get provider_quota_five_hour_session => 'Session de 5 heures';

  @override
  String get provider_quota_unavailable =>
      'Quota de l’abonnement indisponible.';

  @override
  String get provider_quota_failed =>
      'Impossible d’actualiser le quota de l’abonnement. Les valeurs conservées proviennent de la consultation précédente.';

  @override
  String get provider_quota_account => 'Compte';

  @override
  String get provider_quota_unknown => 'inconnu';

  @override
  String provider_quota_state(String state) {
    return 'État du compte : $state';
  }

  @override
  String provider_quota_scope(String scope) {
    return 'Portée : $scope';
  }

  @override
  String provider_quota_percent(String used, String remaining) {
    return '$used% utilisé · $remaining% restant';
  }

  @override
  String provider_quota_reset(String reset) {
    return 'Réinitialisation : $reset';
  }

  @override
  String get provider_quota_reset_unknown =>
      'Heure de réinitialisation indisponible.';

  @override
  String get auxiliary_models => 'Modèles auxiliaires';

  @override
  String get auxiliary_notice =>
      'Choisissez un modèle par tâche. Gérez les points de terminaison personnalisés sur le serveur. Auto suit les règles d’héritage de la tâche.';

  @override
  String get auxiliary_inherit => 'Auto (hériter)';

  @override
  String get auxiliary_unavailable =>
      'Les paramètres auxiliaires sont indisponibles.';

  @override
  String get provider_oauth_title => 'Connexion aux fournisseurs';

  @override
  String get provider_oauth_more_subtitle =>
      'Gérer la connexion aux fournisseurs sur votre hôte Hermes';

  @override
  String get provider_oauth_settings_subtitle =>
      'Connectez-vous sur votre hôte Hermes ; les jetons du fournisseur restent hors de cet appareil';

  @override
  String get provider_oauth_intro =>
      'Connectez-vous à votre fournisseur dans un navigateur externe. Les jetons sont stockés uniquement sur votre hôte Hermes, pas sur cet appareil. La connexion ne sélectionne pas de modèle de discussion dans cette application.';

  @override
  String get provider_oauth_defaults_notice =>
      'Certaines procédures de l’hôte, dont le remplacement d’un compte gratuit Nous, peuvent modifier ses paramètres par défaut. Vérifiez les paramètres de votre hôte après la connexion.';

  @override
  String get provider_oauth_transport_init_failed =>
      'Impossible d’initialiser la connexion sécurisée au tableau de bord sélectionné. Vérifiez son identité TLS et ses paramètres de connexion.';

  @override
  String get provider_oauth_https_required =>
      'La connexion aux fournisseurs nécessite une connexion HTTPS au tableau de bord Hermes.';

  @override
  String get provider_oauth_auth_required =>
      'Configurez l’authentification par mot de passe du tableau de bord ou un proxy de confiance avant de vous connecter.';

  @override
  String get provider_oauth_catalog_failed =>
      'La connexion aux fournisseurs est indisponible sur cet hôte. Vérifiez l’authentification du tableau de bord et mettez l’hôte à jour s’il ne prend pas en charge OAuth pour les fournisseurs.';

  @override
  String get provider_oauth_expired => 'La connexion a expiré. Recommencez.';

  @override
  String get provider_oauth_start_failed =>
      'Impossible de démarrer la connexion sécurisée au fournisseur. Réessayez.';

  @override
  String get provider_oauth_denied =>
      'La connexion a été refusée. Recommencez.';

  @override
  String get provider_oauth_cancelled => 'Connexion annulée.';

  @override
  String get provider_oauth_host_failed =>
      'L’hôte n’a pas pu terminer la connexion. Recommencez.';

  @override
  String get provider_oauth_poll_failed =>
      'Impossible de vérifier l’état de la connexion. Recommencez.';

  @override
  String provider_oauth_cancellation_unconfirmed(String message) {
    return '$message L’annulation n’a pas pu être confirmée ; la session de l’hôte peut se poursuivre jusqu’à son expiration.';
  }

  @override
  String get provider_oauth_browser_failed =>
      'Impossible d’ouvrir le navigateur externe. Réessayez ou annulez la connexion.';

  @override
  String get provider_oauth_retry => 'Réessayer';

  @override
  String provider_oauth_complete(String provider) {
    return 'Terminer la connexion à $provider';
  }

  @override
  String get provider_oauth_code_instruction =>
      'Saisissez ce code temporaire sur la page du fournisseur :';

  @override
  String get provider_oauth_waiting =>
      'En attente d’approbation. Cette session expire automatiquement.';

  @override
  String get provider_oauth_open_browser =>
      'Ouvrir le fournisseur dans le navigateur';

  @override
  String get provider_oauth_cancel => 'Annuler la connexion';

  @override
  String get provider_oauth_signed_out => 'Non connecté sur l’hôte';

  @override
  String get provider_oauth_sign_in_again => 'Se reconnecter';

  @override
  String get provider_oauth_sign_in => 'Se connecter';

  @override
  String get provider_oauth_cli_required =>
      'Connectez-vous avec la CLI du fournisseur sur votre hôte Hermes. Cet hôte ne propose pas de connexion dans l’application pour ce fournisseur.';

  @override
  String get provider_oauth_checking_account =>
      'Autorisation reçue. Vérification du compte sur le serveur…';

  @override
  String get provider_oauth_verification_unavailable =>
      'Autorisation reçue ; vérification du compte indisponible. Ouvrez Utilisation pour actualiser les données du compte.';

  @override
  String provider_oauth_verified_account(String email) {
    return 'Connecté sur le serveur Hermes en tant que $email. Ouvrez Utilisation pour actualiser les données du compte.';
  }

  @override
  String get provider_oauth_credentials_unverified =>
      'Le serveur signale des identifiants disponibles ; l’identité du compte n’est pas vérifiée.';

  @override
  String get provider_oauth_account_status_unknown =>
      'État du compte sur le serveur indisponible.';

  @override
  String get app_language => 'App language';

  @override
  String get app_language_system => 'Same as phone';

  @override
  String get auto_archives_after_72_hours => 'Auto-archives after 72 hours';

  @override
  String get automation => 'Automation';

  @override
  String get voice_recording_start => 'Record voice message';

  @override
  String get voice_recording_pause => 'Pause recording';

  @override
  String get voice_recording_preview => 'Play recording';

  @override
  String get voice_recording_resume => 'Continue recording';

  @override
  String get voice_recording_send => 'Send voice message';

  @override
  String get voice_recording_discard => 'Discard recording';

  @override
  String get voice_recording_processing => 'Preparing voice message…';

  @override
  String voice_recording_elapsed(String time) {
    return 'Recording $time';
  }

  @override
  String voice_recording_draft(String time) {
    return 'Voice message $time';
  }

  @override
  String get voice_recording_permission =>
      'Allow microphone access to record a voice message.';

  @override
  String get voice_recording_limit =>
      'This recording has reached the ten-minute limit.';

  @override
  String get voice_recording_empty => 'No audio was recorded. Try again.';

  @override
  String get voice_recording_failed =>
      'Could not process the recording. Any saved fragments have been kept.';

  @override
  String get voice_recording_unconfirmed =>
      'Delivery was not confirmed. Your recording is saved. Check the chat before trying again.';

  @override
  String get voice_recording_submit_failed =>
      'Could not send the voice message. Your recording is saved. Check the connection, Dashboard access and server transcription settings.';

  @override
  String get voice_recording_pause_playback => 'Pause playback';

  @override
  String get projects_root_title => 'Dossier des Projets sur le serveur';

  @override
  String get projects_root_more_subtitle =>
      'Où sont créés les nouveaux dossiers de Projet sur le serveur';

  @override
  String get projects_root_description =>
      'Les Projets créés sur ce téléphone reçoivent leur dossier ici. Pointez-le vers le dossier utilisé par Hermes afin que le téléphone et le serveur partagent les mêmes Projets.';

  @override
  String get projects_root_label => 'Chemin racine des Projets';

  @override
  String projects_root_default_hint(String path) {
    return 'Valeur par défaut du serveur : $path';
  }

  @override
  String get projects_root_locked_title => 'Défini par le serveur';

  @override
  String get projects_root_locked_explanation =>
      'Ce serveur limite l\'accès aux fichiers à une seule racine ; le dossier des Projets ne peut donc pas être modifié depuis l\'application.';

  @override
  String get projects_root_saved => 'Dossier des Projets enregistré.';

  @override
  String get projects_root_reset => 'Utiliser la valeur par défaut du serveur';

  @override
  String get projects_root_invalid_empty => 'Saisissez un chemin de dossier.';

  @override
  String get projects_root_invalid_absolute =>
      'Saisissez un chemin absolu commençant par une barre oblique.';

  @override
  String get projects_root_invalid_segments =>
      'Supprimez les segments en points et les caractères de contrôle du chemin.';

  @override
  String get projects_root_unsupported =>
      'Non pris en charge sur cette connexion. Une connexion Desktop Gateway avec accès au Tableau de bord est nécessaire pour lire ou modifier le dossier des Projets du serveur.';

  @override
  String get projects_root_unavailable =>
      'Impossible de lire le dossier des Projets du serveur. Vérifiez la connexion au Tableau de bord, puis réessayez.';

  @override
  String get adopt_folder_action => 'Ajouter un dossier existant';

  @override
  String adopt_folder_description(String root) {
    return 'Dossiers sous $root qui ne sont pas encore enregistrés comme Projet.';
  }

  @override
  String adopt_folder_registered(String name) {
    return 'Déjà un Projet : $name';
  }

  @override
  String get adopt_folder_none =>
      'Tous les dossiers de ce chemin sont déjà des Projets.';

  @override
  String get adopt_folder_unsupported =>
      'Cette connexion ne peut pas lister les dossiers du serveur. Saisissez plutôt le chemin absolu d\'un dossier existant.';

  @override
  String adopt_folder_failed(String error) {
    return 'Impossible de lister les dossiers du serveur : $error';
  }

  @override
  String get adopt_folder_manual_label => 'Chemin du dossier existant';

  @override
  String get adopt_folder_name_label => 'Nom du Projet';

  @override
  String get adopt_folder_add => 'Ajouter comme Projet';

  @override
  String adopt_folder_added(String name, String path) {
    return '$name utilise désormais $path';
  }

  @override
  String adopt_folder_error(String error) {
    return 'Impossible d\'ajouter le dossier : $error';
  }

  @override
  String adopt_folder_folderless(String name) {
    return '$name a été créé, mais le dossier n\'a pas été rattaché. Rattachez-le depuis Hermes sur le serveur.';
  }

  @override
  String get slash_commands => 'Slash commands';

  @override
  String get slash_commands_loading => 'Loading commands…';

  @override
  String get slash_commands_empty => 'No matching commands';

  @override
  String get slash_command_output => 'Command output';

  @override
  String get slash_command_no_output => 'The command completed with no output.';

  @override
  String get slash_command_delivery_unknown =>
      'The command was sent but its reply never arrived. It may still be running on the gateway, so your draft was kept. Check the gateway before retrying.';

  @override
  String get slash_command_failed => 'The command could not be run.';

  @override
  String get nextgen_toggle => 'Interface NextGen';

  @override
  String get nextgen_toggle_subtitle =>
      'Un nouveau design avec une seule connexion, des discussions en direct et la découverte réseau. Vos passerelles et discussions sont partagées avec cette interface.';

  @override
  String get nextgen_single_login => 'Se connecter avec un seul identifiant';

  @override
  String get nextgen_single_login_subtitle =>
      'Ajoutez une passerelle avec la seule adresse de son tableau de bord et une connexion.';

  @override
  String get ng_allow_this_command => 'Autoriser cette commande ?';

  @override
  String ng_hermes_wants_to_run_this_with(Object tool) {
    return 'Hermes veut exécuter ceci avec $tool.';
  }

  @override
  String get ng_hermes_wants_to_run_this => 'Hermes veut exécuter ceci.';

  @override
  String get ng_hermes_has_a_question => 'Hermes a une question';

  @override
  String get ng_hermes_has_questions => 'Hermes a des questions';

  @override
  String get ng_password_for_sudo => 'Mot de passe sudo';

  @override
  String get ng_hermes_needs_your_sudo_password_to =>
      'Hermes a besoin de votre mot de passe sudo pour exécuter cette commande.';

  @override
  String get ng_a_secret_value => 'Une valeur secrète';

  @override
  String ng_value_for(Object variable) {
    return 'Valeur pour $variable';
  }

  @override
  String get ng_your_password_manager => 'votre gestionnaire de mots de passe';

  @override
  String ng_unlock(Object name) {
    return 'Déverrouiller $name';
  }

  @override
  String ng_hermes_needs_unlocked_to_sign_in(Object name) {
    return 'Hermes a besoin que $name soit déverrouillé pour vous connecter.';
  }

  @override
  String get ng_sign_in_code => 'Code de connexion';

  @override
  String get ng_enter_the_sign_in_code => 'Saisissez le code de connexion.';

  @override
  String ng_enter_the_sign_in_code_for(Object site) {
    return 'Saisissez le code de connexion pour $site.';
  }

  @override
  String get ng_save_a_login => 'Enregistrer ces identifiants ?';

  @override
  String ng_save_your_login(Object site) {
    return 'Enregistrer vos identifiants pour $site ?';
  }

  @override
  String ng_couldn_t_load_this_chat(Object error) {
    return 'Impossible de charger cette conversation : $error';
  }

  @override
  String ng_live_updates_are_unavailable(Object error) {
    return 'Les mises à jour en direct sont indisponibles : $error';
  }

  @override
  String ng_preparing(Object name) {
    return 'préparation de $name…';
  }

  @override
  String get ng_the_turn_failed => 'Le tour a échoué.';

  @override
  String ng_couldn_t_stop(Object error) {
    return 'Impossible d\'arrêter : $error';
  }

  @override
  String get ng_server_access => 'Accès au serveur';

  @override
  String get ng_sign_in => 'Connexion';

  @override
  String get ng_live_connection => 'Connexion en direct';

  @override
  String get ng_check_that_tailscale_is_on_on =>
      'Vérifiez que Tailscale est activé sur ce téléphone et sur le serveur.';

  @override
  String get ng_check_the_address_and_that_the =>
      'Vérifiez l\'adresse et que le proxy redirige vers le tableau de bord.';

  @override
  String get ng_use_the_same_network_as_the =>
      'Utilisez le même réseau que le serveur et lancez le tableau de bord avec --host 0.0.0.0 pour qu\'il soit accessible depuis d\'autres appareils.';

  @override
  String get ng_check_the_address_vpn_or_tailscale =>
      'Vérifiez l\'adresse, le VPN ou la connexion Tailscale.';

  @override
  String get ng_not_checked_yet => 'Pas encore vérifié.';

  @override
  String get ng_checking => 'Vérification…';

  @override
  String ng_hermes_answers_at(Object version, Object address) {
    return 'Hermes $version répond à $address.';
  }

  @override
  String get ng_something_answered_but_not_a_hermes =>
      'Une réponse a été reçue, mais ce n\'est pas un tableau de bord Hermes.';

  @override
  String ng_something_answered_http_but_not_a(Object status) {
    return 'Une réponse a été reçue (HTTP $status), mais ce n\'est pas un tableau de bord Hermes.';
  }

  @override
  String get ng_use_the_dashboard_s_address_and =>
      'Utilisez l\'adresse et le port du tableau de bord (9119 par défaut), et non ceux du serveur API.';

  @override
  String get ng_cloudflare_access_turned_the_service_token =>
      'Cloudflare Access a refusé le jeton de service.';

  @override
  String get ng_cloudflare_access_is_in_front_of =>
      'Cloudflare Access se trouve devant cette adresse.';

  @override
  String get ng_check_the_service_token_and_its =>
      'Vérifiez le jeton de service et sa règle Service Auth.';

  @override
  String get ng_add_a_cloudflare_access_service_token =>
      'Ajoutez un jeton de service Cloudflare Access pour cette adresse.';

  @override
  String get ng_the_server_asks_for_a_client =>
      'Le serveur demande un certificat client.';

  @override
  String get ng_pick_the_client_certificate_for_this =>
      'Sélectionnez le certificat client de cette passerelle, puis réessayez.';

  @override
  String get ng_needs_server_access_first =>
      'L\'accès au serveur est requis au préalable.';

  @override
  String get ng_needs_a_sign_in_first => 'Vous devez d\'abord vous connecter.';

  @override
  String ng_signed_in_as(Object name) {
    return 'Connecté en tant que $name.';
  }

  @override
  String get ng_this_dashboard_doesn_t_need_a =>
      'Ce tableau de bord ne nécessite pas de connexion.';

  @override
  String get ng_the_saved_sign_in_has_expired =>
      'La connexion enregistrée a expiré.';

  @override
  String get ng_sign_in_again => 'Reconnectez-vous.';

  @override
  String get ng_too_many_sign_in_attempts => 'Trop de tentatives de connexion.';

  @override
  String get ng_wait_a_minute_then_check_again =>
      'Attendez une minute, puis réessayez.';

  @override
  String ng_the_gateway_answered(Object message) {
    return 'La passerelle a répondu : $message.';
  }

  @override
  String get ng_sign_in_again_or_update_hermes =>
      'Reconnectez-vous ou mettez Hermes à jour.';

  @override
  String ng_couldn_t_check_the_sign_in(Object error) {
    return 'Impossible de vérifier la connexion : $error';
  }

  @override
  String ng_the_gateway_wouldn_t_issue_a(Object message) {
    return 'La passerelle n\'a pas voulu émettre de ticket de chat ($message).';
  }

  @override
  String get ng_the_chat_connection_opened_and_the =>
      'La connexion au chat est ouverte et la passerelle indique qu\'elle est prête.';

  @override
  String get ng_the_gateway_never_said_it_was =>
      'La passerelle n\'a jamais indiqué qu\'elle était prête.';

  @override
  String get ng_check_that_the_agent_is_running =>
      'Vérifiez que l\'agent est en cours d\'exécution sur le serveur.';

  @override
  String get ng_the_gateway_refused_the_chat_connection =>
      'La passerelle a refusé la connexion au chat (HTTP 403).';

  @override
  String get ng_this_dashboard_has_no_chat_endpoint =>
      'Ce tableau de bord n\'a pas de point de terminaison de chat (/api/ws).';

  @override
  String ng_the_chat_connection_failed(Object detail) {
    return 'La connexion au chat a échoué : $detail';
  }

  @override
  String get ng_use_the_exact_address_the_dashboard =>
      'Utilisez l\'adresse exacte configurée pour le tableau de bord.';

  @override
  String get ng_update_hermes => 'Mettez Hermes à jour.';

  @override
  String get ng_make_sure_the_proxy_allows_websocket =>
      'Vérifiez que le proxy autorise les mises à niveau WebSocket sur /api/ws.';

  @override
  String get ng_offline => 'Hors ligne';

  @override
  String get ng_connecting => 'Connexion…';

  @override
  String get ng_connected => 'Connecté';

  @override
  String get ng_reconnecting => 'Reconnexion…';

  @override
  String get ng_signed_out => 'Déconnecté';

  @override
  String get ng_connection_failed => 'Échec de la connexion';

  @override
  String get ng_rate_limited_by_gateway =>
      'Limite de requêtes atteinte auprès de la passerelle';

  @override
  String ng_couldn_t_open_the_chat_connection(Object message) {
    return 'Impossible d’ouvrir la connexion au chat : $message';
  }

  @override
  String get ng_the_gateway_returned_no_websocket_ticket =>
      'La passerelle n’a renvoyé aucun ticket WebSocket.';

  @override
  String get ng_connection_lost => 'Connexion perdue';

  @override
  String get ng_this_dashboard_has_no_chat_endpoint_2 =>
      'Ce tableau de bord n’a pas de point de terminaison pour le chat (/api/ws). Mettez Hermes à jour.';

  @override
  String get ng_the_gateway_refused_the_chat_connection_2 =>
      'La passerelle a refusé la connexion au chat. Vérifiez que l’adresse correspond à l’hôte configuré pour le tableau de bord et que le chat intégré est activé.';

  @override
  String ng_the_gateway_refused(Object method) {
    return 'La passerelle a refusé $method.';
  }

  @override
  String ng_couldn_t_read_your_saved_gateways(Object error) {
    return 'Impossible de lire vos passerelles enregistrées : $error';
  }

  @override
  String get ng_applies_to_new_chats => 'S’applique aux nouveaux chats';

  @override
  String ng_couldn_t_change(Object label, Object error) {
    return 'Impossible de modifier $label : $error';
  }

  @override
  String get ng_capabilities => 'Capacités';

  @override
  String get ng_skills => 'Compétences';

  @override
  String get ng_toolsets => 'Ensembles d’outils';

  @override
  String get ng_search => 'Rechercher';

  @override
  String get ng_couldn_t_load => 'Impossible de charger';

  @override
  String get ng_try_again => 'Réessayer';

  @override
  String get ng_no_skills => 'Aucune compétence';

  @override
  String get ng_no_toolsets => 'Aucun ensemble d’outils';

  @override
  String get ng_no_mcp_servers => 'Aucun serveur MCP';

  @override
  String get ng_that_file_is_too_large_to =>
      'Ce fichier est trop volumineux pour être un certificat.';

  @override
  String ng_the_certificate_couldn_t_be_imported(Object error) {
    return 'Impossible d’importer le certificat : $error';
  }

  @override
  String get ng_now_pick_its_private_key =>
      'Choisissez maintenant sa clé privée.';

  @override
  String get ng_now_pick_its_certificate =>
      'Choisissez maintenant son certificat.';

  @override
  String get ng_that_file_isn_t_a_certificate =>
      'Ce fichier n’est ni un certificat ni une clé privée.';

  @override
  String get ng_if_a_proxy_in_front_of =>
      'Si un proxy situé devant cette adresse demande un certificat client, choisissez-le ici pour que le test, la connexion et le chat le présentent.';

  @override
  String get ng_client_certificates_are_only_used_with =>
      'Les certificats client sont utilisés uniquement avec les adresses https://.';

  @override
  String get ng_remove => 'Supprimer';

  @override
  String get ng_certificate_password => 'Mot de passe du certificat';

  @override
  String get ng_importing => 'Importation…';

  @override
  String get ng_pick_certificate => 'Choisir un certificat';

  @override
  String get ng_pick_a_different_certificate => 'Choisir un autre certificat';

  @override
  String get ng_accepts_p12_pfx_or_pem_certificate =>
      'Accepte les fichiers .p12/.pfx, ou les fichiers de certificat et de clé PEM. La clé reste dans le stockage privé de cette app.';

  @override
  String get ng_photos => 'Photos';

  @override
  String get ng_camera => 'Appareil photo';

  @override
  String get ng_files => 'Fichiers';

  @override
  String ng_you_can_attach_up_to_files(Object count) {
    return 'Vous pouvez joindre jusqu’à $count fichiers.';
  }

  @override
  String ng_couldn_t_read(Object name) {
    return 'Impossible de lire $name.';
  }

  @override
  String ng_couldn_t_prepare_that_file(Object error) {
    return 'Impossible de préparer ce fichier : $error';
  }

  @override
  String get ng_hermes_is_still_working => 'Hermes travaille encore';

  @override
  String get ng_steer => 'Orienter';

  @override
  String get ng_adds_this_to_the_running_turn =>
      'Ajoute ceci au tour en cours à l’étape suivante';

  @override
  String get ng_queue => 'Mettre en file d’attente';

  @override
  String get ng_sends_it_when_the_turn_finishes =>
      'Envoie ceci à la fin du tour';

  @override
  String get ng_stop_and_send => 'Arrêter et envoyer';

  @override
  String get ng_stops_the_turn_then_sends_this =>
      'Arrête le tour, puis envoie ceci';

  @override
  String ng_dictation_stopped(Object message) {
    return 'Dictée arrêtée : $message';
  }

  @override
  String get ng_speech_recognition_isn_t_available =>
      'La reconnaissance vocale n’est pas disponible.';

  @override
  String get ng_working => 'En cours';

  @override
  String get ng_ready => 'Prêt';

  @override
  String get ng_chats => 'Chats';

  @override
  String get ng_new_chat => 'Nouveau chat';

  @override
  String get ng_usage => 'Utilisation';

  @override
  String get ng_rename_chat => 'Renommer le chat';

  @override
  String ng_couldn_t_rename(Object error) {
    return 'Impossible de renommer : $error';
  }

  @override
  String get ng_this_chat => 'Ce chat';

  @override
  String get ng_input_tokens => 'Jetons d’entrée';

  @override
  String get ng_output_tokens => 'Jetons de sortie';

  @override
  String get ng_reasoning_tokens => 'Jetons de raisonnement';

  @override
  String get ng_cache_reads => 'Lectures du cache';

  @override
  String get ng_api_calls => 'Appels API';

  @override
  String get ng_cost => 'Coût';

  @override
  String get ng_context => 'Contexte';

  @override
  String get ng_your_sign_in_expired => 'Votre session a expiré.';

  @override
  String get ng_sign_in_2 => 'Se connecter';

  @override
  String get ng_retry => 'Réessayer';

  @override
  String get ng_what_should_we_work_on => 'Sur quoi voulez-vous travailler ?';

  @override
  String get ng_ask_hermes_anything_it_can_run =>
      'Demandez ce que vous voulez à Hermes. Il peut utiliser des outils, naviguer sur le Web et travailler sur vos fichiers sur le serveur.';

  @override
  String ng_working_2(Object frame) {
    return 'En cours · $frame';
  }

  @override
  String get ng_default_model => 'Modèle par défaut';

  @override
  String get ng_listening => 'Écoute…';

  @override
  String get ng_steer_or_queue_a_message =>
      'Orientez Hermes ou mettez un message en attente';

  @override
  String get ng_message_hermes => 'Envoyer un message à Hermes';

  @override
  String get ng_attach => 'Joindre';

  @override
  String get ng_stop_dictation => 'Arrêter la dictée';

  @override
  String get ng_dictate => 'Dicter';

  @override
  String get ng_stop => 'Arrêter';

  @override
  String get ng_send => 'Envoyer';

  @override
  String get ng_steered => 'Orienté';

  @override
  String get ng_copied => 'Copié';

  @override
  String ng_not_sent(Object reason) {
    return 'Non envoyé : $reason';
  }

  @override
  String get ng_thinking => 'Réflexion…';

  @override
  String get ng_thought => 'Réflexion';

  @override
  String ng_used(Object name) {
    return 'A utilisé $name';
  }

  @override
  String ng_used_tools(Object count) {
    return 'A utilisé $count outils';
  }

  @override
  String get ng_copy => 'Copier';

  @override
  String get ng_the_gateway_connection_dropped_try_again =>
      'La connexion à la passerelle a été interrompue. Réessayez.';

  @override
  String get ng_allow_once => 'Autoriser une fois';

  @override
  String get ng_allow_for_this_chat => 'Autoriser pour cette conversation';

  @override
  String get ng_always_allow => 'Toujours autoriser';

  @override
  String get ng_deny => 'Refuser';

  @override
  String get ng_your_answer => 'Votre réponse';

  @override
  String get ng_or_type_an_answer => 'Ou saisissez une réponse';

  @override
  String get ng_skip => 'Ignorer';

  @override
  String get ng_answer => 'Répondre';

  @override
  String get ng_cancel => 'Annuler';

  @override
  String get ng_username_or_email => 'Nom d’utilisateur ou e-mail';

  @override
  String get ng_password => 'Mot de passe';

  @override
  String get ng_not_now => 'Pas maintenant';

  @override
  String get ng_save => 'Enregistrer';

  @override
  String get ng_enter_both_the_client_id_and =>
      'Saisissez l’ID client et le secret client, ou ne saisissez ni l’un ni l’autre.';

  @override
  String get ng_enter_your_username_and_password =>
      'Saisissez votre nom d’utilisateur et votre mot de passe.';

  @override
  String ng_couldn_t_save_the_sign_in(Object error) {
    return 'Impossible d’enregistrer les identifiants : $error';
  }

  @override
  String get ng_wrong_username_or_password =>
      'Nom d’utilisateur ou mot de passe incorrect.';

  @override
  String get ng_too_many_attempts_wait_a_moment =>
      'Trop de tentatives. Attendez un instant, puis réessayez.';

  @override
  String get ng_welcome_to_hermes => 'Bienvenue sur Ares';

  @override
  String get ng_add_a_gateway => 'Ajouter une passerelle';

  @override
  String get ng_connect_to_your_hermes_agent_dashboard =>
      'Connectez-vous au tableau de bord de votre Hermes Agent. Une adresse et une connexion vous donnent accès à vos conversations, outils et paramètres. Rien n’est envoyé avant votre connexion.';

  @override
  String get ng_connect_to_another_hermes_agent_dashboard =>
      'Connectez-vous à un autre tableau de bord Hermes Agent. Vous restez connecté aux tableaux de bord que vous avez enregistrés.';

  @override
  String get ng_dashboard_address => 'Adresse du tableau de bord';

  @override
  String get ng_testing => 'Test en cours…';

  @override
  String get ng_test => 'Tester';

  @override
  String get ng_where_your_hermes_dashboard_runs_lan =>
      'Adresse de votre tableau de bord Hermes : réseau local, Tailscale ou HTTPS.';

  @override
  String get ng_find_on_my_network => 'Rechercher sur mon réseau';

  @override
  String get ng_which_address_do_i_use => 'Quelle adresse utiliser ?';

  @override
  String get ng_behind_cloudflare_access => 'Derrière Cloudflare Access ?';

  @override
  String get ng_need_a_client_certificate => 'Besoin d’un certificat client ?';

  @override
  String get ng_this_address_isn_t_private_and =>
      'Cette adresse n’est pas privée et n’utilise pas https://. Votre mot de passe et vos conversations circuleraient donc sur Internet sans chiffrement. Utilisez plutôt https://, Tailscale ou votre propre réseau.';

  @override
  String get ng_continue_to_sign_in => 'Continuer la connexion';

  @override
  String get ng_use_the_classic_interface_instead =>
      'Utiliser plutôt l’interface classique';

  @override
  String get ng_if_cloudflare_access_protects_this_address =>
      'Si Cloudflare Access protège cette adresse, créez un jeton de service dans Cloudflare Zero Trust (Access, Service credentials), puis ajoutez une règle Service Auth à l’application Access.';

  @override
  String get ng_a_service_token_is_saved_for =>
      'Un jeton de service est enregistré pour cette adresse';

  @override
  String get ng_forget => 'Oublier';

  @override
  String get ng_client_id => 'ID client';

  @override
  String get ng_client_secret => 'Secret client';

  @override
  String get ng_stored_encrypted_on_this_phone_and =>
      'Stockés de façon chiffrée sur ce téléphone et envoyés uniquement à cette adresse.';

  @override
  String get ng_hermes_is_reachable => 'Hermes est accessible';

  @override
  String ng_hermes_is_reachable_2(Object version) {
    return 'Hermes $version est accessible';
  }

  @override
  String get ng_sign_in_is_tested_next_then =>
      'La connexion est testée ensuite, puis le chat';

  @override
  String get ng_agent_gateway => 'Passerelle d’agent';

  @override
  String get ng_running => 'En cours';

  @override
  String get ng_stopped => 'Arrêté';

  @override
  String get ng_username_password => 'Nom d’utilisateur et mot de passe';

  @override
  String get ng_browser => 'Navigateur';

  @override
  String get ng_in_the_browser_sso => 'Dans le navigateur (SSO)';

  @override
  String get ng_profiles => 'Profils';

  @override
  String get ng_this_dashboard_offers_neither_a_username =>
      'Ce tableau de bord ne propose ni connexion par nom d’utilisateur et mot de passe, ni connexion dans le navigateur. Mettez Hermes à jour ou configurez le fournisseur de nom d’utilisateur et mot de passe sur le serveur.';

  @override
  String get ng_the_auth_gate_is_off_on =>
      'Le contrôle d’accès est désactivé sur ce tableau de bord. Toute personne qui peut y accéder peut utiliser votre agent.';

  @override
  String get ng_couldn_t_reach_the_dashboard =>
      'Impossible de joindre le tableau de bord';

  @override
  String ng_check_the_address_and_port_9119(Object reason) {
    return '$reason\n\nVérifiez l’adresse et le port (9119 par défaut). Si le tableau de bord n’est pas encore lancé, exécutez cette commande sur le serveur :\nhermes dashboard --host 0.0.0.0';
  }

  @override
  String get ng_that_isn_t_a_hermes_dashboard =>
      'Ce n’est pas un tableau de bord Hermes';

  @override
  String get ng_something_answered_but_not_a_hermes_2 =>
      'Une réponse a été reçue, mais ce n’est pas un tableau de bord Hermes. Utilisez l’adresse du tableau de bord, pas celle du serveur API (port 8642).';

  @override
  String ng_something_answered_http_but_not_a_2(Object status) {
    return 'Une réponse a été reçue (HTTP $status), mais ce n’est pas un tableau de bord Hermes. Utilisez l’adresse du tableau de bord, pas celle du serveur API (port 8642).';
  }

  @override
  String get ng_cloudflare_access_stopped_the_request =>
      'Cloudflare Access a bloqué la requête';

  @override
  String ng_cloudflare_access_turned_down_the_service(Object status) {
    return 'Cloudflare Access a refusé le jeton de service (HTTP $status). Vérifiez le Client ID, le Secret et la règle Service Auth.';
  }

  @override
  String get ng_add_a_cloudflare_access_service_token_2 =>
      'Ajoutez un jeton de service Cloudflare Access ci-dessous, puis réessayez.';

  @override
  String get ng_a_client_certificate_is_needed =>
      'Un certificat client est requis';

  @override
  String get ng_this_server_asks_for_a_client =>
      'Ce serveur demande un certificat client avant toute communication. Sélectionnez ci-dessous celui qu’il vous a fourni, puis réessayez.';

  @override
  String get ng_this_dashboard_doesn_t_ask_for =>
      'Ce tableau de bord ne demande pas de connexion.';

  @override
  String ng_use_the_dashboard_username_and_password(Object address) {
    return 'Utilisez le nom d’utilisateur et le mot de passe configurés pour le tableau de bord sur $address, ou connectez-vous dans votre navigateur.';
  }

  @override
  String ng_use_the_dashboard_username_and_password_2(Object address) {
    return 'Utilisez le nom d’utilisateur et le mot de passe configurés pour le tableau de bord sur $address.';
  }

  @override
  String ng_sign_in_to_in_your_browser(Object address) {
    return 'Connectez-vous à $address dans votre navigateur avec le compte utilisé par son tableau de bord.';
  }

  @override
  String ng_gateway(Object address) {
    return 'Passerelle $address';
  }

  @override
  String get ng_profile => 'Profil';

  @override
  String get ng_server_default => 'Valeur par défaut du serveur';

  @override
  String get ng_continue => 'Continuer';

  @override
  String get ng_username => 'Nom d’utilisateur';

  @override
  String get ng_signing_in => 'Connexion…';

  @override
  String get ng_waiting_for_the_browser => 'En attente du navigateur…';

  @override
  String get ng_sign_in_with_browser => 'Se connecter avec le navigateur';

  @override
  String get ng_finish_signing_in_on_the_page =>
      'Terminez la connexion sur la page qui s’est ouverte. Hermes reviendra automatiquement une fois terminé.';

  @override
  String get ng_use_a_different_gateway => 'Utiliser une autre passerelle';

  @override
  String get ng_same_wi_fi_or_local_network => 'Même Wi-Fi ou réseau local';

  @override
  String get ng_use_the_server_s_local_address =>
      'Utilisez l’adresse locale et le port du serveur, par exemple 192.168.1.20:9119. Lancez le tableau de bord avec --host 0.0.0.0 pour que d’autres appareils puissent y accéder.';

  @override
  String get ng_tailscale => 'Tailscale';

  @override
  String get ng_turn_on_tailscale_on_this_phone =>
      'Activez Tailscale sur ce téléphone et utilisez l’adresse Tailscale du serveur, par exemple 100.64.0.1:9119 ou son nom .ts.net. Fonctionne aussi en dehors de chez vous.';

  @override
  String get ng_use_your_https_address_when_the =>
      'Utilisez votre adresse https:// si le tableau de bord se trouve derrière un proxy avec un certificat. Le proxy doit aussi transmettre les mises à niveau WebSocket sur /api/ws.';

  @override
  String get ng_start_the_dashboard_on_the_server =>
      'Lancez le tableau de bord sur le serveur :';

  @override
  String get ng_enter_a_port_from_1_to =>
      'Saisissez un port compris entre 1 et 65535.';

  @override
  String get ng_looks_for_hermes_dashboards_on_port =>
      'Recherche les tableaux de bord Hermes sur le port 9119 de ce réseau Wi-Fi et vérifie les ordinateurs déjà enregistrés.';

  @override
  String ng_looks_for_hermes_dashboards_on_ports(Object port) {
    return 'Recherche les tableaux de bord Hermes sur les ports 9119 et $port de ce réseau Wi-Fi et vérifie les ordinateurs déjà enregistrés.';
  }

  @override
  String get ng_other_port_optional => 'Autre port (facultatif)';

  @override
  String get ng_no_dashboards_answered_start_one_with =>
      'Aucun tableau de bord n’a répondu. Lancez-en un avec hermes dashboard --host 0.0.0.0, ou saisissez son adresse.';

  @override
  String get ng_using_tailscale_or_a_vpn_those =>
      'Vous utilisez Tailscale ou un VPN ? Ces réseaux ne peuvent pas être explorés. Saisissez plutôt l’adresse 100.x de l’ordinateur ou son nom .ts.net.';

  @override
  String get ng_search_again => 'Rechercher à nouveau';

  @override
  String get ng_insights => 'Statistiques';

  @override
  String get ng_couldn_t_load_insights =>
      'Impossible de charger les statistiques';

  @override
  String get ng_sessions => 'Sessions';

  @override
  String get ng_tokens => 'Tokens';

  @override
  String get ng_est_cost => 'Coût estimé';

  @override
  String get ng_daily_tokens => 'Tokens quotidiens';

  @override
  String get ng_models => 'Modèles';

  @override
  String get ng_tools => 'Outils';

  @override
  String get ng_hermes_is_waiting_for_you => 'Hermes vous attend.';

  @override
  String get ng_hermes_replied => 'Hermes a répondu';

  @override
  String get ng_the_turn_finished => 'Le tour est terminé.';

  @override
  String get ng_off => 'Désactivé';

  @override
  String get ng_minimal => 'Minimal';

  @override
  String get ng_low => 'Faible';

  @override
  String get ng_medium => 'Moyen';

  @override
  String get ng_high => 'Élevé';

  @override
  String get ng_extra_high => 'Très élevé';

  @override
  String get ng_max => 'Max';

  @override
  String get ng_ultra => 'Ultra';

  @override
  String get ng_default => 'Par défaut';

  @override
  String ng_couldn_t_switch_model(Object error) {
    return 'Impossible de changer de modèle : $error';
  }

  @override
  String get ng_model => 'Modèle';

  @override
  String get ng_thinking_2 => 'Réflexion';

  @override
  String get ng_search_models => 'Rechercher des modèles';

  @override
  String ng_couldn_t_load_models(Object error) {
    return 'Impossible de charger les modèles : $error';
  }

  @override
  String get ng_no_providers_are_set_up_on =>
      'Aucun fournisseur n’est encore configuré sur cette passerelle.';

  @override
  String get ng_starred => 'Favoris';

  @override
  String get ng_recent => 'Récents';

  @override
  String get ng_more => 'Plus';

  @override
  String get ng_archived_chats => 'Conversations archivées';

  @override
  String get ng_projects => 'Projets';

  @override
  String get ng_chats_grouped_by_project_and_workspace =>
      'Conversations regroupées par projet et espace de travail';

  @override
  String get ng_agent => 'Agent';

  @override
  String get ng_memory => 'Mémoire';

  @override
  String get ng_what_hermes_remembers_about_you =>
      'Ce que Hermes retient de vous';

  @override
  String get ng_skills_library => 'Bibliothèque de compétences';

  @override
  String get ng_browse_and_read_installed_skills =>
      'Parcourir et lire les compétences installées';

  @override
  String get ng_cron_editor => 'Éditeur cron';

  @override
  String get ng_edit_schedules_prompts_and_delivery =>
      'Modifier les planifications, les instructions et les envois';

  @override
  String get ng_config_file => 'Fichier de configuration';

  @override
  String get ng_edit_config_yaml_on_the_gateway =>
      'Modifier config.yaml sur la passerelle';

  @override
  String get ng_models_and_providers => 'Modèles et fournisseurs';

  @override
  String get ng_model_management => 'Gestion des modèles';

  @override
  String get ng_default_fallback_and_auxiliary_models =>
      'Modèles par défaut, de secours et auxiliaires';

  @override
  String get ng_provider_sign_in => 'Connexion aux fournisseurs';

  @override
  String get ng_connect_provider_accounts_with_oauth =>
      'Connecter des comptes fournisseurs avec OAuth';

  @override
  String get ng_nous_portal => 'Nous Portal';

  @override
  String get ng_subscription_credits_and_usage =>
      'Abonnement, crédits et utilisation';

  @override
  String get ng_interface => 'Interface';

  @override
  String get ng_switch_to_the_classic_interface =>
      'Passer à l’interface classique';

  @override
  String get ng_turns_nextgen_off_you_can_turn =>
      'Désactive NextGen. Vous pourrez le réactiver dans les paramètres.';

  @override
  String get ng_restored => 'Restauré';

  @override
  String get ng_archived => 'Archivé';

  @override
  String get ng_couldn_t_load_archived_chats =>
      'Impossible de charger les conversations archivées';

  @override
  String get ng_nothing_archived => 'Aucune conversation archivée';

  @override
  String get ng_restore => 'Restaurer';

  @override
  String get ng_saved_new_chats_use_it =>
      'Enregistré. Les nouvelles conversations l’utiliseront.';

  @override
  String ng_couldn_t_save(Object error) {
    return 'Impossible d’enregistrer : $error';
  }

  @override
  String get ng_saving => 'Enregistrement…';

  @override
  String ng_today(Object time) {
    return 'Aujourd’hui $time';
  }

  @override
  String get ng_mon => 'lun.';

  @override
  String get ng_tue => 'mar.';

  @override
  String get ng_wed => 'mer.';

  @override
  String get ng_thu => 'jeu.';

  @override
  String get ng_fri => 'ven.';

  @override
  String get ng_sat => 'sam.';

  @override
  String get ng_sun => 'dim.';

  @override
  String get ng_scheduled => 'Planifié';

  @override
  String get ng_new_job => 'Nouvelle tâche';

  @override
  String get ng_couldn_t_load_scheduled_jobs =>
      'Impossible de charger les tâches planifiées';

  @override
  String get ng_nothing_scheduled => 'Aucune tâche planifiée';

  @override
  String get ng_ask_hermes_to_do_something_on =>
      'Demandez à Hermes d’effectuer une tâche selon un calendrier, ou ajoutez-en une ici.';

  @override
  String get ng_active => 'Actif';

  @override
  String get ng_paused => 'En pause';

  @override
  String ng_next(Object when) {
    return 'Prochaine occurrence : $when';
  }

  @override
  String ng_last(Object when) {
    return 'Dernière occurrence : $when';
  }

  @override
  String ng_last_2(Object when, Object result) {
    return 'Dernière occurrence : $when · $result';
  }

  @override
  String ng_job(Object id) {
    return 'Tâche $id';
  }

  @override
  String get ng_delete => 'Supprimer';

  @override
  String get ng_delete_this_job => 'Supprimer cette tâche ?';

  @override
  String get ng_it_stops_running_past_runs_stay =>
      'Elle cessera de s’exécuter. Les exécutions passées resteront dans vos conversations.';

  @override
  String ng_next_run(Object when) {
    return 'Prochaine exécution : $when';
  }

  @override
  String ng_delivers_to(Object target) {
    return 'Envoi à $target';
  }

  @override
  String get ng_run_now => 'Exécuter maintenant';

  @override
  String get ng_started => 'Démarré';

  @override
  String get ng_pause => 'Mettre en pause';

  @override
  String get ng_resume => 'Reprendre';

  @override
  String get ng_resumed => 'Repris';

  @override
  String get ng_prompt => 'Instruction';

  @override
  String get ng_runs => 'Exécutions';

  @override
  String get ng_no_runs_yet => 'Aucune exécution pour le moment.';

  @override
  String get ng_enter_a_schedule_and_a_prompt =>
      'Saisissez une planification et une instruction.';

  @override
  String get ng_name_optional => 'Nom (facultatif)';

  @override
  String get ng_schedule => 'Planification';

  @override
  String get ng_every_1h_0_9_or_30m => 'every 1h, 0 9 * * *, or 30m';

  @override
  String get ng_create => 'Créer';

  @override
  String get ng_unpin => 'Désépingler';

  @override
  String get ng_pin => 'Épingler';

  @override
  String get ng_rename => 'Renommer';

  @override
  String get ng_archive => 'Archiver';

  @override
  String get ng_delete_this_chat => 'Supprimer cette discussion ?';

  @override
  String get ng_it_is_removed_from_the_gateway =>
      'Elle sera supprimée de la passerelle sur tous les appareils.';

  @override
  String get ng_search_chats => 'Rechercher des discussions';

  @override
  String get ng_pinned => 'Épinglées';

  @override
  String get ng_no_chats_match => 'Aucune discussion correspondante.';

  @override
  String get ng_no_chats_yet => 'Aucune discussion pour le moment.';

  @override
  String get ng_nothing_is_running => 'Aucune tâche en cours.';

  @override
  String get ng_nothing_is_waiting_on_you =>
      'Aucune action n’est requise de votre part.';

  @override
  String get ng_settings => 'Paramètres';

  @override
  String get ng_all => 'Tout';

  @override
  String ng_needs_you(Object count) {
    return 'À traiter · $count';
  }

  @override
  String get ng_needs_you_2 => 'À traiter';

  @override
  String get ng_gateways => 'Passerelles';

  @override
  String ng_classic_connection(Object address) {
    return '$address · connexion classique';
  }

  @override
  String get ng_gateway_2 => 'Passerelle';

  @override
  String get ng_signed_in => 'Session ouverte';

  @override
  String get ng_classic_connection_2 => 'Connexion classique';

  @override
  String get ng_in_the_browser => 'Dans le navigateur';

  @override
  String ng_in_the_browser_as(Object name) {
    return 'Dans le navigateur en tant que $name';
  }

  @override
  String get ng_not_required => 'Non requis';

  @override
  String get ng_test_connection => 'Tester la connexion';

  @override
  String get ng_sign_in_again_2 => 'Se reconnecter';

  @override
  String get ng_sign_out => 'Se déconnecter';

  @override
  String get ng_saved_gateways => 'Passerelles enregistrées';

  @override
  String get ng_in_use => 'Utilisée';

  @override
  String get ng_appearance => 'Apparence';

  @override
  String get ng_theme => 'Thème';

  @override
  String get ng_system => 'Système';

  @override
  String get ng_light => 'Clair';

  @override
  String get ng_dark => 'Sombre';

  @override
  String get ng_accent => 'Couleur d’accentuation';

  @override
  String get ng_pure_black => 'Noir pur';

  @override
  String get ng_dark_theme_uses_true_black_oled =>
      'Le thème sombre utilise un vrai noir (OLED)';

  @override
  String get ng_glow => 'Halo';

  @override
  String get ng_soft_accent_light_behind_each_screen =>
      'Une douce lueur d’accentuation derrière chaque écran';

  @override
  String get ng_the_new_interface_turn_off_to =>
      'La nouvelle interface. Désactivez-la pour revenir à l’interface classique ; vos passerelles et vos discussions sont partagées.';

  @override
  String get ng_more_settings => 'Plus de paramètres';

  @override
  String get ng_voice_notifications_language_backups_and_the =>
      'Voix, notifications, langue, sauvegardes et configuration de la passerelle';

  @override
  String get ng_licences => 'Licences';

  @override
  String ng_sign_out_of(Object name) {
    return 'Se déconnecter de $name ?';
  }

  @override
  String get ng_this_gateway_and_its_saved_sign =>
      'Cette passerelle et ses informations de connexion enregistrées seront supprimées de ce téléphone, dans les deux interfaces. Vos discussions restent sur la passerelle.';

  @override
  String get ng_password_or_browser => 'Mot de passe ou navigateur';

  @override
  String get ng_unsupported => 'Non pris en charge';

  @override
  String get ng_background_task_finished => 'Tâche en arrière-plan terminée';

  @override
  String get ng_background_process_finished =>
      'Processus en arrière-plan terminé';

  @override
  String get ng_system_message => 'Message système';

  @override
  String get classic_interface_only => 'Interface classique uniquement';

  @override
  String get classic_only_settings_hint =>
      'Les sections marquées « Interface classique uniquement » modifient uniquement l’apparence et les discussions de l’interface classique, pas celles de NextGen. NextGen dispose de ses propres options d’apparence dans ses paramètres.';

  @override
  String get attachment_preview_too_large =>
      'Aperçu trop volumineux. Enregistrez ou partagez le fichier pour le télécharger sur votre téléphone (jusqu’à 1 Go).';

  @override
  String get attachment_over_phone_limit =>
      'Ce fichier dépasse 1 Go et la limite de téléchargement. Ouvrez le tableau de bord pour le télécharger.';

  @override
  String attachment_downloading_percent(int percent) {
    return 'Téléchargement… $percent %';
  }

  @override
  String attachment_downloading_mb(int megabytes) {
    return 'Téléchargement… $megabytes Mo';
  }

  @override
  String ng_attachment_too_large_for_gateway(String name) {
    return '$name dépasse la limite de 12 Mo de cette passerelle. Mettez Hermes à jour pour envoyer des fichiers jusqu’à 100 Mo.';
  }

  @override
  String ng_couldn_t_upload(String name) {
    return 'Impossible d’importer $name.';
  }

  @override
  String ng_uploading_percent(int percent) {
    return 'Importation… $percent %';
  }

  @override
  String get ng_show_tasks => 'Afficher les tâches';

  @override
  String get ng_hide_tasks => 'Masquer les tâches';

  @override
  String get ng_goal => 'Objectif';

  @override
  String get ng_loop => 'Boucle';

  @override
  String get ng_heartbeat => 'Rappel périodique';

  @override
  String get ng_goal_working => 'En cours';

  @override
  String get ng_goal_waiting => 'En attente';

  @override
  String get ng_goal_blocked => 'Bloqué';

  @override
  String get ng_goal_done => 'Terminé';

  @override
  String ng_goal_turns_of(int used, int max) {
    return '$used tours sur $max';
  }

  @override
  String ng_goal_turn(int used) {
    return 'tour $used';
  }

  @override
  String get ng_loop_held => 'En pause pour l’objectif';

  @override
  String get ng_loop_finished => 'Terminée';

  @override
  String get ng_loop_running => 'En cours';

  @override
  String ng_loop_runs_of(int fired, int times) {
    return '$fired exécutions sur $times';
  }

  @override
  String ng_loop_runs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exécutions',
      one: '1 exécution',
    );
    return '$_temp0';
  }

  @override
  String ng_loop_next(String time) {
    return 'prochaine : $time';
  }

  @override
  String get ng_loop_due_now => 'prévue maintenant';

  @override
  String ng_every_seconds(int seconds) {
    return 'toutes les $seconds s';
  }

  @override
  String ng_every_minutes(int minutes) {
    return 'toutes les $minutes min';
  }

  @override
  String ng_every_hours(int hours) {
    return 'toutes les $hours h';
  }

  @override
  String ng_every_hours_minutes(int hours, int minutes) {
    return 'toutes les $hours h et $minutes min';
  }

  @override
  String ng_heartbeat_fired(int count) {
    return '$count déclenchements';
  }

  @override
  String ng_heartbeat_last_fired(String time) {
    return 'Dernier déclenchement à $time';
  }

  @override
  String ng_wait_until(String time) {
    return 'En attente jusqu’à $time';
  }

  @override
  String get ng_wait_resume => 'En attente de reprise';

  @override
  String get ng_wait_other_chat => 'En attente d’une autre conversation';

  @override
  String ng_wait_process(String pid) {
    return 'En attente du processus $pid';
  }

  @override
  String get ng_control_open => 'Ouvrir les objectifs et l’automatisation';

  @override
  String get ng_control_title => 'Objectif et automatisation';

  @override
  String get ng_control_subtitle =>
      'Ce que cette conversation cherche à accomplir et ce qui s’exécute automatiquement.';

  @override
  String get ng_contract_outcome => 'Résultat';

  @override
  String get ng_contract_verification => 'Vérification';

  @override
  String get ng_contract_constraints => 'Contraintes';

  @override
  String get ng_contract_boundaries => 'Limites';

  @override
  String get ng_contract_stop_when => 'Arrêter lorsque';

  @override
  String get ng_subgoals => 'Sous-objectifs';

  @override
  String get ng_subgoal_add_placeholder => 'Ajouter un sous-objectif';

  @override
  String get ng_add => 'Ajouter';

  @override
  String get ng_subgoal_remove => 'Supprimer le sous-objectif';

  @override
  String get ng_goal_checks => 'Vérifications';

  @override
  String get ng_gate_not_run => 'Pas encore exécuté';

  @override
  String ng_gate_attempts(int attempts, int tries) {
    return '$attempts tentatives sur $tries';
  }

  @override
  String ng_gate_exit(int code) {
    return 'code de sortie $code';
  }

  @override
  String get ng_resume_now => 'Reprendre maintenant';

  @override
  String get ng_goal_clear => 'Effacer l’objectif';

  @override
  String get ng_goal_clear_title => 'Effacer cet objectif ?';

  @override
  String get ng_goal_clear_message =>
      'L’agent cessera de travailler sur cet objectif. Ses sous-objectifs et ses vérifications seront également supprimés.';

  @override
  String get ng_subgoal_remove_title => 'Supprimer ce sous-objectif ?';

  @override
  String ng_subgoal_remove_message(String text) {
    return '« $text » ne fera plus partie de l’objectif.';
  }

  @override
  String get ng_subgoals_clear_title => 'Effacer tous les sous-objectifs ?';

  @override
  String get ng_subgoals_clear_message =>
      'L’objectif conservera son titre, mais tous ses sous-objectifs seront supprimés.';

  @override
  String get ng_clear_all => 'Tout effacer';

  @override
  String get ng_clear => 'Effacer';

  @override
  String get ng_dismiss => 'Fermer';

  @override
  String get ng_loop_stop_title => 'Arrêter cette boucle ?';

  @override
  String get ng_heartbeat_clear_title => 'Effacer ce rappel périodique ?';

  @override
  String get ng_wont_fire_again => 'Il ne se déclenchera plus.';

  @override
  String get ng_loop_self_paced => 'À son propre rythme';

  @override
  String ng_loop_until(String condition) {
    return 'Jusqu’à : $condition';
  }

  @override
  String get ng_loop_waits_for_goal =>
      'Attend pendant que l’objectif est en cours.';

  @override
  String get ng_loop_awaiting_reply => 'En attente de la réponse de l’agent.';

  @override
  String ng_loop_stopped_reason(String reason) {
    return 'Arrêtée : $reason';
  }

  @override
  String get ng_hide_subagents => 'Masquer les sous-agents';

  @override
  String get ng_show_subagents => 'Afficher les sous-agents';

  @override
  String get ng_subagent => 'Sous-agent';

  @override
  String get ng_subagent_queued => 'En file d’attente';

  @override
  String get ng_subagent_starting => 'Démarrage…';

  @override
  String get ng_subagent_running => 'En cours';

  @override
  String get ng_subagent_done => 'Terminé';

  @override
  String get ng_subagent_failed => 'Échec';

  @override
  String get ng_subagent_stopped => 'Arrêté';

  @override
  String get ng_subagent_stop => 'Arrêter le sous-agent';

  @override
  String ng_subagent_tools(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count outils',
      one: '1 outil',
    );
    return '$_temp0';
  }

  @override
  String get ng_mark_as_read => 'Marquer comme lu';

  @override
  String get ng_mark_as_unread => 'Marquer comme non lu';

  @override
  String ng_chats_unread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Conversations, $count non lues',
      one: 'Conversations, 1 non lue',
    );
    return '$_temp0';
  }

  @override
  String get ng_unread_finished => 'Terminé, réponse non lue';

  @override
  String get ng_unread_updates => 'En cours, mises à jour non lues';

  @override
  String get ng_notifications => 'Notifications';

  @override
  String get ng_notifications_hint =>
      'Réponses et demandes lorsque Ares est en arrière-plan';

  @override
  String get ng_notify_replies => 'Réponses';

  @override
  String get ng_notify_replies_hint =>
      'Lorsqu’un tour se termine ou échoue dans la conversation ouverte';

  @override
  String get ng_notify_requests => 'Autorisations et questions';

  @override
  String get ng_notify_requests_hint =>
      'Une notification lorsque l’agent attend votre réponse, avec les boutons « Autoriser une fois » et « Refuser »';

  @override
  String get ng_keep_running =>
      'Rester connecté pendant la génération d’une réponse';

  @override
  String get ng_keep_running_hint =>
      'Maintient la connexion en arrière-plan jusqu’à la fin de la réponse, avec une notification discrète';

  @override
  String get ng_battery_settings => 'Optimisation de la batterie';

  @override
  String get ng_battery_settings_hint =>
      'Autorisez Ares à fonctionner en arrière-plan pour recevoir les notifications à temps';

  @override
  String get ng_send_test_notification => 'Envoyer une notification de test';

  @override
  String get ng_test_notification_title =>
      'Les notifications Ares fonctionnent';

  @override
  String get ng_test_notification_body =>
      'Les réponses et les demandes s’afficheront ainsi.';

  @override
  String get ng_test_notification_sent => 'Notification de test envoyée';

  @override
  String get ng_notifications_blocked =>
      'Les notifications sont bloquées. Autorisez-les dans les paramètres Android.';

  @override
  String get ng_notifications_off_hint =>
      'Les notifications sont désactivées : rien ne s’affichera lorsque Ares sera en arrière-plan.';

  @override
  String get ng_insights_building =>
      'Création du rapport en cours. La première génération d’un rapport couvrant une longue période peut prendre jusqu’à une minute.';

  @override
  String get ng_insights_timed_out =>
      'La passerelle a mis trop de temps à générer ce rapport. Réessayez ou sélectionnez une période plus courte.';

  @override
  String get ng_dock_goal_active => 'Objectif en cours';

  @override
  String get ng_dock_goal_paused => 'Objectif en pause';

  @override
  String get ng_dock_goal_waiting => 'Objectif en attente';

  @override
  String get ng_dock_goal_blocked => 'Objectif bloqué';

  @override
  String get ng_dock_goal_done => 'Objectif terminé';

  @override
  String ng_dock_turn_of(int used, int max) {
    return 'Tour $used/$max';
  }

  @override
  String ng_dock_turn(int used) {
    return 'Tour $used';
  }

  @override
  String ng_dock_subagents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sous-agents',
      one: '1 sous-agent',
    );
    return '$_temp0';
  }

  @override
  String ng_dock_subagents_done(int count) {
    return '$count terminés';
  }

  @override
  String ng_dock_tasks(int done, int total) {
    return 'Tâches $done/$total';
  }

  @override
  String ng_dock_previous_tasks(int done, int total) {
    return 'Tâches précédentes $done/$total';
  }

  @override
  String get ng_dock_manage => 'Gérer';

  @override
  String get ng_recent_notifications => 'Notifications récentes';

  @override
  String get ng_recent_notifications_hint =>
      'Ce qu’Ares a tenté de publier et si Android l’a affiché';

  @override
  String get ng_recent_notifications_empty =>
      'Rien pour l’instant. Les tentatives apparaîtront ici dès qu’une réponse, une question ou un échec devrait vous envoyer une notification.';

  @override
  String get ng_notify_permission_granted => 'Autorisation accordée';

  @override
  String get ng_notify_permission_denied => 'Autorisation refusée';

  @override
  String get ng_notify_master_on => 'Notifications activées';

  @override
  String get ng_notify_master_off => 'Notifications désactivées';
}
