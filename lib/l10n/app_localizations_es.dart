// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      'Una pregunta puntual. Se archiva sola a las 72 horas; lo que valga la pena conservar seguirá en la memoria.';

  @override
  String get ai_full_text => 'IA + texto completo';

  @override
  String get ai_search_model => 'Modelo de búsqueda con IA';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'La IA buscó: $aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'Archivado asistido por IA';

  @override
  String get api_key => 'Clave de API';

  @override
  String get api_server_key_from_hermes_env =>
      'API_SERVER_KEY de ~/.hermes/.env';

  @override
  String get active => 'Activo';

  @override
  String get activity => 'Actividad';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      'La actividad lee el diario de turnos persistente para saber qué está haciendo Hermes. Comprueba que el Gateway sea accesible y vuelve a intentarlo.';

  @override
  String get add => 'Agregar';

  @override
  String get add_connection => 'Agregar conexión';

  @override
  String get add_cron_job => 'Agregar tarea de Cron';

  @override
  String get add_gateway_connection => 'Agregar conexión de Gateway';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      'Agregar y actualizar conexiones desde la copia de seguridad; conservar las demás.';

  @override
  String get add_attachment => 'Agregar adjunto';

  @override
  String get add_new_cron_job => 'Agregar nueva tarea de Cron';

  @override
  String get add_to_chat => 'Agregar al chat';

  @override
  String get all_chats => 'Todos los chats';

  @override
  String get all_stored_message_content =>
      'Todo el contenido de mensajes almacenado';

  @override
  String get allow_for_this_session => 'Permitir durante esta sesión';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      'Permitir los comandos coincidentes hasta que finalice esta sesión de Hermes.';

  @override
  String get allow_once => 'Permitir una vez';

  @override
  String get always_allow => 'Permitir siempre';

  @override
  String get apply_to_this_chat => 'Aplicar a este chat';

  @override
  String get approval_needed => 'Se requiere aprobación';

  @override
  String get archive => 'Archivar';

  @override
  String get archive_project => 'Archivar proyecto';

  @override
  String archive_2(Object projectName) {
    return '¿Archivar $projectName?';
  }

  @override
  String archive_3(Object name) {
    return '¿Archivar $name?';
  }

  @override
  String get archived => 'Archivado';

  @override
  String get archived_conversations_appear_here =>
      'Las conversaciones archivadas aparecen aquí.';

  @override
  String get archived_quick_chats => 'Chats rápidos archivados';

  @override
  String get artifacts_attachments_and_generated_media =>
      'Artefactos, adjuntos y contenido generado';

  @override
  String get ask_ai_to_find_a_conversation =>
      'Pedir a la IA que busque una conversación';

  @override
  String get assets => 'Recursos';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      'Los recursos necesitan un índice autoritativo del servidor en el Gateway de Hermes para poder mostrarse por proyecto.';

  @override
  String get assets_unavailable => 'Recursos no disponibles';

  @override
  String get attach_image_or_file => 'Adjuntar imagen o archivo';

  @override
  String get attachment_drafts => 'Borradores de adjuntos';

  @override
  String attachment_of(Object index, Object total) {
    return 'Adjunto $index de $total';
  }

  @override
  String get auto_device_default =>
      'Automático (predeterminado del dispositivo)';

  @override
  String get auto_archives_after_72_hours => 'Se archiva solo a las 72 horas';

  @override
  String get automation => 'Automatización';

  @override
  String get autonomous_agents => 'Agentes autónomos';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      'Recuperación en segundo plano no disponible: transporte heredado';

  @override
  String get backup_restore => 'Copia de seguridad y restauración';

  @override
  String backup_exported(Object destination) {
    return 'Copia de seguridad exportada: $destination';
  }

  @override
  String get base_url => 'URL base';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      'La vista previa binaria no está disponible. Descarga el archivo para abrirlo.';

  @override
  String get branch => 'Rama';

  @override
  String get branch_chat => 'Bifurcar chat';

  @override
  String get branch_created_in_hermes_history =>
      'Rama creada en el historial de Hermes.';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      'Explora y administra tus sesiones de Hermes Agent desde el teléfono. Se conecta a un panel de Hermes que se ejecuta en tu red local.';

  @override
  String get browse_server_files => 'Explorar archivos del servidor';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      'Explora las carpetas de miniserver detrás de tus proyectos';

  @override
  String get cancel => 'Cancelar';

  @override
  String get cancel_voice_input => 'Cancelar entrada de voz';

  @override
  String cannot_reach(Object host, Object port) {
    return 'No se puede conectar con $host:$port.';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return 'No se puede conectar con $host:$port. Comprueba el host y el puerto.';
  }

  @override
  String get change_ai_search_model => 'Cambiar el modelo de búsqueda con IA';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return 'Cambia el valor predeterminado de $label. Usa el selector dentro de un chat para anularlo solo en esa conversación.';
  }

  @override
  String get chat_actions => 'Acciones del chat';

  @override
  String get chats => 'Chats';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      'Los chats de este Gateway aún no se agrupan. La agrupación permanece en este teléfono hasta que el Gateway pueda alojar proyectos.';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      'Los chats de este proyecto mostrarán aquí su estado y su última actividad.';

  @override
  String get chats_that_are_not_assigned_to_a_project =>
      'Chats que no están asignados a un proyecto';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      'Los chats que inicies en este proyecto aparecerán aquí, en todos los dispositivos conectados a este Hermes.';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      'Comprueba que el Gateway esté en ejecución y sea accesible, y vuelve a intentarlo.';

  @override
  String get check_the_dashboard_connection_and_try_again =>
      'Comprueba la conexión del panel y vuelve a intentarlo.';

  @override
  String get check_the_connection_and_try_again =>
      'Comprueba la conexión y vuelve a intentarlo.';

  @override
  String get choose_a_small_model_to_rewrite_queries =>
      'Elige un modelo pequeño para reescribir las consultas';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      'Elige un modelo de búsqueda con IA antes de usar la búsqueda con IA.';

  @override
  String get choose_an_active_project_next =>
      'A continuación, elige un proyecto activo';

  @override
  String get choose_chat_model => 'Elegir modelo del chat';

  @override
  String get choose_files => 'Elegir archivos';

  @override
  String get choose_image => 'Elegir imagen';

  @override
  String get choose_images => 'Elegir imágenes';

  @override
  String get choose_its_destination_space => 'Elige su espacio de destino';

  @override
  String get clear_search => 'Borrar búsqueda';

  @override
  String get close => 'Cerrar';

  @override
  String get code_copied => 'Código copiado';

  @override
  String get coming_next => 'Próximamente';

  @override
  String get command => 'Comando';

  @override
  String get command_line_chats => 'Chats de línea de comandos';

  @override
  String get compatibility_mode => 'Modo de compatibilidad';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      'Configura una URL válida del Desktop Gateway antes de adjuntar archivos.';

  @override
  String get confirm_always_allow => 'Confirmar permitir siempre';

  @override
  String get confirm_passphrase => 'Confirmar frase de contraseña';

  @override
  String connecting_to(Object baseUrl) {
    return 'Conectando con $baseUrl...';
  }

  @override
  String get connection_issue => 'Problema de conexión';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      'Conexión cambiada: la respuesta en curso continúa en el servidor y se volverá a adjuntar automáticamente.';

  @override
  String get connection_appearance_and_device_preferences =>
      'Conexión, apariencia y preferencias del dispositivo';

  @override
  String context_tokens(Object effectiveContextLength) {
    return 'Contexto: $effectiveContextLength tokens';
  }

  @override
  String get continue_label => 'Continuar';

  @override
  String get continue_working => 'Seguir trabajando';

  @override
  String get conversations_in_this_project => 'Conversaciones en este proyecto';

  @override
  String get copy_code => 'Copiar código';

  @override
  String get copy_message => 'Copiar mensaje';

  @override
  String could_not_branch_chat(Object error) {
    return 'No se pudo bifurcar el chat: $error';
  }

  @override
  String could_not_delete_session(Object error) {
    return 'No se pudo eliminar la sesión: $error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return 'No se pudo denegar el comando: $error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return 'No se pudieron cargar los modelos de búsqueda con IA: $error';
  }

  @override
  String get could_not_load_conversations =>
      'No se pudieron cargar las conversaciones';

  @override
  String get could_not_load_files => 'No se pudieron cargar los archivos';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return 'No se pudieron cargar los modelos de este perfil: $error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return 'No se pudieron cargar más chats: $error';
  }

  @override
  String get could_not_open_the_hermes_dashboard =>
      'No se pudo abrir el panel de Hermes.';

  @override
  String get could_not_open_this_project => 'No se pudo abrir este proyecto';

  @override
  String get could_not_preview_file => 'No se pudo previsualizar el archivo';

  @override
  String get could_not_reach_hermes => 'No se pudo conectar con Hermes';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return 'No se pudo conectar o autenticar con el panel en $host:$dashboardPort. Comprueba el puerto y las credenciales.';
  }

  @override
  String get could_not_read_activity => 'No se pudo leer la actividad';

  @override
  String could_not_rename_chat(Object error) {
    return 'No se pudo cambiar el nombre del chat: $error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return 'No se pudo enviar la aprobación: $error';
  }

  @override
  String get could_not_skip_the_hermes_question =>
      'No se pudo omitir la pregunta de Hermes.';

  @override
  String could_not_the_project(Object action, Object error) {
    return 'No se pudo $action el proyecto: $error';
  }

  @override
  String get couldn_t_delete_project => 'No se pudo eliminar el proyecto';

  @override
  String couldn_t_load_runs(Object error) {
    return 'No se pudieron cargar las ejecuciones: $error';
  }

  @override
  String get couldn_t_move_conversation => 'No se pudo mover la conversación';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return 'No se pudo mover a $label: $reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files =>
      'No se pudieron preparar los archivos compartidos.';

  @override
  String get couldn_t_promote_conversation =>
      'No se pudo promover la conversación';

  @override
  String couldn_t_project(Object action) {
    return 'No se pudo $action el proyecto';
  }

  @override
  String get create => 'Crear';

  @override
  String get create_a_project => 'Crear un proyecto';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      'Crea primero un proyecto; los chats podrán vivir dentro de él.';

  @override
  String get create_a_space_to_separate_related_conversations =>
      'Crea un espacio para separar conversaciones relacionadas.';

  @override
  String get create_branch => 'Crear rama';

  @override
  String get cron => 'Cron';

  @override
  String get cron_jobs => 'Tareas de Cron';

  @override
  String get cron_job_added => 'Tarea de Cron agregada';

  @override
  String get cron_job_updated => 'Tarea de Cron actualizada';

  @override
  String get cron_run => 'Ejecución de Cron';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      'Ordenación entre dispositivos y organización masiva reversible';

  @override
  String get current_profile_default =>
      'Valor predeterminado del perfil actual';

  @override
  String get custom_proxy_and_dashboard_details =>
      'Detalles personalizados de proxy y panel';

  @override
  String get dark => 'Oscuro';

  @override
  String get dashboard_proxy_settings => 'Configuración del panel / proxy';

  @override
  String get dashboard_password_optional => 'Contraseña del panel (opcional)';

  @override
  String get dashboard_port => 'Puerto del panel';

  @override
  String get dashboard_username_optional =>
      'Nombre de usuario del panel (opcional)';

  @override
  String get dashboard_behind_proxy => 'Panel detrás de un proxy';

  @override
  String get dashboard_path_prefix => 'Prefijo de ruta del panel';

  @override
  String delegated_task(Object goal) {
    return 'Tarea delegada: $goal';
  }

  @override
  String get delete => 'Eliminar';

  @override
  String delete_2(Object name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return '¿Eliminar «$title» del historial remoto de Hermes? Esta acción no se puede deshacer.';
  }

  @override
  String get delete_cron_job => 'Eliminar tarea de Cron';

  @override
  String get delete_connections_that_are_not_in_the_backup =>
      'Eliminar las conexiones que no estén en la copia de seguridad.';

  @override
  String delete_failed(Object error) {
    return 'Error al eliminar: $error';
  }

  @override
  String get delete_project => 'Eliminar proyecto';

  @override
  String get delete_session => '¿Eliminar la sesión?';

  @override
  String delete_3(Object projectName) {
    return '¿Eliminar $projectName?';
  }

  @override
  String deleted(Object name) {
    return 'Se eliminó «$name»';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      'La entrega es incierta; se está recuperando sin reenviar…';

  @override
  String get desktop_gateway_url_optional =>
      'URL del Desktop Gateway (opcional)';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      'Desktop Gateway no está configurado para esta conexión.';

  @override
  String get desktop_app => 'Aplicación de escritorio';

  @override
  String get developer_tool_calls =>
      'Llamadas a herramientas del desarrollador';

  @override
  String get discord_chats => 'Chats de Discord';

  @override
  String get dismiss => 'Descartar';

  @override
  String get do_not_run_this_command => 'No ejecutes este comando.';

  @override
  String get documents_archives_audio_video_or_data =>
      'Documentos, archivos comprimidos, audio, vídeo o datos';

  @override
  String get download => 'Descargar';

  @override
  String download_failed(Object error) {
    return 'Error de descarga: $error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you =>
      'Datos duraderos que Hermes guarda sobre ti';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      'Trabajo duradero dentro de uno de tus proyectos, compartido con Desktop.';

  @override
  String get edit => 'Editar';

  @override
  String get edit_connection => 'Editar conexión';

  @override
  String get edit_cron_job => 'Editar tarea de Cron';

  @override
  String get edit_gateway_connection => 'Editar conexión de Gateway';

  @override
  String get edit_and_resend => 'Editar y reenviar';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      'Habilita los archivos adjuntos a través del Gateway remoto de Desktop.';

  @override
  String get enter_a_name => 'Escribe un nombre';

  @override
  String get enter_a_passphrase => 'Escribe una frase de contraseña.';

  @override
  String get enter_the_passphrase_for_this_backup =>
      'Escribe la frase de contraseña de esta copia de seguridad.';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      'Todas las conversaciones ya están asignadas a un proyecto.';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      'Todo lo que aún no es nativo, en el panel web autenticado';

  @override
  String get explain_the_attached_content_clearly =>
      'Explica claramente el contenido adjunto.';

  @override
  String explain_this_content_clearly(Object text) {
    return 'Explica claramente este contenido:\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      'Las opciones explícitas ajustan el tamaño de texto de accesibilidad de Android; «Sistema» lo deja sin cambios.';

  @override
  String get export_label => 'Exportar';

  @override
  String get export_share => 'Exportar / compartir';

  @override
  String get external_api_clients => 'Clientes externos de la API';

  @override
  String get extra_high => 'Muy alto';

  @override
  String get extract_tasks => 'Extraer tareas';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      'Extrae del contenido adjunto las decisiones, los plazos, los responsables y las tareas accionables.';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return 'Extrae de este contenido las decisiones, los plazos, los responsables y las tareas accionables:\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return 'No se pudo agregar la tarea: $error';
  }

  @override
  String get failed_to_load_cron_jobs =>
      'No se pudieron cargar las tareas de Cron';

  @override
  String get failed_to_load_memory => 'No se pudo cargar la memoria';

  @override
  String get failed_to_load_messages => 'No se pudieron cargar los mensajes';

  @override
  String get failed_to_load_settings => 'No se pudieron cargar los ajustes';

  @override
  String get failed_to_load_skills => 'No se pudieron cargar las habilidades';

  @override
  String failed_to_update_job(Object error) {
    return 'No se pudo actualizar la tarea: $error';
  }

  @override
  String failed(Object error) {
    return 'Error: $error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      'Archivo adjuntado; el registro en el catálogo de documentos está pendiente.';

  @override
  String get file_reference_added_to_chat =>
      'Referencia de archivo agregada al chat';

  @override
  String get files => 'Archivos';

  @override
  String get fill_from_document => 'Rellenar desde el documento';

  @override
  String get folder_is_empty => 'La carpeta está vacía';

  @override
  String get folders => 'Carpetas';

  @override
  String get full_text => 'Texto completo';

  @override
  String get gateway_api_access => 'Acceso a la API del Gateway';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      'Gateway conectado, pero no se pudo alcanzar o autenticar el panel. Revisa los detalles del panel o bórralos para omitirlo.';

  @override
  String get gateway_path_prefix => 'Prefijo de ruta del Gateway';

  @override
  String get go_to_end => 'Ir al final';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Hermes Agent para Android';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'Hermes no pudo aceptar la respuesta. Inténtalo de nuevo.';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      'Hermes no pudo cargar tus conexiones guardadas';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'Hermes no aceptó la respuesta. Inténtalo de nuevo.';

  @override
  String get hermes_is_responding => 'Hermes está respondiendo…';

  @override
  String get hermes_is_waiting_for_input => 'Hermes está esperando tu entrada…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'Hermes mantiene activo el escalado de texto de accesibilidad de Android.';

  @override
  String get hermes_needs_your_input => 'Hermes necesita tu entrada';

  @override
  String get hermes_profile_optional => 'Perfil de Hermes (opcional)';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'El perfil de Hermes debe ser un nombre de perfil simple como «sol», no una ruta.';

  @override
  String get hermes_reasoning_details => 'Detalles de razonamiento de Hermes';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'La recuperación de Hermes no está disponible: $error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'Hermes detuvo la recuperación de forma segura. No se reenvió ningún prompt.';

  @override
  String get hide_passphrase => 'Ocultar frase de contraseña';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      'El inicio necesita tus chats recientes para saber qué merece tu atención. Comprueba que el Gateway sea accesible y vuelve a intentarlo.';

  @override
  String get host => 'Host';

  @override
  String get image_selection_was_interrupted_try_again =>
      'La selección de imagen se interrumpió. Inténtalo de nuevo.';

  @override
  String get import_label => 'Importar';

  @override
  String get inbox => 'Bandeja de entrada';

  @override
  String get inbox_is_clear => 'La bandeja de entrada está vacía';

  @override
  String get insert_a_remote_file_reference =>
      'Insertar una referencia remota a @file';

  @override
  String get invalid_port_number => 'Número de puerto no válido.';

  @override
  String get job_paused => 'Tarea en pausa';

  @override
  String get job_resumed => 'Tarea reanudada';

  @override
  String get job_triggered => 'Tarea activada';

  @override
  String get label => 'Etiqueta';

  @override
  String last_activity(Object day, Object month, Object year) {
    return 'Última actividad $day/$month/$year';
  }

  @override
  String last(Object lastRun) {
    return 'Última: $lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      'Déjalo en blanco para usar el valor predeterminado (8642; 443 con https)';

  @override
  String get leave_blank_for_default_9119 =>
      'Déjalo en blanco para usar el valor predeterminado (9119)';

  @override
  String get light => 'Claro';

  @override
  String listening(Object elapsed) {
    return 'Escuchando • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return 'Escuchando, tiempo transcurrido: $elapsed';
  }

  @override
  String get load_more => 'Cargar más…';

  @override
  String get loading => 'Cargando';

  @override
  String get location => 'Ubicación';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      'Asegúrate de que el servidor de la API del Gateway esté en ejecución\n(hermes gateway status)';

  @override
  String matches(Object assigned, Object name) {
    return 'Coincide con $name · $assigned';
  }

  @override
  String get memory => 'Memoria';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'Las entradas de memoria son datos entre sesiones que el agente recuerda.\nSe configuran en ~/.hermes/config.yaml';

  @override
  String get merge => 'Combinar';

  @override
  String get message => 'Mensaje';

  @override
  String get message_hermes => 'Enviar un mensaje a Hermes…';

  @override
  String get message_actions => 'Acciones del mensaje';

  @override
  String get message_copied => 'Mensaje copiado';

  @override
  String get migrating => 'Migrando…';

  @override
  String get migration_complete => 'Migración completada';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      'La migración falló. Los espacios locales no se modificaron.';

  @override
  String get migration_incomplete => 'Migración incompleta';

  @override
  String get migration_preview => 'Vista previa de la migración';

  @override
  String get model => 'Modelo';

  @override
  String get model_and_thinking_for_this_chat =>
      'Modelo y razonamiento para este chat';

  @override
  String model_was_not_changed(Object error) {
    return 'El modelo no cambió: $error';
  }

  @override
  String get move_attachment_next => 'Mover el adjunto al siguiente';

  @override
  String get move_attachment_previous => 'Mover el adjunto al anterior';

  @override
  String get move_chat => 'Mover chat';

  @override
  String get move_conversation => 'Mover conversación';

  @override
  String get move_to_project => 'Mover a un proyecto';

  @override
  String get move_to_space => 'Mover a un espacio';

  @override
  String get moved_to_a_project => 'Movido a un proyecto';

  @override
  String moved_to(Object label) {
    return 'Movido a $label';
  }

  @override
  String get name => 'Nombre';

  @override
  String get name_prompt_and_schedule_are_required =>
      'El nombre, el prompt y la programación son obligatorios';

  @override
  String get nav_activity => 'Actividad';

  @override
  String get nav_projects => 'Proyectos';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Requiere un contrato de archivado con corrección de errores en el Gateway de Hermes.';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      'Requiere un panel de Hermes accesible. Comprueba el host, el puerto y las credenciales de esta conexión.';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Requiere un índice de recursos autoritativo del servidor en el Gateway de Hermes.';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Requiere contratos de orden de fijados, mutación por lotes y deshacer en el Gateway de Hermes.';

  @override
  String get needs_you => 'Te necesita';

  @override
  String get new_label => 'Nuevo';

  @override
  String get new_chat => 'Nuevo chat';

  @override
  String get new_chat_2 => 'Nuevo chat';

  @override
  String new_chat_3(Object projectName) {
    return 'Nuevo chat · $projectName';
  }

  @override
  String get new_project => 'Nuevo proyecto';

  @override
  String get new_space => 'Nuevo espacio';

  @override
  String next(Object nextRun) {
    return 'Próxima: $nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'Nginx inyecta la autenticación; la aplicación envía solicitudes limpias';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      'No se encontraron voces de TTS.\nInstala Google Text-to-Speech y descarga los datos de voz.';

  @override
  String get no_active_projects_on_this_gateway =>
      'No hay proyectos activos en este Gateway';

  @override
  String get no_activity_yet => 'Aún no hay actividad';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      'Ningún chat está bloqueado, en ejecución o esperando reanudarse. Inicia uno nuevo cuando quieras.';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return 'Ningún chat de este proyecto coincide con «$searchQuery».';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      'Aún no hay chats en este espacio. Toca + para iniciar uno.';

  @override
  String get no_chats_yet => 'Aún no hay chats';

  @override
  String get no_connections => 'Sin conexiones';

  @override
  String get no_conversation_matches_this_view =>
      'Ninguna conversación coincide con esta vista.';

  @override
  String get no_cron_jobs => 'No hay tareas de Cron';

  @override
  String get no_folders_yet => 'Aún no hay carpetas';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      'No se encontraron espacios locales para esta conexión, así que los proyectos ya son la única forma de organización en uso.';

  @override
  String get no_matches => 'Sin coincidencias';

  @override
  String get no_memory_entries => 'No hay entradas de memoria';

  @override
  String get no_message_content_matches =>
      'No hay coincidencias en el contenido de los mensajes';

  @override
  String get no_new_messages => 'No hay mensajes nuevos';

  @override
  String get no_projects_yet => 'Aún no hay proyectos';

  @override
  String get no_runs_yet => 'Aún no hay ejecuciones.';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return 'Ningún proyecto del servidor coincide con este nombre · $assigned';
  }

  @override
  String get no_sessions_yet => 'Aún no hay sesiones';

  @override
  String get no_skills_found => 'No se encontraron habilidades';

  @override
  String get no_spaces_on_this_device => 'No hay espacios en este dispositivo';

  @override
  String get no_text_shared => 'No se compartió texto';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      'Ningún turno está bloqueado, en curso o finalizado recientemente. El trabajo que inicies aparecerá aquí.';

  @override
  String get no_turn_needs_your_input_or_has_failed =>
      'Ningún turno necesita tu entrada ni ha fallado.';

  @override
  String get no_unassigned_chats => 'No hay chats sin asignar.';

  @override
  String get nothing_changed_in_the_last_seven_days =>
      'Nada cambió en los últimos siete días.';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      'Todavía no se ha movido nada; esto es solo lo que haría una migración.';

  @override
  String get nothing_here => 'No hay nada aquí';

  @override
  String get nothing_is_running => 'No hay nada en ejecución';

  @override
  String get nothing_needs_you => 'Nada te necesita';

  @override
  String get nothing_to_migrate => 'Nada que migrar';

  @override
  String get off_no_thinking => 'Desactivado (sin razonamiento)';

  @override
  String get offline_showing_the_last_known_activity =>
      'Sin conexión: se muestra la última actividad conocida.';

  @override
  String get offline_showing_the_last_known_chats =>
      'Sin conexión: se muestran los últimos chats conocidos';

  @override
  String get offline_showing_the_last_known_projects =>
      'Sin conexión: se muestran los últimos proyectos conocidos.';

  @override
  String get on_this_device => 'En este dispositivo';

  @override
  String get on_device => 'En el dispositivo';

  @override
  String get open_inbox => 'Abrir bandeja de entrada';

  @override
  String open_inbox_2(Object count) {
    return 'Abrir bandeja de entrada ($count)';
  }

  @override
  String get open_the_hermes_dashboard => 'Abrir el panel de Hermes';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      'Opcional. Para las pestañas Memoria/Cron/Habilidades/Ajustes. Déjalo en blanco para usar el puerto predeterminado del panel (9119) sin inicio de sesión.';

  @override
  String get organization => 'Organización';

  @override
  String get other_answer => 'Otra respuesta';

  @override
  String get overview => 'Resumen';

  @override
  String get passphrase => 'Frase de contraseña';

  @override
  String get password_optional => 'Contraseña (opcional)';

  @override
  String get phone_or_tablet => 'Teléfono o tableta';

  @override
  String get pin_batch_and_undo => 'Fijar, por lotes y deshacer';

  @override
  String get port => 'Puerto';

  @override
  String get preparing_attachments => 'Preparando adjuntos…';

  @override
  String get preview_truncated => 'Vista previa truncada';

  @override
  String get preview_unavailable => 'Vista previa no disponible';

  @override
  String get profile => 'Perfil';

  @override
  String get profile_default_model => 'Modelo predeterminado del perfil';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return 'Valor predeterminado del perfil establecido en $selectedModel. Los chats con su propio modelo conservan esa anulación.';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      'Perfil con el que chatea esta conexión cuando el panel sirve varios perfiles. Déjalo en blanco para un panel aislado por perfil.';

  @override
  String get project => 'Proyecto';

  @override
  String get project_actions => 'Acciones del proyecto';

  @override
  String get project_chat => 'Chat del proyecto';

  @override
  String get project_chats_unavailable => 'Chats del proyecto no disponibles';

  @override
  String get projects => 'Proyectos';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      'Los proyectos agrupan chats, archivos y actividad relacionados, y se mantienen sincronizados con Hermes en tu computadora.';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      'Los proyectos necesitan una conexión con Desktop Gateway. Agrega la URL del Desktop Gateway a esta conexión para organizar chats en todos tus dispositivos.';

  @override
  String get projects_unavailable => 'Proyectos no disponibles';

  @override
  String get projects_activity_new_navigation =>
      'Proyectos, Actividad: nueva navegación';

  @override
  String get promote_to_project => 'Promover a proyecto';

  @override
  String get prompt => 'Prompt';

  @override
  String get protect_this_backup => 'Protege esta copia de seguridad';

  @override
  String get provider => 'Proveedor';

  @override
  String get proxy_injects_auth_app_sends_clean_requests =>
      'El proxy inyecta la autenticación; la aplicación envía solicitudes limpias';

  @override
  String get quick_chat => 'Chat rápido';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      'Los chats rápidos aparecen aquí después de su período de retención.';

  @override
  String get read_aloud => 'Leer en voz alta';

  @override
  String get read_aloud_is_unavailable_on_this_device =>
      'Leer en voz alta no está disponible en este dispositivo';

  @override
  String get reading_response_aloud => 'Leyendo la respuesta en voz alta';

  @override
  String get ready_to_upload => 'Listo para subir';

  @override
  String get reasoning => 'Razonamiento';

  @override
  String get recently_completed => 'Completado recientemente';

  @override
  String get recovering_hermes => 'Recuperando Hermes…';

  @override
  String get refresh => 'Actualizar';

  @override
  String get regenerate_response => 'Regenerar respuesta';

  @override
  String get remove_attachment => 'Quitar adjunto';

  @override
  String get rename => 'Cambiar nombre';

  @override
  String get rename_chat => 'Cambiar nombre del chat';

  @override
  String get rename_project => 'Cambiar nombre del proyecto';

  @override
  String get rename_space => 'Cambiar nombre del espacio';

  @override
  String rename_2(Object projectName) {
    return 'Cambiar nombre de $projectName';
  }

  @override
  String rename_3(Object name) {
    return 'Cambiar nombre de $name';
  }

  @override
  String get replace => 'Reemplazar';

  @override
  String get repositories => 'Repositorios';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      'Investiga el contenido adjunto, verifica las afirmaciones importantes y cita las fuentes.';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return 'Investiga este contenido, verifica las afirmaciones importantes y cita las fuentes:\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return 'Error al restablecer: $retryError. Es posible que haya que reinstalar el almacenamiento seguro.';
  }

  @override
  String get reset_saved_connections => 'Restablecer conexiones guardadas';

  @override
  String get responding => 'Respondiendo…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return 'Respuesta cerrada localmente; error al detener el Gateway: $error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      'Respuesta cerrada localmente; no se encontró ningún turno activo del Gateway.';

  @override
  String get response_ready => 'Respuesta lista';

  @override
  String get response_stopped => 'Respuesta detenida.';

  @override
  String get restore => 'Restaurar';

  @override
  String get restore_configuration => 'Restaurar configuración';

  @override
  String get restore_project => 'Restaurar proyecto';

  @override
  String get retry => 'Reintentar';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return 'Error al reintentar $name. El borrador y el prompt se conservaron.';
  }

  @override
  String get retry_upload => 'Reintentar subida';

  @override
  String retrying(Object name) {
    return 'Reintentando $name…';
  }

  @override
  String get review_local_spaces => 'Revisar espacios locales';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      'Revisar o promover chats rápidos que superaron su período de retención';

  @override
  String get review_the_attached_content => 'Revisa el contenido adjunto.';

  @override
  String get run_only_this_command => 'Ejecuta solo este comando.';

  @override
  String get running_now => 'En ejecución';

  @override
  String get save => 'Guardar';

  @override
  String get save_changes => 'Guardar cambios';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      'Guarda una regla permanente en la configuración de Hermes.';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      'Guarda los datos duraderos del contenido adjunto en la memoria y confirma qué se conservó.';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return 'Guarda los datos duraderos de este contenido en la memoria y confirma qué se conservó:\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      'Guarda tus conexiones y ajustes en un archivo cifrado y restáuralos tras reinstalar o en otro dispositivo.';

  @override
  String save_2(Object filename) {
    return 'Guardar $filename';
  }

  @override
  String get schedule => 'Programación';

  @override
  String get scheduled_jobs_and_their_last_runs =>
      'Tareas programadas y sus últimas ejecuciones';

  @override
  String get scheduled_tasks => 'Tareas programadas';

  @override
  String get script_only_no_agent => 'Solo script (sin agente)';

  @override
  String get scroll_horizontally => 'Desplazar horizontalmente';

  @override
  String get search_all_chats => 'Buscar en todos los chats';

  @override
  String get search_all_message_content =>
      'Buscar en todo el contenido de los mensajes';

  @override
  String get search_chats => 'Buscar chats';

  @override
  String get search_conversations => 'Buscar conversaciones';

  @override
  String get search_loaded_chats => 'Buscar en los chats cargados';

  @override
  String get search_mode => 'Modo de búsqueda';

  @override
  String get select_one_option_or_enter_another_answer =>
      'Selecciona una opción o escribe otra respuesta.';

  @override
  String get select_one_or_more_options_then_continue =>
      'Selecciona una o más opciones y continúa.';

  @override
  String get select_text => 'Seleccionar texto';

  @override
  String get send => 'Enviar';

  @override
  String send_failed(Object error) {
    return 'Error de envío: $error';
  }

  @override
  String get send_message => 'Enviar mensaje';

  @override
  String get session_sources => 'Fuentes de sesiones';

  @override
  String get session_deleted_from_remote_hermes =>
      'Sesión eliminada del Hermes remoto.';

  @override
  String session_search_failed(Object error) {
    return 'Error en la búsqueda de sesiones: $error';
  }

  @override
  String get set_profile_default => 'Establecer como predeterminado del perfil';

  @override
  String get settings => 'Ajustes';

  @override
  String get share_to_hermes => 'Compartir con Hermes';

  @override
  String get show_passphrase => 'Mostrar frase de contraseña';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      'Mostrar llamadas a herramientas, razonamiento y metadatos de mensajes';

  @override
  String get signal_messages => 'Mensajes de Signal';

  @override
  String get skills => 'Habilidades';

  @override
  String skills_2(Object count) {
    return 'Habilidades ($count)';
  }

  @override
  String get skills_and_tools => 'Habilidades y herramientas';

  @override
  String get skip => 'Omitir';

  @override
  String get slack_chats => 'Chats de Slack';

  @override
  String source(Object source) {
    return 'Origen: $source';
  }

  @override
  String get space_actions => 'Acciones del espacio';

  @override
  String get spaces => 'Espacios';

  @override
  String get speak_to_hermes => 'Habla con Hermes';

  @override
  String get speech_recognition_is_unavailable =>
      'El reconocimiento de voz no está disponible';

  @override
  String get spoken_replies => 'Respuestas habladas';

  @override
  String get spoken_replies_off => 'Respuestas habladas desactivadas';

  @override
  String get spoken_replies_on => 'Respuestas habladas activadas';

  @override
  String get stalled_no_update_from_hermes =>
      'Estancado: sin actualizaciones de Hermes';

  @override
  String get start_something_new => 'Empezar algo nuevo';

  @override
  String get start_voice_input => 'Iniciar entrada de voz';

  @override
  String get starting_hermes => 'Iniciando Hermes…';

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
  String get still_loading_your_projects => 'Todavía cargando tus proyectos.';

  @override
  String get stop => 'Detener';

  @override
  String get stop_response => 'Detener respuesta';

  @override
  String get stop_voice_input => 'Detener entrada de voz';

  @override
  String get submitted_waiting_for_hermes => 'Enviado, esperando a Hermes';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      'Sugerir proyectos y aprender de tus correcciones';

  @override
  String get summarize_the_attached_content => 'Resume el contenido adjunto.';

  @override
  String summarize_this_content(Object text) {
    return 'Resume este contenido:\n\n$text';
  }

  @override
  String get switch_profile => 'Cambiar de perfil';

  @override
  String get system => 'Sistema';

  @override
  String get take_photo => 'Tomar foto';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      'Toca + para agregar un Gateway de Hermes remoto\n(servidor de API, puerto 8642)';

  @override
  String get tap_the_button_to_start_a_new_chat =>
      'Toca el botón + para iniciar un chat nuevo';

  @override
  String get telegram_messages => 'Mensajes de Telegram';

  @override
  String get terminal_sessions => 'Sesiones de terminal';

  @override
  String get text_size => 'Tamaño del texto';

  @override
  String get text_size_preview => 'Vista previa del tamaño del texto';

  @override
  String text_size_2(Object label) {
    return 'Tamaño del texto: $label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely =>
      'No se pudo almacenar la clave de API de forma segura.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      'El proyecto pasará a «Archivado». Sus chats y archivos se conservarán intactos y podrás restaurarlo cuando quieras.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      'El proyecto pasará a «Archivado». Sus chats y archivos se conservarán intactos y podrás restaurarlo más adelante.';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      'El perfil activo no devolvió ningún modelo seleccionable.';

  @override
  String get the_backup_could_not_be_exported =>
      'No se pudo exportar la copia de seguridad.';

  @override
  String get the_backup_could_not_be_restored =>
      'No se pudo restaurar la copia de seguridad.';

  @override
  String get the_connection_could_not_be_deleted_safely =>
      'No se pudo eliminar la conexión de forma segura.';

  @override
  String get the_connection_could_not_be_stored_securely =>
      'No se pudo almacenar la conexión de forma segura.';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      'No se pudieron almacenar las credenciales del panel de forma segura.';

  @override
  String get the_detached_reply_failed => 'La respuesta desacoplada falló.';

  @override
  String the_detached_reply_failed_2(Object error) {
    return 'La respuesta desacoplada falló: $error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      'El archivo contiene tus claves de API y la contraseña del panel, por lo que está cifrado. Sin esta frase de contraseña no se puede restaurar la copia de seguridad.';

  @override
  String get the_last_turn_failed => 'El último turno falló';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return 'El almacén local de conexiones parece dañado ($errorType). Puedes restablecer las conexiones guardadas y empezar de cero. Los chats de tu Gateway no se ven afectados.';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      'El modelo solo reescribe tu pregunta como una consulta breve de texto completo. Hermes usa las credenciales del proveedor ya configuradas en el host.';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      'El servidor aún no ha informado carpetas para este proyecto. Archivos globales sigue disponible en Más.';

  @override
  String get the_turn_failed => 'El turno falló';

  @override
  String get the_two_passphrases_do_not_match =>
      'Las dos frases de contraseña no coinciden.';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      'El valor se envía directamente al Gateway de Hermes activo y esta aplicación de Android no lo guarda.';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      'No hay archivos visibles en esta carpeta del servidor.';

  @override
  String get thinking_effort => 'Esfuerzo de razonamiento';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      'Este Gateway de Hermes aún no admite abrir proyectos. Actualiza Hermes en el servidor para explorar un proyecto desde el teléfono.';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      'Este Gateway de Hermes es anterior a los proyectos del servidor, por lo que los chats se agrupan solo en este dispositivo. Actualiza Hermes para compartir los mismos proyectos entre tus dispositivos.';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      'Este proyecto no tiene una carpeta para abrir el chat; se abrió sin asignar. Agrega una carpeta al proyecto para agrupar sus chats.';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      'Este chat aún no tiene mensajes disponibles en la sesión de Desktop.';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      'Esto crea una regla permanente en Hermes. Revisa el comando completo antes de confirmar.';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      'Este Gateway aún no aloja proyectos. Actualiza el Gateway para organizar chats en todos tus dispositivos.';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      'Esto elimina el proyecto de forma permanente. Los chats no se eliminarán; volverán a «Sin asignar».';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      'Este servidor no ofrece recuperación en segundo plano; los chats se ejecutan en vivo';

  @override
  String get this_week => 'Esta semana';

  @override
  String get titles_previews_and_models => 'Títulos, vistas previas y modelos';

  @override
  String get tool_activity => 'Actividad de herramientas';

  @override
  String get trigger_now => 'Ejecutar ahora';

  @override
  String get turn_completed => 'Turno completado';

  @override
  String get turn_recovery_failed => 'Error en la recuperación del turno';

  @override
  String get unable_to_prepare_this_file_try_another_one =>
      'No se pudo preparar este archivo. Prueba con otro.';

  @override
  String get unable_to_prepare_this_image_try_another_one =>
      'No se pudo preparar esta imagen. Prueba con otra.';

  @override
  String unable_to_prepare(Object name) {
    return 'No se pudo preparar $name.';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      'No se pudo leer la imagen seleccionada. La selección se conservó.';

  @override
  String get unassigned => 'Sin asignar';

  @override
  String get unassigned_chats => 'Chats sin asignar';

  @override
  String get untitled_chat => 'Chat sin título';

  @override
  String get untitled_session => 'Sesión sin título';

  @override
  String get update_api_key => 'Actualizar clave de API';

  @override
  String get upload_failed => 'Error de subida';

  @override
  String get upload_failed_tap_retry =>
      'Error de subida • toca para reintentar';

  @override
  String uploading(Object index, Object name, Object total) {
    return 'Subiendo $index/$total: $name';
  }

  @override
  String get use_as_is => 'Usar tal cual';

  @override
  String get use_at_least_8_characters => 'Usa al menos 8 caracteres.';

  @override
  String get use_for_cron_jobs_backed_by_scripts =>
      'Úsalo para tareas de Cron respaldadas por scripts.';

  @override
  String get use_on_device => 'Usar en el dispositivo';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      'Usa el contenido adjunto para identificar y rellenar los campos relevantes del documento o formulario. Pregunta antes de enviar cualquier cosa.';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return 'Usa este contenido para identificar y rellenar los campos relevantes del documento o formulario. Pregunta antes de enviar cualquier cosa:\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      'Se usa para prefijos de rutas alojadas y para las pestañas Ajustes, Memoria, Habilidades y Cron. Deja el usuario y la contraseña en blanco para un panel abierto, o activa el modo de proxy cuando tu proxy inverso inyecte la autenticación del panel.';

  @override
  String get username_optional => 'Nombre de usuario (opcional)';

  @override
  String using(Object displayName) {
    return 'Usando $displayName…';
  }

  @override
  String get verbose_mode => 'Modo detallado';

  @override
  String get voice => 'Voz';

  @override
  String voice_setup_failed(Object error) {
    return 'Error al configurar la voz: $error';
  }

  @override
  String get waiting_for_your_input => 'Esperando tu entrada';

  @override
  String get what_hermes_knows_how_to_do => 'Lo que Hermes sabe hacer';

  @override
  String get what_should_the_agent_do => '¿Qué debe hacer el agente?';

  @override
  String get whatsapp_messages => 'Mensajes de WhatsApp';

  @override
  String get which_project => '¿Qué proyecto?';

  @override
  String get workspace => 'Espacio de trabajo';

  @override
  String get wrap_lines => 'Ajustar líneas';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return 'Puedes adjuntar hasta $maxRemoteAttachmentDrafts elementos.';
  }

  @override
  String get your_answer => 'Tu respuesta';

  @override
  String get e_g_dashboard => 'p. ej., /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      'p. ej., /dashboard (ruta del proxy antes de /api/)';

  @override
  String get e_g_profile_peter => 'p. ej., /profile/peter';

  @override
  String get e_g_sol => 'p. ej., sol';

  @override
  String get e_g_0_9_or_every_2h => 'p. ej., 0 9 * * * o every 2h';

  @override
  String get e_g_daily_backup => 'p. ej., copia diaria';

  @override
  String downloaded(Object filename) {
    return '$filename descargado';
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
      '192.168.1.50, 100.x.y.z o hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      'p. ej., /profile/peter (ruta del proxy antes de /api/ y /v1/)';

  @override
  String and_more(Object count) {
    return 'y $count más';
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
    return '$chats · solo en este dispositivo';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count espacios',
      one: '$count espacio',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => 'no se necesitan proyectos nuevos';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count proyectos por crear',
      one: '$count proyecto por crear',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return '$linkedSessions chats migrados · $createdProjects proyectos creados';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '$unlinkedSessions chats permanecieron en espacios locales y se pueden reintentar sin riesgo.';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • Recomendado: pequeño y económico';
  }

  @override
  String session_meta(Object count, Object model, Object time) {
    return '$count mensajes • $model • $time';
  }

  @override
  String model_scope_label(Object model, Object scope) {
    return '$model • $scope';
  }

  @override
  String get this_chat => 'este chat';

  @override
  String get profile_default => 'predeterminado del perfil';

  @override
  String minutes_ago(Object count) {
    return 'hace $count min';
  }

  @override
  String hours_ago(Object count) {
    return 'hace $count h';
  }

  @override
  String days_ago(Object count) {
    return 'hace $count d';
  }

  @override
  String get now_label => 'ahora';

  @override
  String get latest_label => 'Último';

  @override
  String new_count_indicator(Object count) {
    return '$count nuevos';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensajes nuevos',
      one: '$count mensaje nuevo',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return '$failures fallidos • $total en total';
  }

  @override
  String activity_completed_summary(Object count) {
    return '$count completados';
  }

  @override
  String get hermes_is_using_a_tool => 'Hermes está usando una herramienta';

  @override
  String hermes_is_using_tools(Object count) {
    return 'Hermes está usando $count herramientas';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return '$count tarea(s) delegada(s) completada(s)';
  }

  @override
  String delegated_tasks_active(Object count) {
    return '$count tarea(s) delegada(s) activa(s)';
  }

  @override
  String branch_main(Object label) {
    return '$label · main';
  }

  @override
  String get you_heading => '## Tú';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => 'Acción';

  @override
  String get destination_label => 'Destino';

  @override
  String get preview_label => 'Vista previa';

  @override
  String get share_action_summarize => 'Resumir';

  @override
  String get share_action_explain => 'Explicar';

  @override
  String get share_action_research => 'Investigar';

  @override
  String get share_action_remember => 'Recordar';

  @override
  String get text_size_small => 'Pequeño';

  @override
  String get text_size_default => 'Predeterminado';

  @override
  String get text_size_large => 'Grande';

  @override
  String get text_size_extra_large => 'Muy grande';

  @override
  String get text_size_use_system_description =>
      'Usar exactamente el tamaño de texto de accesibilidad de Android.';

  @override
  String text_size_percent_description(Object percent) {
    return '$percent% del tamaño de texto de Android.';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return '$count archivo(s) omitido(s): límite, tamaño, ilegible o nombre de archivo sensible.';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort ahora se aplican solo a este chat.';
  }

  @override
  String get reasoning_minimal => 'Mínimo';

  @override
  String get reasoning_low => 'Bajo';

  @override
  String get reasoning_medium => 'Medio';

  @override
  String get reasoning_high => 'Alto';

  @override
  String get reasoning_max => 'Máximo';

  @override
  String get reasoning_ultra => 'Ultra';

  @override
  String get status_running => 'En ejecución';

  @override
  String get status_failed => 'Fallido';

  @override
  String get status_done => 'Listo';

  @override
  String get status_idle => 'Inactivo';

  @override
  String get upload_status_uploading => 'Subiendo';

  @override
  String get upload_status_uploaded => 'Subido';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count adjuntos',
      one: '$count adjunto',
    );
    return '$_temp0';
  }

  @override
  String get action_create => 'crear';

  @override
  String get action_rename => 'cambiar el nombre de';

  @override
  String get action_archive => 'archivar';

  @override
  String get action_restore => 'restaurar';

  @override
  String get action_delete => 'eliminar';

  @override
  String get migrate => 'Migrar';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chats asignados',
      one: '$count chat asignado',
    );
    return '$_temp0';
  }

  @override
  String get date_today => 'Hoy';

  @override
  String get date_yesterday => 'Ayer';

  @override
  String get date_earlier => 'Anterior';

  @override
  String get nav_home => 'Inicio';

  @override
  String get nav_more => 'Más';

  @override
  String get status_completed => 'Completado';

  @override
  String get filter_all => 'Todos';

  @override
  String get filter_recent => 'Recientes';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  Clave: $status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model  \nmediante `$provider`';
  }

  @override
  String get deny => 'Denegar';

  @override
  String get connect => 'Conectar';

  @override
  String get appearance => 'Apariencia';

  @override
  String get connection_section => 'Conexión';

  @override
  String get about => 'Acerca de';

  @override
  String version_label(Object version) {
    return 'Versión $version';
  }

  @override
  String get matched => 'Coincidencia';

  @override
  String get search => 'Buscar';

  @override
  String get on => 'Activado';

  @override
  String get off => 'Desactivado';

  @override
  String get reasoning_off => 'Desactivado';

  @override
  String get hermes_response_ready => 'Respuesta de Hermes lista';

  @override
  String get admin_password_needed =>
      'Se necesita la contraseña de administrador';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      'Hermes necesita una contraseña de sudo para el comando de terminal pendiente.';

  @override
  String get sudo_password => 'Contraseña de sudo';

  @override
  String get secret_needed => 'Se necesita un secreto';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      'Hermes necesita un secreto para la habilidad pendiente.';

  @override
  String get secret_value => 'Valor del secreto';

  @override
  String get attached_file => 'Archivo adjunto';
}
