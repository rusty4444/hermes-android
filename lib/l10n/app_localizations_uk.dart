// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get fallback_title => 'Резервні моделі';

  @override
  String get fallback_notice =>
      'Використовуються по черзі, коли основна модель недоступна. Зміни застосовуються лише до цього профілю; збережіть повний список явно.';

  @override
  String get fallback_unavailable =>
      'Параметри резерву недоступні або недійсні. Перевірте з’єднання, вибраний профіль і версію хоста, потім повторіть спробу.';

  @override
  String get fallback_discovery_unavailable =>
      'Виявлення провайдерів недоступне. Наявні записи збережено; повторіть спробу, щоб вибрати провайдерів і моделі.';

  @override
  String get fallback_empty => 'У цьому списку резерву немає записів.';

  @override
  String get fallback_incomplete =>
      'Виберіть провайдера і модель для кожного запису або видаліть незавершені записи перед збереженням.';

  @override
  String get fallback_add => 'Додати резерв';

  @override
  String get fallback_save => 'Зберегти список резерву';

  @override
  String get fallback_save_failed =>
      'Не вдалося перевірити збережений список резерву. Ваш чернетку збережено. Повторіть спробу збереження або оновіть, щоб перезавантажити параметри хоста.';

  @override
  String get fallback_saved => 'Список резерву збережено і перевірено.';

  @override
  String get fallback_legacy_title => 'Застарілі резерви (лише для читання)';

  @override
  String get fallback_legacy_notice =>
      'Хост також використовує fallback_model після цього списку, пропускаючи дублікати маршрутів. Ці застарілі записи зберігаються, навіть коли список вище порожній. Редагуйте їх на хості.';

  @override
  String fallback_priority(String position) {
    return 'Пріоритет $position';
  }

  @override
  String get fallback_move_up => 'Перемістити вгору';

  @override
  String get fallback_move_down => 'Перемістити вниз';

  @override
  String get fallback_routing_read_only =>
      'Деталі маршрутизації або неперерахований провайдер зберігаються. Редагуйте цього провайдера/модель на хості; ви все ще можете перевпорядкувати або видалити запис.';

  @override
  String get cron_model_default => 'За замовчуванням';

  @override
  String get cron_model_notice =>
      'Лише для цього завдання за розкладом. Без закріпленої моделі Hermes використовує типову модель розкладу, а потім основну. Власними моделями керуйте на сервері.';

  @override
  String get model_management_unavailable =>
      'Не вдалося завантажити або зберегти налаштування моделей. Оновіть і спробуйте ще раз.';

  @override
  String get model_management_subtitle =>
      'Основна та допоміжні моделі цього профілю';

  @override
  String get usage => 'Використання';

  @override
  String get nous_portal => 'Nous Portal';

  @override
  String get portal_menu_subtitle => 'Стан шлюзу й облік використання';

  @override
  String get portal_read_only =>
      'Дані шлюзу доступні лише для читання. Входом до Nous керуйте на сервері Hermes. Ці запити не надають залишок передплати чи кредитів.';

  @override
  String get portal_status => 'Стан порталу шлюзу';

  @override
  String get portal_free_tier =>
      'Безкоштовний доступ без входу в обліковий запис';

  @override
  String get portal_signed_in => 'Вхід виконано';

  @override
  String get portal_signed_out => 'Вхід не виконано';

  @override
  String get portal_account_tier => 'Рівень облікового запису';

  @override
  String get portal_recorded_usage => 'Облік використання';

  @override
  String get portal_all_providers =>
      'Усі провайдери вибраного профілю шлюзу. Нульова записана вартість не означає, що модель безкоштовна.';

  @override
  String portal_period(String days) {
    return 'Останні $days днів';
  }

  @override
  String get portal_sessions => 'Сесії';

  @override
  String get portal_input => 'Вхідні токени';

  @override
  String get portal_output => 'Вихідні токени';

  @override
  String get portal_estimated => 'Орієнтовна записана вартість';

  @override
  String get portal_actual => 'Фактична записана вартість';

  @override
  String get portal_recorded_models => 'Використані моделі';

  @override
  String get portal_no_models => 'Записів про моделі немає.';

  @override
  String get portal_unavailable =>
      'Недоступно. Перевірте підключення, вибраний профіль і версію шлюзу та повторіть спробу.';

  @override
  String get paste_attachment_failed_text_kept =>
      'Не вдалося додати вставлений текст як вкладення. Текст залишено в повідомленні.';

  @override
  String get background_task_report => 'Фонове завдання';

  @override
  String get background_process_report => 'Фоновий процес';

  @override
  String get background_report_issues =>
      'Виявлено проблеми — розгорніть подробиці.';

  @override
  String get background_report_expand => 'Розгорнути звіт';

  @override
  String get background_report_collapse => 'Згорнути звіт';

  @override
  String get hands_free_title => 'Голос без рук';

  @override
  String get hands_free_start => 'Увімкнути голос без рук';

  @override
  String get hands_free_stop => 'Вимкнути голос без рук';

  @override
  String get hands_free_preparing => 'Підготовка голосу — зачекайте сигналу';

  @override
  String get hands_free_listening => 'Скажіть Hey Hermes';

  @override
  String get hands_free_recording => 'Готово — говоріть';

  @override
  String get hands_free_waiting => 'Очікування Hermes';

  @override
  String get hands_free_speaking => 'Відтворення відповіді — мікрофон вимкнено';

  @override
  String hands_free_followup(int seconds) {
    return 'Слухати до $seconds секунд';
  }

  @override
  String get hands_free_error => 'Голос без рук зупинено';

  @override
  String get hands_free_setup => 'Налаштування голосу без рук';

  @override
  String hands_free_preview(String transcript) {
    return 'Розпізнаний текст: $transcript';
  }

  @override
  String get hands_free_short_disclosure =>
      'Лише поки цей чат відкритий на екрані. Активація працює локально; розпізнавання мовлення може використовувати мережу. Витрачає заряд.';

  @override
  String get hands_free_error_action =>
      'Перевірте дозвіл мікрофона, службу розпізнавання, голос відповідей і підключення. Для повторної спроби натисніть «Зупинити», а потім «Почати». Повторного надсилання немає.';

  @override
  String get hands_free_disclosure =>
      'Активація голосом працює локально на процесорі. Розпізнавання Android, вибраний голос відповіді та шлюз можуть використовувати мережу. Слухання витрачає заряд; можливі хибні спрацювання. Зупиняється, коли чат перекритий, закритий або застосунок у фоні; повторне відкриття не запускає його. Звичайне диктування залишається редагованою чернеткою.';

  @override
  String get hands_free_ready_cue =>
      'Скажіть «Hey Hermes», дочекайтеся «Готово — говоріть» і починайте. Початок фрази до сигналу не записується. Якщо для дозволів довелося вийти із застосунку, після повернення знову натисніть «Почати».';

  @override
  String get hands_free_settings_title => 'Голосове керування без рук';

  @override
  String get hands_free_settings_subtitle =>
      'Показувати кнопку запуску «Hey Hermes» у чатах. Вимкнення зупиняє поточне голосове керування.';

  @override
  String get hands_free_timing_limit =>
      'Час для продовження — максимальний, а не мінімальний. Android може завершити запис раніше. Після тиші повертається локальне очікування активації без повторних запусків розпізнавання.';

  @override
  String get hands_free_followup_off =>
      'Продовження вимкнено — кажіть Hey Hermes перед кожним запитом';

  @override
  String get hands_free_start_blocked =>
      'Для запуску потрібні порожня чернетка, відсутність вкладень, підключений вільний чат і ввімкнені голосові відповіді. Спершу завершіть ручний запис.';

  @override
  String get hands_free_setup_complete =>
      'Мікрофон налаштовано. Знову натисніть «Почати».';

  @override
  String message_time_recorded(String time) {
    return 'Збережено сервером: $time (місцевий час)';
  }

  @override
  String message_time_sent(String time) {
    return 'Надсилання зафіксовано на цьому пристрої: $time (місцевий час)';
  }

  @override
  String message_time_received(String time) {
    return 'Уперше отримано на цьому пристрої: $time (місцевий час)';
  }

  @override
  String get stop_and_send => 'Зупинити й надіслати';

  @override
  String get message_queued_for_running_turn =>
      'Повідомлення додано в чергу поточного запуску.';

  @override
  String get running_message_not_accepted =>
      'Hermes не зміг прийняти повідомлення. Чернетку збережено; зупиніть відповідь або дочекайтеся завершення й надішліть знову.';

  @override
  String get running_message_delivery_unknown =>
      'Не вдалося підтвердити доставку. Чернетку збережено. Перед повторним надсиланням перевірте чат.';

  @override
  String get attachment_tap_to_preview => 'Торкніться для перегляду';

  @override
  String get attachment_save => 'Зберегти';

  @override
  String get attachment_share => 'Поділитися';

  @override
  String get attachment_saved => 'Файл збережено';

  @override
  String get attachment_save_cancelled => 'Збереження скасовано';

  @override
  String get attachment_save_failed =>
      'Не вдалося зберегти файл. Спробуйте ще раз.';

  @override
  String get attachment_share_failed =>
      'Не вдалося поділитися файлом. Спробуйте ще раз.';

  @override
  String get attachment_download_failed =>
      'Не вдалося завантажити файл. Перевірте підключення й повторіть спробу.';

  @override
  String get attachment_no_inline_preview =>
      'Для цього типу файлу попередній перегляд недоступний. Збережіть оригінал або поділіться ним, щоб відкрити в іншому застосунку.';

  @override
  String get attachment_image_failed =>
      'Не вдалося прочитати зображення. Ви можете зберегти оригінал або поділитися ним.';

  @override
  String get attachment_text_truncated =>
      'Перегляд скорочено. Збережіть файл або поділіться ним, щоб прочитати повністю.';

  @override
  String get attachment_text_unavailable =>
      'Не вдалося показати файл як текст. Збережіть оригінал або поділіться ним.';

  @override
  String get attachment_pdf_failed =>
      'Не вдалося показати PDF. Збережіть оригінал або поділіться ним.';

  @override
  String get attachment_pdf_unavailable =>
      'Попередній перегляд PDF доступний на Android. Ви можете зберегти цей файл або поділитися ним.';

  @override
  String attachment_pdf_page(int page, int total) {
    return 'Сторінка $page з $total';
  }

  @override
  String get attachment_previous_page => 'Попередня сторінка';

  @override
  String get attachment_next_page => 'Наступна сторінка';

  @override
  String get attachment_loading => 'Завантаження перегляду…';

  @override
  String get attachment_document_text_notice =>
      'Текстовий перегляд. Розташування, зображення та форматування можуть відрізнятися від оригіналу.';

  @override
  String get attachment_document_failed =>
      'Не вдалося показати документ. Збережіть оригінал або поділіться ним.';

  @override
  String get attachment_document_empty =>
      'У документі не знайдено читабельного тексту.';

  @override
  String get attachment_video_failed =>
      'Не вдалося відтворити відео. Формат або кодек може не підтримуватися. Збережіть оригінал або поділіться ним.';

  @override
  String get attachment_video_play => 'Відтворити';

  @override
  String get attachment_video_pause => 'Пауза';

  @override
  String get attachment_video_mute => 'Вимкнути звук';

  @override
  String get attachment_video_unmute => 'Увімкнути звук';

  @override
  String get attachment_video_seek => 'Позиція відео';

  @override
  String get attachment_close => 'Закрити перегляд';

  @override
  String get attachment_retry => 'Повторити';

  @override
  String get saved_history_heading => 'Збережена історія';

  @override
  String get received_output_heading =>
      'Отримана відповідь — збіг зі збереженою історією не підтверджено';

  @override
  String get received_output_details => 'Про отриману відповідь';

  @override
  String get received_output_explanation =>
      'Це також може бути у збереженій історії. Застосунок не може підтвердити збіг.';

  @override
  String get local_prompt_context => 'Локальний контекст запиту';

  @override
  String get received_output_badge => 'Отримано · збіг не підтверджено';

  @override
  String get received_output_lifetime =>
      'Отримана відповідь тимчасово зберігається в цій сесії застосунку. Після досягнення обмежень її можуть скоротити або видалити. Після закриття застосунку чи підключення вона може бути недоступною.';

  @override
  String get theme_palette => 'Колірна тема';

  @override
  String get theme_palette_gold => 'Золота';

  @override
  String get theme_palette_purple => 'Фіолетова';

  @override
  String get theme_palette_orange => 'Оранжева';

  @override
  String get theme_palette_green => 'Зелена';

  @override
  String get theme_palette_blue => 'Синя';

  @override
  String get theme_palette_red => 'Червона';

  @override
  String get theme_palette_teal => 'Бірюзова';

  @override
  String get theme_palette_pink => 'Рожева';

  @override
  String get theme_palette_indigo => 'Індиго';

  @override
  String get theme_palette_cyan => 'Блакитна';

  @override
  String get assets_recent_subtitle =>
      'Файли, якими Hermes поділився у збережених чатах';

  @override
  String get assets_scope_notice =>
      'Створені файли, на які Hermes явно послався у збережених відповідях. Це частковий перегляд історії, а не повний каталог файлів чи вкладень. Файли за посиланнями вже можуть не існувати.';

  @override
  String get assets_download_limit =>
      'Файли завантажуються лише після натискання. Межа перегляду й завантаження — 25 МіБ на файл; для більших файлів використовуйте вебпанель.';

  @override
  String get assets_search_hint =>
      'Пошук серед знайдених файлів і чатів-джерел';

  @override
  String get assets_all => 'Усі';

  @override
  String get assets_images => 'Зображення';

  @override
  String get assets_audio => 'Аудіо';

  @override
  String get assets_video => 'Відео';

  @override
  String get assets_documents => 'Документи та інші файли';

  @override
  String get assets_empty => 'У перевірених повідомленнях файлів не знайдено';

  @override
  String get assets_empty_detail =>
      'Перевірте більше чатів або старіші повідомлення. Звичайні вкладення й файли без посилань тут не індексуються.';

  @override
  String get assets_no_matches => 'Відповідних файлів немає';

  @override
  String get assets_load_more_chats => 'Перевірити більше чатів';

  @override
  String get assets_load_older_messages => 'Перевірити старіші повідомлення';

  @override
  String get assets_load_failed =>
      'Частину історії не вдалося прочитати. Результати неповні. Перевірте підключення до вебпанелі й повторіть спробу.';

  @override
  String get assets_retry_failed => 'Повторити невдалі читання історії';

  @override
  String get assets_partial =>
      'Сервер повідомив про неповну історію. Перевірте вебпанель і оновіть.';

  @override
  String assets_scan_summary(int files, int chats) {
    return 'Знайдено $files посилань на файли в $chats перевірених чатах';
  }

  @override
  String assets_open_chat(String title) {
    return 'Відкрити чат: $title';
  }

  @override
  String get assets_file_too_large =>
      'Файл перевищує межу завантаження. Відкрийте вебпанель, щоб завантажити його.';

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      'Разове запитання. Через 72 години чат автоматично архівується; важливе залишається в пам’яті.';

  @override
  String get archive_chat => 'Архівувати чат';

  @override
  String get unarchive_chat => 'Повернути чат з архіву';

  @override
  String get chat_archived => 'Чат архівовано';

  @override
  String get chat_unarchived => 'Чат повернуто з архіву';

  @override
  String could_not_update_chat_archive(Object error) {
    return 'Не вдалося змінити архівний стан чату: $error';
  }

  @override
  String get quick_chat_description => 'Разове запитання.';

  @override
  String get ai_full_text => 'ШІ + повнотекстовий';

  @override
  String get ai_search_model => 'Модель ШІ для пошуку';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'ШІ шукав: $aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'Упорядкування за допомогою ШІ';

  @override
  String get api_key => 'Ключ API';

  @override
  String get api_server_key_from_hermes_env =>
      'API_SERVER_KEY із ~/.hermes/.env';

  @override
  String get active => 'Активний';

  @override
  String get activity => 'Активність';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      'Вкладка активності читає збережений журнал ходів, щоб показувати роботу Hermes. Перевірте доступність шлюзу й повторіть спробу.';

  @override
  String get add => 'Додати';

  @override
  String get add_connection => 'Додати підключення';

  @override
  String get add_cron_job => 'Додати завдання за розкладом';

  @override
  String get add_gateway_connection => 'Додати підключення до шлюзу';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      'Додати й оновити підключення з резервної копії, решту залишити.';

  @override
  String get add_attachment => 'Додати вкладення';

  @override
  String get add_new_cron_job => 'Додати нове завдання за розкладом';

  @override
  String get add_to_chat => 'Додати до чату';

  @override
  String get all_chats => 'Усі чати';

  @override
  String get all_stored_message_content => 'Увесь збережений вміст повідомлень';

  @override
  String get allow_for_this_session => 'Дозволити на цю сесію';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      'Дозволяти відповідні команди до завершення цієї сесії Hermes.';

  @override
  String get allow_once => 'Дозволити один раз';

  @override
  String get always_allow => 'Завжди дозволяти';

  @override
  String get apply_to_this_chat => 'Застосувати до цього чату';

  @override
  String get approval_needed => 'Потрібне підтвердження';

  @override
  String get approval_needed_description =>
      'Команда очікує вашого дозволу або відмови.';

  @override
  String get approve => 'Дозволити';

  @override
  String get archive => 'Архівувати';

  @override
  String get archive_project => 'Архівувати проєкт';

  @override
  String archive_2(Object projectName) {
    return 'Архівувати $projectName?';
  }

  @override
  String archive_3(Object name) {
    return 'Архівувати $name?';
  }

  @override
  String get archived => 'Архів';

  @override
  String get archived_conversations_appear_here =>
      'Тут лише архівні розмови. Старіші чати залишаються в розділі «Усі чати».';

  @override
  String get archived_quick_chats => 'Архівні швидкі чати';

  @override
  String get artifacts_attachments_and_generated_media =>
      'Артефакти, вкладення та створені медіафайли';

  @override
  String get ask_ai_to_find_a_conversation => 'Попросити ШІ знайти розмову';

  @override
  String get assets => 'Файли';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      'Для показу файлів за проєктами потрібен серверний індекс файлів у шлюзі Hermes.';

  @override
  String get assets_unavailable => 'Файли недоступні';

  @override
  String get attach_image_or_file => 'Додати зображення або файл';

  @override
  String get attachment_drafts => 'Чернетки вкладень';

  @override
  String attachment_of(Object index, Object total) {
    return 'Вкладення $index з $total';
  }

  @override
  String get auto_device_default => 'Автоматично (як на пристрої)';

  @override
  String get agent => 'Агент';

  @override
  String get autonomous_agents => 'Автономні агенти';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      'Фонове відновлення недоступне — застаріле підключення';

  @override
  String get background_task_completed => 'Фонове завдання завершено';

  @override
  String get background_task_completed_description =>
      'Фонова команда термінала завершилася.';

  @override
  String get backup_restore => 'Резервна копія та відновлення';

  @override
  String backup_exported(Object destination) {
    return 'Резервну копію експортовано — $destination';
  }

  @override
  String get base_url => 'Базова адреса';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      'Попередній перегляд двійкових файлів недоступний. Завантажте файл, щоб відкрити його.';

  @override
  String get branch => 'Гілка';

  @override
  String get branch_chat => 'Створити відгалуження чату';

  @override
  String get branch_created_in_hermes_history =>
      'Відгалуження створено в історії Hermes.';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      'Переглядайте сесії Hermes Agent і керуйте ними з телефона. Підключається до вебпанелі Hermes у вашій локальній мережі.';

  @override
  String get browse_server_files => 'Перегляд файлів сервера';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      'Переглядайте серверні папки ваших проєктів';

  @override
  String get cancel => 'Скасувати';

  @override
  String get cancel_voice_input => 'Скасувати голосовий ввід';

  @override
  String cannot_reach(Object host, Object port) {
    return 'Немає зв’язку з $host:$port.';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return 'Немає зв’язку з $host:$port. Перевірте адресу й порт.';
  }

  @override
  String get change_ai_search_model => 'Змінити модель пошуку ШІ';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return 'Змінює типову модель для $label. Щоб змінити лише одну розмову, скористайтеся вибором моделі в чаті.';
  }

  @override
  String get chat_actions => 'Дії чату';

  @override
  String get chats => 'Чати';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      'Чати цього шлюзу ще не згруповані. Групування залишатиметься на телефоні, доки шлюз не підтримуватиме проєкти.';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      'Тут відображатимуться стан і остання активність чатів цього проєкту.';

  @override
  String get chats_that_are_not_assigned_to_a_project =>
      'Чати, що не належать до жодного проєкту';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      'Створені в цьому проєкті чати відображатимуться тут на всіх пристроях, підключених до цього Hermes.';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      'Перевірте, чи шлюз запущений і доступний, та повторіть спробу.';

  @override
  String get check_the_dashboard_connection_and_try_again =>
      'Перевірте підключення до вебпанелі й повторіть спробу.';

  @override
  String get check_the_connection_and_try_again =>
      'Перевірте підключення й повторіть спробу.';

  @override
  String get choose_a_small_model_to_rewrite_queries =>
      'Виберіть невелику модель для переформулювання запитів';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      'Перед використанням пошуку ШІ виберіть його модель.';

  @override
  String get choose_an_active_project_next => 'Далі виберіть активний проєкт';

  @override
  String get choose_chat_model => 'Вибрати модель чату';

  @override
  String get choose_files => 'Вибрати файли';

  @override
  String get choose_image => 'Вибрати зображення';

  @override
  String get choose_images => 'Вибрати зображення';

  @override
  String get choose_its_destination_space => 'Виберіть розділ призначення';

  @override
  String get clear_search => 'Очистити пошук';

  @override
  String get close => 'Закрити';

  @override
  String get code_copied => 'Код скопійовано';

  @override
  String get code_format => 'Код';

  @override
  String get coming_next => 'Незабаром';

  @override
  String get command => 'Команда';

  @override
  String get command_palette => 'Палітра команд';

  @override
  String get command_palette_hint => 'Введіть команду';

  @override
  String get command_palette_no_results => 'Команд не знайдено';

  @override
  String get command_palette_new_chat => 'Новий чат';

  @override
  String get command_palette_search_chats => 'Пошук чатів';

  @override
  String get command_palette_toggle_theme => 'Змінити тему';

  @override
  String get command_palette_copy_last_code => 'Копіювати останній блок коду';

  @override
  String get command_line_chats => 'Чати командного рядка';

  @override
  String get compatibility_mode => 'Режим сумісності';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      'Перед додаванням файлів налаштуйте правильну адресу серверного Desktop Gateway.';

  @override
  String get confirm_always_allow => 'Підтвердити постійний дозвіл';

  @override
  String get confirm_passphrase => 'Підтвердьте парольну фразу';

  @override
  String connecting_to(Object baseUrl) {
    return 'Підключення до $baseUrl…';
  }

  @override
  String get connection_issue => 'Проблема підключення';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      'Підключення змінено — відповідь продовжує формуватися на сервері й автоматично під’єднається знову.';

  @override
  String get connection_appearance_and_device_preferences =>
      'Підключення, вигляд і налаштування пристрою';

  @override
  String context_tokens(Object effectiveContextLength) {
    return 'Контекст: $effectiveContextLength токенів';
  }

  @override
  String get continue_label => 'Продовжити';

  @override
  String get continue_working => 'Продовжити роботу';

  @override
  String get conversations_in_this_project => 'Розмови цього проєкту';

  @override
  String get copy_code => 'Копіювати код';

  @override
  String get copy_message => 'Копіювати повідомлення';

  @override
  String could_not_branch_chat(Object error) {
    return 'Не вдалося створити відгалуження чату: $error';
  }

  @override
  String could_not_delete_session(Object error) {
    return 'Не вдалося видалити сесію: $error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return 'Не вдалося відхилити команду: $error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return 'Не вдалося завантажити моделі пошуку ШІ: $error';
  }

  @override
  String get could_not_load_conversations => 'Не вдалося завантажити розмови';

  @override
  String get could_not_load_files => 'Не вдалося завантажити файли';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return 'Не вдалося завантажити моделі цього профілю: $error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return 'Не вдалося завантажити інші чати: $error';
  }

  @override
  String get could_not_open_link => 'Не вдалося відкрити посилання.';

  @override
  String get could_not_open_the_hermes_dashboard =>
      'Не вдалося відкрити вебпанель Hermes.';

  @override
  String get could_not_open_this_project => 'Не вдалося відкрити проєкт';

  @override
  String get could_not_preview_file => 'Не вдалося переглянути файл';

  @override
  String get could_not_reach_hermes => 'Не вдалося підключитися до Hermes';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return 'Не вдалося підключитися або увійти до вебпанелі за адресою $host:$dashboardPort. Перевірте порт і облікові дані.';
  }

  @override
  String get could_not_read_activity => 'Не вдалося прочитати активність';

  @override
  String could_not_rename_chat(Object error) {
    return 'Не вдалося перейменувати чат: $error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return 'Не вдалося надіслати підтвердження: $error';
  }

  @override
  String get could_not_skip_the_hermes_question =>
      'Не вдалося пропустити запитання Hermes.';

  @override
  String could_not_the_project(Object action, Object error) {
    return 'Не вдалося виконати дію «$action» для проєкту: $error';
  }

  @override
  String get couldn_t_delete_project => 'Не вдалося видалити проєкт';

  @override
  String couldn_t_load_runs(Object error) {
    return 'Не вдалося завантажити запуски: $error';
  }

  @override
  String get couldn_t_move_conversation => 'Не вдалося перемістити розмову';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return 'Не вдалося перемістити до $label: $reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files =>
      'Не вдалося підготувати файли для поширення.';

  @override
  String get couldn_t_promote_conversation =>
      'Не вдалося перенести розмову до проєкту';

  @override
  String couldn_t_project(Object action) {
    return 'Не вдалося виконати дію «$action» для проєкту';
  }

  @override
  String get create => 'Створити';

  @override
  String get create_a_project => 'Створити проєкт';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      'Спершу створіть проєкт, потім додайте до нього чати.';

  @override
  String get create_a_space_to_separate_related_conversations =>
      'Створіть розділ, щоб відокремити пов’язані розмови.';

  @override
  String get create_branch => 'Створити відгалуження';

  @override
  String get credit_notifications => 'Сповіщення про кредити';

  @override
  String get credit_notifications_description =>
      'Використання кредитів зупинено або відновлено.';

  @override
  String get cron => 'Розклад';

  @override
  String get crons => 'Розклади';

  @override
  String get cron_conversations_empty =>
      'Тут розмови із завдань за розкладом, зокрема попередні запуски.';

  @override
  String get search_cron_conversations => 'Пошук розмов за розкладом';

  @override
  String get cron_jobs => 'Завдання за розкладом';

  @override
  String cron_schedule_timezone(Object zone) {
    return 'Часовий пояс розкладу: $zone';
  }

  @override
  String get crons_upcoming => 'Майбутні';

  @override
  String get crons_history => 'Історія';

  @override
  String cron_time_with_zone(Object time, Object zone) {
    return '$time ($zone)';
  }

  @override
  String cron_time_zone_unknown(Object time) {
    return '$time (часовий пояс невідомий)';
  }

  @override
  String get cron_no_next_run => 'Наступний запуск не заплановано';

  @override
  String get cron_status_scheduled => 'Заплановано';

  @override
  String get cron_status_paused => 'Призупинено';

  @override
  String cron_delivers_to(Object target) {
    return 'Доставка до $target';
  }

  @override
  String get cron_upcoming_empty_title => 'Немає запланованих завдань';

  @override
  String get cron_upcoming_empty_message =>
      'До запуску нічого не заплановано. Створіть завдання в розділі «Завдання за розкладом» або попросіть агента запланувати його.';

  @override
  String get cron_upcoming_unavailable => 'Заплановані завдання недоступні';

  @override
  String get cron_upcoming_needs_dashboard =>
      'Для запланованих завдань потрібне підключення до вебпанелі. Ця адреса не надає розклад Cron. Перевірте адресу вебпанелі та підтримку цієї функції на сервері.';

  @override
  String get cron_upcoming_needs_dashboard_auth =>
      'Для запланованих завдань потрібна автентифікація вебпанелі. Додайте ім’я користувача та пароль вебпанелі до цього підключення або увімкніть режим через проксі.';

  @override
  String get cron_upcoming_dashboard_unreachable =>
      'Не вдалося підключитися до вебпанелі. Перевірте вузол, порт вебпанелі та мережу, потім повторіть спробу.';

  @override
  String get cron_upcoming_load_failed =>
      'Не вдалося прочитати заплановані завдання. Перевірте підключення до вебпанелі й повторіть спробу.';

  @override
  String get cron_upcoming_refresh_failed =>
      'Не вдалося оновити розклад. Показано останній успішний результат.';

  @override
  String get cron_job_added => 'Завдання за розкладом додано';

  @override
  String get cron_job_updated => 'Завдання за розкладом оновлено';

  @override
  String get cron_run => 'Запуск за розкладом';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      'Порядок на всіх пристроях і зворотне масове впорядкування';

  @override
  String get current_profile_default => 'Типова модель поточного профілю';

  @override
  String get custom_proxy_and_dashboard_details =>
      'Додаткові параметри проксі та вебпанелі';

  @override
  String get dark => 'Темна';

  @override
  String get dashboard_proxy_settings => 'Налаштування вебпанелі та проксі';

  @override
  String get dashboard_password_optional => 'Пароль вебпанелі (необов’язково)';

  @override
  String get dashboard_port => 'Порт вебпанелі';

  @override
  String get dashboard_username_optional =>
      'Ім’я користувача вебпанелі (необов’язково)';

  @override
  String get dashboard_behind_proxy => 'Вебпанель за проксі';

  @override
  String get dashboard_path_prefix => 'Префікс шляху вебпанелі';

  @override
  String delegated_task(Object goal) {
    return 'Делеговане завдання: $goal';
  }

  @override
  String get delete => 'Видалити';

  @override
  String delete_2(Object name) {
    return 'Видалити «$name»?';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return 'Видалити «$title» з історії на сервері Hermes? Цю дію неможливо скасувати.';
  }

  @override
  String get delete_cron_job => 'Видалити завдання за розкладом';

  @override
  String get delete_connections_that_are_not_in_the_backup =>
      'Видалити підключення, яких немає в резервній копії.';

  @override
  String delete_failed(Object error) {
    return 'Не вдалося видалити: $error';
  }

  @override
  String get delete_project => 'Видалити проєкт';

  @override
  String get delete_session => 'Видалити сесію?';

  @override
  String delete_3(Object projectName) {
    return 'Видалити $projectName?';
  }

  @override
  String deleted(Object name) {
    return '«$name» видалено';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      'Доставка не підтверджена; відновлення без повторного надсилання…';

  @override
  String get desktop_gateway_url_optional =>
      'Адреса серверного Desktop Gateway (необов’язково)';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      'Для цього підключення серверний Desktop Gateway не налаштовано.';

  @override
  String get desktop_app => 'Десктопний застосунок';

  @override
  String get developer_tool_calls => 'Виклики інструментів розробника';

  @override
  String get discord_chats => 'Чати Discord';

  @override
  String get dismiss => 'Приховати';

  @override
  String get do_not_run_this_command => 'Не виконувати цю команду.';

  @override
  String get documents_archives_audio_video_or_data =>
      'Документи, архіви, аудіо, відео або дані';

  @override
  String get download => 'Завантажити';

  @override
  String download_failed(Object error) {
    return 'Не вдалося завантажити: $error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you =>
      'Відомості про вас, які Hermes зберігає надовго';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      'Тривала робота в одному з ваших проєктів, спільна з Desktop.';

  @override
  String get edit => 'Редагувати';

  @override
  String get edit_connection => 'Редагувати підключення';

  @override
  String get edit_cron_job => 'Редагувати завдання за розкладом';

  @override
  String get edit_gateway_connection => 'Редагувати підключення до шлюзу';

  @override
  String get edit_and_resend => 'Редагувати й надіслати знову';

  @override
  String get enable_notifications => 'Увімкнути сповіщення';

  @override
  String get enable_notifications_description =>
      'Вимкнення заблокує всі наведені нижче сповіщення.';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      'Дозволяє додавати файли через серверний Desktop Gateway.';

  @override
  String get enter_a_name => 'Введіть назву';

  @override
  String get enter_a_passphrase => 'Введіть парольну фразу.';

  @override
  String get enter_the_passphrase_for_this_backup =>
      'Введіть парольну фразу цієї резервної копії.';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      'Усі розмови вже належать до проєктів.';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      'Функції без вбудованого екрана доступні у вебпанелі після входу';

  @override
  String get explain_the_attached_content_clearly =>
      'Зрозуміло поясни вміст вкладення.';

  @override
  String explain_this_content_clearly(Object text) {
    return 'Зрозуміло поясни цей вміст:\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      'Явний вибір змінює масштаб доступності тексту Android; варіант «Системний» залишає його без змін.';

  @override
  String get export_label => 'Експорт';

  @override
  String get export_share => 'Експортувати / поділитися';

  @override
  String get external_api_clients => 'Зовнішні клієнти API';

  @override
  String get extra_high => 'Дуже високий';

  @override
  String get extract_tasks => 'Виділити завдання';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      'Виділи рішення, строки, відповідальних і конкретні дії зі вмісту вкладення.';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return 'Виділи рішення, строки, відповідальних і конкретні дії з цього вмісту:\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return 'Не вдалося додати завдання: $error';
  }

  @override
  String get failed_to_load_cron_jobs =>
      'Не вдалося завантажити завдання за розкладом';

  @override
  String get failed_to_load_memory => 'Не вдалося завантажити пам’ять';

  @override
  String get failed_to_load_messages => 'Не вдалося завантажити повідомлення';

  @override
  String get failed_to_load_settings => 'Не вдалося завантажити налаштування';

  @override
  String get failed_to_load_skills => 'Не вдалося завантажити навички';

  @override
  String failed_to_update_job(Object error) {
    return 'Не вдалося оновити завдання: $error';
  }

  @override
  String failed(Object error) {
    return 'Помилка: $error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      'Файл додано; реєстрація в каталозі документів очікується.';

  @override
  String get file_reference_added_to_chat => 'Посилання на файл додано до чату';

  @override
  String get files => 'Файли';

  @override
  String get fill_from_document => 'Заповнити з документа';

  @override
  String get folder_is_empty => 'Папка порожня';

  @override
  String get folders => 'Папки';

  @override
  String get full_text => 'Повнотекстовий';

  @override
  String get gateway_api_access => 'Доступ до API шлюзу';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      'Шлюз підключено, але вебпанель недоступна або вхід не виконано. Перевірте її параметри або очистьте їх, щоб пропустити.';

  @override
  String get gateway_path_prefix => 'Префікс шляху шлюзу';

  @override
  String get go_to_end => 'До останнього повідомлення';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Hermes Agent для Android';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'Hermes не зміг прийняти відповідь. Спробуйте ще раз.';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      'Hermes не зміг завантажити збережені підключення';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'Hermes не прийняв відповідь. Спробуйте ще раз.';

  @override
  String get hermes_is_responding => 'Hermes відповідає…';

  @override
  String get hermes_is_waiting_for_input => 'Hermes очікує введення…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'Hermes зберігає системне масштабування тексту Android.';

  @override
  String get hermes_needs_your_input => 'Hermes потребує вашої відповіді';

  @override
  String get hermes_profile_optional => 'Профіль Hermes (необов’язково)';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'Профіль Hermes має бути простою назвою, наприклад «sol», а не шляхом.';

  @override
  String get hermes_reasoning_details => 'Подробиці міркувань Hermes';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'Відновлення Hermes недоступне: $error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'Hermes безпечно зупинив відновлення. Повторного надсилання запиту не було.';

  @override
  String get hide_passphrase => 'Приховати парольну фразу';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      'Для визначення важливих подій головному екрану потрібні ваші останні чати. Перевірте доступність шлюзу й повторіть спробу.';

  @override
  String get host => 'Адреса сервера';

  @override
  String get image_selection_was_interrupted_try_again =>
      'Вибір зображення перервано. Спробуйте ще раз.';

  @override
  String get import_label => 'Імпорт';

  @override
  String get inbox => 'Вхідні';

  @override
  String get inbox_is_clear => 'Вхідних дій немає';

  @override
  String get input_needed => 'Потрібна відповідь';

  @override
  String get input_needed_description =>
      'Hermes поставив запитання або запитує пароль чи секрет.';

  @override
  String get insert_a_remote_file_reference =>
      'Вставити посилання @file на серверний файл';

  @override
  String get invalid_port_number => 'Некоректний номер порту.';

  @override
  String get job_paused => 'Завдання призупинено';

  @override
  String get job_resumed => 'Завдання відновлено';

  @override
  String get job_triggered => 'Завдання запущено';

  @override
  String get label => 'Назва';

  @override
  String last_activity(Object day, Object month, Object year) {
    return 'Остання активність $day/$month/$year';
  }

  @override
  String last(Object lastRun) {
    return 'Востаннє: $lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      'Залиште порожнім для типового порту (8642; для HTTPS — 443)';

  @override
  String get leave_blank_for_default_9119 =>
      'Залиште порожнім для типового порту (9119)';

  @override
  String get light => 'Світла';

  @override
  String listening(Object elapsed) {
    return 'Слухаю • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return 'Слухаю, минуло $elapsed';
  }

  @override
  String get load_more => 'Завантажити ще…';

  @override
  String get loading => 'Завантаження';

  @override
  String get location => 'Розташування';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      'Переконайтеся, що API-сервер шлюзу працює\n(hermes gateway status)';

  @override
  String matches(Object assigned, Object name) {
    return 'Збіг: $name · $assigned';
  }

  @override
  String get memory => 'Пам’ять';

  @override
  String get memory_about_you => 'Про вас';

  @override
  String get memory_agent_notes => 'Нотатки агента';

  @override
  String get memory_builtin_scope =>
      'Збережені відомості з USER.md і MEMORY.md цього профілю. Дані зовнішніх сховищ пам’яті, зокрема MemPalace, тут не показуються.';

  @override
  String get memory_read_only =>
      'Лише для читання. Попросіть Hermes у чаті виправити або забути відомості.';

  @override
  String get memory_unavailable =>
      'Цей шлюз або профіль не надає збережених відомостей пам’яті. Перевірте вибраний профіль і за потреби оновіть Hermes.';

  @override
  String get memory_load_error =>
      'Перевірте підключення та вхід до вебпанелі й повторіть спробу.';

  @override
  String get memory_read_full_fact => 'Прочитати повністю';

  @override
  String get memory_full_fact_requires_update =>
      'Для повних записів потрібна новіша версія шлюзу Hermes. Оновіть Hermes і цей список.';

  @override
  String get memory_fact_detail_error =>
      'Не вдалося завантажити повний запис. Можливо, він змінився; оновіть список і повторіть спробу.';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'Збережені відомості з’являться тут, коли Hermes їх запам’ятає.';

  @override
  String get merge => 'Об’єднати';

  @override
  String get message => 'Повідомлення';

  @override
  String get message_hermes => 'Повідомлення Hermes…';

  @override
  String get message_actions => 'Дії повідомлення';

  @override
  String get message_copied => 'Повідомлення скопійовано';

  @override
  String get migrating => 'Перенесення…';

  @override
  String get migration_complete => 'Перенесення завершено';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      'Перенесення не вдалося. Локальні розділи залишено без змін.';

  @override
  String get migration_incomplete => 'Перенесення не завершено';

  @override
  String get migration_preview => 'Попередній перегляд перенесення';

  @override
  String get model => 'Модель';

  @override
  String get model_and_thinking_for_this_chat =>
      'Модель і міркування для цього чату';

  @override
  String model_was_not_changed(Object error) {
    return 'Модель не змінено: $error';
  }

  @override
  String get move_attachment_next => 'Перемістити вкладення далі';

  @override
  String get move_attachment_previous => 'Перемістити вкладення раніше';

  @override
  String get move_chat => 'Перемістити чат';

  @override
  String get move_conversation => 'Перемістити розмову';

  @override
  String get move_to_project => 'Перемістити до проєкту';

  @override
  String get move_to_space => 'Перемістити до розділу';

  @override
  String get moved_to_a_project => 'Переміщено до проєкту';

  @override
  String moved_to(Object label) {
    return 'Переміщено до $label';
  }

  @override
  String get name => 'Назва';

  @override
  String get name_prompt_and_schedule_are_required =>
      'Назва, запит і розклад обов’язкові';

  @override
  String get nav_activity => 'Активність';

  @override
  String get nav_projects => 'Проєкти';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Потрібна підтримка впорядкування з виправленнями у шлюзі Hermes.';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      'Потрібна доступна вебпанель Hermes. Перевірте адресу, порт і облікові дані підключення.';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Потрібен серверний індекс файлів у шлюзі Hermes.';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Потрібна підтримка збереження порядку закріплень, масових змін і скасування у шлюзі Hermes.';

  @override
  String get needs_you => 'Потрібна ваша дія';

  @override
  String get new_label => 'Нове';

  @override
  String get new_chat => 'Новий чат';

  @override
  String get new_chat_2 => 'Новий чат';

  @override
  String new_chat_3(Object projectName) {
    return 'Новий чат · $projectName';
  }

  @override
  String get new_project => 'Новий проєкт';

  @override
  String get new_space => 'Новий розділ';

  @override
  String next(Object nextRun) {
    return 'Далі: $nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'Nginx додає авторизацію — застосунок надсилає запити без неї';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      'Голоси озвучення не знайдено.\nУстановіть Google Text-to-Speech і завантажте голосові дані.';

  @override
  String get no_active_projects_on_this_gateway =>
      'На цьому шлюзі немає активних проєктів';

  @override
  String get no_activity_yet => 'Активності ще немає';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      'Немає чатів, що заблоковані, виконуються або очікують відновлення. Почніть новий, коли будете готові.';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return 'У цьому проєкті немає чатів за запитом «$searchQuery».';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      'У цьому розділі ще немає чатів. Натисніть +, щоб почати.';

  @override
  String get no_chats_yet => 'Чатів ще немає';

  @override
  String get no_connections => 'Підключень немає';

  @override
  String get no_conversation_matches_this_view =>
      'Цьому перегляду не відповідає жодна розмова.';

  @override
  String get no_cron_jobs => 'Завдань за розкладом немає';

  @override
  String get no_folders_yet => 'Папок ще немає';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      'Для цього підключення немає локальних розділів; тут уже використовуються лише проєкти.';

  @override
  String get no_matches => 'Збігів немає';

  @override
  String get no_memory_entries => 'Записів пам’яті немає';

  @override
  String get no_message_content_matches => 'Збігів у вмісті повідомлень немає';

  @override
  String get no_new_messages => 'Нових повідомлень немає';

  @override
  String get no_projects_yet => 'Проєктів ще немає';

  @override
  String get no_runs_yet => 'Запусків ще немає.';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return 'Немає серверного проєкту з такою назвою · $assigned';
  }

  @override
  String get no_sessions_yet => 'Сесій ще немає';

  @override
  String get no_skills_found => 'Навичок не знайдено';

  @override
  String get no_spaces_on_this_device => 'На цьому пристрої немає розділів';

  @override
  String get no_text_shared => 'Текст не передано';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      'Немає заблокованих, поточних або нещодавно завершених ходів. Розпочата робота з’явиться тут.';

  @override
  String get no_turn_needs_your_input_or_has_failed =>
      'Немає ходів, які потребують відповіді або завершилися помилкою.';

  @override
  String get no_unassigned_chats => 'Чатів без проєкту немає.';

  @override
  String get nothing_changed_in_the_last_seven_days =>
      'За останні сім днів змін не було.';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      'Ще нічого не переміщено — це лише попередній перегляд майбутнього перенесення.';

  @override
  String get nothing_here => 'Тут порожньо';

  @override
  String get nothing_is_running => 'Зараз нічого не виконується';

  @override
  String get nothing_needs_you => 'Немає дій, що потребують вашої уваги';

  @override
  String get nothing_to_migrate => 'Немає даних для перенесення';

  @override
  String get notifications => 'Сповіщення';

  @override
  String get notifications_permission_denied =>
      'Сповіщення заблоковані системою. Увімкніть їх для цього застосунку в налаштуваннях Android.';

  @override
  String get off_no_thinking => 'Вимкнено (без міркувань)';

  @override
  String get offline_showing_the_last_known_activity =>
      'Немає зв’язку — показано останній відомий стан активності.';

  @override
  String get offline_showing_the_last_known_chats =>
      'Немає зв’язку — показано останні відомі чати';

  @override
  String get offline_showing_the_last_known_projects =>
      'Немає зв’язку — показано останні відомі проєкти.';

  @override
  String get on_this_device => 'На цьому пристрої';

  @override
  String get on_device => 'На пристрої';

  @override
  String get open_inbox => 'Відкрити вхідні';

  @override
  String open_inbox_2(Object count) {
    return 'Відкрити вхідні ($count)';
  }

  @override
  String get open_the_hermes_dashboard => 'Відкрити вебпанель Hermes';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      'Необов’язково. Для вкладок пам’яті, розкладу, навичок і налаштувань. Порожнє значення використовує типовий порт вебпанелі (9119) без входу.';

  @override
  String get organization => 'Упорядкування';

  @override
  String get other_answer => 'Інша відповідь';

  @override
  String get overview => 'Огляд';

  @override
  String get passphrase => 'Парольна фраза';

  @override
  String get password_optional => 'Пароль (необов’язково)';

  @override
  String get phone_or_tablet => 'Телефон або планшет';

  @override
  String get pin_batch_and_undo => 'Закріплення, масові дії та скасування';

  @override
  String get plugin_notifications => 'Сповіщення плагінів';

  @override
  String get plugin_notifications_description =>
      'Шлюз надіслав сповіщення, поки застосунок був у фоні.';

  @override
  String get port => 'Порт';

  @override
  String get preparing_attachments => 'Підготовка вкладень…';

  @override
  String get preview_truncated => 'Перегляд скорочено';

  @override
  String get preview_unavailable => 'Перегляд недоступний';

  @override
  String get profile => 'Профіль';

  @override
  String get profile_default_model => 'Типова модель профілю';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return 'Типову модель профілю змінено на $selectedModel. Чати з власною моделлю зберігають свій вибір.';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      'Профіль для чатів цього підключення, якщо вебпанель обслуговує кілька профілів. Для окремої вебпанелі одного профілю залиште порожнім.';

  @override
  String get project => 'Проєкт';

  @override
  String get project_actions => 'Дії проєкту';

  @override
  String get project_chat => 'Чат проєкту';

  @override
  String get project_chats_unavailable => 'Чати проєкту недоступні';

  @override
  String get projects => 'Проєкти';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      'Проєкти об’єднують пов’язані чати, файли й активність та синхронізуються з Hermes на комп’ютері.';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      'Потрібна підтримка проєктів у серверному підключенні. Перевірте доступність сервера та підтримку API проєктів.';

  @override
  String get projects_unavailable => 'Проєкти недоступні';

  @override
  String get projects_activity_new_navigation =>
      'Проєкти й активність — нова навігація';

  @override
  String get promote_to_project => 'Перенести до проєкту';

  @override
  String get prompt => 'Запит';

  @override
  String get protect_this_backup => 'Захистити резервну копію';

  @override
  String get provider => 'Провайдер';

  @override
  String get proxy_injects_auth_app_sends_clean_requests =>
      'Проксі додає авторизацію; застосунок надсилає запити без неї';

  @override
  String get quick_chat => 'Швидкий чат';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      'Швидкі чати з’являються тут після завершення строку зберігання.';

  @override
  String get read_aloud => 'Прочитати вголос';

  @override
  String get read_aloud_is_unavailable_on_this_device =>
      'Озвучення недоступне на цьому пристрої';

  @override
  String get reading_response_aloud => 'Озвучення відповіді';

  @override
  String get ready_to_upload => 'Готово до надсилання';

  @override
  String get reasoning => 'Міркування';

  @override
  String get recently_completed => 'Нещодавно завершено';

  @override
  String get recently_active => 'Нещодавня активність';

  @override
  String get recovering_hermes => 'Відновлення Hermes…';

  @override
  String get refresh => 'Оновити';

  @override
  String get regenerate_response => 'Згенерувати відповідь знову';

  @override
  String get remove_attachment => 'Прибрати вкладення';

  @override
  String get rename => 'Перейменувати';

  @override
  String get rename_chat => 'Перейменувати чат';

  @override
  String get rename_project => 'Перейменувати проєкт';

  @override
  String get rename_space => 'Перейменувати розділ';

  @override
  String rename_2(Object projectName) {
    return 'Перейменувати $projectName';
  }

  @override
  String rename_3(Object name) {
    return 'Перейменувати $name';
  }

  @override
  String get replace => 'Замінити';

  @override
  String get repositories => 'Репозиторії';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      'Досліди вміст вкладення, перевір важливі твердження й наведи джерела.';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return 'Досліди цей вміст, перевір важливі твердження й наведи джерела:\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return 'Скидання не вдалося: $retryError. Можливо, потрібно перевстановити захищене сховище.';
  }

  @override
  String get reset_saved_connections => 'Скинути збережені підключення';

  @override
  String get responding => 'Відповідає…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return 'Відповідь закрито локально; зупинка на шлюзі не вдалася: $error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      'Відповідь закрито локально; активного ходу на шлюзі не знайдено.';

  @override
  String get response_complete => 'Відповідь завершено';

  @override
  String get response_complete_description =>
      'Хід завершився, поки застосунок був у фоні.';

  @override
  String get response_ready => 'Відповідь готова';

  @override
  String get response_stopped => 'Відповідь зупинено.';

  @override
  String get restore => 'Відновити';

  @override
  String get restore_configuration => 'Відновити конфігурацію';

  @override
  String get restore_project => 'Відновити проєкт';

  @override
  String get retry => 'Повторити';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return 'Повторна спроба для $name не вдалася. Чернетку й запит збережено.';
  }

  @override
  String get retry_upload => 'Повторити надсилання';

  @override
  String retrying(Object name) {
    return 'Повторне надсилання $name…';
  }

  @override
  String get review_local_spaces => 'Переглянути локальні розділи';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      'Перегляньте швидкі чати після завершення строку зберігання або перенесіть їх до проєкту';

  @override
  String get review_the_attached_content => 'Переглянь вміст вкладення.';

  @override
  String get run_only_this_command => 'Виконати лише цю команду.';

  @override
  String get running_now => 'Зараз виконується';

  @override
  String get save => 'Зберегти';

  @override
  String get save_changes => 'Зберегти зміни';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      'Зберегти постійне правило в конфігурації Hermes.';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      'Збережи важливі довготривалі відомості зі вкладення в пам’яті й підтвердь, що саме збережено.';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return 'Збережи важливі довготривалі відомості з цього вмісту в пам’яті й підтвердь, що саме збережено:\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      'Збережіть підключення й налаштування в зашифрованому файлі, щоб відновити їх після перевстановлення або на іншому пристрої.';

  @override
  String save_2(Object filename) {
    return 'Зберегти $filename';
  }

  @override
  String get schedule => 'Розклад';

  @override
  String get scheduled_jobs_and_their_last_runs =>
      'Завдання за розкладом та останні запуски';

  @override
  String get scheduled_tasks => 'Заплановані завдання';

  @override
  String get script_only_no_agent => 'Лише скрипт (без агента)';

  @override
  String get scroll_horizontally => 'Прокручувати горизонтально';

  @override
  String get search_all_chats => 'Пошук усіх чатів';

  @override
  String get search_all_message_content => 'Пошук у всьому вмісті повідомлень';

  @override
  String get search_chats => 'Пошук чатів';

  @override
  String get search_conversations => 'Пошук розмов';

  @override
  String get search_loaded_chats => 'Пошук завантажених чатів';

  @override
  String get search_mode => 'Режим пошуку';

  @override
  String get select_one_option_or_enter_another_answer =>
      'Виберіть один варіант або введіть іншу відповідь.';

  @override
  String get select_one_or_more_options_then_continue =>
      'Виберіть один чи кілька варіантів і продовжуйте.';

  @override
  String get select_text => 'Виділити текст';

  @override
  String get send => 'Надіслати';

  @override
  String send_failed(Object error) {
    return 'Не вдалося надіслати: $error';
  }

  @override
  String send_failed_api_only_permission_denied(Object error) {
    return 'Не вдалося надіслати: $error. Сервер відхилив цей запис для ключа API. Якщо цей чат належить Dashboard, додавання імені користувача та пароля Dashboard для цього підключення може дозволити надсилання; сервер також може відхиляти його навмисно.';
  }

  @override
  String get send_message => 'Надіслати повідомлення';

  @override
  String get send_test_notification => 'Надіслати тестове сповіщення';

  @override
  String get session_sources => 'Джерела сесій';

  @override
  String get session_deleted_from_remote_hermes =>
      'Сесію видалено з історії на сервері Hermes.';

  @override
  String session_search_failed(Object error) {
    return 'Помилка пошуку сесій: $error';
  }

  @override
  String get set_profile_default => 'Зробити типовою для профілю';

  @override
  String get settings => 'Налаштування';

  @override
  String get share_to_hermes => 'Поділитися з Hermes';

  @override
  String get show_passphrase => 'Показати парольну фразу';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      'Показувати інструменти, міркування, завдання та подробиці повідомлень у згорнутих блоках. Якщо вимкнено, видно лише розмову.';

  @override
  String get signal_messages => 'Повідомлення Signal';

  @override
  String get skills => 'Навички';

  @override
  String skills_2(Object count) {
    return 'Навички ($count)';
  }

  @override
  String get skills_and_tools => 'Навички й інструменти';

  @override
  String get skip => 'Пропустити';

  @override
  String get slack_chats => 'Чати Slack';

  @override
  String source(Object source) {
    return 'Джерело: $source';
  }

  @override
  String get space_actions => 'Дії розділу';

  @override
  String get spaces => 'Розділи';

  @override
  String get speak_to_hermes => 'Говорити до Hermes';

  @override
  String get speech_recognition_is_unavailable =>
      'Розпізнавання мовлення недоступне';

  @override
  String get spoken_replies => 'Голосові відповіді';

  @override
  String get spoken_replies_off => 'Голосові відповіді вимкнено';

  @override
  String get spoken_replies_on => 'Голосові відповіді ввімкнено';

  @override
  String get stalled_no_update_from_hermes =>
      'Очікування затягнулося — немає оновлень від Hermes';

  @override
  String get start_something_new => 'Почати щось нове';

  @override
  String get start_voice_input => 'Почати голосовий ввід';

  @override
  String get starting_hermes => 'Hermes починає відповідь…';

  @override
  String get media_card_download => 'Завантажити файл';

  @override
  String get media_card_tap_to_download => 'Торкніться, щоб завантажити';

  @override
  String get still_loading_your_projects => 'Проєкти ще завантажуються.';

  @override
  String get stop => 'Зупинити';

  @override
  String get stop_response => 'Зупинити відповідь';

  @override
  String get stop_voice_input => 'Зупинити голосовий ввід';

  @override
  String get submitted_waiting_for_hermes => 'Надіслано, очікування Hermes';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      'Пропонувати проєкти й навчатися на ваших виправленнях';

  @override
  String get summarize_the_attached_content => 'Підсумуй вміст вкладення.';

  @override
  String summarize_this_content(Object text) {
    return 'Підсумуй цей вміст:\n\n$text';
  }

  @override
  String get switch_profile => 'Змінити профіль';

  @override
  String get system => 'Системний';

  @override
  String get take_photo => 'Зробити фото';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      'Натисніть +, щоб додати віддалений шлюз Hermes\n(API-сервер, порт 8642)';

  @override
  String get tap_the_button_to_start_a_new_chat =>
      'Натисніть +, щоб почати новий чат';

  @override
  String get telegram_messages => 'Повідомлення Telegram';

  @override
  String get terminal_sessions => 'Сесії термінала';

  @override
  String get test_notification_body =>
      'Якщо ви це бачите, системні сповіщення працюють.';

  @override
  String get test_notification_sent => 'Тестове сповіщення надіслано.';

  @override
  String get test_notification_title => 'Перевірка сповіщень Hermes';

  @override
  String get test_notification_unsupported =>
      'Не вдалося надіслати сповіщення — перевірте системний дозвіл сповіщень.';

  @override
  String get text_size => 'Розмір тексту';

  @override
  String get text_size_preview => 'Попередній перегляд розміру тексту';

  @override
  String text_size_2(Object label) {
    return 'Розмір тексту: $label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely =>
      'Не вдалося безпечно зберегти ключ API.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      'Проєкт переміститься до архіву. Чати й файли збережуться; відновити проєкт можна будь-коли.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      'Проєкт переміститься до архіву. Чати й файли збережуться; відновити проєкт можна пізніше.';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      'Активний профіль не повернув моделей для вибору.';

  @override
  String get the_backup_could_not_be_exported =>
      'Не вдалося експортувати резервну копію.';

  @override
  String get the_backup_could_not_be_restored =>
      'Не вдалося відновити резервну копію.';

  @override
  String get the_connection_could_not_be_deleted_safely =>
      'Не вдалося безпечно видалити підключення.';

  @override
  String get the_connection_could_not_be_stored_securely =>
      'Не вдалося безпечно зберегти підключення.';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      'Не вдалося безпечно зберегти облікові дані вебпанелі.';

  @override
  String get the_detached_reply_failed =>
      'Фонова відповідь завершилася помилкою.';

  @override
  String the_detached_reply_failed_2(Object error) {
    return 'Фонова відповідь завершилася помилкою: $error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      'Файл містить ключі API та пароль вебпанелі, тому його зашифровано. Без цієї парольної фрази відновлення неможливе.';

  @override
  String get the_last_turn_failed => 'Останній хід завершився помилкою';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return 'Локальне сховище підключень виглядає пошкодженим ($errorType). Можна скинути збережені підключення й налаштувати їх заново. Чати на шлюзі не постраждають.';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      'Модель лише переформульовує ваше запитання в короткий повнотекстовий запит. Hermes використовує облікові дані провайдера, уже налаштовані на сервері.';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      'Сервер ще не надав папок цього проєкту. Загальний перегляд файлів доступний у розділі «Ще».';

  @override
  String get the_turn_failed => 'Хід завершився помилкою';

  @override
  String get the_two_passphrases_do_not_match =>
      'Парольні фрази не збігаються.';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      'Значення надсилається безпосередньо до активного шлюзу Hermes і не зберігається цим Android-застосунком.';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      'У цій папці сервера немає видимих файлів.';

  @override
  String get thinking_effort => 'Рівень міркувань';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      'Цей шлюз Hermes ще не підтримує відкриття проєктів. Оновіть Hermes на сервері для перегляду проєктів із телефона.';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      'Цей шлюз Hermes не підтримує серверні проєкти, тому групування чатів зберігається лише на цьому пристрої. Оновіть Hermes для спільних проєктів на всіх пристроях.';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      'Для створення чату в цьому проєкті потрібна папка. Додайте її та повторіть спробу.';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      'У цій серверній сесії ще немає доступних повідомлень.';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      'Ця дія створює постійне правило Hermes. Перед підтвердженням перегляньте повну команду.';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      'Цей шлюз ще не підтримує проєкти. Оновіть його для впорядкування чатів на всіх пристроях.';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      'Проєкт буде видалено назавжди. Чати залишаться та повернуться до розділу «Без проєкту».';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      'Цей сервер не підтримує фонове відновлення — чати працюють у живому режимі';

  @override
  String get this_week => 'Цього тижня';

  @override
  String get titles_previews_and_models => 'Назви, прев’ю й моделі';

  @override
  String get tool_activity => 'Інструменти';

  @override
  String get trigger_now => 'Запустити зараз';

  @override
  String get received_outcome_unknown =>
      'Хід завершено — результат не підтверджено';

  @override
  String get turn_completed => 'Хід завершено';

  @override
  String get turn_failed => 'Хід завершився помилкою';

  @override
  String get turn_failed_description => 'Фоновий хід завершився помилкою.';

  @override
  String get turn_recovery_failed => 'Не вдалося відновити хід';

  @override
  String get unable_to_prepare_this_file_try_another_one =>
      'Не вдалося підготувати файл. Спробуйте інший.';

  @override
  String get unable_to_prepare_this_image_try_another_one =>
      'Не вдалося підготувати зображення. Спробуйте інше.';

  @override
  String unable_to_prepare(Object name) {
    return 'Не вдалося підготувати $name.';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      'Не вдалося прочитати вибране зображення. Вибір збережено.';

  @override
  String get unassigned => 'Без проєкту';

  @override
  String get unassigned_chats => 'Чати без проєкту';

  @override
  String get untitled_chat => 'Чат без назви';

  @override
  String get untitled_session => 'Сесія без назви';

  @override
  String get update_api_key => 'Оновити ключ API';

  @override
  String get upload_failed => 'Надсилання не вдалося';

  @override
  String get upload_failed_tap_retry =>
      'Надсилання не вдалося • торкніться для повтору';

  @override
  String uploading(Object index, Object name, Object total) {
    return 'Надсилання $index/$total: $name';
  }

  @override
  String get use_as_is => 'Використати як є';

  @override
  String get use_at_least_8_characters => 'Використайте щонайменше 8 символів.';

  @override
  String get use_for_cron_jobs_backed_by_scripts =>
      'Для завдань за розкладом на основі скриптів.';

  @override
  String get use_on_device => 'Використати локально';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      'Використай вкладення, щоб визначити та заповнити відповідні поля документа чи форми. Перед будь-яким надсиланням запитай.';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return 'Використай цей вміст, щоб визначити та заповнити відповідні поля документа чи форми. Перед будь-яким надсиланням запитай:\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      'Для префіксів шляхів і вкладок налаштувань, пам’яті, навичок та розкладу. Для відкритої вебпанелі залиште ім’я й пароль порожніми; якщо авторизацію додає проксі, увімкніть відповідний режим.';

  @override
  String get username_optional => 'Ім’я користувача (необов’язково)';

  @override
  String using(Object displayName) {
    return 'Використовується $displayName…';
  }

  @override
  String get verbose_mode => 'Розширений режим';

  @override
  String get message_metadata => 'Подробиці повідомлення';

  @override
  String get voice => 'Голос';

  @override
  String voice_setup_failed(Object error) {
    return 'Не вдалося налаштувати голос: $error';
  }

  @override
  String get waiting_for_your_input => 'Очікує вашої відповіді';

  @override
  String get what_hermes_knows_how_to_do => 'Що вміє Hermes';

  @override
  String get what_should_the_agent_do => 'Що має зробити агент?';

  @override
  String get whatsapp_messages => 'Повідомлення WhatsApp';

  @override
  String get which_project => 'Який проєкт?';

  @override
  String get workspace => 'Робочий простір';

  @override
  String get wrap_lines => 'Переносити рядки';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return 'Можна додати до $maxRemoteAttachmentDrafts вкладень.';
  }

  @override
  String get your_answer => 'Ваша відповідь';

  @override
  String get e_g_dashboard => 'наприклад, /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      'наприклад, /dashboard (шлях проксі перед /api/)';

  @override
  String get e_g_profile_peter => 'наприклад, /profile/peter';

  @override
  String get e_g_sol => 'наприклад, sol';

  @override
  String get e_g_0_9_or_every_2h => 'наприклад, 0 9 * * * або every 2h';

  @override
  String get e_g_daily_backup => 'наприклад, Щоденна резервна копія';

  @override
  String downloaded(Object filename) {
    return '$filename завантажено';
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
      '192.168.1.50, 100.x.y.z або hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      'наприклад, /profile/peter (шлях проксі перед /api/ та /v1/)';

  @override
  String and_more(Object count) {
    return 'та ще $count';
  }

  @override
  String chats_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count чату',
      many: '$count чатів',
      few: '$count чати',
      one: '$count чат',
    );
    return '$_temp0';
  }

  @override
  String on_this_device_only(Object chats) {
    return '$chats · лише на цьому пристрої';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count розділу',
      many: '$count розділів',
      few: '$count розділи',
      one: '$count розділ',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => 'нові проєкти не потрібні';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count проєкту для створення',
      many: '$count проєктів для створення',
      few: '$count проєкти для створення',
      one: '$count проєкт для створення',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return 'Перенесено чатів: $linkedSessions · створено проєктів: $createdProjects';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '$unlinkedSessions чатів залишилися в локальних розділах; повторна спроба безпечна.';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • Рекомендовано: невелика й недорога';
  }

  @override
  String session_meta(Object count, Object model, Object time) {
    return '$count повід. • $model • $time';
  }

  @override
  String model_scope_label(Object model, Object scope) {
    return '$model • $scope';
  }

  @override
  String get this_chat => 'цей чат';

  @override
  String get profile_default => 'типова для профілю';

  @override
  String minutes_ago(Object count) {
    return '$count хв тому';
  }

  @override
  String hours_ago(Object count) {
    return '$count год тому';
  }

  @override
  String days_ago(Object count) {
    return '$count дн тому';
  }

  @override
  String get now_label => 'зараз';

  @override
  String get latest_label => 'Останнє';

  @override
  String new_count_indicator(Object count) {
    return '$count нових';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count нового повідомлення',
      many: '$count нових повідомлень',
      few: '$count нові повідомлення',
      one: '$count нове повідомлення',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return 'Помилок: $failures • усього: $total';
  }

  @override
  String activity_completed_summary(Object count) {
    return 'Завершено: $count';
  }

  @override
  String tool_start_observed(Object time) {
    return 'Початок зафіксовано о $time (місцевий час)';
  }

  @override
  String tool_last_observed(Object time) {
    return 'Востаннє зафіксовано о $time (місцевий час)';
  }

  @override
  String tool_result_recorded(Object time) {
    return 'Результат записано о $time (місцевий час)';
  }

  @override
  String get tool_time_unavailable => 'Час недоступний';

  @override
  String get hermes_is_using_a_tool => 'Hermes використовує інструмент';

  @override
  String hermes_is_using_tools(Object count) {
    return 'Hermes використовує інструменти: $count';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return 'Завершено делегованих завдань: $count';
  }

  @override
  String delegated_tasks_active(Object count) {
    return 'Активних делегованих завдань: $count';
  }

  @override
  String branch_main(Object label) {
    return '$label · основна';
  }

  @override
  String get you_heading => '## Ви';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => 'Дія';

  @override
  String get destination_label => 'Призначення';

  @override
  String get preview_label => 'Перегляд';

  @override
  String get share_action_summarize => 'Підсумувати';

  @override
  String get share_action_explain => 'Пояснити';

  @override
  String get share_action_research => 'Дослідити';

  @override
  String get share_action_remember => 'Запам’ятати';

  @override
  String get text_size_small => 'Малий';

  @override
  String get text_size_default => 'Типовий';

  @override
  String get text_size_large => 'Великий';

  @override
  String get text_size_extra_large => 'Дуже великий';

  @override
  String get text_size_use_system_description =>
      'Використовувати системний розмір тексту Android без змін.';

  @override
  String text_size_percent_description(Object percent) {
    return '$percent% від системного розміру тексту Android.';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return 'Пропущено файлів: $count. Причина: кількість, розмір, неможливість читання або чутлива назва.';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort тепер діють лише для цього чату.';
  }

  @override
  String get reasoning_minimal => 'Мінімальний';

  @override
  String get reasoning_low => 'Низький';

  @override
  String get reasoning_medium => 'Середній';

  @override
  String get reasoning_high => 'Високий';

  @override
  String get reasoning_max => 'Максимальний';

  @override
  String get reasoning_ultra => 'Ультра';

  @override
  String get status_running => 'Виконується';

  @override
  String get status_failed => 'Помилка';

  @override
  String get status_done => 'Готово';

  @override
  String get status_idle => 'Очікує';

  @override
  String get upload_status_uploading => 'Надсилання';

  @override
  String get upload_status_uploaded => 'Надіслано';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count вкладення',
      many: '$count вкладень',
      few: '$count вкладення',
      one: '$count вкладення',
    );
    return '$_temp0';
  }

  @override
  String get action_create => 'створити';

  @override
  String get action_rename => 'перейменувати';

  @override
  String get action_archive => 'архівувати';

  @override
  String get action_restore => 'відновити';

  @override
  String get action_delete => 'видалити';

  @override
  String get migrate => 'Перенести';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count чату в проєкті',
      many: '$count чатів у проєкті',
      few: '$count чати в проєкті',
      one: '$count чат у проєкті',
    );
    return '$_temp0';
  }

  @override
  String get date_today => 'Сьогодні';

  @override
  String get date_yesterday => 'Учора';

  @override
  String get date_earlier => 'Раніше';

  @override
  String get nav_home => 'Головна';

  @override
  String get nav_more => 'Ще';

  @override
  String get status_completed => 'Завершено';

  @override
  String get filter_all => 'Усі';

  @override
  String get filter_recent => 'Нещодавні';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  Ключ: $status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model\nчерез `$provider`';
  }

  @override
  String get deny => 'Відхилити';

  @override
  String get connect => 'Підключити';

  @override
  String get appearance => 'Вигляд';

  @override
  String get connection_section => 'Підключення';

  @override
  String get about => 'Про застосунок';

  @override
  String version_label(Object version) {
    return 'Версія $version';
  }

  @override
  String get matched => 'Збігається';

  @override
  String get search => 'Пошук';

  @override
  String get on => 'Увімкнено';

  @override
  String get off => 'Вимкнено';

  @override
  String get reasoning_off => 'Вимкнено';

  @override
  String get hermes_response_ready => 'Відповідь Hermes готова';

  @override
  String get admin_password_needed => 'Потрібен пароль адміністратора';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      'Hermes потрібен пароль sudo для очікуваної команди термінала.';

  @override
  String get sudo_password => 'Пароль sudo';

  @override
  String get secret_needed => 'Потрібен секрет';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      'Hermes потрібен секрет для очікуваної навички.';

  @override
  String get secret_value => 'Значення секрету';

  @override
  String get attached_file => 'Прикріплений файл';

  @override
  String get pin_chat => 'Закріпити чат';

  @override
  String get unpin_chat => 'Відкріпити чат';

  @override
  String get pinned_chats => 'Закріплені';

  @override
  String could_not_update_chat_pin(Object error) {
    return 'Не вдалося змінити закріплення чату: $error';
  }

  @override
  String get could_not_save_chat_spaces =>
      'Не вдалося зберегти розділи чатів на цьому пристрої';

  @override
  String get update_available => 'Доступне оновлення';

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
      'На GitHub доступна новіша збірка Hermes Android.';

  @override
  String get release_notes => 'Примітки до випуску';

  @override
  String get view_release => 'Переглянути випуск';

  @override
  String get skip_this_version => 'Пропустити цю версію';

  @override
  String get later => 'Пізніше';

  @override
  String get check_for_updates => 'Перевірити оновлення';

  @override
  String get check_for_updates_on_launch =>
      'Перевіряти оновлення під час запуску';

  @override
  String get you_re_on_the_latest_version => 'У вас найновіша версія.';

  @override
  String get couldn_t_check_for_updates => 'Не вдалося перевірити оновлення.';

  @override
  String get chat_density => 'Щільність чату';

  @override
  String chat_density_2(Object label) {
    return 'Щільність чату: $label';
  }

  @override
  String get chat_density_comfortable => 'Зручна';

  @override
  String get chat_density_compact => 'Компактна';

  @override
  String get chat_density_comfortable_description =>
      'Просторіші повідомлення з підписом автора над кожним.';

  @override
  String get chat_density_compact_description =>
      'Щільніші повідомлення без підписів, щоб більше тексту вміщалося на екрані.';

  @override
  String chat_density_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String
  get compact_removes_the_you_and_hermes_labels_and_trims_bubble_padding_spacing_and_side_margins =>
      'Компактний режим прибирає підписи «Ви» й «Hermes» та зменшує внутрішні, міжрядкові й бічні відступи повідомлень.';

  @override
  String get client_certificate_mtls => 'Клієнтський сертифікат (mTLS)';

  @override
  String get client_certificate_mtls_description =>
      'Надавати сертифікат, коли HTTPS-проксі вимагає взаємного TLS.';

  @override
  String get client_certificate_https_only =>
      'Клієнтські сертифікати використовуються лише для HTTPS-підключень.';

  @override
  String get choose_certificate => 'Вибрати сертифікат';

  @override
  String get certificate_password => 'Пароль сертифіката';

  @override
  String get this_certificate_is_password_protected =>
      'Цей сертифікат захищений паролем. Він відкривається під час введення.';

  @override
  String get enter_the_certificate_password_to_finish_loading_it =>
      'Введіть пароль сертифіката, щоб завершити завантаження.';

  @override
  String get client_certificate_required =>
      'Завантажте клієнтський сертифікат або вимкніть його використання.';

  @override
  String client_certificate_loaded(String label) {
    return 'Завантажено: $label';
  }

  @override
  String get remove_certificate => 'Прибрати сертифікат';

  @override
  String get certificate_import_failed => 'Не вдалося завантажити сертифікат.';

  @override
  String get background_work => 'Фонова робота';

  @override
  String get keep_chats_active_in_background => 'Підтримувати чати у фоні';

  @override
  String get background_work_description =>
      'Зберігати підключення розпочатих вами чатів, поки застосунок у фоні. Неактивні підключення можуть закриватися. Витрачає більше заряду й трафіку. Вимкнення не зупиняє роботу сервера.';

  @override
  String get background_work_limits =>
      'Android може призупинити підключення в режимі Doze або завершити процес застосунку. Для сповіщень після завершення процесу потрібне окреме налаштування push. Примусова зупинка не підтримується.';

  @override
  String get background_work_disclosure =>
      'Поки захист фонової роботи активний, обов’язкове службове сповіщення залишається видимим, навіть якщо сповіщення чатів вимкнено.';

  @override
  String get battery_optimisation_settings => 'Налаштування економії заряду';

  @override
  String get battery_optimisation_description =>
      'Відкрити налаштування Android для перегляду обмежень батареї. Автоматичного запиту винятків немає; зміна налаштувань не гарантує доставку.';

  @override
  String get battery_settings_unavailable =>
      'Не вдалося відкрити налаштування батареї на цьому пристрої.';

  @override
  String get background_work_save_failed =>
      'Не вдалося зберегти налаштування фонової роботи.';

  @override
  String get ongoing_chat_channel_name => 'Активні чати';

  @override
  String get ongoing_chat_channel_description =>
      'Тихі оновлення стану незавершених чатів, розпочатих користувачем';

  @override
  String get task_timeline => 'Хронологія завдання';

  @override
  String get task_refresh_history => 'Оновити історію завдання';

  @override
  String get task_live_preview =>
      'Поточний перегляд із подій батьківського чату';

  @override
  String get task_preview_explanation =>
      'Лише останнє доступне прев’ю; це не збережений рядок історії.';

  @override
  String get task_preview => 'Перегляд';

  @override
  String get task_recorded_history => 'Збережена історія завдання';

  @override
  String get task_loading_history => 'Завантаження історії завдання…';

  @override
  String get task_empty_history =>
      'Збережених повідомлень ще немає. Завдання могло ще не записати історію; це не означає, що воно нічого не зробило.';

  @override
  String get task_load_older => 'Завантажити старіші';

  @override
  String get task_default_goal => 'Делеговане завдання';

  @override
  String task_status(Object status) {
    return 'Стан: $status';
  }

  @override
  String task_identity(Object id) {
    return 'Завдання: $id';
  }

  @override
  String task_stored_session(Object id) {
    return 'Збережена сесія: $id';
  }

  @override
  String task_delegation(Object id) {
    return 'Делегування: $id';
  }

  @override
  String get task_read_only_notice =>
      'Лише для читання · історія може з’явитися після запису завданням. Оновіть для перевірки.';

  @override
  String task_row_label(Object id, Object role) {
    return '$role · рядок $id';
  }

  @override
  String get task_role_assistant => 'Асистент';

  @override
  String get task_role_user => 'Користувач';

  @override
  String get task_role_tool => 'Інструмент';

  @override
  String task_tool_call(Object name) {
    return 'Виклик інструмента · $name';
  }

  @override
  String task_tool_result(Object name) {
    return 'Результат інструмента · $name';
  }

  @override
  String task_call_details(Object arguments, Object id) {
    return 'ID виклику: $id\nАргументи\n$arguments';
  }

  @override
  String task_result_details(Object id, Object result) {
    return 'ID виклику: $id\nРезультат\n$result';
  }

  @override
  String get task_not_supplied => 'Не надано';

  @override
  String get task_missing_arguments => 'Сервер не зберіг аргументи.';

  @override
  String get task_image_placeholder => '[зображення]';

  @override
  String get task_invalid_reference =>
      'Історія завдання недоступна: некоректне посилання на збережену сесію.';

  @override
  String get task_auth_required =>
      'Історія завдання недоступна: налаштуйте вхід до вебпанелі цього шлюзу. Ключ API-сервера не дає доступу до міркувань завдання.';

  @override
  String get task_auth_rejected =>
      'Історія завдання недоступна: вебпанель відхилила авторизацію. Перевірте налаштування вебпанелі цього шлюзу.';

  @override
  String get task_incompatible_history =>
      'Історія завдання недоступна: вебпанель не надає сумісної обмеженої історії для вибраного профілю.';

  @override
  String get task_identity_unproven =>
      'Історія завдання недоступна: вебпанель не підтвердила точну збережену сесію чи її ланцюжок стискання. Історія іншої сесії не показується.';

  @override
  String get task_partial_compression =>
      'Неповна історія: завдання продовжилося після стискання, але шлюз не надав перевірюваного нового посилання. Останньої відповіді може бракувати. Автоматичне оновлення призупинено; натисніть «Оновити» для повтору.';

  @override
  String get task_partial_ancestors =>
      'Неповна історія: шлюз не надає попередні частини завдання до стискання. Відомі рядки збережено; натисніть «Оновити» для повтору.';

  @override
  String get task_missing_reference =>
      'Історія завдання недоступна: сервер не зберіг посилання на сесію.';

  @override
  String get task_missing_row_identity =>
      'Історія завдання недоступна: сервер не надав постійних ідентифікаторів рядків повідомлень.';

  @override
  String get task_history_not_ready =>
      'Історія завдання ще недоступна (HTTP 404). Можливо, завдання ще не записало історію або вебпанель не підтримує її. Повторіть спробу.';

  @override
  String get task_refresh_failed =>
      'Не вдалося оновити історію завдання. Перевірте підключення й повторіть спробу.';

  @override
  String get task_status_interrupted => 'Перервано';

  @override
  String get task_status_cancelled => 'Скасовано';

  @override
  String get task_status_requested => 'Запитано';

  @override
  String get task_status_thinking => 'Міркує';

  @override
  String get task_status_tool => 'Використовує інструмент';

  @override
  String get task_status_pending => 'Очікує';

  @override
  String get task_status_dispatched => 'Передано';

  @override
  String task_status_unknown(Object status) {
    return 'Невідомий стан: $status';
  }

  @override
  String task_tasks_finished(Object count) {
    return 'Завершено делегованих завдань: $count';
  }

  @override
  String get activity_status_unconfirmed => 'Стан не підтверджено';

  @override
  String get activity_recently_updated => 'Нещодавно оновлено';

  @override
  String get activity_reconnecting => 'Перепідключення — перевірка стану ходу';

  @override
  String get activity_outcome_unknown =>
      'Не вдалося підтвердити результат ходу. Відкрийте чат для перевірки.';

  @override
  String get activity_chat_updated_detail =>
      'Шлюз зафіксував активність чату; поточний стан роботи недоступний.';

  @override
  String get activity_updated => 'Оновлено';

  @override
  String get activity_empty_title => 'Нещодавньої активності немає';

  @override
  String get activity_empty_detail =>
      'Тут відображаються ходи, розпочаті в цьому застосунку, та чати шлюзу, оновлені за останні 7 днів.';

  @override
  String get activity_read_error =>
      'Не вдалося прочитати записи ходів або чати шлюзу. Перевірте підключення й повторіть спробу.';

  @override
  String get activity_chat_unavailable =>
      'Чат більше недоступний або немає зв’язку зі шлюзом.';

  @override
  String get activity_partial_title => 'Активність завантажено частково';

  @override
  String get activity_partial_detail =>
      'Показано обмежену частину активності шлюзу. Можуть існувати інші чати; потягніть для оновлення.';

  @override
  String get provider_usage => 'Облік використання';

  @override
  String get provider_usage_notice =>
      'Використання Hermes за останні 30 днів, а не баланс кредитів чи ціни моделей. Облікові дані провайдерів налаштовуються на сервері Hermes; застосунок не зберігає їхніх ключів API.';

  @override
  String get provider_usage_failed =>
      'Не вдалося завантажити облік використання.';

  @override
  String get provider_usage_empty =>
      'Для цього провайдера немає записів використання.';

  @override
  String provider_usage_counts(String sessions, String input, String output) {
    return 'Сесій: $sessions · Вхід: $input · Вихід: $output';
  }

  @override
  String provider_usage_costs(String estimated, String actual) {
    return 'Орієнтовно: $estimated · За звітом: $actual';
  }

  @override
  String get provider_quota_codex => 'Передплата OpenAI Codex';

  @override
  String get provider_quota_claude => 'Передплата Claude';

  @override
  String get provider_quota_openai_api => 'Облік використання OpenAI API';

  @override
  String get provider_quota_notice =>
      'Вікна передплати за даними провайдера, окремо від обліку Hermes та оплати API. Облікові записи показуються окремо; обмеження моделі не означає вичерпання всього облікового запису.';

  @override
  String get provider_quota_windows_notice =>
      'Передплати Codex і Claude мають п’ятигодинні та тижневі обмеження. Показуються лише дані провайдера; відсутні межі й час скидання лишаються невідомими. Тижневі межі можуть стосуватися облікового запису або окремих моделей.';

  @override
  String get provider_quota_five_hour_session => 'П’ятигодинна сесія';

  @override
  String get provider_quota_unavailable => 'Залишок передплати недоступний.';

  @override
  String get provider_quota_failed =>
      'Не вдалося оновити залишок передплати. Збережені значення належать до попередньої перевірки.';

  @override
  String get provider_quota_account => 'Обліковий запис';

  @override
  String get provider_quota_unknown => 'невідомо';

  @override
  String provider_quota_state(String state) {
    return 'Стан облікового запису: $state';
  }

  @override
  String provider_quota_scope(String scope) {
    return 'Область: $scope';
  }

  @override
  String provider_quota_percent(String used, String remaining) {
    return 'Використано $used% · залишилось $remaining%';
  }

  @override
  String provider_quota_reset(String reset) {
    return 'Скидання: $reset';
  }

  @override
  String get provider_quota_reset_unknown => 'Час скидання невідомий.';

  @override
  String get auxiliary_models => 'Допоміжні моделі';

  @override
  String get auxiliary_notice =>
      'Виберіть моделі для окремих завдань. Власними адресами сервісів керуйте на сервері. Автоматичний режим дотримується правил успадкування завдання.';

  @override
  String get auxiliary_inherit => 'Автоматично (успадкувати)';

  @override
  String get auxiliary_unavailable =>
      'Налаштування допоміжних моделей недоступні.';

  @override
  String get provider_oauth_title => 'Вхід до провайдера';

  @override
  String get provider_oauth_more_subtitle =>
      'Керування входом до провайдера на сервері Hermes';

  @override
  String get provider_oauth_settings_subtitle =>
      'Вхід виконується на сервері Hermes; токени не зберігаються на цьому пристрої';

  @override
  String get provider_oauth_intro =>
      'Увійдіть до провайдера в зовнішньому браузері. Токени зберігаються лише на сервері Hermes. Вхід не змінює модель чату в цьому застосунку.';

  @override
  String get provider_oauth_defaults_notice =>
      'Деякі серверні сценарії, зокрема заміна безкоштовного облікового запису Nous, можуть змінити типові налаштування. Перевірте їх на сервері після входу.';

  @override
  String get provider_oauth_transport_init_failed =>
      'Не вдалося ініціалізувати вибране захищене підключення до вебпанелі. Перевірте TLS і налаштування підключення.';

  @override
  String get provider_oauth_https_required =>
      'Для входу до провайдера потрібне HTTPS-підключення до вебпанелі Hermes.';

  @override
  String get provider_oauth_auth_required =>
      'Перед входом налаштуйте авторизацію вебпанелі паролем або довіреним проксі.';

  @override
  String get provider_oauth_catalog_failed =>
      'Вхід до провайдера недоступний на цьому сервері. Перевірте авторизацію вебпанелі й оновіть сервер, якщо він не підтримує OAuth провайдера.';

  @override
  String get provider_oauth_expired => 'Час входу минув. Почніть знову.';

  @override
  String get provider_oauth_start_failed =>
      'Не вдалося почати захищений вхід до провайдера. Спробуйте ще раз.';

  @override
  String get provider_oauth_denied => 'Вхід відхилено. Почніть знову.';

  @override
  String get provider_oauth_cancelled => 'Вхід скасовано.';

  @override
  String get provider_oauth_host_failed =>
      'Сервер не зміг завершити вхід. Почніть знову.';

  @override
  String get provider_oauth_poll_failed =>
      'Не вдалося перевірити стан входу. Почніть знову.';

  @override
  String provider_oauth_cancellation_unconfirmed(String message) {
    return '$message Скасування не підтверджено; серверна сесія може тривати до завершення строку дії.';
  }

  @override
  String get provider_oauth_browser_failed =>
      'Не вдалося відкрити зовнішній браузер. Повторіть спробу або скасуйте вхід.';

  @override
  String get provider_oauth_retry => 'Повторити';

  @override
  String provider_oauth_complete(String provider) {
    return 'Завершити вхід до $provider';
  }

  @override
  String get provider_oauth_code_instruction =>
      'Введіть цей тимчасовий код на сторінці провайдера:';

  @override
  String get provider_oauth_waiting =>
      'Очікування дозволу. Сесія завершиться автоматично.';

  @override
  String get provider_oauth_open_browser => 'Відкрити провайдера в браузері';

  @override
  String get provider_oauth_cancel => 'Скасувати вхід';

  @override
  String get provider_oauth_signed_out => 'Вхід на сервері не виконано';

  @override
  String get provider_oauth_sign_in_again => 'Увійти знову';

  @override
  String get provider_oauth_sign_in => 'Увійти';

  @override
  String get provider_oauth_cli_required =>
      'Увійдіть через CLI провайдера на сервері Hermes. Цей сервер не надає входу до цього провайдера із застосунку.';

  @override
  String get provider_oauth_checking_account =>
      'Дозвіл отримано. Перевірка облікового запису на сервері…';

  @override
  String get provider_oauth_verification_unavailable =>
      'Дозвіл отримано; перевірка облікового запису недоступна. Відкрийте «Використання», щоб оновити дані.';

  @override
  String provider_oauth_verified_account(String email) {
    return 'Вхід на сервері Hermes виконано як $email. Відкрийте «Використання», щоб оновити дані.';
  }

  @override
  String get provider_oauth_credentials_unverified =>
      'Сервер повідомляє про наявність облікових даних; особу облікового запису не підтверджено.';

  @override
  String get provider_oauth_account_status_unknown =>
      'Стан облікового запису на сервері недоступний.';

  @override
  String get app_language => 'Мова застосунку';

  @override
  String get app_language_system => 'Як на телефоні';

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
  String get projects_root_title => 'Папка проєктів на сервері';

  @override
  String get projects_root_more_subtitle =>
      'Де на сервері створюються нові папки проєктів';

  @override
  String get projects_root_description =>
      'Проєкти, створені на цьому телефоні, отримують папку тут. Укажіть папку, яку використовує сам Hermes, щоб телефон і сервер бачили ті самі проєкти.';

  @override
  String get projects_root_label => 'Кореневий шлях проєктів';

  @override
  String projects_root_default_hint(String path) {
    return 'Типове значення сервера: $path';
  }

  @override
  String get projects_root_locked_title => 'Задано сервером';

  @override
  String get projects_root_locked_explanation =>
      'Цей сервер обмежує доступ до файлів одним коренем, тому папку проєктів неможливо змінити з програми.';

  @override
  String get projects_root_saved => 'Папку проєктів збережено.';

  @override
  String get projects_root_reset => 'Використовувати типове значення сервера';

  @override
  String get projects_root_invalid_empty => 'Введіть шлях до папки.';

  @override
  String get projects_root_invalid_absolute =>
      'Введіть абсолютний шлях, що починається з косої риски.';

  @override
  String get projects_root_invalid_segments =>
      'Видаліть зі шляху точкові сегменти та керуючі символи.';

  @override
  String get projects_root_unsupported =>
      'Не підтримується для цього підключення. Щоб прочитати або змінити папку проєктів на сервері, потрібне підключення Desktop Gateway з доступом до панелі керування.';

  @override
  String get projects_root_unavailable =>
      'Не вдалося прочитати папку проєктів на сервері. Перевірте підключення до панелі керування та повторіть спробу.';

  @override
  String get adopt_folder_action => 'Додати наявну папку';

  @override
  String adopt_folder_description(String root) {
    return 'Папки в $root, які ще не зареєстровані як проєкт.';
  }

  @override
  String adopt_folder_registered(String name) {
    return 'Уже проєкт: $name';
  }

  @override
  String get adopt_folder_none => 'Усі папки за цим шляхом уже є проєктами.';

  @override
  String get adopt_folder_unsupported =>
      'Це підключення не може отримати список папок сервера. Введіть абсолютний шлях до наявної папки.';

  @override
  String adopt_folder_failed(String error) {
    return 'Не вдалося отримати список папок сервера: $error';
  }

  @override
  String get adopt_folder_manual_label => 'Шлях до наявної папки';

  @override
  String get adopt_folder_name_label => 'Назва проєкту';

  @override
  String get adopt_folder_add => 'Додати як проєкт';

  @override
  String adopt_folder_added(String name, String path) {
    return '$name тепер використовує $path';
  }

  @override
  String adopt_folder_error(String error) {
    return 'Не вдалося додати папку: $error';
  }

  @override
  String adopt_folder_folderless(String name) {
    return 'Проєкт $name створено, але папку не прикріплено. Прикріпіть її в Hermes на сервері.';
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
  String get nextgen_toggle => 'Інтерфейс NextGen';

  @override
  String get nextgen_toggle_subtitle =>
      'Новий дизайн з єдиним входом, живими чатами та пошуком у мережі. Шлюзи й чати спільні з цим інтерфейсом.';

  @override
  String get nextgen_single_login => 'Увійти з одним логіном';

  @override
  String get nextgen_single_login_subtitle =>
      'Додайте шлюз лише за адресою панелі та одним входом.';

  @override
  String get ng_allow_this_command => 'Дозволити цю команду?';

  @override
  String ng_hermes_wants_to_run_this_with(Object tool) {
    return 'Hermes хоче запустити це за допомогою $tool.';
  }

  @override
  String get ng_hermes_wants_to_run_this => 'Hermes хоче запустити це.';

  @override
  String get ng_hermes_has_a_question => 'У Hermes є запитання';

  @override
  String get ng_hermes_has_questions => 'У Hermes є запитання';

  @override
  String get ng_password_for_sudo => 'Пароль для sudo';

  @override
  String get ng_hermes_needs_your_sudo_password_to =>
      'Hermes потрібен ваш пароль sudo, щоб виконати цю команду.';

  @override
  String get ng_a_secret_value => 'Конфіденційне значення';

  @override
  String ng_value_for(Object variable) {
    return 'Значення для $variable';
  }

  @override
  String get ng_your_password_manager => 'ваш менеджер паролів';

  @override
  String ng_unlock(Object name) {
    return 'Розблокувати $name';
  }

  @override
  String ng_hermes_needs_unlocked_to_sign_in(Object name) {
    return 'Щоб увійти за вас, Hermes потрібно розблокувати $name.';
  }

  @override
  String get ng_sign_in_code => 'Код входу';

  @override
  String get ng_enter_the_sign_in_code => 'Введіть код входу.';

  @override
  String ng_enter_the_sign_in_code_for(Object site) {
    return 'Введіть код входу для $site.';
  }

  @override
  String get ng_save_a_login => 'Зберегти дані для входу?';

  @override
  String ng_save_your_login(Object site) {
    return 'Зберегти дані входу для $site?';
  }

  @override
  String ng_couldn_t_load_this_chat(Object error) {
    return 'Не вдалося завантажити цей чат: $error';
  }

  @override
  String ng_live_updates_are_unavailable(Object error) {
    return 'Оновлення в реальному часі недоступні: $error';
  }

  @override
  String ng_preparing(Object name) {
    return 'Підготовка $name…';
  }

  @override
  String get ng_the_turn_failed => 'Не вдалося виконати цей запит.';

  @override
  String ng_couldn_t_stop(Object error) {
    return 'Не вдалося зупинити: $error';
  }

  @override
  String get ng_server_access => 'Доступ до сервера';

  @override
  String get ng_sign_in => 'Вхід';

  @override
  String get ng_live_connection => 'З’єднання в реальному часі';

  @override
  String get ng_check_that_tailscale_is_on_on =>
      'Переконайтеся, що Tailscale увімкнено і на цьому телефоні, і на сервері.';

  @override
  String get ng_check_the_address_and_that_the =>
      'Перевірте адресу та переконайтеся, що проксі перенаправляє запити на панель керування.';

  @override
  String get ng_use_the_same_network_as_the =>
      'Під’єднайтеся до тієї самої мережі, що й сервер, і запустіть панель керування з --host 0.0.0.0, щоб інші пристрої могли підключитися.';

  @override
  String get ng_check_the_address_vpn_or_tailscale =>
      'Перевірте адресу, VPN або з’єднання Tailscale.';

  @override
  String get ng_not_checked_yet => 'Ще не перевірено.';

  @override
  String get ng_checking => 'Перевірка…';

  @override
  String ng_hermes_answers_at(Object version, Object address) {
    return 'Hermes $version доступний за адресою $address.';
  }

  @override
  String get ng_something_answered_but_not_a_hermes =>
      'Отримано відповідь, але це не панель керування Hermes.';

  @override
  String ng_something_answered_http_but_not_a(Object status) {
    return 'Отримано відповідь (HTTP $status), але це не панель керування Hermes.';
  }

  @override
  String get ng_use_the_dashboard_s_address_and =>
      'Використовуйте адресу й порт панелі керування (9119 за замовчуванням), а не API-сервера.';

  @override
  String get ng_cloudflare_access_turned_the_service_token =>
      'Cloudflare Access відхилив токен сервісу.';

  @override
  String get ng_cloudflare_access_is_in_front_of =>
      'Перед цією адресою встановлено Cloudflare Access.';

  @override
  String get ng_check_the_service_token_and_its =>
      'Перевірте токен сервісу та політику Service Auth.';

  @override
  String get ng_add_a_cloudflare_access_service_token =>
      'Додайте токен сервісу Cloudflare Access для цієї адреси.';

  @override
  String get ng_the_server_asks_for_a_client =>
      'Сервер запитує сертифікат клієнта.';

  @override
  String get ng_pick_the_client_certificate_for_this =>
      'Виберіть сертифікат клієнта для цього шлюзу й перевірте ще раз.';

  @override
  String get ng_needs_server_access_first =>
      'Спочатку потрібен доступ до сервера.';

  @override
  String get ng_needs_a_sign_in_first => 'Спочатку потрібно увійти.';

  @override
  String ng_signed_in_as(Object name) {
    return 'Ви увійшли як $name.';
  }

  @override
  String get ng_this_dashboard_doesn_t_need_a =>
      'Для цієї панелі керування вхід не потрібен.';

  @override
  String get ng_the_saved_sign_in_has_expired =>
      'Термін дії збереженого входу минув.';

  @override
  String get ng_sign_in_again => 'Увійдіть знову.';

  @override
  String get ng_too_many_sign_in_attempts => 'Забагато спроб входу.';

  @override
  String get ng_wait_a_minute_then_check_again =>
      'Зачекайте хвилину й перевірте ще раз.';

  @override
  String ng_the_gateway_answered(Object message) {
    return 'Шлюз відповів: $message.';
  }

  @override
  String get ng_sign_in_again_or_update_hermes =>
      'Увійдіть знову або оновіть Hermes.';

  @override
  String ng_couldn_t_check_the_sign_in(Object error) {
    return 'Не вдалося перевірити вхід: $error';
  }

  @override
  String ng_the_gateway_wouldn_t_issue_a(Object message) {
    return 'Шлюз не видав квиток для чату ($message).';
  }

  @override
  String get ng_the_chat_connection_opened_and_the =>
      'З’єднання чату встановлено, шлюз повідомив, що готовий.';

  @override
  String get ng_the_gateway_never_said_it_was =>
      'Шлюз так і не повідомив про готовність.';

  @override
  String get ng_check_that_the_agent_is_running =>
      'Переконайтеся, що агент запущено на сервері.';

  @override
  String get ng_the_gateway_refused_the_chat_connection =>
      'Шлюз відхилив з’єднання чату (HTTP 403).';

  @override
  String get ng_this_dashboard_has_no_chat_endpoint =>
      'У цієї панелі керування немає кінцевої точки чату (/api/ws).';

  @override
  String ng_the_chat_connection_failed(Object detail) {
    return 'Не вдалося встановити з’єднання чату: $detail';
  }

  @override
  String get ng_use_the_exact_address_the_dashboard =>
      'Використовуйте точну адресу, налаштовану для панелі керування.';

  @override
  String get ng_update_hermes => 'Оновіть Hermes.';

  @override
  String get ng_make_sure_the_proxy_allows_websocket =>
      'Переконайтеся, що проксі дозволяє оновлення WebSocket на /api/ws.';

  @override
  String get ng_offline => 'Офлайн';

  @override
  String get ng_connecting => 'Підключення…';

  @override
  String get ng_connected => 'Підключено';

  @override
  String get ng_reconnecting => 'Повторне підключення…';

  @override
  String get ng_signed_out => 'Ви вийшли з облікового запису';

  @override
  String get ng_connection_failed => 'Не вдалося підключитися';

  @override
  String get ng_rate_limited_by_gateway => 'Шлюз обмежив частоту запитів';

  @override
  String ng_couldn_t_open_the_chat_connection(Object message) {
    return 'Не вдалося відкрити з’єднання з чатом: $message';
  }

  @override
  String get ng_the_gateway_returned_no_websocket_ticket =>
      'Шлюз не надав квиток WebSocket.';

  @override
  String get ng_connection_lost => 'З’єднання втрачено';

  @override
  String get ng_this_dashboard_has_no_chat_endpoint_2 =>
      'У цій панелі немає кінцевої точки чату (/api/ws). Оновіть Hermes.';

  @override
  String get ng_the_gateway_refused_the_chat_connection_2 =>
      'Шлюз відхилив з’єднання з чатом. Перевірте, чи адреса відповідає налаштованому хосту панелі та чи ввімкнено вбудований чат.';

  @override
  String ng_the_gateway_refused(Object method) {
    return 'Шлюз відхилив $method.';
  }

  @override
  String ng_couldn_t_read_your_saved_gateways(Object error) {
    return 'Не вдалося прочитати збережені шлюзи: $error';
  }

  @override
  String get ng_applies_to_new_chats => 'Застосовується до нових чатів';

  @override
  String ng_couldn_t_change(Object label, Object error) {
    return 'Не вдалося змінити $label: $error';
  }

  @override
  String get ng_capabilities => 'Можливості';

  @override
  String get ng_skills => 'Навички';

  @override
  String get ng_toolsets => 'Набори інструментів';

  @override
  String get ng_search => 'Пошук';

  @override
  String get ng_couldn_t_load => 'Не вдалося завантажити';

  @override
  String get ng_try_again => 'Спробувати ще раз';

  @override
  String get ng_no_skills => 'Немає навичок';

  @override
  String get ng_no_toolsets => 'Немає наборів інструментів';

  @override
  String get ng_no_mcp_servers => 'Немає серверів MCP';

  @override
  String get ng_that_file_is_too_large_to =>
      'Цей файл завеликий, щоб бути сертифікатом.';

  @override
  String ng_the_certificate_couldn_t_be_imported(Object error) {
    return 'Не вдалося імпортувати сертифікат: $error';
  }

  @override
  String get ng_now_pick_its_private_key =>
      'Тепер виберіть відповідний приватний ключ.';

  @override
  String get ng_now_pick_its_certificate =>
      'Тепер виберіть відповідний сертифікат.';

  @override
  String get ng_that_file_isn_t_a_certificate =>
      'Цей файл не є сертифікатом або приватним ключем.';

  @override
  String get ng_if_a_proxy_in_front_of =>
      'Якщо проксі перед цією адресою запитує сертифікат клієнта, виберіть його тут, щоб перевірка, вхід і чат використовували його.';

  @override
  String get ng_client_certificates_are_only_used_with =>
      'Сертифікати клієнта використовуються лише з адресами https://.';

  @override
  String get ng_remove => 'Видалити';

  @override
  String get ng_certificate_password => 'Пароль сертифіката';

  @override
  String get ng_importing => 'Імпорт…';

  @override
  String get ng_pick_certificate => 'Вибрати сертифікат';

  @override
  String get ng_pick_a_different_certificate => 'Вибрати інший сертифікат';

  @override
  String get ng_accepts_p12_pfx_or_pem_certificate =>
      'Підтримуються файли .p12/.pfx або файли сертифіката й ключа PEM. Ключ зберігається у приватному сховищі цього застосунку.';

  @override
  String get ng_photos => 'Фотографії';

  @override
  String get ng_camera => 'Камера';

  @override
  String get ng_files => 'Файли';

  @override
  String ng_you_can_attach_up_to_files(Object count) {
    return 'Можна прикріпити до $count файлів.';
  }

  @override
  String ng_couldn_t_read(Object name) {
    return 'Не вдалося прочитати $name.';
  }

  @override
  String ng_couldn_t_prepare_that_file(Object error) {
    return 'Не вдалося підготувати цей файл: $error';
  }

  @override
  String get ng_hermes_is_still_working => 'Hermes ще працює';

  @override
  String get ng_steer => 'Скерувати';

  @override
  String get ng_adds_this_to_the_running_turn =>
      'Додає це до поточного ходу на наступному кроці';

  @override
  String get ng_queue => 'У чергу';

  @override
  String get ng_sends_it_when_the_turn_finishes =>
      'Надсилає це після завершення ходу';

  @override
  String get ng_stop_and_send => 'Зупинити й надіслати';

  @override
  String get ng_stops_the_turn_then_sends_this =>
      'Зупиняє хід, а потім надсилає це';

  @override
  String ng_dictation_stopped(Object message) {
    return 'Диктування зупинено: $message';
  }

  @override
  String get ng_speech_recognition_isn_t_available =>
      'Розпізнавання мовлення недоступне.';

  @override
  String get ng_working => 'Працює';

  @override
  String get ng_ready => 'Готово';

  @override
  String get ng_chats => 'Чати';

  @override
  String get ng_new_chat => 'Новий чат';

  @override
  String get ng_usage => 'Використання';

  @override
  String get ng_rename_chat => 'Перейменувати чат';

  @override
  String ng_couldn_t_rename(Object error) {
    return 'Не вдалося перейменувати: $error';
  }

  @override
  String get ng_this_chat => 'Цей чат';

  @override
  String get ng_input_tokens => 'Вхідні токени';

  @override
  String get ng_output_tokens => 'Вихідні токени';

  @override
  String get ng_reasoning_tokens => 'Токени міркування';

  @override
  String get ng_cache_reads => 'Читання з кешу';

  @override
  String get ng_api_calls => 'Виклики API';

  @override
  String get ng_cost => 'Вартість';

  @override
  String get ng_context => 'Контекст';

  @override
  String get ng_your_sign_in_expired => 'Термін дії входу завершився.';

  @override
  String get ng_sign_in_2 => 'Увійти';

  @override
  String get ng_retry => 'Повторити';

  @override
  String get ng_what_should_we_work_on => 'Над чим попрацюємо?';

  @override
  String get ng_ask_hermes_anything_it_can_run =>
      'Запитайте Hermes про що завгодно. Він може запускати інструменти, переглядати вебсторінки й працювати з файлами на сервері.';

  @override
  String ng_working_2(Object frame) {
    return 'Працює · $frame';
  }

  @override
  String get ng_default_model => 'Модель за замовчуванням';

  @override
  String get ng_listening => 'Слухаю…';

  @override
  String get ng_steer_or_queue_a_message =>
      'Спрямуйте розмову або додайте повідомлення в чергу';

  @override
  String get ng_message_hermes => 'Повідомлення для Hermes';

  @override
  String get ng_attach => 'Додати файл';

  @override
  String get ng_stop_dictation => 'Зупинити диктування';

  @override
  String get ng_dictate => 'Диктувати';

  @override
  String get ng_stop => 'Зупинити';

  @override
  String get ng_send => 'Надіслати';

  @override
  String get ng_steered => 'Спрямовано';

  @override
  String get ng_copied => 'Скопійовано';

  @override
  String ng_not_sent(Object reason) {
    return 'Не надіслано: $reason';
  }

  @override
  String get ng_thinking => 'Думаю…';

  @override
  String get ng_thought => 'Міркування';

  @override
  String ng_used(Object name) {
    return 'Використано: $name';
  }

  @override
  String ng_used_tools(Object count) {
    return 'Використано інструментів: $count';
  }

  @override
  String get ng_copy => 'Копіювати';

  @override
  String get ng_the_gateway_connection_dropped_try_again =>
      'З’єднання зі шлюзом втрачено. Спробуйте ще раз.';

  @override
  String get ng_allow_once => 'Дозволити один раз';

  @override
  String get ng_allow_for_this_chat => 'Дозволити в цьому чаті';

  @override
  String get ng_always_allow => 'Дозволяти завжди';

  @override
  String get ng_deny => 'Заборонити';

  @override
  String get ng_your_answer => 'Ваша відповідь';

  @override
  String get ng_or_type_an_answer => 'Або введіть відповідь';

  @override
  String get ng_skip => 'Пропустити';

  @override
  String get ng_answer => 'Відповісти';

  @override
  String get ng_cancel => 'Скасувати';

  @override
  String get ng_username_or_email => 'Ім’я користувача або електронна пошта';

  @override
  String get ng_password => 'Пароль';

  @override
  String get ng_not_now => 'Не зараз';

  @override
  String get ng_save => 'Зберегти';

  @override
  String get ng_enter_both_the_client_id_and =>
      'Введіть ідентифікатор клієнта й секрет клієнта або не вводьте жодного.';

  @override
  String get ng_enter_your_username_and_password =>
      'Введіть ім’я користувача й пароль.';

  @override
  String ng_couldn_t_save_the_sign_in(Object error) {
    return 'Не вдалося зберегти дані для входу: $error';
  }

  @override
  String get ng_wrong_username_or_password =>
      'Неправильне ім’я користувача або пароль.';

  @override
  String get ng_too_many_attempts_wait_a_moment =>
      'Забагато спроб. Зачекайте трохи й повторіть.';

  @override
  String get ng_welcome_to_hermes => 'Ласкаво просимо до Hermes';

  @override
  String get ng_add_a_gateway => 'Додати шлюз';

  @override
  String get ng_connect_to_your_hermes_agent_dashboard =>
      'Під’єднайтеся до панелі Hermes Agent. Одна адреса й один вхід дають доступ до чатів, інструментів і налаштувань. Дані не надсилаються, доки ви не ввійдете.';

  @override
  String get ng_connect_to_another_hermes_agent_dashboard =>
      'Під’єднайтеся до іншої панелі Hermes Agent. Ви залишатиметеся в системі на збережених панелях.';

  @override
  String get ng_dashboard_address => 'Адреса панелі';

  @override
  String get ng_testing => 'Перевірка…';

  @override
  String get ng_test => 'Перевірити';

  @override
  String get ng_where_your_hermes_dashboard_runs_lan =>
      'Адреса панелі Hermes у вашій мережі: LAN, Tailscale або HTTPS.';

  @override
  String get ng_find_on_my_network => 'Знайти в моїй мережі';

  @override
  String get ng_which_address_do_i_use => 'Яку адресу використовувати?';

  @override
  String get ng_behind_cloudflare_access => 'За Cloudflare Access?';

  @override
  String get ng_need_a_client_certificate => 'Потрібен сертифікат клієнта?';

  @override
  String get ng_this_address_isn_t_private_and =>
      'Ця адреса не є приватною та не використовує https://, тож ваш пароль і чати передаватимуться інтернетом без шифрування. Натомість використайте https://, Tailscale або власну мережу.';

  @override
  String get ng_continue_to_sign_in => 'Перейти до входу';

  @override
  String get ng_use_the_classic_interface_instead =>
      'Натомість скористатися класичним інтерфейсом';

  @override
  String get ng_if_cloudflare_access_protects_this_address =>
      'Якщо цю адресу захищає Cloudflare Access, створіть сервісний токен у Cloudflare Zero Trust (Access, Service credentials) і додайте для нього політику Service Auth у застосунку Access.';

  @override
  String get ng_a_service_token_is_saved_for =>
      'Для цієї адреси збережено сервісний токен';

  @override
  String get ng_forget => 'Забути';

  @override
  String get ng_client_id => 'Ідентифікатор клієнта';

  @override
  String get ng_client_secret => 'Секрет клієнта';

  @override
  String get ng_stored_encrypted_on_this_phone_and =>
      'Зберігається в зашифрованому вигляді на цьому телефоні й надсилається лише на цю адресу.';

  @override
  String get ng_hermes_is_reachable => 'Hermes доступний';

  @override
  String ng_hermes_is_reachable_2(Object version) {
    return 'Hermes $version доступний';
  }

  @override
  String get ng_sign_in_is_tested_next_then =>
      'Спочатку перевіряється вхід, потім чат';

  @override
  String get ng_agent_gateway => 'Шлюз агента';

  @override
  String get ng_running => 'Працює';

  @override
  String get ng_stopped => 'Зупинено';

  @override
  String get ng_username_password => 'Ім’я користувача й пароль';

  @override
  String get ng_browser => 'Браузер';

  @override
  String get ng_in_the_browser_sso => 'У браузері (SSO)';

  @override
  String get ng_profiles => 'Профілі';

  @override
  String get ng_this_dashboard_offers_neither_a_username =>
      'Ця панель керування не підтримує вхід ні за ім’ям користувача й паролем, ні через браузер. Оновіть Hermes або налаштуйте на сервері провайдера входу за ім’ям користувача й паролем.';

  @override
  String get ng_the_auth_gate_is_off_on =>
      'Захист входу на цій панелі вимкнено. Будь-хто, хто має до неї доступ, може користуватися вашим агентом.';

  @override
  String get ng_couldn_t_reach_the_dashboard =>
      'Не вдалося підключитися до панелі керування';

  @override
  String ng_check_the_address_and_port_9119(Object reason) {
    return '$reason\n\nПеревірте адресу й порт (9119 за замовчуванням). Якщо панель ще не запущена, виконайте на сервері:\nhermes dashboard --host 0.0.0.0';
  }

  @override
  String get ng_that_isn_t_a_hermes_dashboard =>
      'Це не панель керування Hermes';

  @override
  String get ng_something_answered_but_not_a_hermes_2 =>
      'Відповідь отримано, але це не панель керування Hermes. Використовуйте адресу панелі, а не API-сервера (порт 8642).';

  @override
  String ng_something_answered_http_but_not_a_2(Object status) {
    return 'Отримано відповідь (HTTP $status), але це не панель керування Hermes. Використовуйте адресу панелі, а не API-сервера (порт 8642).';
  }

  @override
  String get ng_cloudflare_access_stopped_the_request =>
      'Cloudflare Access заблокував запит';

  @override
  String ng_cloudflare_access_turned_down_the_service(Object status) {
    return 'Cloudflare Access відхилив токен служби (HTTP $status). Перевірте Client ID і Secret, а також політику Service Auth.';
  }

  @override
  String get ng_add_a_cloudflare_access_service_token_2 =>
      'Додайте нижче токен служби Cloudflare Access і перевірте ще раз.';

  @override
  String get ng_a_client_certificate_is_needed =>
      'Потрібен клієнтський сертифікат';

  @override
  String get ng_this_server_asks_for_a_client =>
      'Цей сервер запитує клієнтський сертифікат для підключення. Виберіть нижче сертифікат, який вам видали, і спробуйте ще раз.';

  @override
  String get ng_this_dashboard_doesn_t_ask_for =>
      'На цій панелі не потрібно входити.';

  @override
  String ng_use_the_dashboard_username_and_password(Object address) {
    return 'Використовуйте ім’я користувача й пароль панелі, налаштовані для $address, або увійдіть у браузері.';
  }

  @override
  String ng_use_the_dashboard_username_and_password_2(Object address) {
    return 'Використовуйте ім’я користувача й пароль панелі, налаштовані для $address.';
  }

  @override
  String ng_sign_in_to_in_your_browser(Object address) {
    return 'Увійдіть у $address у браузері за допомогою облікового запису, який використовується для панелі.';
  }

  @override
  String ng_gateway(Object address) {
    return 'Шлюз $address';
  }

  @override
  String get ng_profile => 'Профіль';

  @override
  String get ng_server_default => 'За замовчуванням сервера';

  @override
  String get ng_continue => 'Продовжити';

  @override
  String get ng_username => 'Ім’я користувача';

  @override
  String get ng_signing_in => 'Вхід…';

  @override
  String get ng_waiting_for_the_browser => 'Очікування браузера…';

  @override
  String get ng_sign_in_with_browser => 'Увійти через браузер';

  @override
  String get ng_finish_signing_in_on_the_page =>
      'Завершіть вхід на відкритій сторінці. Hermes повернеться автоматично, коли ви закінчите.';

  @override
  String get ng_use_a_different_gateway => 'Використати інший шлюз';

  @override
  String get ng_same_wi_fi_or_local_network =>
      'Та сама мережа Wi-Fi або локальна мережа';

  @override
  String get ng_use_the_server_s_local_address =>
      'Використовуйте локальну адресу й порт сервера, наприклад 192.168.1.20:9119. Запустіть панель із --host 0.0.0.0, щоб інші пристрої могли підключитися.';

  @override
  String get ng_tailscale => 'Tailscale';

  @override
  String get ng_turn_on_tailscale_on_this_phone =>
      'Увімкніть Tailscale на цьому телефоні й використовуйте адресу Tailscale сервера, наприклад 100.64.0.1:9119 або його ім’я .ts.net. Працює і поза домом.';

  @override
  String get ng_use_your_https_address_when_the =>
      'Використовуйте адресу https://, якщо панель розміщена за проксі із сертифікатом. Проксі також має підтримувати оновлення WebSocket на /api/ws.';

  @override
  String get ng_start_the_dashboard_on_the_server =>
      'Запустіть панель на сервері:';

  @override
  String get ng_enter_a_port_from_1_to => 'Введіть порт від 1 до 65535.';

  @override
  String get ng_looks_for_hermes_dashboards_on_port =>
      'Шукає панелі Hermes на порту 9119 у цій мережі Wi-Fi та перевіряє комп’ютери, які ви вже зберегли.';

  @override
  String ng_looks_for_hermes_dashboards_on_ports(Object port) {
    return 'Шукає панелі Hermes на портах 9119 і $port у цій мережі Wi-Fi та перевіряє комп’ютери, які ви вже зберегли.';
  }

  @override
  String get ng_other_port_optional => 'Інший порт (необов’язково)';

  @override
  String get ng_no_dashboards_answered_start_one_with =>
      'Жодна панель не відповіла. Запустіть її командою hermes dashboard --host 0.0.0.0 або введіть її адресу.';

  @override
  String get ng_using_tailscale_or_a_vpn_those =>
      'Користуєтеся Tailscale або VPN? Такі мережі не можна просканувати. Введіть адресу комп’ютера 100.x або його ім’я .ts.net.';

  @override
  String get ng_search_again => 'Шукати знову';

  @override
  String get ng_insights => 'Статистика';

  @override
  String get ng_couldn_t_load_insights => 'Не вдалося завантажити статистику';

  @override
  String get ng_sessions => 'Сеанси';

  @override
  String get ng_tokens => 'Токени';

  @override
  String get ng_est_cost => 'Орієнт. вартість';

  @override
  String get ng_daily_tokens => 'Щоденні токени';

  @override
  String get ng_models => 'Моделі';

  @override
  String get ng_tools => 'Інструменти';

  @override
  String get ng_hermes_is_waiting_for_you => 'Hermes чекає на вас.';

  @override
  String get ng_hermes_replied => 'Hermes відповів';

  @override
  String get ng_the_turn_finished => 'Хід завершено.';

  @override
  String get ng_off => 'Вимкнено';

  @override
  String get ng_minimal => 'Мінімальний';

  @override
  String get ng_low => 'Низький';

  @override
  String get ng_medium => 'Середній';

  @override
  String get ng_high => 'Високий';

  @override
  String get ng_extra_high => 'Дуже високий';

  @override
  String get ng_max => 'Максимальний';

  @override
  String get ng_ultra => 'Ультра';

  @override
  String get ng_default => 'За замовчуванням';

  @override
  String ng_couldn_t_switch_model(Object error) {
    return 'Не вдалося змінити модель: $error';
  }

  @override
  String get ng_model => 'Модель';

  @override
  String get ng_thinking_2 => 'Думає';

  @override
  String get ng_search_models => 'Пошук моделей';

  @override
  String ng_couldn_t_load_models(Object error) {
    return 'Не вдалося завантажити моделі: $error';
  }

  @override
  String get ng_no_providers_are_set_up_on =>
      'На цьому шлюзі ще не налаштовано жодного провайдера.';

  @override
  String get ng_starred => 'Обране';

  @override
  String get ng_recent => 'Нещодавні';

  @override
  String get ng_more => 'Ще';

  @override
  String get ng_archived_chats => 'Архівовані чати';

  @override
  String get ng_projects => 'Проєкти';

  @override
  String get ng_chats_grouped_by_project_and_workspace =>
      'Чати згруповано за проєктом і робочим простором';

  @override
  String get ng_agent => 'Агент';

  @override
  String get ng_memory => 'Пам’ять';

  @override
  String get ng_what_hermes_remembers_about_you => 'Що Hermes пам’ятає про вас';

  @override
  String get ng_skills_library => 'Бібліотека навичок';

  @override
  String get ng_browse_and_read_installed_skills =>
      'Переглядайте й читайте встановлені навички';

  @override
  String get ng_cron_editor => 'Редактор Cron';

  @override
  String get ng_edit_schedules_prompts_and_delivery =>
      'Редагуйте розклади, запити й доставлення';

  @override
  String get ng_config_file => 'Файл конфігурації';

  @override
  String get ng_edit_config_yaml_on_the_gateway =>
      'Редагуйте config.yaml на шлюзі';

  @override
  String get ng_models_and_providers => 'Моделі й провайдери';

  @override
  String get ng_model_management => 'Керування моделями';

  @override
  String get ng_default_fallback_and_auxiliary_models =>
      'Моделі за замовчуванням, резервні й допоміжні';

  @override
  String get ng_provider_sign_in => 'Вхід у провайдера';

  @override
  String get ng_connect_provider_accounts_with_oauth =>
      'Під’єднайте облікові записи провайдерів через OAuth';

  @override
  String get ng_nous_portal => 'Nous Portal';

  @override
  String get ng_subscription_credits_and_usage =>
      'Підписка, кредити й використання';

  @override
  String get ng_interface => 'Інтерфейс';

  @override
  String get ng_switch_to_the_classic_interface =>
      'Перейти до класичного інтерфейсу';

  @override
  String get ng_turns_nextgen_off_you_can_turn =>
      'Вимикає NextGen. Ви можете знову ввімкнути його в налаштуваннях.';

  @override
  String get ng_restored => 'Відновлено';

  @override
  String get ng_archived => 'Заархівовано';

  @override
  String get ng_couldn_t_load_archived_chats =>
      'Не вдалося завантажити архівовані чати';

  @override
  String get ng_nothing_archived => 'Немає архівованих чатів';

  @override
  String get ng_restore => 'Відновити';

  @override
  String get ng_saved_new_chats_use_it =>
      'Збережено. У нових чатах використовуватиметься цей варіант.';

  @override
  String ng_couldn_t_save(Object error) {
    return 'Не вдалося зберегти: $error';
  }

  @override
  String get ng_saving => 'Збереження…';

  @override
  String ng_today(Object time) {
    return 'Сьогодні $time';
  }

  @override
  String get ng_mon => 'Пн';

  @override
  String get ng_tue => 'Вт';

  @override
  String get ng_wed => 'Ср';

  @override
  String get ng_thu => 'Чт';

  @override
  String get ng_fri => 'Пт';

  @override
  String get ng_sat => 'Сб';

  @override
  String get ng_sun => 'Нд';

  @override
  String get ng_scheduled => 'Заплановано';

  @override
  String get ng_new_job => 'Нове завдання';

  @override
  String get ng_couldn_t_load_scheduled_jobs =>
      'Не вдалося завантажити заплановані завдання';

  @override
  String get ng_nothing_scheduled => 'Нічого не заплановано';

  @override
  String get ng_ask_hermes_to_do_something_on =>
      'Попросіть Hermes виконувати щось за розкладом або додайте завдання тут.';

  @override
  String get ng_active => 'Активне';

  @override
  String get ng_paused => 'Призупинене';

  @override
  String ng_next(Object when) {
    return 'Наступне: $when';
  }

  @override
  String ng_last(Object when) {
    return 'Останнє: $when';
  }

  @override
  String ng_last_2(Object when, Object result) {
    return 'Останнє: $when · $result';
  }

  @override
  String ng_job(Object id) {
    return 'Завдання $id';
  }

  @override
  String get ng_delete => 'Видалити';

  @override
  String get ng_delete_this_job => 'Видалити це завдання?';

  @override
  String get ng_it_stops_running_past_runs_stay =>
      'Воно більше не запускатиметься. Попередні запуски залишаться у ваших чатах.';

  @override
  String ng_next_run(Object when) {
    return 'Наступний запуск: $when';
  }

  @override
  String ng_delivers_to(Object target) {
    return 'Надсилає до $target';
  }

  @override
  String get ng_run_now => 'Запустити зараз';

  @override
  String get ng_started => 'Запущено';

  @override
  String get ng_pause => 'Призупинити';

  @override
  String get ng_resume => 'Продовжити';

  @override
  String get ng_resumed => 'Відновлено';

  @override
  String get ng_prompt => 'Запит';

  @override
  String get ng_runs => 'Запуски';

  @override
  String get ng_no_runs_yet => 'Поки що запусків немає.';

  @override
  String get ng_enter_a_schedule_and_a_prompt => 'Укажіть розклад і запит.';

  @override
  String get ng_name_optional => 'Назва (необов’язково)';

  @override
  String get ng_schedule => 'Розклад';

  @override
  String get ng_every_1h_0_9_or_30m => 'every 1h, 0 9 * * *, or 30m';

  @override
  String get ng_create => 'Створити';

  @override
  String get ng_unpin => 'Відкріпити';

  @override
  String get ng_pin => 'Закріпити';

  @override
  String get ng_rename => 'Перейменувати';

  @override
  String get ng_archive => 'Архівувати';

  @override
  String get ng_delete_this_chat => 'Видалити цей чат?';

  @override
  String get ng_it_is_removed_from_the_gateway =>
      'Його буде видалено зі шлюзу на всіх пристроях.';

  @override
  String get ng_search_chats => 'Шукати чати';

  @override
  String get ng_pinned => 'Закріплені';

  @override
  String get ng_no_chats_match => 'Чатів не знайдено.';

  @override
  String get ng_no_chats_yet => 'Поки що чатів немає.';

  @override
  String get ng_nothing_is_running => 'Нічого не виконується.';

  @override
  String get ng_nothing_is_waiting_on_you =>
      'Немає запитів, що чекають на вас.';

  @override
  String get ng_settings => 'Налаштування';

  @override
  String get ng_all => 'Усі';

  @override
  String ng_needs_you(Object count) {
    return 'Потрібна ваша увага · $count';
  }

  @override
  String get ng_needs_you_2 => 'Потрібна ваша увага';

  @override
  String get ng_gateways => 'Шлюзи';

  @override
  String ng_classic_connection(Object address) {
    return '$address · класичне підключення';
  }

  @override
  String get ng_gateway_2 => 'Шлюз';

  @override
  String get ng_signed_in => 'Ви ввійшли';

  @override
  String get ng_classic_connection_2 => 'Класичне підключення';

  @override
  String get ng_in_the_browser => 'У браузері';

  @override
  String ng_in_the_browser_as(Object name) {
    return 'У браузері як $name';
  }

  @override
  String get ng_not_required => 'Не потрібно';

  @override
  String get ng_test_connection => 'Перевірити з’єднання';

  @override
  String get ng_sign_in_again_2 => 'Увійти знову';

  @override
  String get ng_sign_out => 'Вийти';

  @override
  String get ng_saved_gateways => 'Збережені шлюзи';

  @override
  String get ng_in_use => 'Використовується';

  @override
  String get ng_appearance => 'Вигляд';

  @override
  String get ng_theme => 'Тема';

  @override
  String get ng_system => 'Системна';

  @override
  String get ng_light => 'Світла';

  @override
  String get ng_dark => 'Темна';

  @override
  String get ng_accent => 'Акцент';

  @override
  String get ng_pure_black => 'Чистий чорний';

  @override
  String get ng_dark_theme_uses_true_black_oled =>
      'Темна тема використовує справжній чорний (OLED)';

  @override
  String get ng_glow => 'Світіння';

  @override
  String get ng_soft_accent_light_behind_each_screen =>
      'М’яке акцентне підсвічування за кожним екраном';

  @override
  String get ng_the_new_interface_turn_off_to =>
      'Новий інтерфейс. Вимкніть, щоб повернутися до класичного; шлюзи й чати спільні.';

  @override
  String get ng_more_settings => 'Інші налаштування';

  @override
  String get ng_voice_notifications_language_backups_and_the =>
      'Голос, сповіщення, мова, резервні копії та конфігурація шлюзу';

  @override
  String get ng_licences => 'Ліцензії';

  @override
  String ng_sign_out_of(Object name) {
    return 'Вийти з $name?';
  }

  @override
  String get ng_this_gateway_and_its_saved_sign =>
      'Цей шлюз і збережені дані для входу буде видалено з цього телефона в обох інтерфейсах. Ваші чати залишаться на шлюзі.';

  @override
  String get ng_password_or_browser => 'Пароль або браузер';

  @override
  String get ng_unsupported => 'Не підтримується';

  @override
  String get ng_background_task_finished => 'Фонове завдання завершено';

  @override
  String get ng_background_process_finished => 'Фоновий процес завершився';

  @override
  String get ng_system_message => 'Системне повідомлення';
}
