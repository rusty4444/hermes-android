// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get background_task_report => 'Tarefa em segundo plano';

  @override
  String get background_process_report => 'Processo em segundo plano';

  @override
  String get background_report_issues =>
      'Foram comunicados problemas — expanda para ver os detalhes.';

  @override
  String get background_report_expand => 'Expandir relatório';

  @override
  String get background_report_collapse => 'Recolher relatório';

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
  String get stop_and_send => 'Parar e enviar';

  @override
  String get message_queued_for_running_turn =>
      'Mensagem em fila para a execução atual.';

  @override
  String get running_message_not_accepted =>
      'O Hermes não conseguiu aceitar esta mensagem. O rascunho foi guardado; pare a resposta ou aguarde e volte a enviar.';

  @override
  String get running_message_delivery_unknown =>
      'Não foi possível confirmar a entrega. O rascunho foi guardado. Verifique a conversa antes de tentar novamente.';

  @override
  String get attachment_tap_to_preview => 'Toque para pré-visualizar';

  @override
  String get attachment_save => 'Guardar';

  @override
  String get attachment_share => 'Partilhar';

  @override
  String get attachment_saved => 'Ficheiro guardado';

  @override
  String get attachment_save_cancelled => 'Gravação cancelada';

  @override
  String get attachment_save_failed =>
      'Não foi possível guardar este ficheiro. Tente novamente.';

  @override
  String get attachment_share_failed =>
      'Não foi possível partilhar este ficheiro. Tente novamente.';

  @override
  String get attachment_download_failed =>
      'Não foi possível carregar este ficheiro. Verifique a ligação e tente novamente.';

  @override
  String get attachment_no_inline_preview =>
      'Não existe pré-visualização para este tipo de ficheiro. Guarde ou partilhe o ficheiro original para o abrir noutra aplicação.';

  @override
  String get attachment_image_failed =>
      'Não foi possível descodificar esta imagem. Pode guardar ou partilhar o ficheiro original.';

  @override
  String get attachment_text_truncated =>
      'Pré-visualização abreviada. Guarde ou partilhe o ficheiro para o ler na íntegra.';

  @override
  String get attachment_text_unavailable =>
      'Não foi possível apresentar este ficheiro como texto. Guarde ou partilhe o ficheiro original.';

  @override
  String get attachment_pdf_failed =>
      'Não foi possível pré-visualizar este PDF. Guarde ou partilhe o ficheiro original.';

  @override
  String get attachment_pdf_unavailable =>
      'A pré-visualização de PDF está disponível no Android. Pode guardar ou partilhar este ficheiro.';

  @override
  String attachment_pdf_page(int page, int total) {
    return 'Página $page de $total';
  }

  @override
  String get attachment_previous_page => 'Página anterior';

  @override
  String get attachment_next_page => 'Página seguinte';

  @override
  String get attachment_loading => 'A carregar pré-visualização…';

  @override
  String get attachment_document_text_notice =>
      'Pré-visualização de texto. A disposição, as imagens e a formatação podem diferir do original.';

  @override
  String get attachment_document_failed =>
      'Não foi possível pré-visualizar este documento. Guarde ou partilhe o ficheiro original.';

  @override
  String get attachment_document_empty =>
      'Não foi encontrado texto legível neste documento.';

  @override
  String get attachment_video_failed =>
      'Não foi possível reproduzir este vídeo. O formato ou codec pode não ser suportado. Guarde ou partilhe o ficheiro original.';

  @override
  String get attachment_video_play => 'Reproduzir';

  @override
  String get attachment_video_pause => 'Pausa';

  @override
  String get attachment_video_mute => 'Silenciar';

  @override
  String get attachment_video_unmute => 'Ativar som';

  @override
  String get attachment_video_seek => 'Posição do vídeo';

  @override
  String get attachment_close => 'Fechar pré-visualização';

  @override
  String get attachment_retry => 'Tentar novamente';

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
  String get theme_palette => 'Tema de cor';

  @override
  String get theme_palette_gold => 'Dourado';

  @override
  String get theme_palette_purple => 'Roxo';

  @override
  String get theme_palette_orange => 'Laranja';

  @override
  String get theme_palette_green => 'Verde';

  @override
  String get theme_palette_blue => 'Azul';

  @override
  String get theme_palette_red => 'Vermelho';

  @override
  String get theme_palette_teal => 'Verde-petróleo';

  @override
  String get theme_palette_pink => 'Rosa';

  @override
  String get theme_palette_indigo => 'Índigo';

  @override
  String get theme_palette_cyan => 'Ciano';

  @override
  String get assets_recent_subtitle =>
      'Encontre arquivos compartilhados pelo Hermes em chats salvos';

  @override
  String get assets_scope_notice =>
      'Arquivos gerados e compartilhados explicitamente pelo Hermes em respostas salvas. Esta é uma visão parcial do histórico de chats, não um catálogo completo de arquivos ou anexos. Os arquivos referenciados podem não existir mais.';

  @override
  String get assets_download_limit =>
      'Os arquivos só são carregados ao tocar neles. Pré-visualizações e downloads têm limite de 25 MiB por arquivo; use o painel para arquivos maiores.';

  @override
  String get assets_search_hint =>
      'Buscar nos arquivos encontrados ou nos chats de origem';

  @override
  String get assets_all => 'Todos';

  @override
  String get assets_images => 'Imagens';

  @override
  String get assets_audio => 'Áudio';

  @override
  String get assets_video => 'Vídeo';

  @override
  String get assets_documents => 'Documentos e outros arquivos';

  @override
  String get assets_empty =>
      'Nenhum recurso encontrado nas mensagens examinadas';

  @override
  String get assets_empty_detail =>
      'Examine mais chats ou mensagens mais antigas para consultar um período anterior. Anexos comuns e arquivos sem links não são indexados aqui.';

  @override
  String get assets_no_matches => 'Nenhum recurso correspondente';

  @override
  String get assets_load_more_chats => 'Examinar mais chats';

  @override
  String get assets_load_older_messages => 'Examinar mensagens mais antigas';

  @override
  String get assets_load_failed =>
      'Algumas partes do histórico não puderam ser lidas. Os resultados estão incompletos. Verifique a conexão com o painel e tente novamente.';

  @override
  String get assets_retry_failed => 'Tentar novamente as leituras que falharam';

  @override
  String get assets_partial =>
      'O servidor informou que o histórico está incompleto. Verifique o painel e atualize em seguida.';

  @override
  String assets_scan_summary(int files, int chats) {
    return 'Referências a arquivos encontradas: $files · Chats examinados: $chats';
  }

  @override
  String assets_open_chat(String title) {
    return 'Abrir chat: $title';
  }

  @override
  String get assets_file_too_large =>
      'Este arquivo excede o limite de download. Abra o painel para baixá-lo.';

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      'Uma pergunta pontual. É arquivada automaticamente após 72 horas; o que valer a pena guardar continua na memória.';

  @override
  String get archive_chat => 'Arquivar chat';

  @override
  String get unarchive_chat => 'Desarquivar chat';

  @override
  String get chat_archived => 'Chat arquivado';

  @override
  String get chat_unarchived => 'Chat desarquivado';

  @override
  String could_not_update_chat_archive(Object error) {
    return 'Não foi possível alterar o arquivo do chat: $error';
  }

  @override
  String get quick_chat_description => 'Uma pergunta pontual.';

  @override
  String get ai_full_text => 'IA + texto completo';

  @override
  String get ai_search_model => 'Modelo de busca com IA';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'A IA buscou: $aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'Arquivamento assistido por IA';

  @override
  String get api_key => 'Chave de API';

  @override
  String get api_server_key_from_hermes_env =>
      'API_SERVER_KEY de ~/.hermes/.env';

  @override
  String get active => 'Ativo';

  @override
  String get activity => 'Atividade';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      'A atividade lê o diário de turnos durável para saber o que o Hermes está fazendo. Verifique se o Gateway está acessível e tente novamente.';

  @override
  String get add => 'Adicionar';

  @override
  String get add_connection => 'Adicionar conexão';

  @override
  String get add_cron_job => 'Adicionar tarefa Cron';

  @override
  String get add_gateway_connection => 'Adicionar conexão de Gateway';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      'Adicionar e atualizar conexões do backup; manter as demais.';

  @override
  String get add_attachment => 'Adicionar anexo';

  @override
  String get add_new_cron_job => 'Adicionar nova tarefa Cron';

  @override
  String get add_to_chat => 'Adicionar ao chat';

  @override
  String get all_chats => 'Todos os chats';

  @override
  String get all_stored_message_content =>
      'Todo o conteúdo de mensagens armazenado';

  @override
  String get allow_for_this_session => 'Permitir nesta sessão';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      'Permitir comandos correspondentes até esta sessão do Hermes terminar.';

  @override
  String get allow_once => 'Permitir uma vez';

  @override
  String get always_allow => 'Permitir sempre';

  @override
  String get apply_to_this_chat => 'Aplicar a este chat';

  @override
  String get approval_needed => 'Aprovação necessária';

  @override
  String get approval_needed_description =>
      'Um comando aguarda sua aprovação ou recusa.';

  @override
  String get approve => 'Aprovar';

  @override
  String get archive => 'Arquivar';

  @override
  String get archive_project => 'Arquivar projeto';

  @override
  String archive_2(Object projectName) {
    return 'Arquivar $projectName?';
  }

  @override
  String archive_3(Object name) {
    return 'Arquivar $name?';
  }

  @override
  String get archived => 'Arquivado';

  @override
  String get archived_conversations_appear_here =>
      'Só as conversas arquivadas aparecem aqui. Os chats antigos continuam em Todos os chats.';

  @override
  String get archived_quick_chats => 'Chats rápidos arquivados';

  @override
  String get artifacts_attachments_and_generated_media =>
      'Artefatos, anexos e mídia gerada';

  @override
  String get ask_ai_to_find_a_conversation =>
      'Pedir à IA para encontrar uma conversa';

  @override
  String get assets => 'Recursos';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      'Os recursos precisam de um índice autoritativo do servidor no Gateway do Hermes antes de serem exibidos por projeto.';

  @override
  String get assets_unavailable => 'Recursos indisponíveis';

  @override
  String get attach_image_or_file => 'Anexar imagem ou arquivo';

  @override
  String get attachment_drafts => 'Rascunhos de anexos';

  @override
  String attachment_of(Object index, Object total) {
    return 'Anexo $index de $total';
  }

  @override
  String get auto_device_default => 'Automático (padrão do dispositivo)';

  @override
  String get agent => 'Agente';

  @override
  String get autonomous_agents => 'Agentes autônomos';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      'Recuperação em segundo plano indisponível — transporte legado';

  @override
  String get background_task_completed => 'Tarefa em segundo plano concluída';

  @override
  String get background_task_completed_description =>
      'Um comando de terminal em segundo plano foi concluído.';

  @override
  String get backup_restore => 'Backup e restauração';

  @override
  String backup_exported(Object destination) {
    return 'Backup exportado — $destination';
  }

  @override
  String get base_url => 'URL base';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      'A pré-visualização de binários não está disponível. Baixe o arquivo para abri-lo.';

  @override
  String get branch => 'Ramificação';

  @override
  String get branch_chat => 'Criar ramificação do chat';

  @override
  String get branch_created_in_hermes_history =>
      'Ramificação criada no histórico do Hermes.';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      'Navegue e gerencie suas sessões do Hermes Agent pelo celular. Conecta-se a um painel do Hermes em execução na sua rede local.';

  @override
  String get browse_server_files => 'Navegar pelos arquivos do servidor';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      'Navegue pelas pastas do miniserver por trás dos seus projetos';

  @override
  String get cancel => 'Cancelar';

  @override
  String get cancel_voice_input => 'Cancelar entrada de voz';

  @override
  String cannot_reach(Object host, Object port) {
    return 'Não é possível alcançar $host:$port.';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return 'Não é possível alcançar $host:$port. Verifique o host e a porta.';
  }

  @override
  String get change_ai_search_model => 'Alterar modelo de busca com IA';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return 'Altera o padrão de $label. Use o seletor em um chat para substituir apenas aquela conversa.';
  }

  @override
  String get chat_actions => 'Ações do chat';

  @override
  String get chats => 'Chats';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      'Os chats deste Gateway ainda não são agrupados. O agrupamento fica neste celular até que o Gateway possa hospedar projetos.';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      'Os chats deste projeto mostrarão aqui seu estado e última atividade.';

  @override
  String get chats_that_are_not_assigned_to_a_project =>
      'Chats que não estão atribuídos a um projeto';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      'Os chats que você iniciar neste projeto aparecerão aqui, em todos os dispositivos conectados a este Hermes.';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      'Verifique se o Gateway está em execução e acessível e tente novamente.';

  @override
  String get check_the_dashboard_connection_and_try_again =>
      'Verifique a conexão do painel e tente novamente.';

  @override
  String get check_the_connection_and_try_again =>
      'Verifique a conexão e tente novamente.';

  @override
  String get choose_a_small_model_to_rewrite_queries =>
      'Escolha um modelo pequeno para reescrever consultas';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      'Escolha um modelo de busca com IA antes de usar a busca com IA.';

  @override
  String get choose_an_active_project_next =>
      'Escolha um projeto ativo em seguida';

  @override
  String get choose_chat_model => 'Escolher modelo do chat';

  @override
  String get choose_files => 'Escolher arquivos';

  @override
  String get choose_image => 'Escolher imagem';

  @override
  String get choose_images => 'Escolher imagens';

  @override
  String get choose_its_destination_space => 'Escolha o espaço de destino';

  @override
  String get clear_search => 'Limpar busca';

  @override
  String get close => 'Fechar';

  @override
  String get code_copied => 'Código copiado';

  @override
  String get coming_next => 'Em breve';

  @override
  String get command => 'Comando';

  @override
  String get command_line_chats => 'Chats de linha de comando';

  @override
  String get compatibility_mode => 'Modo de compatibilidade';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      'Configure uma URL válida do Desktop Gateway antes de anexar arquivos.';

  @override
  String get confirm_always_allow => 'Confirmar permitir sempre';

  @override
  String get confirm_passphrase => 'Confirmar frase secreta';

  @override
  String connecting_to(Object baseUrl) {
    return 'Conectando a $baseUrl...';
  }

  @override
  String get connection_issue => 'Problema de conexão';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      'Conexão alterada — a resposta em andamento continua no servidor e será reconectada automaticamente.';

  @override
  String get connection_appearance_and_device_preferences =>
      'Conexão, aparência e preferências do dispositivo';

  @override
  String context_tokens(Object effectiveContextLength) {
    return 'Contexto: $effectiveContextLength tokens';
  }

  @override
  String get continue_label => 'Continuar';

  @override
  String get continue_working => 'Continuar trabalhando';

  @override
  String get conversations_in_this_project => 'Conversas neste projeto';

  @override
  String get copy_code => 'Copiar código';

  @override
  String get copy_message => 'Copiar mensagem';

  @override
  String could_not_branch_chat(Object error) {
    return 'Não foi possível criar ramificação do chat: $error';
  }

  @override
  String could_not_delete_session(Object error) {
    return 'Não foi possível excluir a sessão: $error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return 'Não foi possível negar o comando: $error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return 'Não foi possível carregar os modelos de busca com IA: $error';
  }

  @override
  String get could_not_load_conversations =>
      'Não foi possível carregar as conversas';

  @override
  String get could_not_load_files => 'Não foi possível carregar os arquivos';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return 'Não foi possível carregar os modelos deste perfil: $error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return 'Não foi possível carregar mais chats: $error';
  }

  @override
  String get could_not_open_link => 'Não foi possível abrir este link.';

  @override
  String get could_not_open_the_hermes_dashboard =>
      'Não foi possível abrir o painel do Hermes.';

  @override
  String get could_not_open_this_project =>
      'Não foi possível abrir este projeto';

  @override
  String get could_not_preview_file =>
      'Não foi possível pré-visualizar o arquivo';

  @override
  String get could_not_reach_hermes => 'Não foi possível alcançar o Hermes';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return 'Não foi possível alcançar/autenticar o painel em $host:$dashboardPort. Verifique a porta e as credenciais.';
  }

  @override
  String get could_not_read_activity => 'Não foi possível ler a atividade';

  @override
  String could_not_rename_chat(Object error) {
    return 'Não foi possível renomear o chat: $error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return 'Não foi possível enviar a aprovação: $error';
  }

  @override
  String get could_not_skip_the_hermes_question =>
      'Não foi possível pular a pergunta do Hermes.';

  @override
  String could_not_the_project(Object action, Object error) {
    return 'Não foi possível $action o projeto: $error';
  }

  @override
  String get couldn_t_delete_project => 'Não foi possível excluir o projeto';

  @override
  String couldn_t_load_runs(Object error) {
    return 'Não foi possível carregar as execuções: $error';
  }

  @override
  String get couldn_t_move_conversation => 'Não foi possível mover a conversa';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return 'Não foi possível mover para $label: $reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files =>
      'Não foi possível preparar os arquivos compartilhados.';

  @override
  String get couldn_t_promote_conversation =>
      'Não foi possível promover a conversa';

  @override
  String couldn_t_project(Object action) {
    return 'Não foi possível $action o projeto';
  }

  @override
  String get create => 'Criar';

  @override
  String get create_a_project => 'Criar um projeto';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      'Crie um projeto primeiro; depois os chats poderão viver dentro dele.';

  @override
  String get create_a_space_to_separate_related_conversations =>
      'Crie um espaço para separar conversas relacionadas.';

  @override
  String get create_branch => 'Criar ramificação';

  @override
  String get credit_notifications => 'Notificações de crédito';

  @override
  String get credit_notifications_description =>
      'O uso de crédito foi interrompido ou restaurado.';

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
  String get cron_jobs => 'Tarefas Cron';

  @override
  String get cron_job_added => 'Tarefa Cron adicionada';

  @override
  String get cron_job_updated => 'Tarefa Cron atualizada';

  @override
  String get cron_run => 'Execução do Cron';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      'Ordenação entre dispositivos e organização em massa reversível';

  @override
  String get current_profile_default => 'Padrão do perfil atual';

  @override
  String get custom_proxy_and_dashboard_details =>
      'Detalhes personalizados de proxy e painel';

  @override
  String get dark => 'Escuro';

  @override
  String get dashboard_proxy_settings => 'Configurações do painel / proxy';

  @override
  String get dashboard_password_optional => 'Senha do painel (opcional)';

  @override
  String get dashboard_port => 'Porta do painel';

  @override
  String get dashboard_username_optional =>
      'Nome de usuário do painel (opcional)';

  @override
  String get dashboard_behind_proxy => 'Painel atrás de proxy';

  @override
  String get dashboard_path_prefix => 'Prefixo de caminho do painel';

  @override
  String delegated_task(Object goal) {
    return 'Tarefa delegada: $goal';
  }

  @override
  String get delete => 'Excluir';

  @override
  String delete_2(Object name) {
    return 'Excluir “$name”?';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return 'Excluir “$title” do histórico remoto do Hermes? Esta ação não pode ser desfeita.';
  }

  @override
  String get delete_cron_job => 'Excluir tarefa Cron';

  @override
  String get delete_connections_that_are_not_in_the_backup =>
      'Excluir conexões que não estão no backup.';

  @override
  String delete_failed(Object error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String get delete_project => 'Excluir projeto';

  @override
  String get delete_session => 'Excluir sessão?';

  @override
  String delete_3(Object projectName) {
    return 'Excluir $projectName?';
  }

  @override
  String deleted(Object name) {
    return '“$name” excluído';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      'A entrega é incerta; recuperando sem reenviar…';

  @override
  String get desktop_gateway_url_optional =>
      'URL do Desktop Gateway (opcional)';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      'O Desktop Gateway não está configurado para esta conexão.';

  @override
  String get desktop_app => 'Aplicativo para desktop';

  @override
  String get developer_tool_calls => 'Chamadas de ferramentas do desenvolvedor';

  @override
  String get discord_chats => 'Chats do Discord';

  @override
  String get dismiss => 'Descartar';

  @override
  String get do_not_run_this_command => 'Não execute este comando.';

  @override
  String get documents_archives_audio_video_or_data =>
      'Documentos, arquivos compactados, áudio, vídeo ou dados';

  @override
  String get download => 'Baixar';

  @override
  String download_failed(Object error) {
    return 'Falha no download: $error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you =>
      'Fatos duráveis que o Hermes guarda sobre você';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      'Trabalho durável dentro de um dos seus projetos, compartilhado com o Desktop.';

  @override
  String get edit => 'Editar';

  @override
  String get edit_connection => 'Editar conexão';

  @override
  String get edit_cron_job => 'Editar tarefa Cron';

  @override
  String get edit_gateway_connection => 'Editar conexão de Gateway';

  @override
  String get edit_and_resend => 'Editar e reenviar';

  @override
  String get enable_notifications => 'Ativar notificações';

  @override
  String get enable_notifications_description =>
      'Desativar isto desativa todas as notificações abaixo.';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      'Permite anexos de arquivos pelo Gateway remoto do Desktop.';

  @override
  String get enter_a_name => 'Digite um nome';

  @override
  String get enter_a_passphrase => 'Digite uma frase secreta.';

  @override
  String get enter_the_passphrase_for_this_backup =>
      'Digite a frase secreta deste backup.';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      'Todas as conversas já estão atribuídas a um projeto.';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      'Tudo que ainda não é nativo, no painel web autenticado';

  @override
  String get explain_the_attached_content_clearly =>
      'Explique claramente o conteúdo anexado.';

  @override
  String explain_this_content_clearly(Object text) {
    return 'Explique claramente este conteúdo:\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      'Escolhas explícitas ajustam o tamanho do texto de acessibilidade do Android; “Sistema” o mantém inalterado.';

  @override
  String get export_label => 'Exportar';

  @override
  String get export_share => 'Exportar / compartilhar';

  @override
  String get external_api_clients => 'Clientes de API externos';

  @override
  String get extra_high => 'Muito alto';

  @override
  String get extract_tasks => 'Extrair tarefas';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      'Extraia do conteúdo anexado as decisões, prazos, responsáveis e itens de ação executáveis.';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return 'Extraia deste conteúdo as decisões, prazos, responsáveis e itens de ação executáveis:\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return 'Falha ao adicionar tarefa: $error';
  }

  @override
  String get failed_to_load_cron_jobs => 'Falha ao carregar as tarefas Cron';

  @override
  String get failed_to_load_memory => 'Falha ao carregar a memória';

  @override
  String get failed_to_load_messages => 'Falha ao carregar as mensagens';

  @override
  String get failed_to_load_settings => 'Falha ao carregar as configurações';

  @override
  String get failed_to_load_skills => 'Falha ao carregar as habilidades';

  @override
  String failed_to_update_job(Object error) {
    return 'Falha ao atualizar tarefa: $error';
  }

  @override
  String failed(Object error) {
    return 'Falha: $error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      'Arquivo anexado; o registro no catálogo de documentos está pendente.';

  @override
  String get file_reference_added_to_chat =>
      'Referência de arquivo adicionada ao chat';

  @override
  String get files => 'Arquivos';

  @override
  String get fill_from_document => 'Preencher a partir do documento';

  @override
  String get folder_is_empty => 'A pasta está vazia';

  @override
  String get folders => 'Pastas';

  @override
  String get full_text => 'Texto completo';

  @override
  String get gateway_api_access => 'Acesso à API do Gateway';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      'Gateway conectado, mas o painel não pôde ser alcançado ou autenticado. Verifique os detalhes do painel ou limpe-os para pular.';

  @override
  String get gateway_path_prefix => 'Prefixo de caminho do Gateway';

  @override
  String get go_to_end => 'Ir para o fim';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Hermes Agent para Android';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'O Hermes não pôde aceitar a resposta. Tente novamente.';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      'O Hermes não pôde carregar suas conexões salvas';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'O Hermes não aceitou a resposta. Tente novamente.';

  @override
  String get hermes_is_responding => 'O Hermes está respondendo…';

  @override
  String get hermes_is_waiting_for_input =>
      'O Hermes está aguardando sua entrada…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'O Hermes mantém a escala de texto de acessibilidade do Android ativa.';

  @override
  String get hermes_needs_your_input => 'O Hermes precisa da sua entrada';

  @override
  String get hermes_profile_optional => 'Perfil do Hermes (opcional)';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'O perfil do Hermes deve ser um nome simples de perfil, como “sol”, e não um caminho.';

  @override
  String get hermes_reasoning_details => 'Detalhes de raciocínio do Hermes';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'A recuperação do Hermes está indisponível: $error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'O Hermes interrompeu a recuperação com segurança. Nenhum prompt foi reenviado.';

  @override
  String get hide_passphrase => 'Ocultar frase secreta';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      'O início precisa dos seus chats recentes para saber o que merece sua atenção. Verifique se o Gateway está acessível e tente novamente.';

  @override
  String get host => 'Host';

  @override
  String get image_selection_was_interrupted_try_again =>
      'A seleção de imagem foi interrompida. Tente novamente.';

  @override
  String get import_label => 'Importar';

  @override
  String get inbox => 'Caixa de entrada';

  @override
  String get inbox_is_clear => 'Caixa de entrada vazia';

  @override
  String get input_needed => 'Entrada necessária';

  @override
  String get input_needed_description =>
      'O Hermes fez uma pergunta ou precisa de uma senha ou segredo.';

  @override
  String get insert_a_remote_file_reference =>
      'Inserir uma referência remota a @file';

  @override
  String get invalid_port_number => 'Número de porta inválido.';

  @override
  String get job_paused => 'Tarefa pausada';

  @override
  String get job_resumed => 'Tarefa retomada';

  @override
  String get job_triggered => 'Tarefa acionada';

  @override
  String get label => 'Rótulo';

  @override
  String last_activity(Object day, Object month, Object year) {
    return 'Última atividade $day/$month/$year';
  }

  @override
  String last(Object lastRun) {
    return 'Última: $lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      'Deixe em branco para o padrão (8642; 443 com https)';

  @override
  String get leave_blank_for_default_9119 =>
      'Deixe em branco para o padrão (9119)';

  @override
  String get light => 'Claro';

  @override
  String listening(Object elapsed) {
    return 'Ouvindo • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return 'Ouvindo, decorrido: $elapsed';
  }

  @override
  String get load_more => 'Carregar mais…';

  @override
  String get loading => 'Carregando';

  @override
  String get location => 'Localização';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      'Certifique-se de que o servidor de API do Gateway esteja em execução\n(hermes gateway status)';

  @override
  String matches(Object assigned, Object name) {
    return 'Corresponde a $name · $assigned';
  }

  @override
  String get memory => 'Memória';

  @override
  String get memory_about_you => 'Sobre si';

  @override
  String get memory_agent_notes => 'Notas do agente';

  @override
  String get memory_builtin_scope =>
      'Factos guardados em USER.md e MEMORY.md deste perfil. Os fornecedores de memória externos (incluindo MemPalace) não são apresentados aqui.';

  @override
  String get memory_read_only =>
      'Só de leitura. Peça ao Hermes no chat para corrigir ou esquecer um facto.';

  @override
  String get memory_unavailable =>
      'Este gateway ou perfil não pode fornecer os factos guardados. Verifique o perfil selecionado e atualize o Hermes, se necessário.';

  @override
  String get memory_load_error =>
      'Verifique a ligação e a autenticação do painel e tente novamente.';

  @override
  String get memory_read_full_fact => 'Ler o facto completo';

  @override
  String get memory_full_fact_requires_update =>
      'Os factos completos requerem um gateway Hermes mais recente. Atualize o Hermes e a lista.';

  @override
  String get memory_fact_detail_error =>
      'Não foi possível carregar o facto completo. Pode ter sido alterado; atualize a lista e tente novamente.';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'Os factos guardados aparecerão aqui quando o Hermes os memorizar.';

  @override
  String get merge => 'Mesclar';

  @override
  String get message => 'Mensagem';

  @override
  String get message_hermes => 'Enviar mensagem ao Hermes…';

  @override
  String get message_actions => 'Ações da mensagem';

  @override
  String get message_copied => 'Mensagem copiada';

  @override
  String get migrating => 'Migrando…';

  @override
  String get migration_complete => 'Migração concluída';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      'A migração falhou. Os espaços locais foram mantidos inalterados.';

  @override
  String get migration_incomplete => 'Migração incompleta';

  @override
  String get migration_preview => 'Pré-visualização da migração';

  @override
  String get model => 'Modelo';

  @override
  String get model_and_thinking_for_this_chat =>
      'Modelo e raciocínio para este chat';

  @override
  String model_was_not_changed(Object error) {
    return 'O modelo não foi alterado: $error';
  }

  @override
  String get move_attachment_next => 'Mover anexo para frente';

  @override
  String get move_attachment_previous => 'Mover anexo para trás';

  @override
  String get move_chat => 'Mover chat';

  @override
  String get move_conversation => 'Mover conversa';

  @override
  String get move_to_project => 'Mover para projeto';

  @override
  String get move_to_space => 'Mover para espaço';

  @override
  String get moved_to_a_project => 'Movido para um projeto';

  @override
  String moved_to(Object label) {
    return 'Movido para $label';
  }

  @override
  String get name => 'Nome';

  @override
  String get name_prompt_and_schedule_are_required =>
      'Nome, prompt e agendamento são obrigatórios';

  @override
  String get nav_activity => 'Atividade';

  @override
  String get nav_projects => 'Projetos';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Requer um contrato de arquivamento com correção no Gateway do Hermes.';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      'Requer um painel do Hermes acessível. Verifique o host, a porta e as credenciais desta conexão.';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Requer um índice de recursos autoritativo do servidor no Gateway do Hermes.';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Requer contratos de ordenação de fixados, mutação em lote e desfazer no Gateway do Hermes.';

  @override
  String get needs_you => 'Precisa de você';

  @override
  String get new_label => 'Novo';

  @override
  String get new_chat => 'Novo chat';

  @override
  String get new_chat_2 => 'Novo chat';

  @override
  String new_chat_3(Object projectName) {
    return 'Novo chat · $projectName';
  }

  @override
  String get new_project => 'Novo projeto';

  @override
  String get new_space => 'Novo espaço';

  @override
  String next(Object nextRun) {
    return 'Próxima: $nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'O Nginx injeta a autenticação — o app envia requisições limpas';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      'Nenhuma voz de TTS encontrada.\nInstale o Google Text-to-Speech e baixe os dados de voz.';

  @override
  String get no_active_projects_on_this_gateway =>
      'Nenhum projeto ativo neste Gateway';

  @override
  String get no_activity_yet => 'Nenhuma atividade ainda';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      'Nenhum chat está bloqueado, em execução ou aguardando retomada. Inicie um novo quando quiser.';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return 'Nenhum chat deste projeto corresponde a “$searchQuery”.';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      'Ainda não há chats neste espaço. Toque em + para iniciar um.';

  @override
  String get no_chats_yet => 'Ainda não há chats';

  @override
  String get no_connections => 'Sem conexões';

  @override
  String get no_conversation_matches_this_view =>
      'Nenhuma conversa corresponde a esta visualização.';

  @override
  String get no_cron_jobs => 'Sem tarefas Cron';

  @override
  String get no_folders_yet => 'Ainda não há pastas';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      'Nenhum espaço local foi encontrado para esta conexão, então os projetos já são a única forma de organização em uso aqui.';

  @override
  String get no_matches => 'Sem correspondências';

  @override
  String get no_memory_entries => 'Sem entradas de memória';

  @override
  String get no_message_content_matches =>
      'Nenhuma correspondência no conteúdo das mensagens';

  @override
  String get no_new_messages => 'Sem mensagens novas';

  @override
  String get no_projects_yet => 'Ainda não há projetos';

  @override
  String get no_runs_yet => 'Ainda não há execuções.';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return 'Nenhum projeto do servidor corresponde a este nome · $assigned';
  }

  @override
  String get no_sessions_yet => 'Ainda não há sessões';

  @override
  String get no_skills_found => 'Nenhuma habilidade encontrada';

  @override
  String get no_spaces_on_this_device => 'Nenhum espaço neste dispositivo';

  @override
  String get no_text_shared => 'Nenhum texto compartilhado';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      'Nenhum turno está bloqueado, em andamento ou recém-concluído. O trabalho que você iniciar aparecerá aqui.';

  @override
  String get no_turn_needs_your_input_or_has_failed =>
      'Nenhum turno precisa da sua entrada ou falhou.';

  @override
  String get no_unassigned_chats => 'Nenhum chat não atribuído.';

  @override
  String get nothing_changed_in_the_last_seven_days =>
      'Nada mudou nos últimos sete dias.';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      'Nada foi movido ainda — isto é apenas o que uma migração faria.';

  @override
  String get nothing_here => 'Nada aqui';

  @override
  String get nothing_is_running => 'Nada em execução';

  @override
  String get nothing_needs_you => 'Nada precisa de você';

  @override
  String get nothing_to_migrate => 'Nada para migrar';

  @override
  String get notifications => 'Notificações';

  @override
  String get notifications_permission_denied =>
      'As notificações estão bloqueadas pelo sistema. Ative-as para este app nas configurações do Android.';

  @override
  String get off_no_thinking => 'Desativado (sem raciocínio)';

  @override
  String get offline_showing_the_last_known_activity =>
      'Offline — mostrando a última atividade conhecida.';

  @override
  String get offline_showing_the_last_known_chats =>
      'Offline — mostrando os últimos chats conhecidos';

  @override
  String get offline_showing_the_last_known_projects =>
      'Offline — mostrando os últimos projetos conhecidos.';

  @override
  String get on_this_device => 'Neste dispositivo';

  @override
  String get on_device => 'No dispositivo';

  @override
  String get open_inbox => 'Abrir caixa de entrada';

  @override
  String open_inbox_2(Object count) {
    return 'Abrir caixa de entrada ($count)';
  }

  @override
  String get open_the_hermes_dashboard => 'Abrir o painel do Hermes';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      'Opcional. Para as abas Memória/Cron/Habilidades/Configurações. Deixe em branco para usar a porta padrão do painel (9119) sem login.';

  @override
  String get organization => 'Organização';

  @override
  String get other_answer => 'Outra resposta';

  @override
  String get overview => 'Visão geral';

  @override
  String get passphrase => 'Frase secreta';

  @override
  String get password_optional => 'Senha (opcional)';

  @override
  String get phone_or_tablet => 'Telefone ou tablet';

  @override
  String get pin_batch_and_undo => 'Fixar, em lote e desfazer';

  @override
  String get plugin_notifications => 'Notificações de plugins';

  @override
  String get plugin_notifications_description =>
      'O gateway enviou um aviso enquanto o app estava em segundo plano.';

  @override
  String get port => 'Porta';

  @override
  String get preparing_attachments => 'Preparando anexos…';

  @override
  String get preview_truncated => 'Pré-visualização truncada';

  @override
  String get preview_unavailable => 'Pré-visualização indisponível';

  @override
  String get profile => 'Perfil';

  @override
  String get profile_default_model => 'Modelo padrão do perfil';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return 'Padrão do perfil definido como $selectedModel. Chats com modelo próprio mantêm essa substituição.';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      'Perfil com que esta conexão conversa quando o painel serve vários perfis. Deixe em branco para um painel isolado por perfil.';

  @override
  String get project => 'Projeto';

  @override
  String get project_actions => 'Ações do projeto';

  @override
  String get project_chat => 'Chat do projeto';

  @override
  String get project_chats_unavailable => 'Chats do projeto indisponíveis';

  @override
  String get projects => 'Projetos';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      'Os projetos agrupam chats, arquivos e atividades relacionados e ficam sincronizados com o Hermes no seu computador.';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      'Os projetos precisam de uma conexão com o Desktop Gateway. Adicione a URL do Desktop Gateway a esta conexão para organizar chats entre dispositivos.';

  @override
  String get projects_unavailable => 'Projetos indisponíveis';

  @override
  String get projects_activity_new_navigation =>
      'Projetos, Atividade — nova navegação';

  @override
  String get promote_to_project => 'Promover a projeto';

  @override
  String get prompt => 'Prompt';

  @override
  String get protect_this_backup => 'Proteger este backup';

  @override
  String get provider => 'Provedor';

  @override
  String get proxy_injects_auth_app_sends_clean_requests =>
      'O proxy injeta a autenticação; o app envia requisições limpas';

  @override
  String get quick_chat => 'Chat rápido';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      'Chats rápidos aparecem aqui após o período de retenção.';

  @override
  String get read_aloud => 'Ler em voz alta';

  @override
  String get read_aloud_is_unavailable_on_this_device =>
      'A leitura em voz alta não está disponível neste dispositivo';

  @override
  String get reading_response_aloud => 'Lendo a resposta em voz alta';

  @override
  String get ready_to_upload => 'Pronto para enviar';

  @override
  String get reasoning => 'Raciocínio';

  @override
  String get recently_completed => 'Concluído recentemente';

  @override
  String get recently_active => 'Ativo recentemente';

  @override
  String get recovering_hermes => 'Recuperando o Hermes…';

  @override
  String get refresh => 'Atualizar';

  @override
  String get regenerate_response => 'Regenerar resposta';

  @override
  String get remove_attachment => 'Remover anexo';

  @override
  String get rename => 'Renomear';

  @override
  String get rename_chat => 'Renomear chat';

  @override
  String get rename_project => 'Renomear projeto';

  @override
  String get rename_space => 'Renomear espaço';

  @override
  String rename_2(Object projectName) {
    return 'Renomear $projectName';
  }

  @override
  String rename_3(Object name) {
    return 'Renomear $name';
  }

  @override
  String get replace => 'Substituir';

  @override
  String get repositories => 'Repositórios';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      'Pesquise o conteúdo anexado, verifique as afirmações importantes e cite as fontes.';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return 'Pesquise este conteúdo, verifique as afirmações importantes e cite as fontes:\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return 'Falha na redefinição: $retryError. O armazenamento seguro pode precisar ser reinstalado.';
  }

  @override
  String get reset_saved_connections => 'Redefinir conexões salvas';

  @override
  String get responding => 'Respondendo…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return 'Resposta fechada localmente; falha ao parar o Gateway: $error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      'Resposta fechada localmente; nenhum turno ativo do Gateway foi encontrado.';

  @override
  String get response_complete => 'Resposta concluída';

  @override
  String get response_complete_description =>
      'Um turno foi concluído enquanto o app estava em segundo plano.';

  @override
  String get response_ready => 'Resposta pronta';

  @override
  String get response_stopped => 'Resposta interrompida.';

  @override
  String get restore => 'Restaurar';

  @override
  String get restore_configuration => 'Restaurar configuração';

  @override
  String get restore_project => 'Restaurar projeto';

  @override
  String get retry => 'Tentar novamente';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return 'Falha ao tentar novamente para $name. O rascunho e o prompt foram mantidos.';
  }

  @override
  String get retry_upload => 'Tentar enviar novamente';

  @override
  String retrying(Object name) {
    return 'Tentando novamente $name…';
  }

  @override
  String get review_local_spaces => 'Revisar espaços locais';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      'Revisar ou promover chats rápidos além do período de retenção';

  @override
  String get review_the_attached_content => 'Revise o conteúdo anexado.';

  @override
  String get run_only_this_command => 'Execute apenas este comando.';

  @override
  String get running_now => 'Em execução';

  @override
  String get save => 'Salvar';

  @override
  String get save_changes => 'Salvar alterações';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      'Salve uma regra permanente na configuração do Hermes.';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      'Salve os fatos duráveis do conteúdo anexado na memória e confirme o que foi retido.';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return 'Salve os fatos duráveis deste conteúdo na memória e confirme o que foi retido:\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      'Salve suas conexões e configurações em um arquivo criptografado e restaure-as após reinstalar ou em outro dispositivo.';

  @override
  String save_2(Object filename) {
    return 'Salvar $filename';
  }

  @override
  String get schedule => 'Agendamento';

  @override
  String get scheduled_jobs_and_their_last_runs =>
      'Tarefas agendadas e suas últimas execuções';

  @override
  String get scheduled_tasks => 'Tarefas agendadas';

  @override
  String get script_only_no_agent => 'Somente script (sem agente)';

  @override
  String get scroll_horizontally => 'Rolar horizontalmente';

  @override
  String get search_all_chats => 'Pesquisar todos os chats';

  @override
  String get search_all_message_content =>
      'Pesquisar todo o conteúdo das mensagens';

  @override
  String get search_chats => 'Pesquisar chats';

  @override
  String get search_conversations => 'Pesquisar conversas';

  @override
  String get search_loaded_chats => 'Pesquisar chats carregados';

  @override
  String get search_mode => 'Modo de busca';

  @override
  String get select_one_option_or_enter_another_answer =>
      'Selecione uma opção ou digite outra resposta.';

  @override
  String get select_one_or_more_options_then_continue =>
      'Selecione uma ou mais opções e continue.';

  @override
  String get select_text => 'Selecionar texto';

  @override
  String get send => 'Enviar';

  @override
  String send_failed(Object error) {
    return 'Falha no envio: $error';
  }

  @override
  String get send_message => 'Enviar mensagem';

  @override
  String get send_test_notification => 'Enviar notificação de teste';

  @override
  String get session_sources => 'Fontes de sessões';

  @override
  String get session_deleted_from_remote_hermes =>
      'Sessão excluída do Hermes remoto.';

  @override
  String session_search_failed(Object error) {
    return 'Falha na busca de sessões: $error';
  }

  @override
  String get set_profile_default => 'Definir como padrão do perfil';

  @override
  String get settings => 'Configurações';

  @override
  String get share_to_hermes => 'Compartilhar com o Hermes';

  @override
  String get show_passphrase => 'Mostrar frase secreta';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      'Mostrar chamadas de ferramentas, raciocínio e metadados de mensagens';

  @override
  String get signal_messages => 'Mensagens do Signal';

  @override
  String get skills => 'Habilidades';

  @override
  String skills_2(Object count) {
    return 'Habilidades ($count)';
  }

  @override
  String get skills_and_tools => 'Habilidades e ferramentas';

  @override
  String get skip => 'Pular';

  @override
  String get slack_chats => 'Chats do Slack';

  @override
  String source(Object source) {
    return 'Origem: $source';
  }

  @override
  String get space_actions => 'Ações do espaço';

  @override
  String get spaces => 'Espaços';

  @override
  String get speak_to_hermes => 'Fale com o Hermes';

  @override
  String get speech_recognition_is_unavailable =>
      'O reconhecimento de fala não está disponível';

  @override
  String get spoken_replies => 'Respostas faladas';

  @override
  String get spoken_replies_off => 'Respostas faladas desativadas';

  @override
  String get spoken_replies_on => 'Respostas faladas ativadas';

  @override
  String get stalled_no_update_from_hermes =>
      'Travado — sem atualizações do Hermes';

  @override
  String get start_something_new => 'Começar algo novo';

  @override
  String get start_voice_input => 'Iniciar entrada de voz';

  @override
  String get starting_hermes => 'Iniciando o Hermes…';

  @override
  String get media_card_download => 'Download file';

  @override
  String get media_card_tap_to_download => 'Tap to download';

  @override
  String get still_loading_your_projects => 'Ainda carregando seus projetos.';

  @override
  String get stop => 'Parar';

  @override
  String get stop_response => 'Parar resposta';

  @override
  String get stop_voice_input => 'Parar entrada de voz';

  @override
  String get submitted_waiting_for_hermes => 'Enviado, aguardando o Hermes';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      'Sugerir projetos e aprender com suas correções';

  @override
  String get summarize_the_attached_content => 'Resuma o conteúdo anexado.';

  @override
  String summarize_this_content(Object text) {
    return 'Resuma este conteúdo:\n\n$text';
  }

  @override
  String get switch_profile => 'Trocar de perfil';

  @override
  String get system => 'Sistema';

  @override
  String get take_photo => 'Tirar foto';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      'Toque em + para adicionar um Gateway do Hermes remoto\n(servidor de API, porta 8642)';

  @override
  String get tap_the_button_to_start_a_new_chat =>
      'Toque no botão + para iniciar um novo chat';

  @override
  String get telegram_messages => 'Mensagens do Telegram';

  @override
  String get terminal_sessions => 'Sessões de terminal';

  @override
  String get test_notification_body =>
      'Se você está vendo isto, as notificações estão funcionando.';

  @override
  String get test_notification_sent => 'Notificação de teste enviada.';

  @override
  String get test_notification_title => 'Teste de notificação do Hermes';

  @override
  String get test_notification_unsupported =>
      'Não foi possível enviar a notificação — verifique se o sistema permite notificações.';

  @override
  String get text_size => 'Tamanho do texto';

  @override
  String get text_size_preview => 'Pré-visualização do tamanho do texto';

  @override
  String text_size_2(Object label) {
    return 'Tamanho do texto: $label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely =>
      'A chave de API não pôde ser armazenada com segurança.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      'O projeto será movido para “Arquivado”. Seus chats e arquivos permanecem intactos, e você pode restaurá-lo a qualquer momento.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      'O projeto será movido para “Arquivado”. Seus chats e arquivos permanecem intactos, e você pode restaurá-lo depois.';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      'O perfil ativo não retornou nenhum modelo selecionável.';

  @override
  String get the_backup_could_not_be_exported =>
      'O backup não pôde ser exportado.';

  @override
  String get the_backup_could_not_be_restored =>
      'O backup não pôde ser restaurado.';

  @override
  String get the_connection_could_not_be_deleted_safely =>
      'A conexão não pôde ser excluída com segurança.';

  @override
  String get the_connection_could_not_be_stored_securely =>
      'A conexão não pôde ser armazenada com segurança.';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      'As credenciais do painel não puderam ser armazenadas com segurança.';

  @override
  String get the_detached_reply_failed => 'A resposta desacoplada falhou.';

  @override
  String the_detached_reply_failed_2(Object error) {
    return 'A resposta desacoplada falhou: $error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      'O arquivo contém suas chaves de API e a senha do painel, por isso é criptografado. Sem esta frase secreta, o backup não pode ser restaurado.';

  @override
  String get the_last_turn_failed => 'O último turno falhou';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return 'O armazenamento local de conexões parece danificado ($errorType). Você pode redefinir as conexões salvas e começar do zero. Os chats no seu Gateway não são afetados.';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      'O modelo apenas reescreve sua pergunta como uma consulta curta de texto completo. O Hermes usa as credenciais do provedor já configuradas no host.';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      'O servidor ainda não informou pastas para este projeto. Arquivos globais continua disponível em Mais.';

  @override
  String get the_turn_failed => 'O turno falhou';

  @override
  String get the_two_passphrases_do_not_match =>
      'As duas frases secretas não coincidem.';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      'O valor é enviado diretamente ao Gateway do Hermes ativo e não é salvo por este app Android.';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      'Não há arquivos visíveis nesta pasta do servidor.';

  @override
  String get thinking_effort => 'Esforço de raciocínio';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      'Este Gateway do Hermes ainda não oferece suporte a abrir um projeto. Atualize o Hermes no servidor para navegar por um projeto pelo celular.';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      'Este Gateway do Hermes é mais antigo que os projetos do servidor, então os chats ficam agrupados apenas neste dispositivo. Atualize o Hermes para compartilhar os mesmos projetos entre seus dispositivos.';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      'Este projeto precisa de uma pasta antes de iniciar um chat nele. Adicione uma pasta e tente novamente.';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      'Este chat ainda não tem mensagens disponíveis na sessão do Desktop.';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      'Isto cria uma regra permanente no Hermes. Revise o comando completo antes de confirmar.';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      'Este Gateway ainda não hospeda projetos. Atualize o Gateway para organizar chats entre dispositivos.';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      'Isto exclui o projeto permanentemente. Os chats não serão excluídos; voltarão para “Não atribuído”.';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      'Este servidor não oferece recuperação em segundo plano — os chats rodam ao vivo';

  @override
  String get this_week => 'Esta semana';

  @override
  String get titles_previews_and_models =>
      'Títulos, pré-visualizações e modelos';

  @override
  String get tool_activity => 'Atividade de ferramentas';

  @override
  String get trigger_now => 'Acionar agora';

  @override
  String get received_outcome_unknown =>
      'Turno encerrado — resultado não confirmado';

  @override
  String get turn_completed => 'Turno concluído';

  @override
  String get turn_failed => 'Turno falhou';

  @override
  String get turn_failed_description =>
      'Um turno em segundo plano terminou com erro.';

  @override
  String get turn_recovery_failed => 'Falha na recuperação do turno';

  @override
  String get unable_to_prepare_this_file_try_another_one =>
      'Não foi possível preparar este arquivo. Tente outro.';

  @override
  String get unable_to_prepare_this_image_try_another_one =>
      'Não foi possível preparar esta imagem. Tente outra.';

  @override
  String unable_to_prepare(Object name) {
    return 'Não foi possível preparar $name.';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      'Não foi possível ler a imagem selecionada. A seleção foi mantida.';

  @override
  String get unassigned => 'Não atribuído';

  @override
  String get unassigned_chats => 'Chats não atribuídos';

  @override
  String get untitled_chat => 'Chat sem título';

  @override
  String get untitled_session => 'Sessão sem título';

  @override
  String get update_api_key => 'Atualizar chave de API';

  @override
  String get upload_failed => 'Falha no envio';

  @override
  String get upload_failed_tap_retry =>
      'Falha no envio • toque para tentar novamente';

  @override
  String uploading(Object index, Object name, Object total) {
    return 'Enviando $index/$total: $name';
  }

  @override
  String get use_as_is => 'Usar como está';

  @override
  String get use_at_least_8_characters => 'Use pelo menos 8 caracteres.';

  @override
  String get use_for_cron_jobs_backed_by_scripts =>
      'Use para tarefas Cron baseadas em scripts.';

  @override
  String get use_on_device => 'Usar no dispositivo';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      'Use o conteúdo anexado para identificar e preencher os campos relevantes do documento ou formulário. Pergunte antes de enviar qualquer coisa.';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return 'Use este conteúdo para identificar e preencher os campos relevantes do documento ou formulário. Pergunte antes de enviar qualquer coisa:\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      'Usado para prefixos de caminho hospedados e para as abas Configurações, Memória, Habilidades e Cron. Deixe usuário/senha em branco para um painel aberto, ou ative o modo proxy quando seu proxy reverso injetar a autenticação do painel.';

  @override
  String get username_optional => 'Nome de usuário (opcional)';

  @override
  String using(Object displayName) {
    return 'Usando $displayName…';
  }

  @override
  String get verbose_mode => 'Modo detalhado';

  @override
  String get message_metadata => 'Message details';

  @override
  String get voice => 'Voz';

  @override
  String voice_setup_failed(Object error) {
    return 'Falha na configuração de voz: $error';
  }

  @override
  String get waiting_for_your_input => 'Aguardando sua entrada';

  @override
  String get what_hermes_knows_how_to_do => 'O que o Hermes sabe fazer';

  @override
  String get what_should_the_agent_do => 'O que o agente deve fazer?';

  @override
  String get whatsapp_messages => 'Mensagens do WhatsApp';

  @override
  String get which_project => 'Qual projeto?';

  @override
  String get workspace => 'Área de trabalho';

  @override
  String get wrap_lines => 'Quebrar linhas';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return 'Você pode anexar até $maxRemoteAttachmentDrafts itens.';
  }

  @override
  String get your_answer => 'Sua resposta';

  @override
  String get e_g_dashboard => 'ex.: /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      'ex.: /dashboard (caminho do proxy antes de /api/)';

  @override
  String get e_g_profile_peter => 'ex.: /profile/peter';

  @override
  String get e_g_sol => 'ex.: sol';

  @override
  String get e_g_0_9_or_every_2h => 'ex.: 0 9 * * * ou every 2h';

  @override
  String get e_g_daily_backup => 'ex.: Backup diário';

  @override
  String downloaded(Object filename) {
    return '$filename baixado';
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
      '192.168.1.50, 100.x.y.z ou hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      'ex.: /profile/peter (caminho do proxy antes de /api/ e /v1/)';

  @override
  String and_more(Object count) {
    return 'e mais $count';
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
    return '$chats · somente neste dispositivo';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count espaços',
      one: '$count espaço',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => 'nenhum projeto novo necessário';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projetos a criar',
      one: '$count projeto a criar',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return '$linkedSessions chats migrados · $createdProjects projetos criados';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '$unlinkedSessions chats permaneceram em espaços locais e podem ser tentados novamente com segurança.';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • Recomendado: pequeno e econômico';
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
  String get this_chat => 'este chat';

  @override
  String get profile_default => 'padrão do perfil';

  @override
  String minutes_ago(Object count) {
    return 'há $count min';
  }

  @override
  String hours_ago(Object count) {
    return 'há $count h';
  }

  @override
  String days_ago(Object count) {
    return 'há $count d';
  }

  @override
  String get now_label => 'agora';

  @override
  String get latest_label => 'Mais recente';

  @override
  String new_count_indicator(Object count) {
    return '$count novos';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count novas mensagens',
      one: '$count nova mensagem',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return '$failures com falha • $total no total';
  }

  @override
  String activity_completed_summary(Object count) {
    return '$count concluídos';
  }

  @override
  String tool_start_observed(Object time) {
    return 'Início observado às $time (hora local)';
  }

  @override
  String tool_last_observed(Object time) {
    return 'Última observação às $time (hora local)';
  }

  @override
  String tool_result_recorded(Object time) {
    return 'Resultado registado às $time (hora local)';
  }

  @override
  String get tool_time_unavailable => 'Hora indisponível';

  @override
  String get hermes_is_using_a_tool => 'O Hermes está usando uma ferramenta';

  @override
  String hermes_is_using_tools(Object count) {
    return 'O Hermes está usando $count ferramentas';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return '$count tarefa(s) delegada(s) concluída(s)';
  }

  @override
  String delegated_tasks_active(Object count) {
    return '$count tarefa(s) delegada(s) ativa(s)';
  }

  @override
  String branch_main(Object label) {
    return '$label · main';
  }

  @override
  String get you_heading => '## Você';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => 'Ação';

  @override
  String get destination_label => 'Destino';

  @override
  String get preview_label => 'Pré-visualização';

  @override
  String get share_action_summarize => 'Resumir';

  @override
  String get share_action_explain => 'Explicar';

  @override
  String get share_action_research => 'Pesquisar';

  @override
  String get share_action_remember => 'Lembrar';

  @override
  String get text_size_small => 'Pequeno';

  @override
  String get text_size_default => 'Padrão';

  @override
  String get text_size_large => 'Grande';

  @override
  String get text_size_extra_large => 'Muito grande';

  @override
  String get text_size_use_system_description =>
      'Usar exatamente o tamanho de texto de acessibilidade do Android.';

  @override
  String text_size_percent_description(Object percent) {
    return '$percent% do tamanho de texto do Android.';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return '$count arquivo(s) ignorado(s): limite, tamanho, ilegível ou nome de arquivo sensível.';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort agora se aplicam somente a este chat.';
  }

  @override
  String get reasoning_minimal => 'Mínimo';

  @override
  String get reasoning_low => 'Baixo';

  @override
  String get reasoning_medium => 'Médio';

  @override
  String get reasoning_high => 'Alto';

  @override
  String get reasoning_max => 'Máximo';

  @override
  String get reasoning_ultra => 'Ultra';

  @override
  String get status_running => 'Em execução';

  @override
  String get status_failed => 'Falhou';

  @override
  String get status_done => 'Concluído';

  @override
  String get status_idle => 'Inativo';

  @override
  String get upload_status_uploading => 'Enviando';

  @override
  String get upload_status_uploaded => 'Enviado';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anexos',
      one: '$count anexo',
    );
    return '$_temp0';
  }

  @override
  String get action_create => 'criar';

  @override
  String get action_rename => 'renomear';

  @override
  String get action_archive => 'arquivar';

  @override
  String get action_restore => 'restaurar';

  @override
  String get action_delete => 'excluir';

  @override
  String get migrate => 'Migrar';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chats atribuídos',
      one: '$count chat atribuído',
    );
    return '$_temp0';
  }

  @override
  String get date_today => 'Hoje';

  @override
  String get date_yesterday => 'Ontem';

  @override
  String get date_earlier => 'Anterior';

  @override
  String get nav_home => 'Início';

  @override
  String get nav_more => 'Mais';

  @override
  String get status_completed => 'Concluído';

  @override
  String get filter_all => 'Todos';

  @override
  String get filter_recent => 'Recentes';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  Chave: $status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model  \nvia `$provider`';
  }

  @override
  String get deny => 'Negar';

  @override
  String get connect => 'Conectar';

  @override
  String get appearance => 'Aparência';

  @override
  String get connection_section => 'Conexão';

  @override
  String get about => 'Sobre';

  @override
  String version_label(Object version) {
    return 'Versão $version';
  }

  @override
  String get matched => 'Correspondência';

  @override
  String get search => 'Pesquisar';

  @override
  String get on => 'Ativado';

  @override
  String get off => 'Desativado';

  @override
  String get reasoning_off => 'Desativado';

  @override
  String get hermes_response_ready => 'Resposta do Hermes pronta';

  @override
  String get admin_password_needed => 'Senha de administrador necessária';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      'O Hermes precisa de uma senha sudo para o comando de terminal pendente.';

  @override
  String get sudo_password => 'Senha do sudo';

  @override
  String get secret_needed => 'Segredo necessário';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      'O Hermes precisa de um segredo para a habilidade pendente.';

  @override
  String get secret_value => 'Valor do segredo';

  @override
  String get attached_file => 'Arquivo anexado';

  @override
  String get pin_on_this_device => 'Fixar neste dispositivo';

  @override
  String get unpin_on_this_device => 'Desafixar neste dispositivo';

  @override
  String get pinned_on_this_device => 'Fixados neste dispositivo';

  @override
  String get could_not_save_chat_pin =>
      'Não foi possível salvar a fixação neste dispositivo';

  @override
  String get could_not_save_chat_spaces =>
      'Não foi possível guardar os espaços de conversa neste dispositivo';

  @override
  String get update_available => 'Atualização disponível';

  @override
  String get a_newer_hermes_android_build_is_available_on_github =>
      'Está disponível no GitHub uma compilação mais recente do Hermes Android.';

  @override
  String get release_notes => 'Notas de lançamento';

  @override
  String get view_release => 'Ver a versão';

  @override
  String get skip_this_version => 'Ignorar esta versão';

  @override
  String get later => 'Mais tarde';

  @override
  String get check_for_updates => 'Procurar atualizações';

  @override
  String get check_for_updates_on_launch => 'Procurar atualizações ao iniciar';

  @override
  String get you_re_on_the_latest_version => 'Já tem a versão mais recente.';

  @override
  String get couldn_t_check_for_updates =>
      'Não foi possível procurar atualizações.';

  @override
  String get chat_density => 'Densidade do chat';

  @override
  String chat_density_2(Object label) {
    return 'Densidade do chat: $label';
  }

  @override
  String get chat_density_comfortable => 'Confortável';

  @override
  String get chat_density_compact => 'Compacta';

  @override
  String get chat_density_comfortable_description =>
      'Balões mais amplos com um rótulo de remetente acima de cada mensagem.';

  @override
  String get chat_density_compact_description =>
      'Balões mais justos e sem rótulo para caberem mais mensagens no ecrã.';

  @override
  String chat_density_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String
  get compact_removes_the_you_and_hermes_labels_and_trims_bubble_padding_spacing_and_side_margins =>
      'O modo compacto remove os rótulos You e Hermes e reduz as margens internas, o espaçamento e as margens laterais dos balões.';

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
  String get background_work => 'Trabalho em segundo plano';

  @override
  String get keep_chats_active_in_background =>
      'Manter conversas ativas em segundo plano';

  @override
  String get background_work_description =>
      'Mantém conectadas as conversas iniciadas por você enquanto o app está em segundo plano. Conexões ociosas podem ser desconectadas. Consome mais bateria e dados. Desativar não interrompe o trabalho no servidor.';

  @override
  String get background_work_limits =>
      'O Android ainda pode suspender conexões no modo Doze ou encerrar o processo do app. Notificações após o encerramento do processo exigem uma configuração de push separada. A parada forçada não é suportada.';

  @override
  String get background_work_disclosure =>
      'Uma notificação obrigatória do serviço permanece visível enquanto a proteção em segundo plano está ativa, mesmo com as notificações opcionais de conversa desativadas.';

  @override
  String get battery_optimisation_settings =>
      'Configurações de otimização da bateria';

  @override
  String get battery_optimisation_description =>
      'Abre as configurações do Android para revisar as restrições de bateria. Nenhuma exceção é solicitada automaticamente e alterar as configurações não garante a entrega.';

  @override
  String get battery_settings_unavailable =>
      'Não foi possível abrir as configurações de bateria neste dispositivo.';

  @override
  String get background_work_save_failed =>
      'Não foi possível salvar a configuração de trabalho em segundo plano.';

  @override
  String get ongoing_chat_channel_name => 'Conversas ativas';

  @override
  String get ongoing_chat_channel_description =>
      'Atualizações silenciosas de conversas iniciadas por você ainda não concluídas';

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
  String get activity_status_unconfirmed => 'Estado não confirmado';

  @override
  String get activity_recently_updated => 'Atualizado recentemente';

  @override
  String get activity_reconnecting =>
      'A restabelecer ligação — a verificar o estado do turno';

  @override
  String get activity_outcome_unknown =>
      'Não foi possível confirmar o resultado do turno. Abra o chat para verificar.';

  @override
  String get activity_chat_updated_detail =>
      'Atividade do chat registada pelo Gateway; o estado do turno em tempo real não está disponível.';

  @override
  String get activity_updated => 'Atualizado';

  @override
  String get activity_empty_title => 'Sem atividade recente';

  @override
  String get activity_empty_detail =>
      'Aqui aparecem os turnos iniciados nesta app e os chats do Gateway atualizados nos últimos 7 dias.';

  @override
  String get activity_read_error =>
      'A Atividade não conseguiu ler os registos dos turnos ou os chats do Gateway. Verifique a ligação e tente novamente.';

  @override
  String get activity_chat_unavailable =>
      'Este chat já não está disponível ou não foi possível contactar o Gateway.';

  @override
  String get activity_partial_title => 'Atividade parcialmente carregada';

  @override
  String get activity_partial_detail =>
      'É apresentado um intervalo limitado da atividade do gateway. Podem existir mais conversas; puxe para atualizar.';
}

/// The translations for Portuguese, as used in Brazil (`pt_BR`).
class AppLocalizationsPtBr extends AppLocalizationsPt {
  AppLocalizationsPtBr() : super('pt_BR');

  @override
  String get background_task_report => 'Tarefa em segundo plano';

  @override
  String get background_process_report => 'Processo em segundo plano';

  @override
  String get background_report_issues =>
      'Problemas relatados — expanda para ver os detalhes.';

  @override
  String get background_report_expand => 'Expandir relatório';

  @override
  String get background_report_collapse => 'Recolher relatório';

  @override
  String get stop_and_send => 'Parar e enviar';

  @override
  String get message_queued_for_running_turn =>
      'Mensagem na fila da execução atual.';

  @override
  String get running_message_not_accepted =>
      'O Hermes não conseguiu aceitar esta mensagem. Seu rascunho foi mantido; pare a resposta ou aguarde e envie novamente.';

  @override
  String get running_message_delivery_unknown =>
      'Não foi possível confirmar a entrega. Seu rascunho foi mantido. Confira a conversa antes de tentar novamente.';

  @override
  String get attachment_tap_to_preview => 'Toque para visualizar';

  @override
  String get attachment_save => 'Salvar';

  @override
  String get attachment_share => 'Compartilhar';

  @override
  String get attachment_saved => 'Arquivo salvo';

  @override
  String get attachment_save_cancelled => 'Salvamento cancelado';

  @override
  String get attachment_save_failed =>
      'Não foi possível salvar este arquivo. Tente novamente.';

  @override
  String get attachment_share_failed =>
      'Não foi possível compartilhar este arquivo. Tente novamente.';

  @override
  String get attachment_download_failed =>
      'Não foi possível carregar este arquivo. Verifique a conexão e tente novamente.';

  @override
  String get attachment_no_inline_preview =>
      'Não há prévia disponível para este tipo de arquivo. Salve ou compartilhe o arquivo original para abri-lo em outro aplicativo.';

  @override
  String get attachment_image_failed =>
      'Não foi possível decodificar esta imagem. Você ainda pode salvar ou compartilhar o arquivo original.';

  @override
  String get attachment_text_truncated =>
      'Prévia abreviada. Salve ou compartilhe o arquivo para ler todo o conteúdo.';

  @override
  String get attachment_text_unavailable =>
      'Não foi possível exibir este arquivo como texto. Salve ou compartilhe o arquivo original.';

  @override
  String get attachment_pdf_failed =>
      'Não foi possível visualizar este PDF. Salve ou compartilhe o arquivo original.';

  @override
  String get attachment_pdf_unavailable =>
      'A prévia de PDF está disponível no Android. Você ainda pode salvar ou compartilhar este arquivo.';

  @override
  String attachment_pdf_page(int page, int total) {
    return 'Página $page de $total';
  }

  @override
  String get attachment_previous_page => 'Página anterior';

  @override
  String get attachment_next_page => 'Próxima página';

  @override
  String get attachment_loading => 'Carregando prévia…';

  @override
  String get attachment_document_text_notice =>
      'Prévia do texto. O layout, as imagens e a formatação podem diferir do original.';

  @override
  String get attachment_document_failed =>
      'Não foi possível visualizar este documento. Salve ou compartilhe o arquivo original.';

  @override
  String get attachment_document_empty =>
      'Nenhum texto legível foi encontrado neste documento.';

  @override
  String get attachment_video_failed =>
      'Não foi possível reproduzir este vídeo. O formato ou codec pode não ser compatível. Salve ou compartilhe o arquivo original.';

  @override
  String get attachment_video_play => 'Reproduzir';

  @override
  String get attachment_video_pause => 'Pausar';

  @override
  String get attachment_video_mute => 'Silenciar';

  @override
  String get attachment_video_unmute => 'Ativar som';

  @override
  String get attachment_video_seek => 'Posição do vídeo';

  @override
  String get attachment_close => 'Fechar prévia';

  @override
  String get attachment_retry => 'Tentar novamente';

  @override
  String get theme_palette => 'Tema de cor';

  @override
  String get theme_palette_gold => 'Dourado';

  @override
  String get theme_palette_purple => 'Roxo';

  @override
  String get theme_palette_orange => 'Laranja';

  @override
  String get theme_palette_green => 'Verde';

  @override
  String get theme_palette_blue => 'Azul';

  @override
  String get theme_palette_red => 'Vermelho';

  @override
  String get theme_palette_teal => 'Verde-petróleo';

  @override
  String get theme_palette_pink => 'Rosa';

  @override
  String get theme_palette_indigo => 'Índigo';

  @override
  String get theme_palette_cyan => 'Ciano';

  @override
  String get assets_recent_subtitle =>
      'Encontre arquivos compartilhados pelo Hermes em chats salvos';

  @override
  String get assets_scope_notice =>
      'Arquivos gerados e compartilhados explicitamente pelo Hermes em respostas salvas. Esta é uma visão parcial do histórico de chats, não um catálogo completo de arquivos ou anexos. Os arquivos referenciados podem não existir mais.';

  @override
  String get assets_download_limit =>
      'Os arquivos só são carregados ao tocar neles. Pré-visualizações e downloads têm limite de 25 MiB por arquivo; use o painel para arquivos maiores.';

  @override
  String get assets_search_hint =>
      'Buscar nos arquivos encontrados ou nos chats de origem';

  @override
  String get assets_all => 'Todos';

  @override
  String get assets_images => 'Imagens';

  @override
  String get assets_audio => 'Áudio';

  @override
  String get assets_video => 'Vídeo';

  @override
  String get assets_documents => 'Documentos e outros arquivos';

  @override
  String get assets_empty =>
      'Nenhum recurso encontrado nas mensagens examinadas';

  @override
  String get assets_empty_detail =>
      'Examine mais chats ou mensagens mais antigas para consultar um período anterior. Anexos comuns e arquivos sem links não são indexados aqui.';

  @override
  String get assets_no_matches => 'Nenhum recurso correspondente';

  @override
  String get assets_load_more_chats => 'Examinar mais chats';

  @override
  String get assets_load_older_messages => 'Examinar mensagens mais antigas';

  @override
  String get assets_load_failed =>
      'Algumas partes do histórico não puderam ser lidas. Os resultados estão incompletos. Verifique a conexão com o painel e tente novamente.';

  @override
  String get assets_retry_failed => 'Tentar novamente as leituras que falharam';

  @override
  String get assets_partial =>
      'O servidor informou que o histórico está incompleto. Verifique o painel e atualize em seguida.';

  @override
  String assets_scan_summary(int files, int chats) {
    return 'Referências a arquivos encontradas: $files · Chats examinados: $chats';
  }

  @override
  String assets_open_chat(String title) {
    return 'Abrir chat: $title';
  }

  @override
  String get assets_file_too_large =>
      'Este arquivo excede o limite de download. Abra o painel para baixá-lo.';

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      'Uma pergunta pontual. É arquivada automaticamente após 72 horas; o que valer a pena guardar continua na memória.';

  @override
  String get archive_chat => 'Arquivar chat';

  @override
  String get unarchive_chat => 'Desarquivar chat';

  @override
  String get chat_archived => 'Chat arquivado';

  @override
  String get chat_unarchived => 'Chat desarquivado';

  @override
  String could_not_update_chat_archive(Object error) {
    return 'Não foi possível alterar o arquivo do chat: $error';
  }

  @override
  String get quick_chat_description => 'Uma pergunta pontual.';

  @override
  String get ai_full_text => 'IA + texto completo';

  @override
  String get ai_search_model => 'Modelo de busca com IA';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'A IA buscou: $aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'Arquivamento assistido por IA';

  @override
  String get api_key => 'Chave de API';

  @override
  String get api_server_key_from_hermes_env =>
      'API_SERVER_KEY de ~/.hermes/.env';

  @override
  String get active => 'Ativo';

  @override
  String get activity => 'Atividade';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      'A atividade lê o diário de turnos durável para saber o que o Hermes está fazendo. Verifique se o Gateway está acessível e tente novamente.';

  @override
  String get add => 'Adicionar';

  @override
  String get add_connection => 'Adicionar conexão';

  @override
  String get add_cron_job => 'Adicionar tarefa Cron';

  @override
  String get add_gateway_connection => 'Adicionar conexão de Gateway';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      'Adicionar e atualizar conexões do backup; manter as demais.';

  @override
  String get add_attachment => 'Adicionar anexo';

  @override
  String get add_new_cron_job => 'Adicionar nova tarefa Cron';

  @override
  String get add_to_chat => 'Adicionar ao chat';

  @override
  String get all_chats => 'Todos os chats';

  @override
  String get all_stored_message_content =>
      'Todo o conteúdo de mensagens armazenado';

  @override
  String get allow_for_this_session => 'Permitir nesta sessão';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      'Permitir comandos correspondentes até esta sessão do Hermes terminar.';

  @override
  String get allow_once => 'Permitir uma vez';

  @override
  String get always_allow => 'Permitir sempre';

  @override
  String get apply_to_this_chat => 'Aplicar a este chat';

  @override
  String get approval_needed => 'Aprovação necessária';

  @override
  String get approval_needed_description =>
      'Um comando aguarda sua aprovação ou recusa.';

  @override
  String get approve => 'Aprovar';

  @override
  String get archive => 'Arquivar';

  @override
  String get archive_project => 'Arquivar projeto';

  @override
  String archive_2(Object projectName) {
    return 'Arquivar $projectName?';
  }

  @override
  String archive_3(Object name) {
    return 'Arquivar $name?';
  }

  @override
  String get archived => 'Arquivado';

  @override
  String get archived_conversations_appear_here =>
      'Só as conversas arquivadas aparecem aqui. Os chats antigos continuam em Todos os chats.';

  @override
  String get archived_quick_chats => 'Chats rápidos arquivados';

  @override
  String get artifacts_attachments_and_generated_media =>
      'Artefatos, anexos e mídia gerada';

  @override
  String get ask_ai_to_find_a_conversation =>
      'Pedir à IA para encontrar uma conversa';

  @override
  String get assets => 'Recursos';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      'Os recursos precisam de um índice autoritativo do servidor no Gateway do Hermes antes de serem exibidos por projeto.';

  @override
  String get assets_unavailable => 'Recursos indisponíveis';

  @override
  String get attach_image_or_file => 'Anexar imagem ou arquivo';

  @override
  String get attachment_drafts => 'Rascunhos de anexos';

  @override
  String attachment_of(Object index, Object total) {
    return 'Anexo $index de $total';
  }

  @override
  String get auto_device_default => 'Automático (padrão do dispositivo)';

  @override
  String get agent => 'Agente';

  @override
  String get autonomous_agents => 'Agentes autônomos';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      'Recuperação em segundo plano indisponível — transporte legado';

  @override
  String get background_task_completed => 'Tarefa em segundo plano concluída';

  @override
  String get background_task_completed_description =>
      'Um comando de terminal em segundo plano foi concluído.';

  @override
  String get backup_restore => 'Backup e restauração';

  @override
  String backup_exported(Object destination) {
    return 'Backup exportado — $destination';
  }

  @override
  String get base_url => 'URL base';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      'A pré-visualização de binários não está disponível. Baixe o arquivo para abri-lo.';

  @override
  String get branch => 'Ramificação';

  @override
  String get branch_chat => 'Criar ramificação do chat';

  @override
  String get branch_created_in_hermes_history =>
      'Ramificação criada no histórico do Hermes.';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      'Navegue e gerencie suas sessões do Hermes Agent pelo celular. Conecta-se a um painel do Hermes em execução na sua rede local.';

  @override
  String get browse_server_files => 'Navegar pelos arquivos do servidor';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      'Navegue pelas pastas do miniserver por trás dos seus projetos';

  @override
  String get cancel => 'Cancelar';

  @override
  String get cancel_voice_input => 'Cancelar entrada de voz';

  @override
  String cannot_reach(Object host, Object port) {
    return 'Não é possível alcançar $host:$port.';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return 'Não é possível alcançar $host:$port. Verifique o host e a porta.';
  }

  @override
  String get change_ai_search_model => 'Alterar modelo de busca com IA';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return 'Altera o padrão de $label. Use o seletor em um chat para substituir apenas aquela conversa.';
  }

  @override
  String get chat_actions => 'Ações do chat';

  @override
  String get chats => 'Chats';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      'Os chats deste Gateway ainda não são agrupados. O agrupamento fica neste celular até que o Gateway possa hospedar projetos.';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      'Os chats deste projeto mostrarão aqui seu estado e última atividade.';

  @override
  String get chats_that_are_not_assigned_to_a_project =>
      'Chats que não estão atribuídos a um projeto';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      'Os chats que você iniciar neste projeto aparecerão aqui, em todos os dispositivos conectados a este Hermes.';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      'Verifique se o Gateway está em execução e acessível e tente novamente.';

  @override
  String get check_the_dashboard_connection_and_try_again =>
      'Verifique a conexão do painel e tente novamente.';

  @override
  String get check_the_connection_and_try_again =>
      'Verifique a conexão e tente novamente.';

  @override
  String get choose_a_small_model_to_rewrite_queries =>
      'Escolha um modelo pequeno para reescrever consultas';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      'Escolha um modelo de busca com IA antes de usar a busca com IA.';

  @override
  String get choose_an_active_project_next =>
      'Escolha um projeto ativo em seguida';

  @override
  String get choose_chat_model => 'Escolher modelo do chat';

  @override
  String get choose_files => 'Escolher arquivos';

  @override
  String get choose_image => 'Escolher imagem';

  @override
  String get choose_images => 'Escolher imagens';

  @override
  String get choose_its_destination_space => 'Escolha o espaço de destino';

  @override
  String get clear_search => 'Limpar busca';

  @override
  String get close => 'Fechar';

  @override
  String get code_copied => 'Código copiado';

  @override
  String get coming_next => 'Em breve';

  @override
  String get command => 'Comando';

  @override
  String get command_line_chats => 'Chats de linha de comando';

  @override
  String get compatibility_mode => 'Modo de compatibilidade';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      'Configure uma URL válida do Desktop Gateway antes de anexar arquivos.';

  @override
  String get confirm_always_allow => 'Confirmar permitir sempre';

  @override
  String get confirm_passphrase => 'Confirmar frase secreta';

  @override
  String connecting_to(Object baseUrl) {
    return 'Conectando a $baseUrl...';
  }

  @override
  String get connection_issue => 'Problema de conexão';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      'Conexão alterada — a resposta em andamento continua no servidor e será reconectada automaticamente.';

  @override
  String get connection_appearance_and_device_preferences =>
      'Conexão, aparência e preferências do dispositivo';

  @override
  String context_tokens(Object effectiveContextLength) {
    return 'Contexto: $effectiveContextLength tokens';
  }

  @override
  String get continue_label => 'Continuar';

  @override
  String get continue_working => 'Continuar trabalhando';

  @override
  String get conversations_in_this_project => 'Conversas neste projeto';

  @override
  String get copy_code => 'Copiar código';

  @override
  String get copy_message => 'Copiar mensagem';

  @override
  String could_not_branch_chat(Object error) {
    return 'Não foi possível criar ramificação do chat: $error';
  }

  @override
  String could_not_delete_session(Object error) {
    return 'Não foi possível excluir a sessão: $error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return 'Não foi possível negar o comando: $error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return 'Não foi possível carregar os modelos de busca com IA: $error';
  }

  @override
  String get could_not_load_conversations =>
      'Não foi possível carregar as conversas';

  @override
  String get could_not_load_files => 'Não foi possível carregar os arquivos';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return 'Não foi possível carregar os modelos deste perfil: $error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return 'Não foi possível carregar mais chats: $error';
  }

  @override
  String get could_not_open_link => 'Não foi possível abrir este link.';

  @override
  String get could_not_open_the_hermes_dashboard =>
      'Não foi possível abrir o painel do Hermes.';

  @override
  String get could_not_open_this_project =>
      'Não foi possível abrir este projeto';

  @override
  String get could_not_preview_file =>
      'Não foi possível pré-visualizar o arquivo';

  @override
  String get could_not_reach_hermes => 'Não foi possível alcançar o Hermes';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return 'Não foi possível alcançar/autenticar o painel em $host:$dashboardPort. Verifique a porta e as credenciais.';
  }

  @override
  String get could_not_read_activity => 'Não foi possível ler a atividade';

  @override
  String could_not_rename_chat(Object error) {
    return 'Não foi possível renomear o chat: $error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return 'Não foi possível enviar a aprovação: $error';
  }

  @override
  String get could_not_skip_the_hermes_question =>
      'Não foi possível pular a pergunta do Hermes.';

  @override
  String could_not_the_project(Object action, Object error) {
    return 'Não foi possível $action o projeto: $error';
  }

  @override
  String get couldn_t_delete_project => 'Não foi possível excluir o projeto';

  @override
  String couldn_t_load_runs(Object error) {
    return 'Não foi possível carregar as execuções: $error';
  }

  @override
  String get couldn_t_move_conversation => 'Não foi possível mover a conversa';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return 'Não foi possível mover para $label: $reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files =>
      'Não foi possível preparar os arquivos compartilhados.';

  @override
  String get couldn_t_promote_conversation =>
      'Não foi possível promover a conversa';

  @override
  String couldn_t_project(Object action) {
    return 'Não foi possível $action o projeto';
  }

  @override
  String get create => 'Criar';

  @override
  String get create_a_project => 'Criar um projeto';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      'Crie um projeto primeiro; depois os chats poderão viver dentro dele.';

  @override
  String get create_a_space_to_separate_related_conversations =>
      'Crie um espaço para separar conversas relacionadas.';

  @override
  String get create_branch => 'Criar ramificação';

  @override
  String get credit_notifications => 'Notificações de crédito';

  @override
  String get credit_notifications_description =>
      'O uso de crédito foi interrompido ou restaurado.';

  @override
  String get cron => 'Cron';

  @override
  String get cron_jobs => 'Tarefas Cron';

  @override
  String get cron_job_added => 'Tarefa Cron adicionada';

  @override
  String get cron_job_updated => 'Tarefa Cron atualizada';

  @override
  String get cron_run => 'Execução do Cron';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      'Ordenação entre dispositivos e organização em massa reversível';

  @override
  String get current_profile_default => 'Padrão do perfil atual';

  @override
  String get custom_proxy_and_dashboard_details =>
      'Detalhes personalizados de proxy e painel';

  @override
  String get dark => 'Escuro';

  @override
  String get dashboard_proxy_settings => 'Configurações do painel / proxy';

  @override
  String get dashboard_password_optional => 'Senha do painel (opcional)';

  @override
  String get dashboard_port => 'Porta do painel';

  @override
  String get dashboard_username_optional =>
      'Nome de usuário do painel (opcional)';

  @override
  String get dashboard_behind_proxy => 'Painel atrás de proxy';

  @override
  String get dashboard_path_prefix => 'Prefixo de caminho do painel';

  @override
  String delegated_task(Object goal) {
    return 'Tarefa delegada: $goal';
  }

  @override
  String get delete => 'Excluir';

  @override
  String delete_2(Object name) {
    return 'Excluir “$name”?';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return 'Excluir “$title” do histórico remoto do Hermes? Esta ação não pode ser desfeita.';
  }

  @override
  String get delete_cron_job => 'Excluir tarefa Cron';

  @override
  String get delete_connections_that_are_not_in_the_backup =>
      'Excluir conexões que não estão no backup.';

  @override
  String delete_failed(Object error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String get delete_project => 'Excluir projeto';

  @override
  String get delete_session => 'Excluir sessão?';

  @override
  String delete_3(Object projectName) {
    return 'Excluir $projectName?';
  }

  @override
  String deleted(Object name) {
    return '“$name” excluído';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      'A entrega é incerta; recuperando sem reenviar…';

  @override
  String get desktop_gateway_url_optional =>
      'URL do Desktop Gateway (opcional)';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      'O Desktop Gateway não está configurado para esta conexão.';

  @override
  String get desktop_app => 'Aplicativo para desktop';

  @override
  String get developer_tool_calls => 'Chamadas de ferramentas do desenvolvedor';

  @override
  String get discord_chats => 'Chats do Discord';

  @override
  String get dismiss => 'Descartar';

  @override
  String get do_not_run_this_command => 'Não execute este comando.';

  @override
  String get documents_archives_audio_video_or_data =>
      'Documentos, arquivos compactados, áudio, vídeo ou dados';

  @override
  String get download => 'Baixar';

  @override
  String download_failed(Object error) {
    return 'Falha no download: $error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you =>
      'Fatos duráveis que o Hermes guarda sobre você';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      'Trabalho durável dentro de um dos seus projetos, compartilhado com o Desktop.';

  @override
  String get edit => 'Editar';

  @override
  String get edit_connection => 'Editar conexão';

  @override
  String get edit_cron_job => 'Editar tarefa Cron';

  @override
  String get edit_gateway_connection => 'Editar conexão de Gateway';

  @override
  String get edit_and_resend => 'Editar e reenviar';

  @override
  String get enable_notifications => 'Ativar notificações';

  @override
  String get enable_notifications_description =>
      'Desativar isto desativa todas as notificações abaixo.';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      'Permite anexos de arquivos pelo Gateway remoto do Desktop.';

  @override
  String get enter_a_name => 'Digite um nome';

  @override
  String get enter_a_passphrase => 'Digite uma frase secreta.';

  @override
  String get enter_the_passphrase_for_this_backup =>
      'Digite a frase secreta deste backup.';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      'Todas as conversas já estão atribuídas a um projeto.';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      'Tudo que ainda não é nativo, no painel web autenticado';

  @override
  String get explain_the_attached_content_clearly =>
      'Explique claramente o conteúdo anexado.';

  @override
  String explain_this_content_clearly(Object text) {
    return 'Explique claramente este conteúdo:\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      'Escolhas explícitas ajustam o tamanho do texto de acessibilidade do Android; “Sistema” o mantém inalterado.';

  @override
  String get export_label => 'Exportar';

  @override
  String get export_share => 'Exportar / compartilhar';

  @override
  String get external_api_clients => 'Clientes de API externos';

  @override
  String get extra_high => 'Muito alto';

  @override
  String get extract_tasks => 'Extrair tarefas';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      'Extraia do conteúdo anexado as decisões, prazos, responsáveis e itens de ação executáveis.';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return 'Extraia deste conteúdo as decisões, prazos, responsáveis e itens de ação executáveis:\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return 'Falha ao adicionar tarefa: $error';
  }

  @override
  String get failed_to_load_cron_jobs => 'Falha ao carregar as tarefas Cron';

  @override
  String get failed_to_load_memory => 'Falha ao carregar a memória';

  @override
  String get failed_to_load_messages => 'Falha ao carregar as mensagens';

  @override
  String get failed_to_load_settings => 'Falha ao carregar as configurações';

  @override
  String get failed_to_load_skills => 'Falha ao carregar as habilidades';

  @override
  String failed_to_update_job(Object error) {
    return 'Falha ao atualizar tarefa: $error';
  }

  @override
  String failed(Object error) {
    return 'Falha: $error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      'Arquivo anexado; o registro no catálogo de documentos está pendente.';

  @override
  String get file_reference_added_to_chat =>
      'Referência de arquivo adicionada ao chat';

  @override
  String get files => 'Arquivos';

  @override
  String get fill_from_document => 'Preencher a partir do documento';

  @override
  String get folder_is_empty => 'A pasta está vazia';

  @override
  String get folders => 'Pastas';

  @override
  String get full_text => 'Texto completo';

  @override
  String get gateway_api_access => 'Acesso à API do Gateway';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      'Gateway conectado, mas o painel não pôde ser alcançado ou autenticado. Verifique os detalhes do painel ou limpe-os para pular.';

  @override
  String get gateway_path_prefix => 'Prefixo de caminho do Gateway';

  @override
  String get go_to_end => 'Ir para o fim';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Hermes Agent para Android';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'O Hermes não pôde aceitar a resposta. Tente novamente.';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      'O Hermes não pôde carregar suas conexões salvas';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'O Hermes não aceitou a resposta. Tente novamente.';

  @override
  String get hermes_is_responding => 'O Hermes está respondendo…';

  @override
  String get hermes_is_waiting_for_input =>
      'O Hermes está aguardando sua entrada…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'O Hermes mantém a escala de texto de acessibilidade do Android ativa.';

  @override
  String get hermes_needs_your_input => 'O Hermes precisa da sua entrada';

  @override
  String get hermes_profile_optional => 'Perfil do Hermes (opcional)';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'O perfil do Hermes deve ser um nome simples de perfil, como “sol”, e não um caminho.';

  @override
  String get hermes_reasoning_details => 'Detalhes de raciocínio do Hermes';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'A recuperação do Hermes está indisponível: $error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'O Hermes interrompeu a recuperação com segurança. Nenhum prompt foi reenviado.';

  @override
  String get hide_passphrase => 'Ocultar frase secreta';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      'O início precisa dos seus chats recentes para saber o que merece sua atenção. Verifique se o Gateway está acessível e tente novamente.';

  @override
  String get host => 'Host';

  @override
  String get image_selection_was_interrupted_try_again =>
      'A seleção de imagem foi interrompida. Tente novamente.';

  @override
  String get import_label => 'Importar';

  @override
  String get inbox => 'Caixa de entrada';

  @override
  String get inbox_is_clear => 'Caixa de entrada vazia';

  @override
  String get input_needed => 'Entrada necessária';

  @override
  String get input_needed_description =>
      'O Hermes fez uma pergunta ou precisa de uma senha ou segredo.';

  @override
  String get insert_a_remote_file_reference =>
      'Inserir uma referência remota a @file';

  @override
  String get invalid_port_number => 'Número de porta inválido.';

  @override
  String get job_paused => 'Tarefa pausada';

  @override
  String get job_resumed => 'Tarefa retomada';

  @override
  String get job_triggered => 'Tarefa acionada';

  @override
  String get label => 'Rótulo';

  @override
  String last_activity(Object day, Object month, Object year) {
    return 'Última atividade $day/$month/$year';
  }

  @override
  String last(Object lastRun) {
    return 'Última: $lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      'Deixe em branco para o padrão (8642; 443 com https)';

  @override
  String get leave_blank_for_default_9119 =>
      'Deixe em branco para o padrão (9119)';

  @override
  String get light => 'Claro';

  @override
  String listening(Object elapsed) {
    return 'Ouvindo • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return 'Ouvindo, decorrido: $elapsed';
  }

  @override
  String get load_more => 'Carregar mais…';

  @override
  String get loading => 'Carregando';

  @override
  String get location => 'Localização';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      'Certifique-se de que o servidor de API do Gateway esteja em execução\n(hermes gateway status)';

  @override
  String matches(Object assigned, Object name) {
    return 'Corresponde a $name · $assigned';
  }

  @override
  String get memory => 'Memória';

  @override
  String get memory_about_you => 'Sobre você';

  @override
  String get memory_agent_notes => 'Notas do agente';

  @override
  String get memory_builtin_scope =>
      'Fatos salvos em USER.md e MEMORY.md deste perfil. Provedores de memória externos (incluindo MemPalace) não são exibidos aqui.';

  @override
  String get memory_read_only =>
      'Somente leitura. Peça ao Hermes no chat para corrigir ou esquecer um fato.';

  @override
  String get memory_unavailable =>
      'Este gateway ou perfil não pode fornecer os fatos salvos. Confira o perfil selecionado e atualize o Hermes, se necessário.';

  @override
  String get memory_load_error =>
      'Confira a conexão e a autenticação do painel e tente novamente.';

  @override
  String get memory_read_full_fact => 'Ler o fato completo';

  @override
  String get memory_full_fact_requires_update =>
      'Os fatos completos exigem um gateway Hermes mais recente. Atualize o Hermes e a lista.';

  @override
  String get memory_fact_detail_error =>
      'Não foi possível carregar o fato completo. Ele pode ter mudado; atualize a lista e tente novamente.';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'Os fatos salvos aparecerão aqui quando o Hermes os memorizar.';

  @override
  String get merge => 'Mesclar';

  @override
  String get message => 'Mensagem';

  @override
  String get message_hermes => 'Enviar mensagem ao Hermes…';

  @override
  String get message_actions => 'Ações da mensagem';

  @override
  String get message_copied => 'Mensagem copiada';

  @override
  String get migrating => 'Migrando…';

  @override
  String get migration_complete => 'Migração concluída';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      'A migração falhou. Os espaços locais foram mantidos inalterados.';

  @override
  String get migration_incomplete => 'Migração incompleta';

  @override
  String get migration_preview => 'Pré-visualização da migração';

  @override
  String get model => 'Modelo';

  @override
  String get model_and_thinking_for_this_chat =>
      'Modelo e raciocínio para este chat';

  @override
  String model_was_not_changed(Object error) {
    return 'O modelo não foi alterado: $error';
  }

  @override
  String get move_attachment_next => 'Mover anexo para frente';

  @override
  String get move_attachment_previous => 'Mover anexo para trás';

  @override
  String get move_chat => 'Mover chat';

  @override
  String get move_conversation => 'Mover conversa';

  @override
  String get move_to_project => 'Mover para projeto';

  @override
  String get move_to_space => 'Mover para espaço';

  @override
  String get moved_to_a_project => 'Movido para um projeto';

  @override
  String moved_to(Object label) {
    return 'Movido para $label';
  }

  @override
  String get name => 'Nome';

  @override
  String get name_prompt_and_schedule_are_required =>
      'Nome, prompt e agendamento são obrigatórios';

  @override
  String get nav_activity => 'Atividade';

  @override
  String get nav_projects => 'Projetos';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Requer um contrato de arquivamento com correção no Gateway do Hermes.';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      'Requer um painel do Hermes acessível. Verifique o host, a porta e as credenciais desta conexão.';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Requer um índice de recursos autoritativo do servidor no Gateway do Hermes.';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Requer contratos de ordenação de fixados, mutação em lote e desfazer no Gateway do Hermes.';

  @override
  String get needs_you => 'Precisa de você';

  @override
  String get new_label => 'Novo';

  @override
  String get new_chat => 'Novo chat';

  @override
  String get new_chat_2 => 'Novo chat';

  @override
  String new_chat_3(Object projectName) {
    return 'Novo chat · $projectName';
  }

  @override
  String get new_project => 'Novo projeto';

  @override
  String get new_space => 'Novo espaço';

  @override
  String next(Object nextRun) {
    return 'Próxima: $nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'O Nginx injeta a autenticação — o app envia requisições limpas';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      'Nenhuma voz de TTS encontrada.\nInstale o Google Text-to-Speech e baixe os dados de voz.';

  @override
  String get no_active_projects_on_this_gateway =>
      'Nenhum projeto ativo neste Gateway';

  @override
  String get no_activity_yet => 'Nenhuma atividade ainda';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      'Nenhum chat está bloqueado, em execução ou aguardando retomada. Inicie um novo quando quiser.';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return 'Nenhum chat deste projeto corresponde a “$searchQuery”.';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      'Ainda não há chats neste espaço. Toque em + para iniciar um.';

  @override
  String get no_chats_yet => 'Ainda não há chats';

  @override
  String get no_connections => 'Sem conexões';

  @override
  String get no_conversation_matches_this_view =>
      'Nenhuma conversa corresponde a esta visualização.';

  @override
  String get no_cron_jobs => 'Sem tarefas Cron';

  @override
  String get no_folders_yet => 'Ainda não há pastas';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      'Nenhum espaço local foi encontrado para esta conexão, então os projetos já são a única forma de organização em uso aqui.';

  @override
  String get no_matches => 'Sem correspondências';

  @override
  String get no_memory_entries => 'Sem entradas de memória';

  @override
  String get no_message_content_matches =>
      'Nenhuma correspondência no conteúdo das mensagens';

  @override
  String get no_new_messages => 'Sem mensagens novas';

  @override
  String get no_projects_yet => 'Ainda não há projetos';

  @override
  String get no_runs_yet => 'Ainda não há execuções.';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return 'Nenhum projeto do servidor corresponde a este nome · $assigned';
  }

  @override
  String get no_sessions_yet => 'Ainda não há sessões';

  @override
  String get no_skills_found => 'Nenhuma habilidade encontrada';

  @override
  String get no_spaces_on_this_device => 'Nenhum espaço neste dispositivo';

  @override
  String get no_text_shared => 'Nenhum texto compartilhado';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      'Nenhum turno está bloqueado, em andamento ou recém-concluído. O trabalho que você iniciar aparecerá aqui.';

  @override
  String get no_turn_needs_your_input_or_has_failed =>
      'Nenhum turno precisa da sua entrada ou falhou.';

  @override
  String get no_unassigned_chats => 'Nenhum chat não atribuído.';

  @override
  String get nothing_changed_in_the_last_seven_days =>
      'Nada mudou nos últimos sete dias.';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      'Nada foi movido ainda — isto é apenas o que uma migração faria.';

  @override
  String get nothing_here => 'Nada aqui';

  @override
  String get nothing_is_running => 'Nada em execução';

  @override
  String get nothing_needs_you => 'Nada precisa de você';

  @override
  String get nothing_to_migrate => 'Nada para migrar';

  @override
  String get notifications => 'Notificações';

  @override
  String get notifications_permission_denied =>
      'As notificações estão bloqueadas pelo sistema. Ative-as para este app nas configurações do Android.';

  @override
  String get off_no_thinking => 'Desativado (sem raciocínio)';

  @override
  String get offline_showing_the_last_known_activity =>
      'Offline — mostrando a última atividade conhecida.';

  @override
  String get offline_showing_the_last_known_chats =>
      'Offline — mostrando os últimos chats conhecidos';

  @override
  String get offline_showing_the_last_known_projects =>
      'Offline — mostrando os últimos projetos conhecidos.';

  @override
  String get on_this_device => 'Neste dispositivo';

  @override
  String get on_device => 'No dispositivo';

  @override
  String get open_inbox => 'Abrir caixa de entrada';

  @override
  String open_inbox_2(Object count) {
    return 'Abrir caixa de entrada ($count)';
  }

  @override
  String get open_the_hermes_dashboard => 'Abrir o painel do Hermes';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      'Opcional. Para as abas Memória/Cron/Habilidades/Configurações. Deixe em branco para usar a porta padrão do painel (9119) sem login.';

  @override
  String get organization => 'Organização';

  @override
  String get other_answer => 'Outra resposta';

  @override
  String get overview => 'Visão geral';

  @override
  String get passphrase => 'Frase secreta';

  @override
  String get password_optional => 'Senha (opcional)';

  @override
  String get phone_or_tablet => 'Telefone ou tablet';

  @override
  String get pin_batch_and_undo => 'Fixar, em lote e desfazer';

  @override
  String get plugin_notifications => 'Notificações de plugins';

  @override
  String get plugin_notifications_description =>
      'O gateway enviou um aviso enquanto o app estava em segundo plano.';

  @override
  String get port => 'Porta';

  @override
  String get preparing_attachments => 'Preparando anexos…';

  @override
  String get preview_truncated => 'Pré-visualização truncada';

  @override
  String get preview_unavailable => 'Pré-visualização indisponível';

  @override
  String get profile => 'Perfil';

  @override
  String get profile_default_model => 'Modelo padrão do perfil';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return 'Padrão do perfil definido como $selectedModel. Chats com modelo próprio mantêm essa substituição.';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      'Perfil com que esta conexão conversa quando o painel serve vários perfis. Deixe em branco para um painel isolado por perfil.';

  @override
  String get project => 'Projeto';

  @override
  String get project_actions => 'Ações do projeto';

  @override
  String get project_chat => 'Chat do projeto';

  @override
  String get project_chats_unavailable => 'Chats do projeto indisponíveis';

  @override
  String get projects => 'Projetos';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      'Os projetos agrupam chats, arquivos e atividades relacionados e ficam sincronizados com o Hermes no seu computador.';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      'Os projetos precisam de uma conexão com o Desktop Gateway. Adicione a URL do Desktop Gateway a esta conexão para organizar chats entre dispositivos.';

  @override
  String get projects_unavailable => 'Projetos indisponíveis';

  @override
  String get projects_activity_new_navigation =>
      'Projetos, Atividade — nova navegação';

  @override
  String get promote_to_project => 'Promover a projeto';

  @override
  String get prompt => 'Prompt';

  @override
  String get protect_this_backup => 'Proteger este backup';

  @override
  String get provider => 'Provedor';

  @override
  String get proxy_injects_auth_app_sends_clean_requests =>
      'O proxy injeta a autenticação; o app envia requisições limpas';

  @override
  String get quick_chat => 'Chat rápido';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      'Chats rápidos aparecem aqui após o período de retenção.';

  @override
  String get read_aloud => 'Ler em voz alta';

  @override
  String get read_aloud_is_unavailable_on_this_device =>
      'A leitura em voz alta não está disponível neste dispositivo';

  @override
  String get reading_response_aloud => 'Lendo a resposta em voz alta';

  @override
  String get ready_to_upload => 'Pronto para enviar';

  @override
  String get reasoning => 'Raciocínio';

  @override
  String get recently_completed => 'Concluído recentemente';

  @override
  String get recently_active => 'Ativo recentemente';

  @override
  String get recovering_hermes => 'Recuperando o Hermes…';

  @override
  String get refresh => 'Atualizar';

  @override
  String get regenerate_response => 'Regenerar resposta';

  @override
  String get remove_attachment => 'Remover anexo';

  @override
  String get rename => 'Renomear';

  @override
  String get rename_chat => 'Renomear chat';

  @override
  String get rename_project => 'Renomear projeto';

  @override
  String get rename_space => 'Renomear espaço';

  @override
  String rename_2(Object projectName) {
    return 'Renomear $projectName';
  }

  @override
  String rename_3(Object name) {
    return 'Renomear $name';
  }

  @override
  String get replace => 'Substituir';

  @override
  String get repositories => 'Repositórios';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      'Pesquise o conteúdo anexado, verifique as afirmações importantes e cite as fontes.';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return 'Pesquise este conteúdo, verifique as afirmações importantes e cite as fontes:\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return 'Falha na redefinição: $retryError. O armazenamento seguro pode precisar ser reinstalado.';
  }

  @override
  String get reset_saved_connections => 'Redefinir conexões salvas';

  @override
  String get responding => 'Respondendo…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return 'Resposta fechada localmente; falha ao parar o Gateway: $error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      'Resposta fechada localmente; nenhum turno ativo do Gateway foi encontrado.';

  @override
  String get response_complete => 'Resposta concluída';

  @override
  String get response_complete_description =>
      'Um turno foi concluído enquanto o app estava em segundo plano.';

  @override
  String get response_ready => 'Resposta pronta';

  @override
  String get response_stopped => 'Resposta interrompida.';

  @override
  String get restore => 'Restaurar';

  @override
  String get restore_configuration => 'Restaurar configuração';

  @override
  String get restore_project => 'Restaurar projeto';

  @override
  String get retry => 'Tentar novamente';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return 'Falha ao tentar novamente para $name. O rascunho e o prompt foram mantidos.';
  }

  @override
  String get retry_upload => 'Tentar enviar novamente';

  @override
  String retrying(Object name) {
    return 'Tentando novamente $name…';
  }

  @override
  String get review_local_spaces => 'Revisar espaços locais';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      'Revisar ou promover chats rápidos além do período de retenção';

  @override
  String get review_the_attached_content => 'Revise o conteúdo anexado.';

  @override
  String get run_only_this_command => 'Execute apenas este comando.';

  @override
  String get running_now => 'Em execução';

  @override
  String get save => 'Salvar';

  @override
  String get save_changes => 'Salvar alterações';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      'Salve uma regra permanente na configuração do Hermes.';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      'Salve os fatos duráveis do conteúdo anexado na memória e confirme o que foi retido.';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return 'Salve os fatos duráveis deste conteúdo na memória e confirme o que foi retido:\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      'Salve suas conexões e configurações em um arquivo criptografado e restaure-as após reinstalar ou em outro dispositivo.';

  @override
  String save_2(Object filename) {
    return 'Salvar $filename';
  }

  @override
  String get schedule => 'Agendamento';

  @override
  String get scheduled_jobs_and_their_last_runs =>
      'Tarefas agendadas e suas últimas execuções';

  @override
  String get scheduled_tasks => 'Tarefas agendadas';

  @override
  String get script_only_no_agent => 'Somente script (sem agente)';

  @override
  String get scroll_horizontally => 'Rolar horizontalmente';

  @override
  String get search_all_chats => 'Pesquisar todos os chats';

  @override
  String get search_all_message_content =>
      'Pesquisar todo o conteúdo das mensagens';

  @override
  String get search_chats => 'Pesquisar chats';

  @override
  String get search_conversations => 'Pesquisar conversas';

  @override
  String get search_loaded_chats => 'Pesquisar chats carregados';

  @override
  String get search_mode => 'Modo de busca';

  @override
  String get select_one_option_or_enter_another_answer =>
      'Selecione uma opção ou digite outra resposta.';

  @override
  String get select_one_or_more_options_then_continue =>
      'Selecione uma ou mais opções e continue.';

  @override
  String get select_text => 'Selecionar texto';

  @override
  String get send => 'Enviar';

  @override
  String send_failed(Object error) {
    return 'Falha no envio: $error';
  }

  @override
  String get send_message => 'Enviar mensagem';

  @override
  String get send_test_notification => 'Enviar notificação de teste';

  @override
  String get session_sources => 'Fontes de sessões';

  @override
  String get session_deleted_from_remote_hermes =>
      'Sessão excluída do Hermes remoto.';

  @override
  String session_search_failed(Object error) {
    return 'Falha na busca de sessões: $error';
  }

  @override
  String get set_profile_default => 'Definir como padrão do perfil';

  @override
  String get settings => 'Configurações';

  @override
  String get share_to_hermes => 'Compartilhar com o Hermes';

  @override
  String get show_passphrase => 'Mostrar frase secreta';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      'Mostrar chamadas de ferramentas, raciocínio e metadados de mensagens';

  @override
  String get signal_messages => 'Mensagens do Signal';

  @override
  String get skills => 'Habilidades';

  @override
  String skills_2(Object count) {
    return 'Habilidades ($count)';
  }

  @override
  String get skills_and_tools => 'Habilidades e ferramentas';

  @override
  String get skip => 'Pular';

  @override
  String get slack_chats => 'Chats do Slack';

  @override
  String source(Object source) {
    return 'Origem: $source';
  }

  @override
  String get space_actions => 'Ações do espaço';

  @override
  String get spaces => 'Espaços';

  @override
  String get speak_to_hermes => 'Fale com o Hermes';

  @override
  String get speech_recognition_is_unavailable =>
      'O reconhecimento de fala não está disponível';

  @override
  String get spoken_replies => 'Respostas faladas';

  @override
  String get spoken_replies_off => 'Respostas faladas desativadas';

  @override
  String get spoken_replies_on => 'Respostas faladas ativadas';

  @override
  String get stalled_no_update_from_hermes =>
      'Travado — sem atualizações do Hermes';

  @override
  String get start_something_new => 'Começar algo novo';

  @override
  String get start_voice_input => 'Iniciar entrada de voz';

  @override
  String get starting_hermes => 'Iniciando o Hermes…';

  @override
  String get still_loading_your_projects => 'Ainda carregando seus projetos.';

  @override
  String get stop => 'Parar';

  @override
  String get stop_response => 'Parar resposta';

  @override
  String get stop_voice_input => 'Parar entrada de voz';

  @override
  String get submitted_waiting_for_hermes => 'Enviado, aguardando o Hermes';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      'Sugerir projetos e aprender com suas correções';

  @override
  String get summarize_the_attached_content => 'Resuma o conteúdo anexado.';

  @override
  String summarize_this_content(Object text) {
    return 'Resuma este conteúdo:\n\n$text';
  }

  @override
  String get switch_profile => 'Trocar de perfil';

  @override
  String get system => 'Sistema';

  @override
  String get take_photo => 'Tirar foto';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      'Toque em + para adicionar um Gateway do Hermes remoto\n(servidor de API, porta 8642)';

  @override
  String get tap_the_button_to_start_a_new_chat =>
      'Toque no botão + para iniciar um novo chat';

  @override
  String get telegram_messages => 'Mensagens do Telegram';

  @override
  String get terminal_sessions => 'Sessões de terminal';

  @override
  String get test_notification_body =>
      'Se você está vendo isto, as notificações estão funcionando.';

  @override
  String get test_notification_sent => 'Notificação de teste enviada.';

  @override
  String get test_notification_title => 'Teste de notificação do Hermes';

  @override
  String get test_notification_unsupported =>
      'Não foi possível enviar a notificação — verifique se o sistema permite notificações.';

  @override
  String get text_size => 'Tamanho do texto';

  @override
  String get text_size_preview => 'Pré-visualização do tamanho do texto';

  @override
  String text_size_2(Object label) {
    return 'Tamanho do texto: $label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely =>
      'A chave de API não pôde ser armazenada com segurança.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      'O projeto será movido para “Arquivado”. Seus chats e arquivos permanecem intactos, e você pode restaurá-lo a qualquer momento.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      'O projeto será movido para “Arquivado”. Seus chats e arquivos permanecem intactos, e você pode restaurá-lo depois.';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      'O perfil ativo não retornou nenhum modelo selecionável.';

  @override
  String get the_backup_could_not_be_exported =>
      'O backup não pôde ser exportado.';

  @override
  String get the_backup_could_not_be_restored =>
      'O backup não pôde ser restaurado.';

  @override
  String get the_connection_could_not_be_deleted_safely =>
      'A conexão não pôde ser excluída com segurança.';

  @override
  String get the_connection_could_not_be_stored_securely =>
      'A conexão não pôde ser armazenada com segurança.';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      'As credenciais do painel não puderam ser armazenadas com segurança.';

  @override
  String get the_detached_reply_failed => 'A resposta desacoplada falhou.';

  @override
  String the_detached_reply_failed_2(Object error) {
    return 'A resposta desacoplada falhou: $error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      'O arquivo contém suas chaves de API e a senha do painel, por isso é criptografado. Sem esta frase secreta, o backup não pode ser restaurado.';

  @override
  String get the_last_turn_failed => 'O último turno falhou';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return 'O armazenamento local de conexões parece danificado ($errorType). Você pode redefinir as conexões salvas e começar do zero. Os chats no seu Gateway não são afetados.';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      'O modelo apenas reescreve sua pergunta como uma consulta curta de texto completo. O Hermes usa as credenciais do provedor já configuradas no host.';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      'O servidor ainda não informou pastas para este projeto. Arquivos globais continua disponível em Mais.';

  @override
  String get the_turn_failed => 'O turno falhou';

  @override
  String get the_two_passphrases_do_not_match =>
      'As duas frases secretas não coincidem.';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      'O valor é enviado diretamente ao Gateway do Hermes ativo e não é salvo por este app Android.';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      'Não há arquivos visíveis nesta pasta do servidor.';

  @override
  String get thinking_effort => 'Esforço de raciocínio';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      'Este Gateway do Hermes ainda não oferece suporte a abrir um projeto. Atualize o Hermes no servidor para navegar por um projeto pelo celular.';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      'Este Gateway do Hermes é mais antigo que os projetos do servidor, então os chats ficam agrupados apenas neste dispositivo. Atualize o Hermes para compartilhar os mesmos projetos entre seus dispositivos.';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      'Este projeto precisa de uma pasta antes de iniciar um chat nele. Adicione uma pasta e tente novamente.';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      'Este chat ainda não tem mensagens disponíveis na sessão do Desktop.';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      'Isto cria uma regra permanente no Hermes. Revise o comando completo antes de confirmar.';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      'Este Gateway ainda não hospeda projetos. Atualize o Gateway para organizar chats entre dispositivos.';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      'Isto exclui o projeto permanentemente. Os chats não serão excluídos; voltarão para “Não atribuído”.';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      'Este servidor não oferece recuperação em segundo plano — os chats rodam ao vivo';

  @override
  String get this_week => 'Esta semana';

  @override
  String get titles_previews_and_models =>
      'Títulos, pré-visualizações e modelos';

  @override
  String get tool_activity => 'Atividade de ferramentas';

  @override
  String get trigger_now => 'Acionar agora';

  @override
  String get received_outcome_unknown =>
      'Turno encerrado — resultado não confirmado';

  @override
  String get turn_completed => 'Turno concluído';

  @override
  String get turn_failed => 'Turno falhou';

  @override
  String get turn_failed_description =>
      'Um turno em segundo plano terminou com erro.';

  @override
  String get turn_recovery_failed => 'Falha na recuperação do turno';

  @override
  String get unable_to_prepare_this_file_try_another_one =>
      'Não foi possível preparar este arquivo. Tente outro.';

  @override
  String get unable_to_prepare_this_image_try_another_one =>
      'Não foi possível preparar esta imagem. Tente outra.';

  @override
  String unable_to_prepare(Object name) {
    return 'Não foi possível preparar $name.';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      'Não foi possível ler a imagem selecionada. A seleção foi mantida.';

  @override
  String get unassigned => 'Não atribuído';

  @override
  String get unassigned_chats => 'Chats não atribuídos';

  @override
  String get untitled_chat => 'Chat sem título';

  @override
  String get untitled_session => 'Sessão sem título';

  @override
  String get update_api_key => 'Atualizar chave de API';

  @override
  String get upload_failed => 'Falha no envio';

  @override
  String get upload_failed_tap_retry =>
      'Falha no envio • toque para tentar novamente';

  @override
  String uploading(Object index, Object name, Object total) {
    return 'Enviando $index/$total: $name';
  }

  @override
  String get use_as_is => 'Usar como está';

  @override
  String get use_at_least_8_characters => 'Use pelo menos 8 caracteres.';

  @override
  String get use_for_cron_jobs_backed_by_scripts =>
      'Use para tarefas Cron baseadas em scripts.';

  @override
  String get use_on_device => 'Usar no dispositivo';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      'Use o conteúdo anexado para identificar e preencher os campos relevantes do documento ou formulário. Pergunte antes de enviar qualquer coisa.';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return 'Use este conteúdo para identificar e preencher os campos relevantes do documento ou formulário. Pergunte antes de enviar qualquer coisa:\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      'Usado para prefixos de caminho hospedados e para as abas Configurações, Memória, Habilidades e Cron. Deixe usuário/senha em branco para um painel aberto, ou ative o modo proxy quando seu proxy reverso injetar a autenticação do painel.';

  @override
  String get username_optional => 'Nome de usuário (opcional)';

  @override
  String using(Object displayName) {
    return 'Usando $displayName…';
  }

  @override
  String get verbose_mode => 'Modo detalhado';

  @override
  String get voice => 'Voz';

  @override
  String voice_setup_failed(Object error) {
    return 'Falha na configuração de voz: $error';
  }

  @override
  String get waiting_for_your_input => 'Aguardando sua entrada';

  @override
  String get what_hermes_knows_how_to_do => 'O que o Hermes sabe fazer';

  @override
  String get what_should_the_agent_do => 'O que o agente deve fazer?';

  @override
  String get whatsapp_messages => 'Mensagens do WhatsApp';

  @override
  String get which_project => 'Qual projeto?';

  @override
  String get workspace => 'Área de trabalho';

  @override
  String get wrap_lines => 'Quebrar linhas';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return 'Você pode anexar até $maxRemoteAttachmentDrafts itens.';
  }

  @override
  String get your_answer => 'Sua resposta';

  @override
  String get e_g_dashboard => 'ex.: /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      'ex.: /dashboard (caminho do proxy antes de /api/)';

  @override
  String get e_g_profile_peter => 'ex.: /profile/peter';

  @override
  String get e_g_sol => 'ex.: sol';

  @override
  String get e_g_0_9_or_every_2h => 'ex.: 0 9 * * * ou every 2h';

  @override
  String get e_g_daily_backup => 'ex.: Backup diário';

  @override
  String downloaded(Object filename) {
    return '$filename baixado';
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
      '192.168.1.50, 100.x.y.z ou hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      'ex.: /profile/peter (caminho do proxy antes de /api/ e /v1/)';

  @override
  String and_more(Object count) {
    return 'e mais $count';
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
    return '$chats · somente neste dispositivo';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count espaços',
      one: '$count espaço',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => 'nenhum projeto novo necessário';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projetos a criar',
      one: '$count projeto a criar',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return '$linkedSessions chats migrados · $createdProjects projetos criados';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '$unlinkedSessions chats permaneceram em espaços locais e podem ser tentados novamente com segurança.';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • Recomendado: pequeno e econômico';
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
  String get this_chat => 'este chat';

  @override
  String get profile_default => 'padrão do perfil';

  @override
  String minutes_ago(Object count) {
    return 'há $count min';
  }

  @override
  String hours_ago(Object count) {
    return 'há $count h';
  }

  @override
  String days_ago(Object count) {
    return 'há $count d';
  }

  @override
  String get now_label => 'agora';

  @override
  String get latest_label => 'Mais recente';

  @override
  String new_count_indicator(Object count) {
    return '$count novos';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count novas mensagens',
      one: '$count nova mensagem',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return '$failures com falha • $total no total';
  }

  @override
  String activity_completed_summary(Object count) {
    return '$count concluídos';
  }

  @override
  String tool_start_observed(Object time) {
    return 'Início observado às $time (horário local)';
  }

  @override
  String tool_last_observed(Object time) {
    return 'Última observação às $time (horário local)';
  }

  @override
  String tool_result_recorded(Object time) {
    return 'Resultado registrado às $time (horário local)';
  }

  @override
  String get tool_time_unavailable => 'Horário indisponível';

  @override
  String get hermes_is_using_a_tool => 'O Hermes está usando uma ferramenta';

  @override
  String hermes_is_using_tools(Object count) {
    return 'O Hermes está usando $count ferramentas';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return '$count tarefa(s) delegada(s) concluída(s)';
  }

  @override
  String delegated_tasks_active(Object count) {
    return '$count tarefa(s) delegada(s) ativa(s)';
  }

  @override
  String branch_main(Object label) {
    return '$label · main';
  }

  @override
  String get you_heading => '## Você';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => 'Ação';

  @override
  String get destination_label => 'Destino';

  @override
  String get preview_label => 'Pré-visualização';

  @override
  String get share_action_summarize => 'Resumir';

  @override
  String get share_action_explain => 'Explicar';

  @override
  String get share_action_research => 'Pesquisar';

  @override
  String get share_action_remember => 'Lembrar';

  @override
  String get text_size_small => 'Pequeno';

  @override
  String get text_size_default => 'Padrão';

  @override
  String get text_size_large => 'Grande';

  @override
  String get text_size_extra_large => 'Muito grande';

  @override
  String get text_size_use_system_description =>
      'Usar exatamente o tamanho de texto de acessibilidade do Android.';

  @override
  String text_size_percent_description(Object percent) {
    return '$percent% do tamanho de texto do Android.';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return '$count arquivo(s) ignorado(s): limite, tamanho, ilegível ou nome de arquivo sensível.';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort agora se aplicam somente a este chat.';
  }

  @override
  String get reasoning_minimal => 'Mínimo';

  @override
  String get reasoning_low => 'Baixo';

  @override
  String get reasoning_medium => 'Médio';

  @override
  String get reasoning_high => 'Alto';

  @override
  String get reasoning_max => 'Máximo';

  @override
  String get reasoning_ultra => 'Ultra';

  @override
  String get status_running => 'Em execução';

  @override
  String get status_failed => 'Falhou';

  @override
  String get status_done => 'Concluído';

  @override
  String get status_idle => 'Inativo';

  @override
  String get upload_status_uploading => 'Enviando';

  @override
  String get upload_status_uploaded => 'Enviado';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anexos',
      one: '$count anexo',
    );
    return '$_temp0';
  }

  @override
  String get action_create => 'criar';

  @override
  String get action_rename => 'renomear';

  @override
  String get action_archive => 'arquivar';

  @override
  String get action_restore => 'restaurar';

  @override
  String get action_delete => 'excluir';

  @override
  String get migrate => 'Migrar';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chats atribuídos',
      one: '$count chat atribuído',
    );
    return '$_temp0';
  }

  @override
  String get date_today => 'Hoje';

  @override
  String get date_yesterday => 'Ontem';

  @override
  String get date_earlier => 'Anterior';

  @override
  String get nav_home => 'Início';

  @override
  String get nav_more => 'Mais';

  @override
  String get status_completed => 'Concluído';

  @override
  String get filter_all => 'Todos';

  @override
  String get filter_recent => 'Recentes';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  Chave: $status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model  \nvia `$provider`';
  }

  @override
  String get deny => 'Negar';

  @override
  String get connect => 'Conectar';

  @override
  String get appearance => 'Aparência';

  @override
  String get connection_section => 'Conexão';

  @override
  String get about => 'Sobre';

  @override
  String version_label(Object version) {
    return 'Versão $version';
  }

  @override
  String get matched => 'Correspondência';

  @override
  String get search => 'Pesquisar';

  @override
  String get on => 'Ativado';

  @override
  String get off => 'Desativado';

  @override
  String get reasoning_off => 'Desativado';

  @override
  String get hermes_response_ready => 'Resposta do Hermes pronta';

  @override
  String get admin_password_needed => 'Senha de administrador necessária';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      'O Hermes precisa de uma senha sudo para o comando de terminal pendente.';

  @override
  String get sudo_password => 'Senha do sudo';

  @override
  String get secret_needed => 'Segredo necessário';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      'O Hermes precisa de um segredo para a habilidade pendente.';

  @override
  String get secret_value => 'Valor do segredo';

  @override
  String get attached_file => 'Arquivo anexado';

  @override
  String get pin_on_this_device => 'Fixar neste dispositivo';

  @override
  String get unpin_on_this_device => 'Desafixar neste dispositivo';

  @override
  String get pinned_on_this_device => 'Fixados neste dispositivo';

  @override
  String get could_not_save_chat_pin =>
      'Não foi possível salvar a fixação neste dispositivo';

  @override
  String get could_not_save_chat_spaces =>
      'Não foi possível salvar os espaços de conversa neste dispositivo';

  @override
  String get update_available => 'Atualização disponível';

  @override
  String get a_newer_hermes_android_build_is_available_on_github =>
      'Há uma versão mais recente do Hermes Android no GitHub.';

  @override
  String get release_notes => 'Notas da versão';

  @override
  String get view_release => 'Ver a versão';

  @override
  String get skip_this_version => 'Ignorar esta versão';

  @override
  String get later => 'Mais tarde';

  @override
  String get check_for_updates => 'Verificar atualizações';

  @override
  String get check_for_updates_on_launch => 'Verificar atualizações ao iniciar';

  @override
  String get you_re_on_the_latest_version =>
      'Você já está na versão mais recente.';

  @override
  String get couldn_t_check_for_updates =>
      'Não foi possível verificar atualizações.';

  @override
  String get chat_density => 'Densidade do chat';

  @override
  String chat_density_2(Object label) {
    return 'Densidade do chat: $label';
  }

  @override
  String get chat_density_comfortable => 'Confortável';

  @override
  String get chat_density_compact => 'Compacta';

  @override
  String get chat_density_comfortable_description =>
      'Balões mais amplos com um rótulo de remetente acima de cada mensagem.';

  @override
  String get chat_density_compact_description =>
      'Balões mais justos e sem rótulo para caberem mais mensagens na tela.';

  @override
  String chat_density_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String
  get compact_removes_the_you_and_hermes_labels_and_trims_bubble_padding_spacing_and_side_margins =>
      'O modo compacto remove os rótulos You e Hermes e reduz as margens internas, o espaçamento e as margens laterais dos balões.';

  @override
  String get background_work => 'Trabalho em segundo plano';

  @override
  String get keep_chats_active_in_background =>
      'Manter conversas ativas em segundo plano';

  @override
  String get background_work_description =>
      'Mantém conectadas as conversas iniciadas por você enquanto o app está em segundo plano. Conexões ociosas podem ser desconectadas. Consome mais bateria e dados. Desativar não interrompe o trabalho no servidor.';

  @override
  String get background_work_limits =>
      'O Android ainda pode suspender conexões no modo Doze ou encerrar o processo do app. Notificações após o encerramento do processo exigem uma configuração de push separada. A parada forçada não é suportada.';

  @override
  String get background_work_disclosure =>
      'Uma notificação obrigatória do serviço permanece visível enquanto a proteção em segundo plano está ativa, mesmo com as notificações opcionais de conversa desativadas.';

  @override
  String get battery_optimisation_settings =>
      'Configurações de otimização da bateria';

  @override
  String get battery_optimisation_description =>
      'Abre as configurações do Android para revisar as restrições de bateria. Nenhuma exceção é solicitada automaticamente e alterar as configurações não garante a entrega.';

  @override
  String get battery_settings_unavailable =>
      'Não foi possível abrir as configurações de bateria neste dispositivo.';

  @override
  String get background_work_save_failed =>
      'Não foi possível salvar a configuração de trabalho em segundo plano.';

  @override
  String get ongoing_chat_channel_name => 'Conversas ativas';

  @override
  String get ongoing_chat_channel_description =>
      'Atualizações silenciosas de conversas iniciadas por você ainda não concluídas';

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
  String get activity_status_unconfirmed => 'Status não confirmado';

  @override
  String get activity_recently_updated => 'Atualizado recentemente';

  @override
  String get activity_reconnecting =>
      'Reconectando — verificando o status do turno';

  @override
  String get activity_outcome_unknown =>
      'Não foi possível confirmar o resultado do turno. Abra o chat para verificar.';

  @override
  String get activity_chat_updated_detail =>
      'Atividade do chat registrada pelo Gateway; o status do turno em tempo real não está disponível.';

  @override
  String get activity_updated => 'Atualizado';

  @override
  String get activity_empty_title => 'Nenhuma atividade recente';

  @override
  String get activity_empty_detail =>
      'Aqui aparecem os turnos iniciados neste app e os chats do Gateway atualizados nos últimos 7 dias.';

  @override
  String get activity_read_error =>
      'A Atividade não conseguiu ler os registros dos turnos ou os chats do Gateway. Verifique a conexão e tente novamente.';

  @override
  String get activity_chat_unavailable =>
      'Este chat não está mais disponível ou não foi possível acessar o Gateway.';

  @override
  String get activity_partial_title => 'Atividade parcialmente carregada';

  @override
  String get activity_partial_detail =>
      'Um intervalo limitado da atividade do gateway é exibido. Pode haver mais conversas; puxe para atualizar.';
}
