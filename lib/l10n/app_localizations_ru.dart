// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      'Разовый вопрос. Автоматически архивируется через 72 часа; всё, что стоит сохранить, останется в памяти.';

  @override
  String get ai_full_text => 'ИИ + полный текст';

  @override
  String get ai_search_model => 'Модель ИИ-поиска';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'ИИ искал: $aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'Сортировка с помощью ИИ';

  @override
  String get api_key => 'Ключ API';

  @override
  String get api_server_key_from_hermes_env =>
      'API_SERVER_KEY из ~/.hermes/.env';

  @override
  String get active => 'Активно';

  @override
  String get activity => 'Активность';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      'Активность читает долговременный журнал ходов, чтобы знать, что делает Hermes. Проверьте доступность шлюза и повторите попытку.';

  @override
  String get add => 'Добавить';

  @override
  String get add_connection => 'Добавить подключение';

  @override
  String get add_cron_job => 'Добавить задачу Cron';

  @override
  String get add_gateway_connection => 'Добавить подключение к шлюзу';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      'Добавить и обновить подключения из резервной копии, остальные сохранить.';

  @override
  String get add_attachment => 'Добавить вложение';

  @override
  String get add_new_cron_job => 'Добавить новую задачу Cron';

  @override
  String get add_to_chat => 'Добавить в чат';

  @override
  String get all_chats => 'Все чаты';

  @override
  String get all_stored_message_content =>
      'Всё сохранённое содержимое сообщений';

  @override
  String get allow_for_this_session => 'Разрешить в этой сессии';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      'Разрешать совпадающие команды до конца этой сессии Hermes.';

  @override
  String get allow_once => 'Разрешить один раз';

  @override
  String get always_allow => 'Всегда разрешать';

  @override
  String get apply_to_this_chat => 'Применить к этому чату';

  @override
  String get approval_needed => 'Требуется подтверждение';

  @override
  String get archive => 'Архивировать';

  @override
  String get archive_project => 'Архивировать проект';

  @override
  String archive_2(Object projectName) {
    return 'Архивировать $projectName?';
  }

  @override
  String archive_3(Object name) {
    return 'Архивировать $name?';
  }

  @override
  String get archived => 'В архиве';

  @override
  String get archived_conversations_appear_here =>
      'Архивированные диалоги появятся здесь.';

  @override
  String get archived_quick_chats => 'Архивированные быстрые чаты';

  @override
  String get artifacts_attachments_and_generated_media =>
      'Артефакты, вложения и созданные медиа';

  @override
  String get ask_ai_to_find_a_conversation => 'Попросить ИИ найти диалог';

  @override
  String get assets => 'Ресурсы';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      'Ресурсам нужен серверный авторитетный индекс в шлюзе Hermes, прежде чем их можно будет показывать по проектам.';

  @override
  String get assets_unavailable => 'Ресурсы недоступны';

  @override
  String get attach_image_or_file => 'Прикрепить изображение или файл';

  @override
  String get attachment_drafts => 'Черновики вложений';

  @override
  String attachment_of(Object index, Object total) {
    return 'Вложение $index из $total';
  }

  @override
  String get auto_device_default => 'Автоматически (по умолчанию устройства)';

  @override
  String get auto_archives_after_72_hours => 'Автоархивация через 72 часа';

  @override
  String get automation => 'Автоматизация';

  @override
  String get autonomous_agents => 'Автономные агенты';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      'Восстановление в фоне недоступно — устаревший транспорт';

  @override
  String get backup_restore => 'Резервное копирование и восстановление';

  @override
  String backup_exported(Object destination) {
    return 'Резервная копия экспортирована — $destination';
  }

  @override
  String get base_url => 'Базовый URL';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      'Предпросмотр двоичных файлов недоступен. Скачайте файл, чтобы открыть его.';

  @override
  String get branch => 'Ветка';

  @override
  String get branch_chat => 'Создать ветку чата';

  @override
  String get branch_created_in_hermes_history =>
      'Ветка создана в истории Hermes.';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      'Просматривайте сессии Hermes Agent и управляйте ими с телефона. Подключается к панели управления Hermes в вашей локальной сети.';

  @override
  String get browse_server_files => 'Просмотр файлов сервера';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      'Просмотр папок miniserver за вашими проектами';

  @override
  String get cancel => 'Отмена';

  @override
  String get cancel_voice_input => 'Отменить голосовой ввод';

  @override
  String cannot_reach(Object host, Object port) {
    return 'Не удаётся подключиться к $host:$port.';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return 'Не удаётся подключиться к $host:$port. Проверьте хост и порт.';
  }

  @override
  String get change_ai_search_model => 'Сменить модель ИИ-поиска';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return 'Меняет значение по умолчанию для $label. Используйте селектор в чате, чтобы переопределить только этот диалог.';
  }

  @override
  String get chat_actions => 'Действия с чатом';

  @override
  String get chats => 'Чаты';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      'Чаты этого шлюза пока не группируются. Группировка остаётся на этом телефоне, пока шлюз не сможет размещать проекты.';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      'Чаты этого проекта будут показывать здесь своё состояние и последнюю активность.';

  @override
  String get chats_that_are_not_assigned_to_a_project =>
      'Чаты, не назначенные проекту';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      'Чаты, начатые в этом проекте, появятся здесь на всех устройствах, где выполнен вход в этот Hermes.';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      'Проверьте, что шлюз запущен и доступен, и повторите попытку.';

  @override
  String get check_the_dashboard_connection_and_try_again =>
      'Проверьте подключение к панели управления и повторите попытку.';

  @override
  String get check_the_connection_and_try_again =>
      'Проверьте подключение и повторите попытку.';

  @override
  String get choose_a_small_model_to_rewrite_queries =>
      'Выберите небольшую модель для переписывания запросов';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      'Выберите модель ИИ-поиска перед использованием ИИ-поиска.';

  @override
  String get choose_an_active_project_next => 'Затем выберите активный проект';

  @override
  String get choose_chat_model => 'Выбрать модель чата';

  @override
  String get choose_files => 'Выбрать файлы';

  @override
  String get choose_image => 'Выбрать изображение';

  @override
  String get choose_images => 'Выбрать изображения';

  @override
  String get choose_its_destination_space => 'Выберите пространство назначения';

  @override
  String get clear_search => 'Очистить поиск';

  @override
  String get close => 'Закрыть';

  @override
  String get code_copied => 'Код скопирован';

  @override
  String get coming_next => 'Скоро';

  @override
  String get command => 'Команда';

  @override
  String get command_line_chats => 'Чаты в командной строке';

  @override
  String get compatibility_mode => 'Режим совместимости';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      'Настройте корректный URL Desktop Gateway, прежде чем прикреплять файлы.';

  @override
  String get confirm_always_allow => 'Подтвердить «Всегда разрешать»';

  @override
  String get confirm_passphrase => 'Подтвердите парольную фразу';

  @override
  String connecting_to(Object baseUrl) {
    return 'Подключение к $baseUrl...';
  }

  @override
  String get connection_issue => 'Проблема с подключением';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      'Подключение переключено — текущий ответ продолжится на сервере и автоматически переподключится.';

  @override
  String get connection_appearance_and_device_preferences =>
      'Подключение, внешний вид и настройки устройства';

  @override
  String context_tokens(Object effectiveContextLength) {
    return 'Контекст: $effectiveContextLength токенов';
  }

  @override
  String get continue_label => 'Продолжить';

  @override
  String get continue_working => 'Продолжить работу';

  @override
  String get conversations_in_this_project => 'Диалоги в этом проекте';

  @override
  String get copy_code => 'Копировать код';

  @override
  String get copy_message => 'Копировать сообщение';

  @override
  String could_not_branch_chat(Object error) {
    return 'Не удалось создать ветку чата: $error';
  }

  @override
  String could_not_delete_session(Object error) {
    return 'Не удалось удалить сессию: $error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return 'Не удалось отклонить команду: $error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return 'Не удалось загрузить модели ИИ-поиска: $error';
  }

  @override
  String get could_not_load_conversations => 'Не удалось загрузить диалоги';

  @override
  String get could_not_load_files => 'Не удалось загрузить файлы';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return 'Не удалось загрузить модели для этого профиля: $error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return 'Не удалось загрузить больше чатов: $error';
  }

  @override
  String get could_not_open_the_hermes_dashboard =>
      'Не удалось открыть панель управления Hermes.';

  @override
  String get could_not_open_this_project => 'Не удалось открыть этот проект';

  @override
  String get could_not_preview_file => 'Не удалось показать предпросмотр файла';

  @override
  String get could_not_reach_hermes => 'Не удалось подключиться к Hermes';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return 'Не удалось подключиться к панели управления $host:$dashboardPort или пройти аутентификацию. Проверьте порт и учётные данные.';
  }

  @override
  String get could_not_read_activity => 'Не удалось прочитать активность';

  @override
  String could_not_rename_chat(Object error) {
    return 'Не удалось переименовать чат: $error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return 'Не удалось отправить подтверждение: $error';
  }

  @override
  String get could_not_skip_the_hermes_question =>
      'Не удалось пропустить вопрос Hermes.';

  @override
  String could_not_the_project(Object action, Object error) {
    return 'Не удалось $action проект: $error';
  }

  @override
  String get couldn_t_delete_project => 'Не удалось удалить проект';

  @override
  String couldn_t_load_runs(Object error) {
    return 'Не удалось загрузить запуски: $error';
  }

  @override
  String get couldn_t_move_conversation => 'Не удалось переместить диалог';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return 'Не удалось переместить в $label: $reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files =>
      'Не удалось подготовить общие файлы.';

  @override
  String get couldn_t_promote_conversation => 'Не удалось повысить диалог';

  @override
  String couldn_t_project(Object action) {
    return 'Не удалось $action проект';
  }

  @override
  String get create => 'Создать';

  @override
  String get create_a_project => 'Создать проект';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      'Сначала создайте проект — потом в нём смогут жить чаты.';

  @override
  String get create_a_space_to_separate_related_conversations =>
      'Создайте пространство, чтобы разделить связанные диалоги.';

  @override
  String get create_branch => 'Создать ветку';

  @override
  String get cron => 'Cron';

  @override
  String get cron_jobs => 'Задачи Cron';

  @override
  String get cron_job_added => 'Задача Cron добавлена';

  @override
  String get cron_job_updated => 'Задача Cron обновлена';

  @override
  String get cron_run => 'Запуск Cron';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      'Упорядочивание между устройствами и обратимая массовая организация';

  @override
  String get current_profile_default => 'Текущее значение профиля по умолчанию';

  @override
  String get custom_proxy_and_dashboard_details =>
      'Пользовательские параметры прокси и панели управления';

  @override
  String get dark => 'Тёмная';

  @override
  String get dashboard_proxy_settings => 'Настройки панели управления / прокси';

  @override
  String get dashboard_password_optional =>
      'Пароль панели управления (необязательно)';

  @override
  String get dashboard_port => 'Порт панели управления';

  @override
  String get dashboard_username_optional =>
      'Имя пользователя панели управления (необязательно)';

  @override
  String get dashboard_behind_proxy => 'Панель управления за прокси';

  @override
  String get dashboard_path_prefix => 'Префикс пути панели управления';

  @override
  String delegated_task(Object goal) {
    return 'Делегированная задача: $goal';
  }

  @override
  String get delete => 'Удалить';

  @override
  String delete_2(Object name) {
    return 'Удалить «$name»?';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return 'Удалить «$title» из удалённой истории Hermes? Это действие нельзя отменить.';
  }

  @override
  String get delete_cron_job => 'Удалить задачу Cron';

  @override
  String get delete_connections_that_are_not_in_the_backup =>
      'Удалить подключения, которых нет в резервной копии.';

  @override
  String delete_failed(Object error) {
    return 'Не удалось удалить: $error';
  }

  @override
  String get delete_project => 'Удалить проект';

  @override
  String get delete_session => 'Удалить сессию?';

  @override
  String delete_3(Object projectName) {
    return 'Удалить $projectName?';
  }

  @override
  String deleted(Object name) {
    return 'Удалено: «$name»';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      'Доставка не подтверждена; восстановление без повторной отправки…';

  @override
  String get desktop_gateway_url_optional =>
      'URL Desktop Gateway (необязательно)';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      'Desktop Gateway не настроен для этого подключения.';

  @override
  String get desktop_app => 'Приложение для компьютера';

  @override
  String get developer_tool_calls => 'Вызовы инструментов разработчика';

  @override
  String get discord_chats => 'Чаты Discord';

  @override
  String get dismiss => 'Скрыть';

  @override
  String get do_not_run_this_command => 'Не выполняйте эту команду.';

  @override
  String get documents_archives_audio_video_or_data =>
      'Документы, архивы, аудио, видео или данные';

  @override
  String get download => 'Скачать';

  @override
  String download_failed(Object error) {
    return 'Ошибка скачивания: $error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you =>
      'Долговременные факты, которые Hermes хранит о вас';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      'Долговременная работа в одном из ваших проектов, общая с Desktop.';

  @override
  String get edit => 'Редактировать';

  @override
  String get edit_connection => 'Изменить подключение';

  @override
  String get edit_cron_job => 'Редактировать задачу Cron';

  @override
  String get edit_gateway_connection => 'Изменить подключение к шлюзу';

  @override
  String get edit_and_resend => 'Изменить и отправить снова';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      'Включает вложения файлов через удалённый шлюз Desktop.';

  @override
  String get enter_a_name => 'Введите имя';

  @override
  String get enter_a_passphrase => 'Введите парольную фразу.';

  @override
  String get enter_the_passphrase_for_this_backup =>
      'Введите парольную фразу для этой резервной копии.';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      'Все диалоги уже назначены проекту.';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      'Всё, что ещё не реализовано нативно, — в веб-панели управления с аутентификацией';

  @override
  String get explain_the_attached_content_clearly =>
      'Объясните прикреплённое содержимое понятно.';

  @override
  String explain_this_content_clearly(Object text) {
    return 'Объясните это содержимое понятно:\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      'Явный выбор меняет размер текста специальных возможностей Android; «Система» оставляет его без изменений.';

  @override
  String get export_label => 'Экспорт';

  @override
  String get export_share => 'Экспорт / поделиться';

  @override
  String get external_api_clients => 'Внешние клиенты API';

  @override
  String get extra_high => 'Очень высокий';

  @override
  String get extract_tasks => 'Извлечь задачи';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      'Извлеките из прикреплённого содержимого решения, сроки, ответственных и выполнимые задачи.';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return 'Извлеките из этого содержимого решения, сроки, ответственных и выполнимые задачи:\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return 'Не удалось добавить задачу: $error';
  }

  @override
  String get failed_to_load_cron_jobs => 'Не удалось загрузить задачи Cron';

  @override
  String get failed_to_load_memory => 'Не удалось загрузить память';

  @override
  String get failed_to_load_messages => 'Не удалось загрузить сообщения';

  @override
  String get failed_to_load_settings => 'Не удалось загрузить настройки';

  @override
  String get failed_to_load_skills => 'Не удалось загрузить навыки';

  @override
  String failed_to_update_job(Object error) {
    return 'Не удалось обновить задачу: $error';
  }

  @override
  String failed(Object error) {
    return 'Ошибка: $error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      'Файл прикреплён; регистрация в каталоге документов ожидается.';

  @override
  String get file_reference_added_to_chat => 'Ссылка на файл добавлена в чат';

  @override
  String get files => 'Файлы';

  @override
  String get fill_from_document => 'Заполнить из документа';

  @override
  String get folder_is_empty => 'Папка пуста';

  @override
  String get folders => 'Папки';

  @override
  String get full_text => 'Полный текст';

  @override
  String get gateway_api_access => 'Доступ к API шлюза';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      'Шлюз подключён, но панель управления недоступна или не прошла аутентификацию. Проверьте данные панели или очистите их, чтобы пропустить.';

  @override
  String get gateway_path_prefix => 'Префикс пути шлюза';

  @override
  String get go_to_end => 'В конец';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Hermes Agent для Android';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'Hermes не смог принять ответ. Повторите попытку.';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      'Hermes не смог загрузить ваши сохранённые подключения';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'Hermes не принял ответ. Повторите попытку.';

  @override
  String get hermes_is_responding => 'Hermes отвечает…';

  @override
  String get hermes_is_waiting_for_input => 'Hermes ждёт вашего ввода…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'Hermes сохраняет активным масштабирование текста специальных возможностей Android.';

  @override
  String get hermes_needs_your_input => 'Hermes нужен ваш ввод';

  @override
  String get hermes_profile_optional => 'Профиль Hermes (необязательно)';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'Профиль Hermes должен быть простым именем профиля, например «sol», а не путём.';

  @override
  String get hermes_reasoning_details => 'Детали рассуждений Hermes';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'Восстановление Hermes недоступно: $error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'Hermes безопасно остановил восстановление. Промпт не отправлялся повторно.';

  @override
  String get hide_passphrase => 'Скрыть парольную фразу';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      'Главной странице нужны ваши недавние чаты, чтобы знать, что заслуживает внимания. Проверьте доступность шлюза и повторите попытку.';

  @override
  String get host => 'Хост';

  @override
  String get image_selection_was_interrupted_try_again =>
      'Выбор изображения был прерван. Повторите попытку.';

  @override
  String get import_label => 'Импорт';

  @override
  String get inbox => 'Входящие';

  @override
  String get inbox_is_clear => 'Входящие пусты';

  @override
  String get insert_a_remote_file_reference =>
      'Вставить удалённую ссылку @file';

  @override
  String get invalid_port_number => 'Недопустимый номер порта.';

  @override
  String get job_paused => 'Задача приостановлена';

  @override
  String get job_resumed => 'Задача возобновлена';

  @override
  String get job_triggered => 'Задача запущена';

  @override
  String get label => 'Метка';

  @override
  String last_activity(Object day, Object month, Object year) {
    return 'Последняя активность $day.$month.$year';
  }

  @override
  String last(Object lastRun) {
    return 'Последний: $lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      'Оставьте пустым для значения по умолчанию (8642; 443 с https)';

  @override
  String get leave_blank_for_default_9119 =>
      'Оставьте пустым для значения по умолчанию (9119)';

  @override
  String get light => 'Светлая';

  @override
  String listening(Object elapsed) {
    return 'Слушаю • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return 'Слушаю, прошло: $elapsed';
  }

  @override
  String get load_more => 'Загрузить ещё…';

  @override
  String get loading => 'Загрузка';

  @override
  String get location => 'Местоположение';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      'Убедитесь, что сервер API шлюза запущен\n(hermes gateway status)';

  @override
  String matches(Object assigned, Object name) {
    return 'Совпадение: $name · $assigned';
  }

  @override
  String get memory => 'Память';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'Записи памяти — это факты между сессиями, которые помнит агент.\nОни настраиваются в ~/.hermes/config.yaml';

  @override
  String get merge => 'Объединить';

  @override
  String get message => 'Сообщение';

  @override
  String get message_hermes => 'Написать Hermes…';

  @override
  String get message_actions => 'Действия с сообщением';

  @override
  String get message_copied => 'Сообщение скопировано';

  @override
  String get migrating => 'Миграция…';

  @override
  String get migration_complete => 'Миграция завершена';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      'Миграция не удалась. Локальные пространства остались без изменений.';

  @override
  String get migration_incomplete => 'Миграция не завершена';

  @override
  String get migration_preview => 'Предпросмотр миграции';

  @override
  String get model => 'Модель';

  @override
  String get model_and_thinking_for_this_chat =>
      'Модель и рассуждения для этого чата';

  @override
  String model_was_not_changed(Object error) {
    return 'Модель не изменена: $error';
  }

  @override
  String get move_attachment_next => 'Переместить вложение вперёд';

  @override
  String get move_attachment_previous => 'Переместить вложение назад';

  @override
  String get move_chat => 'Переместить чат';

  @override
  String get move_conversation => 'Переместить диалог';

  @override
  String get move_to_project => 'Переместить в проект';

  @override
  String get move_to_space => 'Переместить в пространство';

  @override
  String get moved_to_a_project => 'Перемещено в проект';

  @override
  String moved_to(Object label) {
    return 'Перемещено в $label';
  }

  @override
  String get name => 'Имя';

  @override
  String get name_prompt_and_schedule_are_required =>
      'Имя, промпт и расписание обязательны';

  @override
  String get nav_activity => 'Актив';

  @override
  String get nav_projects => 'Проект';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Требуется контракт сортировки с учётом исправлений в шлюзе Hermes.';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      'Требуется доступная панель управления Hermes. Проверьте хост, порт и учётные данные этого подключения.';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Требуется серверный авторитетный индекс ресурсов в шлюзе Hermes.';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Требуются контракты порядка закрепления, массовых изменений и отмены в шлюзе Hermes.';

  @override
  String get needs_you => 'Требует внимания';

  @override
  String get new_label => 'Новое';

  @override
  String get new_chat => 'Новый чат';

  @override
  String get new_chat_2 => 'Новый чат';

  @override
  String new_chat_3(Object projectName) {
    return 'Новый чат · $projectName';
  }

  @override
  String get new_project => 'Новый проект';

  @override
  String get new_space => 'Новое пространство';

  @override
  String next(Object nextRun) {
    return 'Следующий: $nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'Nginx внедряет аутентификацию — приложение отправляет чистые запросы';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      'Голоса TTS не найдены.\nУстановите Google Text-to-Speech и скачайте голосовые данные.';

  @override
  String get no_active_projects_on_this_gateway =>
      'Нет активных проектов на этом шлюзе';

  @override
  String get no_activity_yet => 'Пока нет активности';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      'Нет чатов, которые заблокированы, выполняются или ждут возобновления. Начните новый, когда будете готовы.';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return 'Ни один чат в этом проекте не соответствует «$searchQuery».';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      'В этом пространстве пока нет чатов. Нажмите +, чтобы начать.';

  @override
  String get no_chats_yet => 'Пока нет чатов';

  @override
  String get no_connections => 'Нет подключений';

  @override
  String get no_conversation_matches_this_view =>
      'Ни один диалог не соответствует этому представлению.';

  @override
  String get no_cron_jobs => 'Нет задач Cron';

  @override
  String get no_folders_yet => 'Пока нет папок';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      'Для этого подключения не найдено локальных пространств, поэтому проекты уже являются единственной используемой организацией.';

  @override
  String get no_matches => 'Нет совпадений';

  @override
  String get no_memory_entries => 'Нет записей памяти';

  @override
  String get no_message_content_matches =>
      'Нет совпадений в содержимом сообщений';

  @override
  String get no_new_messages => 'Нет новых сообщений';

  @override
  String get no_projects_yet => 'Пока нет проектов';

  @override
  String get no_runs_yet => 'Пока нет запусков.';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return 'Ни один серверный проект не соответствует этому имени · $assigned';
  }

  @override
  String get no_sessions_yet => 'Пока нет сессий';

  @override
  String get no_skills_found => 'Навыки не найдены';

  @override
  String get no_spaces_on_this_device => 'На этом устройстве нет пространств';

  @override
  String get no_text_shared => 'Текст не передан';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      'Ни один ход не заблокирован, не выполняется и не завершён недавно. Начатая работа появится здесь.';

  @override
  String get no_turn_needs_your_input_or_has_failed =>
      'Ни один ход не требует вашего ввода и не завершился ошибкой.';

  @override
  String get no_unassigned_chats => 'Нет неназначенных чатов.';

  @override
  String get nothing_changed_in_the_last_seven_days =>
      'За последние семь дней ничего не изменилось.';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      'Пока ничего не перемещено — это лишь то, что сделала бы миграция.';

  @override
  String get nothing_here => 'Здесь ничего нет';

  @override
  String get nothing_is_running => 'Ничего не выполняется';

  @override
  String get nothing_needs_you => 'Ничего не требует вашего внимания';

  @override
  String get nothing_to_migrate => 'Нечего переносить';

  @override
  String get off_no_thinking => 'Выключено (без рассуждений)';

  @override
  String get offline_showing_the_last_known_activity =>
      'Не в сети — показана последняя известная активность.';

  @override
  String get offline_showing_the_last_known_chats =>
      'Не в сети — показаны последние известные чаты';

  @override
  String get offline_showing_the_last_known_projects =>
      'Не в сети — показаны последние известные проекты.';

  @override
  String get on_this_device => 'На этом устройстве';

  @override
  String get on_device => 'На устройстве';

  @override
  String get open_inbox => 'Открыть входящие';

  @override
  String open_inbox_2(Object count) {
    return 'Открыть входящие ($count)';
  }

  @override
  String get open_the_hermes_dashboard => 'Открыть панель управления Hermes';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      'Необязательно. Для вкладок «Память», «Cron», «Навыки» и «Настройки». Оставьте пустым, чтобы использовать стандартный порт панели (9119) без входа.';

  @override
  String get organization => 'Организация';

  @override
  String get other_answer => 'Другой ответ';

  @override
  String get overview => 'Обзор';

  @override
  String get passphrase => 'Парольная фраза';

  @override
  String get password_optional => 'Пароль (необязательно)';

  @override
  String get phone_or_tablet => 'Телефон или планшет';

  @override
  String get pin_batch_and_undo => 'Закрепление, массовые операции и отмена';

  @override
  String get port => 'Порт';

  @override
  String get preparing_attachments => 'Подготовка вложений…';

  @override
  String get preview_truncated => 'Предпросмотр усечён';

  @override
  String get preview_unavailable => 'Предпросмотр недоступен';

  @override
  String get profile => 'Профиль';

  @override
  String get profile_default_model => 'Модель профиля по умолчанию';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return 'Значение профиля по умолчанию: $selectedModel. Чаты с собственной моделью сохраняют это переопределение.';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      'Профиль, от имени которого работает это подключение, когда панель обслуживает несколько профилей. Оставьте пустым для изолированной панели для каждого профиля.';

  @override
  String get project => 'Проект';

  @override
  String get project_actions => 'Действия с проектом';

  @override
  String get project_chat => 'Чат проекта';

  @override
  String get project_chats_unavailable => 'Чаты проекта недоступны';

  @override
  String get projects => 'Проекты';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      'Проекты объединяют связанные чаты, файлы и активность и синхронизируются с Hermes на вашем компьютере.';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      'Проектам нужно подключение к Desktop Gateway. Добавьте URL Desktop Gateway к этому подключению, чтобы упорядочить чаты на всех устройствах.';

  @override
  String get projects_unavailable => 'Проекты недоступны';

  @override
  String get projects_activity_new_navigation =>
      'Проекты, Активность — новая навигация';

  @override
  String get promote_to_project => 'Повысить до проекта';

  @override
  String get prompt => 'Промпт';

  @override
  String get protect_this_backup => 'Защитить эту резервную копию';

  @override
  String get provider => 'Провайдер';

  @override
  String get proxy_injects_auth_app_sends_clean_requests =>
      'Прокси внедряет аутентификацию; приложение отправляет чистые запросы';

  @override
  String get quick_chat => 'Быстрый чат';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      'Быстрые чаты появляются здесь после окончания срока хранения.';

  @override
  String get read_aloud => 'Читать вслух';

  @override
  String get read_aloud_is_unavailable_on_this_device =>
      'Чтение вслух недоступно на этом устройстве';

  @override
  String get reading_response_aloud => 'Чтение ответа вслух';

  @override
  String get ready_to_upload => 'Готово к отправке';

  @override
  String get reasoning => 'Рассуждения';

  @override
  String get recently_completed => 'Недавно завершено';

  @override
  String get recovering_hermes => 'Восстановление Hermes…';

  @override
  String get refresh => 'Обновить';

  @override
  String get regenerate_response => 'Сгенерировать ответ заново';

  @override
  String get remove_attachment => 'Убрать вложение';

  @override
  String get rename => 'Переименовать';

  @override
  String get rename_chat => 'Переименовать чат';

  @override
  String get rename_project => 'Переименовать проект';

  @override
  String get rename_space => 'Переименовать пространство';

  @override
  String rename_2(Object projectName) {
    return 'Переименовать $projectName';
  }

  @override
  String rename_3(Object name) {
    return 'Переименовать $name';
  }

  @override
  String get replace => 'Заменить';

  @override
  String get repositories => 'Репозитории';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      'Изучите прикреплённое содержимое, проверьте важные утверждения и укажите источники.';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return 'Изучите это содержимое, проверьте важные утверждения и укажите источники:\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return 'Сброс не удался: $retryError. Возможно, потребуется переустановить защищённое хранилище.';
  }

  @override
  String get reset_saved_connections => 'Сбросить сохранённые подключения';

  @override
  String get responding => 'Отвечает…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return 'Ответ закрыт локально; не удалось остановить шлюз: $error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      'Ответ закрыт локально; активный ход шлюза не найден.';

  @override
  String get response_ready => 'Ответ готов';

  @override
  String get response_stopped => 'Ответ остановлен.';

  @override
  String get restore => 'Восстановить';

  @override
  String get restore_configuration => 'Восстановить конфигурацию';

  @override
  String get restore_project => 'Восстановить проект';

  @override
  String get retry => 'Повторить';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return 'Не удалось повторить для $name. Черновик и промпт сохранены.';
  }

  @override
  String get retry_upload => 'Повторить отправку';

  @override
  String retrying(Object name) {
    return 'Повторная попытка: $name…';
  }

  @override
  String get review_local_spaces => 'Проверить локальные пространства';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      'Проверить или повысить быстрые чаты с истёкшим сроком хранения';

  @override
  String get review_the_attached_content =>
      'Проверьте прикреплённое содержимое.';

  @override
  String get run_only_this_command => 'Выполните только эту команду.';

  @override
  String get running_now => 'Выполняется';

  @override
  String get save => 'Сохранить';

  @override
  String get save_changes => 'Сохранить изменения';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      'Сохраните постоянное правило в конфигурации Hermes.';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      'Сохраните долговременные факты из прикреплённого содержимого в память и подтвердите, что сохранено.';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return 'Сохраните долговременные факты из этого содержимого в память и подтвердите, что сохранено:\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      'Сохраните подключения и настройки в зашифрованный файл, а затем восстановите их после переустановки или на другом устройстве.';

  @override
  String save_2(Object filename) {
    return 'Сохранить $filename';
  }

  @override
  String get schedule => 'Расписание';

  @override
  String get scheduled_jobs_and_their_last_runs =>
      'Запланированные задачи и их последние запуски';

  @override
  String get scheduled_tasks => 'Запланированные задачи';

  @override
  String get script_only_no_agent => 'Только скрипт (без агента)';

  @override
  String get scroll_horizontally => 'Прокрутить по горизонтали';

  @override
  String get search_all_chats => 'Искать во всех чатах';

  @override
  String get search_all_message_content =>
      'Искать во всём содержимом сообщений';

  @override
  String get search_chats => 'Искать чаты';

  @override
  String get search_conversations => 'Искать диалоги';

  @override
  String get search_loaded_chats => 'Искать в загруженных чатах';

  @override
  String get search_mode => 'Режим поиска';

  @override
  String get select_one_option_or_enter_another_answer =>
      'Выберите один вариант или введите другой ответ.';

  @override
  String get select_one_or_more_options_then_continue =>
      'Выберите один или несколько вариантов и продолжите.';

  @override
  String get select_text => 'Выделить текст';

  @override
  String get send => 'Отправить';

  @override
  String send_failed(Object error) {
    return 'Ошибка отправки: $error';
  }

  @override
  String get send_message => 'Отправить сообщение';

  @override
  String get session_sources => 'Источники сессий';

  @override
  String get session_deleted_from_remote_hermes =>
      'Сессия удалена из удалённого Hermes.';

  @override
  String session_search_failed(Object error) {
    return 'Ошибка поиска сессий: $error';
  }

  @override
  String get set_profile_default => 'Сделать значением профиля по умолчанию';

  @override
  String get settings => 'Настройки';

  @override
  String get share_to_hermes => 'Поделиться с Hermes';

  @override
  String get show_passphrase => 'Показать парольную фразу';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      'Показывать вызовы инструментов, рассуждения и метаданные сообщений';

  @override
  String get signal_messages => 'Сообщения Signal';

  @override
  String get skills => 'Навыки';

  @override
  String skills_2(Object count) {
    return 'Навыки ($count)';
  }

  @override
  String get skills_and_tools => 'Навыки и инструменты';

  @override
  String get skip => 'Пропустить';

  @override
  String get slack_chats => 'Чаты Slack';

  @override
  String source(Object source) {
    return 'Источник: $source';
  }

  @override
  String get space_actions => 'Действия с пространством';

  @override
  String get spaces => 'Пространства';

  @override
  String get speak_to_hermes => 'Поговорить с Hermes';

  @override
  String get speech_recognition_is_unavailable =>
      'Распознавание речи недоступно';

  @override
  String get spoken_replies => 'Голосовые ответы';

  @override
  String get spoken_replies_off => 'Голосовые ответы выключены';

  @override
  String get spoken_replies_on => 'Голосовые ответы включены';

  @override
  String get stalled_no_update_from_hermes =>
      'Застряло — нет обновлений от Hermes';

  @override
  String get start_something_new => 'Начать что-то новое';

  @override
  String get start_voice_input => 'Начать голосовой ввод';

  @override
  String get starting_hermes => 'Запуск Hermes…';

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
  String get still_loading_your_projects => 'Ваши проекты всё ещё загружаются.';

  @override
  String get stop => 'Стоп';

  @override
  String get stop_response => 'Остановить ответ';

  @override
  String get stop_voice_input => 'Остановить голосовой ввод';

  @override
  String get submitted_waiting_for_hermes => 'Отправлено, ожидание Hermes';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      'Предлагать проекты и учиться на ваших исправлениях';

  @override
  String get summarize_the_attached_content =>
      'Суммируйте прикреплённое содержимое.';

  @override
  String summarize_this_content(Object text) {
    return 'Суммируйте это содержимое:\n\n$text';
  }

  @override
  String get switch_profile => 'Сменить профиль';

  @override
  String get system => 'Системная';

  @override
  String get take_photo => 'Сделать фото';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      'Нажмите +, чтобы добавить удалённый шлюз Hermes\n(сервер API, порт 8642)';

  @override
  String get tap_the_button_to_start_a_new_chat =>
      'Нажмите кнопку +, чтобы начать новый чат';

  @override
  String get telegram_messages => 'Сообщения Telegram';

  @override
  String get terminal_sessions => 'Сессии терминала';

  @override
  String get text_size => 'Размер текста';

  @override
  String get text_size_preview => 'Предпросмотр размера текста';

  @override
  String text_size_2(Object label) {
    return 'Размер текста: $label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely =>
      'Ключ API не удалось сохранить безопасно.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      'Проект переместится в «Архив». Его чаты и файлы останутся нетронутыми, и вы сможете восстановить его в любое время.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      'Проект переместится в «Архив». Его чаты и файлы останутся нетронутыми, и вы сможете восстановить его позже.';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      'Активный профиль не вернул ни одной доступной модели.';

  @override
  String get the_backup_could_not_be_exported =>
      'Резервную копию не удалось экспортировать.';

  @override
  String get the_backup_could_not_be_restored =>
      'Резервную копию не удалось восстановить.';

  @override
  String get the_connection_could_not_be_deleted_safely =>
      'Подключение не удалось безопасно удалить.';

  @override
  String get the_connection_could_not_be_stored_securely =>
      'Подключение не удалось безопасно сохранить.';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      'Учётные данные панели управления не удалось безопасно сохранить.';

  @override
  String get the_detached_reply_failed =>
      'Отсоединённый ответ завершился ошибкой.';

  @override
  String the_detached_reply_failed_2(Object error) {
    return 'Отсоединённый ответ завершился ошибкой: $error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      'Файл содержит ваши ключи API и пароль панели управления, поэтому он зашифрован. Без этой парольной фразы резервную копию нельзя восстановить.';

  @override
  String get the_last_turn_failed => 'Последний ход завершился ошибкой';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return 'Локальное хранилище подключений повреждено ($errorType). Вы можете сбросить сохранённые подключения и начать заново. Чаты на вашем шлюзе не затронуты.';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      'Модель лишь переписывает ваш вопрос в короткий полнотекстовый запрос. Hermes использует учётные данные провайдера, уже настроенные на хосте.';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      'Сервер ещё не сообщил папки для этого проекта. «Файлы» остаются доступными в разделе «Ещё».';

  @override
  String get the_turn_failed => 'Ход завершился ошибкой';

  @override
  String get the_two_passphrases_do_not_match =>
      'Парольные фразы не совпадают.';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      'Значение отправляется напрямую активному шлюзу Hermes и не сохраняется этим приложением Android.';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      'В этой папке сервера нет видимых файлов.';

  @override
  String get thinking_effort => 'Усилие рассуждений';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      'Этот шлюз Hermes пока не поддерживает открытие проектов. Обновите Hermes на сервере, чтобы просматривать проект с телефона.';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      'Этот шлюз Hermes старее серверных проектов, поэтому чаты группируются только на этом устройстве. Обновите Hermes, чтобы одни и те же проекты были на всех устройствах.';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      'В этом проекте нет папки, в которой можно открыть чат — он открылся неназначенным. Добавьте папку в проект, чтобы группировать его чаты.';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      'В этом чате пока нет сообщений в сессии Desktop.';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      'Это создаст постоянное правило в Hermes. Проверьте полную команду перед подтверждением.';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      'Этот шлюз пока не размещает проекты. Обновите шлюз, чтобы упорядочивать чаты на всех устройствах.';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      'Это навсегда удалит проект. Чаты не будут удалены — они вернутся в «Неназначенные».';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      'Этот сервер не поддерживает фоновое восстановление — чаты работают в реальном времени';

  @override
  String get this_week => 'На этой неделе';

  @override
  String get titles_previews_and_models => 'Заголовки, предпросмотры и модели';

  @override
  String get tool_activity => 'Активность инструментов';

  @override
  String get trigger_now => 'Запустить сейчас';

  @override
  String get turn_completed => 'Ход завершён';

  @override
  String get turn_recovery_failed => 'Не удалось восстановить ход';

  @override
  String get unable_to_prepare_this_file_try_another_one =>
      'Не удалось подготовить этот файл. Попробуйте другой.';

  @override
  String get unable_to_prepare_this_image_try_another_one =>
      'Не удалось подготовить это изображение. Попробуйте другое.';

  @override
  String unable_to_prepare(Object name) {
    return 'Не удалось подготовить $name.';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      'Не удалось прочитать выбранное изображение. Выбор сохранён.';

  @override
  String get unassigned => 'Неназначенные';

  @override
  String get unassigned_chats => 'Неназначенные чаты';

  @override
  String get untitled_chat => 'Чат без названия';

  @override
  String get untitled_session => 'Сессия без названия';

  @override
  String get update_api_key => 'Обновить ключ API';

  @override
  String get upload_failed => 'Ошибка отправки';

  @override
  String get upload_failed_tap_retry =>
      'Ошибка отправки • нажмите, чтобы повторить';

  @override
  String uploading(Object index, Object name, Object total) {
    return 'Отправка $index/$total: $name';
  }

  @override
  String get use_as_is => 'Использовать как есть';

  @override
  String get use_at_least_8_characters => 'Используйте не менее 8 символов.';

  @override
  String get use_for_cron_jobs_backed_by_scripts =>
      'Для задач Cron на основе скриптов.';

  @override
  String get use_on_device => 'Использовать на устройстве';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      'Используйте прикреплённое содержимое, чтобы определить и заполнить нужные поля документа или формы. Спрашивайте перед отправкой.';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return 'Используйте это содержимое, чтобы определить и заполнить нужные поля документа или формы. Спрашивайте перед отправкой:\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      'Используется для префиксов размещённых путей и для вкладок «Настройки», «Память», «Навыки» и «Cron». Оставьте имя пользователя и пароль пустыми для открытой панели или включите режим прокси, если обратный прокси внедряет аутентификацию панели.';

  @override
  String get username_optional => 'Имя пользователя (необязательно)';

  @override
  String using(Object displayName) {
    return 'Используется $displayName…';
  }

  @override
  String get verbose_mode => 'Подробный режим';

  @override
  String get voice => 'Голос';

  @override
  String voice_setup_failed(Object error) {
    return 'Ошибка настройки голоса: $error';
  }

  @override
  String get waiting_for_your_input => 'Ожидание вашего ввода';

  @override
  String get what_hermes_knows_how_to_do => 'Что Hermes умеет делать';

  @override
  String get what_should_the_agent_do => 'Что должен сделать агент?';

  @override
  String get whatsapp_messages => 'Сообщения WhatsApp';

  @override
  String get which_project => 'Какой проект?';

  @override
  String get workspace => 'Рабочая область';

  @override
  String get wrap_lines => 'Переносить строки';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return 'Можно прикрепить до $maxRemoteAttachmentDrafts элементов.';
  }

  @override
  String get your_answer => 'Ваш ответ';

  @override
  String get e_g_dashboard => 'напр. /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      'напр. /dashboard (путь прокси перед /api/)';

  @override
  String get e_g_profile_peter => 'напр. /profile/peter';

  @override
  String get e_g_sol => 'напр. sol';

  @override
  String get e_g_0_9_or_every_2h => 'напр. 0 9 * * * или every 2h';

  @override
  String get e_g_daily_backup => 'напр. Ежедневная резервная копия';

  @override
  String downloaded(Object filename) {
    return '$filename скачан';
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
      '192.168.1.50, 100.x.y.z или hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      'напр. /profile/peter (путь прокси перед /api/ и /v1/)';

  @override
  String and_more(Object count) {
    return 'и ещё $count';
  }

  @override
  String chats_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count чата',
      many: '$count чатов',
      few: '$count чата',
      one: '$count чат',
    );
    return '$_temp0';
  }

  @override
  String on_this_device_only(Object chats) {
    return '$chats · только на этом устройстве';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count пространства',
      many: '$count пространств',
      few: '$count пространства',
      one: '$count пространство',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => 'новые проекты не нужны';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count проекта для создания',
      many: '$count проектов для создания',
      few: '$count проекта для создания',
      one: '$count проект для создания',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return '$linkedSessions чатов перенесено · $createdProjects проектов создано';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '$unlinkedSessions чатов остались в локальных пространствах, можно безопасно повторить.';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • Рекомендуется: маленькая и недорогая';
  }

  @override
  String session_meta(Object count, Object model, Object time) {
    return '$count сообщ. • $model • $time';
  }

  @override
  String model_scope_label(Object model, Object scope) {
    return '$model • $scope';
  }

  @override
  String get this_chat => 'этот чат';

  @override
  String get profile_default => 'профиль по умолчанию';

  @override
  String minutes_ago(Object count) {
    return '$count мин назад';
  }

  @override
  String hours_ago(Object count) {
    return '$count ч назад';
  }

  @override
  String days_ago(Object count) {
    return '$count дн назад';
  }

  @override
  String get now_label => 'сейчас';

  @override
  String get latest_label => 'Последнее';

  @override
  String new_count_indicator(Object count) {
    return '$count новых';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count нового сообщения',
      many: '$count новых сообщений',
      few: '$count новых сообщения',
      one: '$count новое сообщение',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return '$failures с ошибкой • всего $total';
  }

  @override
  String activity_completed_summary(Object count) {
    return '$count завершено';
  }

  @override
  String get hermes_is_using_a_tool => 'Hermes использует инструмент';

  @override
  String hermes_is_using_tools(Object count) {
    return 'Hermes использует $count инструментов';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return '$count делегированных задач выполнено';
  }

  @override
  String delegated_tasks_active(Object count) {
    return '$count делегированных задач активно';
  }

  @override
  String branch_main(Object label) {
    return '$label · main';
  }

  @override
  String get you_heading => '## Вы';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => 'Действие';

  @override
  String get destination_label => 'Назначение';

  @override
  String get preview_label => 'Предпросмотр';

  @override
  String get share_action_summarize => 'Суммировать';

  @override
  String get share_action_explain => 'Объяснить';

  @override
  String get share_action_research => 'Исследовать';

  @override
  String get share_action_remember => 'Запомнить';

  @override
  String get text_size_small => 'Маленький';

  @override
  String get text_size_default => 'По умолчанию';

  @override
  String get text_size_large => 'Большой';

  @override
  String get text_size_extra_large => 'Очень большой';

  @override
  String get text_size_use_system_description =>
      'Использовать точно размер текста специальных возможностей Android.';

  @override
  String text_size_percent_description(Object percent) {
    return '$percent% от размера текста Android.';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return '$count файл(ов) пропущено: лимит, размер, нечитаемый файл или конфиденциальное имя файла.';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort теперь применяются только к этому чату.';
  }

  @override
  String get reasoning_minimal => 'Минимальный';

  @override
  String get reasoning_low => 'Низкий';

  @override
  String get reasoning_medium => 'Средний';

  @override
  String get reasoning_high => 'Высокий';

  @override
  String get reasoning_max => 'Максимальный';

  @override
  String get reasoning_ultra => 'Ультра';

  @override
  String get status_running => 'Выполняется';

  @override
  String get status_failed => 'Ошибка';

  @override
  String get status_done => 'Готово';

  @override
  String get status_idle => 'Ожидание';

  @override
  String get upload_status_uploading => 'Отправка';

  @override
  String get upload_status_uploaded => 'Отправлено';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count вложения',
      many: '$count вложений',
      few: '$count вложения',
      one: '$count вложение',
    );
    return '$_temp0';
  }

  @override
  String get action_create => 'создать';

  @override
  String get action_rename => 'переименовать';

  @override
  String get action_archive => 'архивировать';

  @override
  String get action_restore => 'восстановить';

  @override
  String get action_delete => 'удалить';

  @override
  String get migrate => 'Перенести';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count назначенного чата',
      many: '$count назначенных чатов',
      few: '$count назначенных чата',
      one: '$count назначенный чат',
    );
    return '$_temp0';
  }

  @override
  String get date_today => 'Сегодня';

  @override
  String get date_yesterday => 'Вчера';

  @override
  String get date_earlier => 'Ранее';

  @override
  String get nav_home => 'Дом';

  @override
  String get nav_more => 'Ещё';

  @override
  String get status_completed => 'Завершено';

  @override
  String get filter_all => 'Все';

  @override
  String get filter_recent => 'Недавние';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  Ключ: $status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model  \nчерез `$provider`';
  }

  @override
  String get deny => 'Отклонить';

  @override
  String get connect => 'Подключиться';

  @override
  String get appearance => 'Внешний вид';

  @override
  String get connection_section => 'Подключение';

  @override
  String get about => 'О приложении';

  @override
  String version_label(Object version) {
    return 'Версия $version';
  }

  @override
  String get matched => 'Совпадение';

  @override
  String get search => 'Поиск';

  @override
  String get on => 'Вкл.';

  @override
  String get off => 'Выкл.';

  @override
  String get reasoning_off => 'Выкл.';

  @override
  String get hermes_response_ready => 'Ответ Hermes готов';

  @override
  String get admin_password_needed => 'Требуется пароль администратора';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      'Hermes требует пароль sudo для ожидающей команды терминала.';

  @override
  String get sudo_password => 'Пароль sudo';

  @override
  String get secret_needed => 'Требуется секрет';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      'Hermes требует секрет для ожидающего навыка.';

  @override
  String get secret_value => 'Значение секрета';

  @override
  String get attached_file => 'Прикреплённый файл';
}
