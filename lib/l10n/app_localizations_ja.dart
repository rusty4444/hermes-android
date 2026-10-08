// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      '単発の質問用。72時間後に自動アーカイブされますが、残す価値のある内容は記憶されます。';

  @override
  String get ai_full_text => 'AI + 全文';

  @override
  String get ai_search_model => 'AI検索モデル';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'AI検索: $aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'AIによる仕分け';

  @override
  String get api_key => 'APIキー';

  @override
  String get api_server_key_from_hermes_env =>
      '~/.hermes/.env の API_SERVER_KEY';

  @override
  String get active => 'アクティブ';

  @override
  String get activity => 'アクティビティ';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      'アクティビティは永続的なターンジャーナルを読み取り、Hermesの動作を把握します。ゲートウェイに到達できることを確認して、もう一度お試しください。';

  @override
  String get add => '追加';

  @override
  String get add_connection => '接続を追加';

  @override
  String get add_cron_job => 'Cronジョブを追加';

  @override
  String get add_gateway_connection => 'ゲートウェイ接続を追加';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      'バックアップの接続を追加・更新し、それ以外はそのままにします。';

  @override
  String get add_attachment => '添付を追加';

  @override
  String get add_new_cron_job => '新しいCronジョブを追加';

  @override
  String get add_to_chat => 'チャットに追加';

  @override
  String get all_chats => 'すべてのチャット';

  @override
  String get all_stored_message_content => '保存されている全メッセージ内容';

  @override
  String get allow_for_this_session => 'このセッション中は許可';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      'このHermesセッションが終了するまで、一致するコマンドを許可します。';

  @override
  String get allow_once => '1回だけ許可';

  @override
  String get always_allow => '常に許可';

  @override
  String get apply_to_this_chat => 'このチャットに適用';

  @override
  String get approval_needed => '承認が必要';

  @override
  String get archive => 'アーカイブ';

  @override
  String get archive_project => 'プロジェクトをアーカイブ';

  @override
  String archive_2(Object projectName) {
    return '$projectNameをアーカイブしますか？';
  }

  @override
  String archive_3(Object name) {
    return '$nameをアーカイブしますか？';
  }

  @override
  String get archived => 'アーカイブ済み';

  @override
  String get archived_conversations_appear_here => 'アーカイブした会話がここに表示されます。';

  @override
  String get archived_quick_chats => 'アーカイブ済みクイックチャット';

  @override
  String get artifacts_attachments_and_generated_media => '成果物、添付ファイル、生成メディア';

  @override
  String get ask_ai_to_find_a_conversation => 'AIに会話を探させる';

  @override
  String get assets => 'アセット';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      'プロジェクトごとに表示するには、Hermesゲートウェイにサーバー権威のアセットインデックスが必要です。';

  @override
  String get assets_unavailable => 'アセットを利用できません';

  @override
  String get attach_image_or_file => '画像またはファイルを添付';

  @override
  String get attachment_drafts => '添付ドラフト';

  @override
  String attachment_of(Object index, Object total) {
    return '添付 $index/$total';
  }

  @override
  String get auto_device_default => '自動（端末のデフォルト）';

  @override
  String get auto_archives_after_72_hours => '72時間後に自動アーカイブ';

  @override
  String get automation => '自動化';

  @override
  String get autonomous_agents => '自律エージェント';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      'バックグラウンド復旧は利用不可 — レガシー通信方式';

  @override
  String get backup_restore => 'バックアップと復元';

  @override
  String backup_exported(Object destination) {
    return 'バックアップを書き出しました — $destination';
  }

  @override
  String get base_url => 'ベースURL';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      'バイナリのプレビューはできません。ファイルをダウンロードして開いてください。';

  @override
  String get branch => 'ブランチ';

  @override
  String get branch_chat => 'チャットを分岐';

  @override
  String get branch_created_in_hermes_history => 'Hermes履歴にブランチを作成しました。';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      'スマホからHermes Agentのセッションを閲覧・管理できます。ローカルネットワーク上のHermesダッシュボードに接続します。';

  @override
  String get browse_server_files => 'サーバーファイルを閲覧';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      'プロジェクトの背後にあるminiserverフォルダを閲覧';

  @override
  String get cancel => 'キャンセル';

  @override
  String get cancel_voice_input => '音声入力をキャンセル';

  @override
  String cannot_reach(Object host, Object port) {
    return '$host:$port に接続できません。';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return '$host:$port に接続できません。ホストとポートを確認してください。';
  }

  @override
  String get change_ai_search_model => 'AI検索モデルを変更';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return '$labelのデフォルトを変更します。チャット内のセレクターで、その会話だけ上書きできます。';
  }

  @override
  String get chat_actions => 'チャット操作';

  @override
  String get chats => 'チャット';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      'このゲートウェイのチャットはまだグループ化されていません。ゲートウェイがプロジェクトをホストできるようになるまで、グループ化はこの端末内のみです。';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      'このプロジェクトで開始したチャットは、ここに状態と最近のアクティビティを表示します。';

  @override
  String get chats_that_are_not_assigned_to_a_project =>
      'プロジェクトに割り当てられていないチャット';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      'このプロジェクトで開始したチャットは、このHermesにサインインしているすべての端末でここに表示されます。';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      'ゲートウェイが起動していて到達可能か確認して、もう一度お試しください。';

  @override
  String get check_the_dashboard_connection_and_try_again =>
      'ダッシュボード接続を確認して、もう一度お試しください。';

  @override
  String get check_the_connection_and_try_again => '接続を確認して、もう一度お試しください。';

  @override
  String get choose_a_small_model_to_rewrite_queries => 'クエリを書き換える小型モデルを選択';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      'AI検索を使う前に、AI検索モデルを選択してください。';

  @override
  String get choose_an_active_project_next => '次にアクティブなプロジェクトを選択';

  @override
  String get choose_chat_model => 'チャットモデルを選択';

  @override
  String get choose_files => 'ファイルを選択';

  @override
  String get choose_image => '画像を選択';

  @override
  String get choose_images => '画像を選択';

  @override
  String get choose_its_destination_space => '移動先スペースを選択';

  @override
  String get clear_search => '検索をクリア';

  @override
  String get close => '閉じる';

  @override
  String get code_copied => 'コードをコピーしました';

  @override
  String get coming_next => '近日対応';

  @override
  String get command => 'コマンド';

  @override
  String get command_line_chats => 'コマンドラインのチャット';

  @override
  String get compatibility_mode => '互換モード';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      'ファイルを添付する前に、有効なDesktop Gateway URLを設定してください。';

  @override
  String get confirm_always_allow => '常に許可を確認';

  @override
  String get confirm_passphrase => 'パスフレーズを確認';

  @override
  String connecting_to(Object baseUrl) {
    return '$baseUrl に接続中…';
  }

  @override
  String get connection_issue => '接続の問題';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      '接続を切り替えました — 実行中の応答はサーバー側で継続し、自動的に再アタッチされます。';

  @override
  String get connection_appearance_and_device_preferences => '接続・外観・端末の設定';

  @override
  String context_tokens(Object effectiveContextLength) {
    return 'コンテキスト: $effectiveContextLength トークン';
  }

  @override
  String get continue_label => '続行';

  @override
  String get continue_working => '作業を続ける';

  @override
  String get conversations_in_this_project => 'このプロジェクトの会話';

  @override
  String get copy_code => 'コードをコピー';

  @override
  String get copy_message => 'メッセージをコピー';

  @override
  String could_not_branch_chat(Object error) {
    return 'チャットを分岐できませんでした: $error';
  }

  @override
  String could_not_delete_session(Object error) {
    return 'セッションを削除できませんでした: $error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return 'コマンドを拒否できませんでした: $error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return 'AI検索モデルを読み込めませんでした: $error';
  }

  @override
  String get could_not_load_conversations => '会話を読み込めませんでした';

  @override
  String get could_not_load_files => 'ファイルを読み込めませんでした';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return 'このプロファイルのモデルを読み込めませんでした: $error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return 'これ以上チャットを読み込めませんでした: $error';
  }

  @override
  String get could_not_open_the_hermes_dashboard => 'Hermesダッシュボードを開けませんでした。';

  @override
  String get could_not_open_this_project => 'このプロジェクトを開けませんでした';

  @override
  String get could_not_preview_file => 'ファイルをプレビューできませんでした';

  @override
  String get could_not_reach_hermes => 'Hermesに接続できませんでした';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return '$host:$dashboardPort のダッシュボードに到達できないか、認証に失敗しました。ポートと認証情報を確認してください。';
  }

  @override
  String get could_not_read_activity => 'アクティビティを読み込めませんでした';

  @override
  String could_not_rename_chat(Object error) {
    return 'チャット名を変更できませんでした: $error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return '承認を送信できませんでした: $error';
  }

  @override
  String get could_not_skip_the_hermes_question => 'Hermesの質問をスキップできませんでした。';

  @override
  String could_not_the_project(Object action, Object error) {
    return 'プロジェクトの$actionに失敗しました: $error';
  }

  @override
  String get couldn_t_delete_project => 'プロジェクトを削除できませんでした';

  @override
  String couldn_t_load_runs(Object error) {
    return '実行履歴を読み込めませんでした: $error';
  }

  @override
  String get couldn_t_move_conversation => '会話を移動できませんでした';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return '$labelに移動できませんでした: $reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files => '共有ファイルを準備できませんでした。';

  @override
  String get couldn_t_promote_conversation => '会話を昇格できませんでした';

  @override
  String couldn_t_project(Object action) {
    return 'プロジェクトの$actionに失敗しました';
  }

  @override
  String get create => '作成';

  @override
  String get create_a_project => 'プロジェクトを作成';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      'まずプロジェクトを作成すると、その中にチャットを置けます。';

  @override
  String get create_a_space_to_separate_related_conversations =>
      '関連する会話を分けるスペースを作成します。';

  @override
  String get create_branch => 'ブランチを作成';

  @override
  String get cron => 'Cron';

  @override
  String get cron_jobs => 'Cronジョブ';

  @override
  String get cron_job_added => 'Cronジョブを追加しました';

  @override
  String get cron_job_updated => 'Cronジョブを更新しました';

  @override
  String get cron_run => 'Cron実行';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      '端末間の並び順と、取り消し可能な一括整理';

  @override
  String get current_profile_default => '現在のプロファイルのデフォルト';

  @override
  String get custom_proxy_and_dashboard_details => 'カスタムプロキシとダッシュボードの詳細';

  @override
  String get dark => 'ダーク';

  @override
  String get dashboard_proxy_settings => 'ダッシュボード / プロキシ設定';

  @override
  String get dashboard_password_optional => 'ダッシュボードのパスワード（任意）';

  @override
  String get dashboard_port => 'ダッシュボードのポート';

  @override
  String get dashboard_username_optional => 'ダッシュボードのユーザー名（任意）';

  @override
  String get dashboard_behind_proxy => 'ダッシュボードがプロキシの背後にある';

  @override
  String get dashboard_path_prefix => 'ダッシュボードのパスプレフィックス';

  @override
  String delegated_task(Object goal) {
    return '委任されたタスク: $goal';
  }

  @override
  String get delete => '削除';

  @override
  String delete_2(Object name) {
    return '「$name」を削除しますか？';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return '「$title」をリモートのHermes履歴から削除しますか？この操作は取り消せません。';
  }

  @override
  String get delete_cron_job => 'Cronジョブを削除';

  @override
  String get delete_connections_that_are_not_in_the_backup =>
      'バックアップにない接続を削除します。';

  @override
  String delete_failed(Object error) {
    return '削除に失敗しました: $error';
  }

  @override
  String get delete_project => 'プロジェクトを削除';

  @override
  String get delete_session => 'セッションを削除しますか？';

  @override
  String delete_3(Object projectName) {
    return '$projectNameを削除しますか？';
  }

  @override
  String deleted(Object name) {
    return '「$name」を削除しました';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      '配信状況が不明です。再送せずに復旧しています…';

  @override
  String get desktop_gateway_url_optional => 'Desktop Gateway URL（任意）';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      'この接続にはDesktop Gatewayが設定されていません。';

  @override
  String get desktop_app => 'デスクトップアプリ';

  @override
  String get developer_tool_calls => '開発ツールの呼び出し';

  @override
  String get discord_chats => 'Discordのチャット';

  @override
  String get dismiss => '閉じる';

  @override
  String get do_not_run_this_command => 'このコマンドを実行しない。';

  @override
  String get documents_archives_audio_video_or_data =>
      'ドキュメント、アーカイブ、音声、動画、データなど';

  @override
  String get download => 'ダウンロード';

  @override
  String download_failed(Object error) {
    return 'ダウンロードに失敗しました: $error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you => 'Hermesが記憶している永続的な情報';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      'プロジェクト内の永続的な作業。Desktopと共有されます。';

  @override
  String get edit => '編集';

  @override
  String get edit_connection => '接続を編集';

  @override
  String get edit_cron_job => 'Cronジョブを編集';

  @override
  String get edit_gateway_connection => 'ゲートウェイ接続を編集';

  @override
  String get edit_and_resend => '編集して再送信';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      'Desktopリモートゲートウェイ経由のファイル添付を有効にします。';

  @override
  String get enter_a_name => '名前を入力';

  @override
  String get enter_a_passphrase => 'パスフレーズを入力してください。';

  @override
  String get enter_the_passphrase_for_this_backup =>
      'このバックアップのパスフレーズを入力してください。';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      'すべての会話はすでにプロジェクトに割り当てられています。';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      'まだネイティブ対応していないすべての機能（認証済みWebダッシュボード）';

  @override
  String get explain_the_attached_content_clearly => '添付コンテンツをわかりやすく説明して。';

  @override
  String explain_this_content_clearly(Object text) {
    return 'この内容をわかりやすく説明して:\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      '明示的に選ぶとAndroidのアクセシビリティ文字サイズを調整します。「システム」は変更しません。';

  @override
  String get export_label => 'エクスポート';

  @override
  String get export_share => 'エクスポート / 共有';

  @override
  String get external_api_clients => '外部APIクライアント';

  @override
  String get extra_high => '最高';

  @override
  String get extract_tasks => 'タスクを抽出';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      '添付コンテンツから、決定事項・締め切り・担当者・実行可能なアクション項目を抽出して。';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return 'この内容から、決定事項・締め切り・担当者・実行可能なアクション項目を抽出して:\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return 'ジョブの追加に失敗しました: $error';
  }

  @override
  String get failed_to_load_cron_jobs => 'Cronジョブを読み込めませんでした';

  @override
  String get failed_to_load_memory => 'メモリを読み込めませんでした';

  @override
  String get failed_to_load_messages => 'メッセージを読み込めませんでした';

  @override
  String get failed_to_load_settings => '設定を読み込めませんでした';

  @override
  String get failed_to_load_skills => 'スキルを読み込めませんでした';

  @override
  String failed_to_update_job(Object error) {
    return 'ジョブの更新に失敗しました: $error';
  }

  @override
  String failed(Object error) {
    return '失敗: $error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      'ファイルを添付しました。ドキュメントカタログへの登録は保留中です。';

  @override
  String get file_reference_added_to_chat => 'ファイル参照をチャットに追加しました';

  @override
  String get files => 'ファイル';

  @override
  String get fill_from_document => '書類から記入';

  @override
  String get folder_is_empty => 'フォルダは空です';

  @override
  String get folders => 'フォルダ';

  @override
  String get full_text => '全文';

  @override
  String get gateway_api_access => 'ゲートウェイAPIアクセス';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      'ゲートウェイには接続しましたが、ダッシュボードに到達できないか認証に失敗しました。ダッシュボードの設定を確認するか、空にしてスキップしてください。';

  @override
  String get gateway_path_prefix => 'ゲートウェイのパスプレフィックス';

  @override
  String get go_to_end => '末尾へ';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Hermes Agent for Android';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'Hermesが回答を受け付けられませんでした。もう一度お試しください。';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      '保存された接続を読み込めませんでした';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'Hermesが応答を受け付けませんでした。もう一度お試しください。';

  @override
  String get hermes_is_responding => 'Hermesが応答中…';

  @override
  String get hermes_is_waiting_for_input => 'Hermesが入力を待っています…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'HermesはAndroidのアクセシビリティ文字拡大を有効に保ちます。';

  @override
  String get hermes_needs_your_input => 'Hermesが入力を求めています';

  @override
  String get hermes_profile_optional => 'Hermesプロファイル（任意）';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'Hermesプロファイルは「sol」のような単純な名前で入力してください。パスは使えません。';

  @override
  String get hermes_reasoning_details => 'Hermesの推論の詳細';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'Hermesの復旧は利用できません: $error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'Hermesはプロンプトを再送せず、安全に復旧を停止しました。';

  @override
  String get hide_passphrase => 'パスフレーズを隠す';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      'ホームで最近のチャットを表示するには接続が必要です。ゲートウェイに到達できるか確認して、もう一度お試しください。';

  @override
  String get host => 'ホスト';

  @override
  String get image_selection_was_interrupted_try_again =>
      '画像の選択が中断されました。もう一度お試しください。';

  @override
  String get import_label => 'インポート';

  @override
  String get inbox => '受信トレイ';

  @override
  String get inbox_is_clear => '受信トレイは空です';

  @override
  String get insert_a_remote_file_reference => 'リモートの@file参照を挿入';

  @override
  String get invalid_port_number => 'ポート番号が無効です。';

  @override
  String get job_paused => 'ジョブを一時停止しました';

  @override
  String get job_resumed => 'ジョブを再開しました';

  @override
  String get job_triggered => 'ジョブを実行しました';

  @override
  String get label => 'ラベル';

  @override
  String last_activity(Object day, Object month, Object year) {
    return '最終アクティビティ $year/$month/$day';
  }

  @override
  String last(Object lastRun) {
    return '前回: $lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      '空欄でデフォルト（8642、https時は443）';

  @override
  String get leave_blank_for_default_9119 => '空欄でデフォルト（9119）';

  @override
  String get light => 'ライト';

  @override
  String listening(Object elapsed) {
    return '聞き取り中 • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return '聞き取り中、経過 $elapsed';
  }

  @override
  String get load_more => 'もっと読み込む…';

  @override
  String get loading => '読み込み中';

  @override
  String get location => '場所';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      'ゲートウェイAPIサーバーが起動していることを確認してください\n（hermes gateway status）';

  @override
  String matches(Object assigned, Object name) {
    return '$name に一致 · $assigned';
  }

  @override
  String get memory => 'メモリ';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'メモリは、エージェントが記憶するセッション横断の事実です。\n~/.hermes/config.yaml で設定します';

  @override
  String get merge => 'マージ';

  @override
  String get message => 'メッセージ';

  @override
  String get message_hermes => 'Hermesにメッセージ…';

  @override
  String get message_actions => 'メッセージ操作';

  @override
  String get message_copied => 'メッセージをコピーしました';

  @override
  String get migrating => '移行中…';

  @override
  String get migration_complete => '移行完了';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      '移行に失敗しました。ローカルスペースは変更されていません。';

  @override
  String get migration_incomplete => '移行未完了';

  @override
  String get migration_preview => '移行プレビュー';

  @override
  String get model => 'モデル';

  @override
  String get model_and_thinking_for_this_chat => 'このチャットのモデルと思考';

  @override
  String model_was_not_changed(Object error) {
    return 'モデルは変更されませんでした: $error';
  }

  @override
  String get move_attachment_next => '添付を次へ移動';

  @override
  String get move_attachment_previous => '添付を前へ移動';

  @override
  String get move_chat => 'チャットを移動';

  @override
  String get move_conversation => '会話を移動';

  @override
  String get move_to_project => 'プロジェクトへ移動';

  @override
  String get move_to_space => 'スペースへ移動';

  @override
  String get moved_to_a_project => 'プロジェクトに移動しました';

  @override
  String moved_to(Object label) {
    return '$labelに移動しました';
  }

  @override
  String get name => '名前';

  @override
  String get name_prompt_and_schedule_are_required => '名前・プロンプト・スケジュールは必須です';

  @override
  String get nav_activity => '活動';

  @override
  String get nav_projects => '案件';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Hermesゲートウェイに訂正対応の仕分けコントラクトが必要です。';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      '到達可能なHermesダッシュボードが必要です。この接続のホスト・ポート・認証情報を確認してください。';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Hermesゲートウェイにサーバー権威のアセットインデックスが必要です。';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Hermesゲートウェイに永続的なピン順序・バッチ変更・取り消しのコントラクトが必要です。';

  @override
  String get needs_you => '対応が必要';

  @override
  String get new_label => '新規';

  @override
  String get new_chat => '新しいチャット';

  @override
  String get new_chat_2 => '新しいチャット';

  @override
  String new_chat_3(Object projectName) {
    return '新しいチャット · $projectName';
  }

  @override
  String get new_project => '新しいプロジェクト';

  @override
  String get new_space => '新しいスペース';

  @override
  String next(Object nextRun) {
    return '次回: $nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'Nginxが認証を付与 — アプリは素のリクエストを送信';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      'TTS音声が見つかりません。\nGoogle Text-to-Speechをインストールして音声データをダウンロードしてください。';

  @override
  String get no_active_projects_on_this_gateway =>
      'このゲートウェイにアクティブなプロジェクトはありません';

  @override
  String get no_activity_yet => 'まだアクティビティはありません';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      '対応が必要なチャットも、実行中・再開待ちのチャットもありません。準備ができたら新しいチャットを始めましょう。';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return 'このプロジェクトに「$searchQuery」に一致するチャットはありません。';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      'このスペースにはまだチャットがありません。+ をタップして開始してください。';

  @override
  String get no_chats_yet => 'まだチャットはありません';

  @override
  String get no_connections => '接続がありません';

  @override
  String get no_conversation_matches_this_view => 'このビューに一致する会話はありません。';

  @override
  String get no_cron_jobs => 'Cronジョブはありません';

  @override
  String get no_folders_yet => 'まだフォルダはありません';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      'この接続にローカルスペースは見つかりませんでした。プロジェクトがすでに唯一の整理手段として使われています。';

  @override
  String get no_matches => '一致なし';

  @override
  String get no_memory_entries => 'メモリエントリはありません';

  @override
  String get no_message_content_matches => 'メッセージ内容に一致はありません';

  @override
  String get no_new_messages => '新しいメッセージはありません';

  @override
  String get no_projects_yet => 'まだプロジェクトはありません';

  @override
  String get no_runs_yet => 'まだ実行履歴はありません。';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return 'この名前に一致するサーバープロジェクトはありません · $assigned';
  }

  @override
  String get no_sessions_yet => 'まだセッションはありません';

  @override
  String get no_skills_found => 'スキルが見つかりません';

  @override
  String get no_spaces_on_this_device => 'この端末にスペースはありません';

  @override
  String get no_text_shared => '共有されたテキストはありません';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      '保留中・実行中・最近完了したターンはありません。開始した作業はここに表示されます。';

  @override
  String get no_turn_needs_your_input_or_has_failed =>
      '入力が必要なターンや失敗したターンはありません。';

  @override
  String get no_unassigned_chats => '未割り当てのチャットはありません。';

  @override
  String get nothing_changed_in_the_last_seven_days => '過去7日間に変更はありません。';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      'まだ何も移動していません — これは移行のプレビューです。';

  @override
  String get nothing_here => 'ここには何もありません';

  @override
  String get nothing_is_running => '実行中のものはありません';

  @override
  String get nothing_needs_you => '対応が必要なものはありません';

  @override
  String get nothing_to_migrate => '移行するものはありません';

  @override
  String get off_no_thinking => 'オフ（思考なし）';

  @override
  String get offline_showing_the_last_known_activity =>
      'オフライン — 最後に確認できたアクティビティを表示中。';

  @override
  String get offline_showing_the_last_known_chats => 'オフライン — 最後に確認できたチャットを表示中';

  @override
  String get offline_showing_the_last_known_projects =>
      'オフライン — 最後に確認できたプロジェクトを表示中。';

  @override
  String get on_this_device => 'この端末内';

  @override
  String get on_device => '端末内';

  @override
  String get open_inbox => '受信トレイを開く';

  @override
  String open_inbox_2(Object count) {
    return '受信トレイを開く（$count）';
  }

  @override
  String get open_the_hermes_dashboard => 'Hermesダッシュボードを開く';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      '任意。メモリ/Cron/スキル/設定タブで使用します。空欄のままにすると、デフォルトのダッシュボードポート（9119）をログインなしで使用します。';

  @override
  String get organization => '整理';

  @override
  String get other_answer => 'その他の回答';

  @override
  String get overview => '概要';

  @override
  String get passphrase => 'パスフレーズ';

  @override
  String get password_optional => 'パスワード（任意）';

  @override
  String get phone_or_tablet => 'スマホまたはタブレット';

  @override
  String get pin_batch_and_undo => 'ピン留め・一括操作・取り消し';

  @override
  String get port => 'ポート';

  @override
  String get preparing_attachments => '添付を準備中…';

  @override
  String get preview_truncated => 'プレビューは省略表示';

  @override
  String get preview_unavailable => 'プレビュー不可';

  @override
  String get profile => 'プロファイル';

  @override
  String get profile_default_model => 'プロファイルのデフォルトモデル';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return 'プロファイルのデフォルトを$selectedModelに設定しました。独自のモデルを使うチャットはそのまま維持されます。';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      'ダッシュボードが複数のプロファイルを提供する場合に、この接続がどのプロファイルとしてチャットするか。空欄にするとプロファイルごとに分離されたダッシュボードになります。';

  @override
  String get project => 'プロジェクト';

  @override
  String get project_actions => 'プロジェクト操作';

  @override
  String get project_chat => 'プロジェクトチャット';

  @override
  String get project_chats_unavailable => 'プロジェクトのチャットを利用できません';

  @override
  String get projects => 'プロジェクト';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      'プロジェクトは関連するチャット・ファイル・アクティビティをまとめ、お使いのPC上のHermesと同期します。';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      'プロジェクトにはDesktop Gateway接続が必要です。この接続にDesktop Gateway URLを追加すると、端末間でチャットを整理できます。';

  @override
  String get projects_unavailable => 'プロジェクトを利用できません';

  @override
  String get projects_activity_new_navigation => 'プロジェクト、アクティビティ — 新しいナビゲーション';

  @override
  String get promote_to_project => 'プロジェクトに昇格';

  @override
  String get prompt => 'プロンプト';

  @override
  String get protect_this_backup => 'このバックアップを保護';

  @override
  String get provider => 'プロバイダー';

  @override
  String get proxy_injects_auth_app_sends_clean_requests =>
      'プロキシが認証を付与; アプリは素のリクエストを送信';

  @override
  String get quick_chat => 'クイックチャット';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      'クイックチャットは保持期間を過ぎるとここに表示されます。';

  @override
  String get read_aloud => '読み上げ';

  @override
  String get read_aloud_is_unavailable_on_this_device => 'この端末では読み上げを利用できません';

  @override
  String get reading_response_aloud => '応答を読み上げ中';

  @override
  String get ready_to_upload => 'アップロード準備完了';

  @override
  String get reasoning => '推論';

  @override
  String get recently_completed => '最近完了';

  @override
  String get recovering_hermes => 'Hermesを復旧中…';

  @override
  String get refresh => '更新';

  @override
  String get regenerate_response => '応答を再生成';

  @override
  String get remove_attachment => '添付を削除';

  @override
  String get rename => '名前を変更';

  @override
  String get rename_chat => 'チャット名を変更';

  @override
  String get rename_project => 'プロジェクト名を変更';

  @override
  String get rename_space => 'スペース名を変更';

  @override
  String rename_2(Object projectName) {
    return '$projectNameの名前を変更';
  }

  @override
  String rename_3(Object name) {
    return '$nameの名前を変更';
  }

  @override
  String get replace => '置き換え';

  @override
  String get repositories => 'リポジトリ';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      '添付コンテンツを調査し、重要な主張を検証して、出典を引用して。';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return 'この内容を調査し、重要な主張を検証して、出典を引用して:\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return 'リセットに失敗しました: $retryError。セキュアストレージの再インストールが必要かもしれません。';
  }

  @override
  String get reset_saved_connections => '保存された接続をリセット';

  @override
  String get responding => '応答中…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return '応答はローカルで終了しましたが、ゲートウェイの停止に失敗しました: $error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      '応答はローカルで終了しました。アクティブなゲートウェイターンは見つかりませんでした。';

  @override
  String get response_ready => '応答が完了';

  @override
  String get response_stopped => '応答を停止しました。';

  @override
  String get restore => '復元';

  @override
  String get restore_configuration => '設定を復元';

  @override
  String get restore_project => 'プロジェクトを復元';

  @override
  String get retry => '再試行';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return '$nameの再試行に失敗しました。ドラフトとプロンプトは保持されています。';
  }

  @override
  String get retry_upload => 'アップロードを再試行';

  @override
  String retrying(Object name) {
    return '$nameを再試行中…';
  }

  @override
  String get review_local_spaces => 'ローカルスペースを確認';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      '保持期間を過ぎたクイックチャットを確認または昇格';

  @override
  String get review_the_attached_content => '添付コンテンツを確認して。';

  @override
  String get run_only_this_command => 'このコマンドだけを実行します。';

  @override
  String get running_now => '実行中';

  @override
  String get save => '保存';

  @override
  String get save_changes => '変更を保存';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      'Hermes設定に永続的なルールを保存します。';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      '添付コンテンツの永続的な事実をメモリに保存し、保存された内容を確認して。';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return 'この内容の永続的な事実をメモリに保存し、保存された内容を確認して:\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      '接続と設定を暗号化ファイルに保存し、再インストール後や別の端末で復元できます。';

  @override
  String save_2(Object filename) {
    return '$filenameを保存';
  }

  @override
  String get schedule => 'スケジュール';

  @override
  String get scheduled_jobs_and_their_last_runs => 'スケジュールされたジョブと前回の実行';

  @override
  String get scheduled_tasks => 'スケジュールされたタスク';

  @override
  String get script_only_no_agent => 'スクリプトのみ（エージェントなし）';

  @override
  String get scroll_horizontally => '横にスクロール';

  @override
  String get search_all_chats => 'すべてのチャットを検索';

  @override
  String get search_all_message_content => '全メッセージ内容を検索';

  @override
  String get search_chats => 'チャットを検索';

  @override
  String get search_conversations => '会話を検索';

  @override
  String get search_loaded_chats => '読み込み済みチャットを検索';

  @override
  String get search_mode => '検索モード';

  @override
  String get select_one_option_or_enter_another_answer =>
      '1つ選択するか、別の回答を入力してください。';

  @override
  String get select_one_or_more_options_then_continue => '1つ以上選択して続行してください。';

  @override
  String get select_text => 'テキストを選択';

  @override
  String get send => '送信';

  @override
  String send_failed(Object error) {
    return '送信に失敗しました: $error';
  }

  @override
  String get send_message => 'メッセージを送信';

  @override
  String get session_sources => 'セッションのソース';

  @override
  String get session_deleted_from_remote_hermes => 'リモートのHermesからセッションを削除しました。';

  @override
  String session_search_failed(Object error) {
    return 'セッション検索に失敗しました: $error';
  }

  @override
  String get set_profile_default => 'プロファイルのデフォルトに設定';

  @override
  String get settings => '設定';

  @override
  String get share_to_hermes => 'Hermesに共有';

  @override
  String get show_passphrase => 'パスフレーズを表示';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      'ツール呼び出し・思考・メッセージのメタデータを表示';

  @override
  String get signal_messages => 'Signalのメッセージ';

  @override
  String get skills => 'スキル';

  @override
  String skills_2(Object count) {
    return 'スキル（$count）';
  }

  @override
  String get skills_and_tools => 'スキルとツール';

  @override
  String get skip => 'スキップ';

  @override
  String get slack_chats => 'Slackのチャット';

  @override
  String source(Object source) {
    return 'ソース: $source';
  }

  @override
  String get space_actions => 'スペース操作';

  @override
  String get spaces => 'スペース';

  @override
  String get speak_to_hermes => 'Hermesに話しかける';

  @override
  String get speech_recognition_is_unavailable => '音声認識を利用できません';

  @override
  String get spoken_replies => '読み上げ応答';

  @override
  String get spoken_replies_off => '読み上げオフ';

  @override
  String get spoken_replies_on => '読み上げオン';

  @override
  String get stalled_no_update_from_hermes => '停滞 — Hermesからの更新がありません';

  @override
  String get start_something_new => '新しく始める';

  @override
  String get start_voice_input => '音声入力を開始';

  @override
  String get starting_hermes => 'Hermesを起動中…';

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
  String get still_loading_your_projects => 'プロジェクトを読み込み中です。';

  @override
  String get stop => '停止';

  @override
  String get stop_response => '応答を停止';

  @override
  String get stop_voice_input => '音声入力を停止';

  @override
  String get submitted_waiting_for_hermes => '送信済み、Hermesの応答待ち';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      'プロジェクトを提案し、あなたの修正から学習します';

  @override
  String get summarize_the_attached_content => '添付コンテンツを要約して。';

  @override
  String summarize_this_content(Object text) {
    return 'この内容を要約して:\n\n$text';
  }

  @override
  String get switch_profile => 'プロファイルを切り替え';

  @override
  String get system => 'システム';

  @override
  String get take_photo => '写真を撮る';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      '+ をタップしてリモートHermesゲートウェイを追加\n（APIサーバー、ポート8642）';

  @override
  String get tap_the_button_to_start_a_new_chat => '+ ボタンをタップして新しいチャットを開始';

  @override
  String get telegram_messages => 'Telegramのメッセージ';

  @override
  String get terminal_sessions => 'ターミナルセッション';

  @override
  String get text_size => '文字サイズ';

  @override
  String get text_size_preview => '文字サイズのプレビュー';

  @override
  String text_size_2(Object label) {
    return '文字サイズ: $label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely => 'APIキーを安全に保存できませんでした。';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      'プロジェクトはアーカイブ済みに移動します。チャットとファイルはそのまま残り、いつでも復元できます。';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      'プロジェクトはアーカイブ済みに移動します。チャットとファイルはそのまま残り、後で復元できます。';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      'アクティブなプロファイルに選択可能なモデルがありません。';

  @override
  String get the_backup_could_not_be_exported => 'バックアップを書き出せませんでした。';

  @override
  String get the_backup_could_not_be_restored => 'バックアップを復元できませんでした。';

  @override
  String get the_connection_could_not_be_deleted_safely => '接続を安全に削除できませんでした。';

  @override
  String get the_connection_could_not_be_stored_securely => '接続を安全に保存できませんでした。';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      'ダッシュボードの認証情報を安全に保存できませんでした。';

  @override
  String get the_detached_reply_failed => '切り離された応答が失敗しました。';

  @override
  String the_detached_reply_failed_2(Object error) {
    return '切り離された応答が失敗しました: $error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      'このファイルにはAPIキーとダッシュボードのパスワードが含まれるため、暗号化されます。このパスフレーズがないとバックアップを復元できません。';

  @override
  String get the_last_turn_failed => '最後のターンが失敗しました';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return 'ローカルの接続ストアが破損しているようです（$errorType）。保存された接続をリセットして最初からやり直せます。ゲートウェイ上のチャットは影響を受けません。';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      'モデルは質問を短い全文検索クエリに書き換えるだけです。Hermesはホスト側に設定済みのプロバイダー認証情報を使用します。';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      'サーバーはまだこのプロジェクトのフォルダを報告していません。グローバルなファイルは「その他」から引き続き利用できます。';

  @override
  String get the_turn_failed => 'ターンが失敗しました';

  @override
  String get the_two_passphrases_do_not_match => '2つのパスフレーズが一致しません。';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      '入力した値はアクティブなHermesゲートウェイに直接送信され、このAndroidアプリには保存されません。';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      'このサーバーフォルダに見えるファイルはありません。';

  @override
  String get thinking_effort => '思考の強度';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      'このHermesゲートウェイはまだプロジェクトを開く機能に対応していません。サーバー上のHermesを更新すると、スマホからプロジェクトを閲覧できます。';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      'このHermesゲートウェイはサーバーサイドプロジェクトより古いため、チャットのグループ化はこの端末内のみになります。端末間で同じプロジェクトを共有するにはHermesを更新してください。';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      'このプロジェクトにはチャットを開くためのフォルダがありません — 未割り当てとして開きました。チャットをまとめるにはプロジェクトにフォルダを追加してください。';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      'このチャットには、まだDesktopセッションで利用できるメッセージがありません。';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      'Hermesに永続的なルールを作成します。確認する前にコマンド全体を確認してください。';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      'このゲートウェイはまだプロジェクトをホストしていません。端末間でチャットを整理するにはゲートウェイを更新してください。';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      'プロジェクトを完全に削除します。チャットは削除されず、未割り当てに戻ります。';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      'このサーバーはバックグラウンド復旧に対応していません — チャットはライブで実行されます';

  @override
  String get this_week => '今週';

  @override
  String get titles_previews_and_models => 'タイトル・プレビュー・モデル';

  @override
  String get tool_activity => 'ツールのアクティビティ';

  @override
  String get trigger_now => '今すぐ実行';

  @override
  String get turn_completed => 'ターン完了';

  @override
  String get turn_recovery_failed => 'ターンの復旧に失敗しました';

  @override
  String get unable_to_prepare_this_file_try_another_one =>
      'このファイルを準備できませんでした。別のファイルをお試しください。';

  @override
  String get unable_to_prepare_this_image_try_another_one =>
      'この画像を準備できませんでした。別の画像をお試しください。';

  @override
  String unable_to_prepare(Object name) {
    return '$nameを準備できませんでした。';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      '選択した画像を読み込めませんでした。選択内容は保持されています。';

  @override
  String get unassigned => '未割り当て';

  @override
  String get unassigned_chats => '未割り当てのチャット';

  @override
  String get untitled_chat => '無題のチャット';

  @override
  String get untitled_session => '無題のセッション';

  @override
  String get update_api_key => 'APIキーを更新';

  @override
  String get upload_failed => 'アップロード失敗';

  @override
  String get upload_failed_tap_retry => 'アップロード失敗 • タップで再試行';

  @override
  String uploading(Object index, Object name, Object total) {
    return 'アップロード中 $index/$total: $name';
  }

  @override
  String get use_as_is => 'そのまま使用';

  @override
  String get use_at_least_8_characters => '8文字以上で入力してください。';

  @override
  String get use_for_cron_jobs_backed_by_scripts => 'スクリプトで実行するCronジョブ向けです。';

  @override
  String get use_on_device => '端末内で使用';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      '添付コンテンツを使って、関連する書類やフォームの項目を特定して記入して。送信する前には必ず確認して。';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return 'この内容を使って、関連する書類やフォームの項目を特定して記入して。送信する前には必ず確認して:\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      'Settings・Memory・Skills・Cronタブや、ホスト型のパスプレフィックスで使用します。ユーザー名/パスワードが空欄の場合はオープンなダッシュボードとして扱われ、リバースプロキシがダッシュボード認証を付与する場合はプロキシモードを有効にしてください。';

  @override
  String get username_optional => 'ユーザー名（任意）';

  @override
  String using(Object displayName) {
    return '$displayNameを使用中…';
  }

  @override
  String get verbose_mode => '詳細モード';

  @override
  String get voice => '音声';

  @override
  String voice_setup_failed(Object error) {
    return '音声のセットアップに失敗しました: $error';
  }

  @override
  String get waiting_for_your_input => '入力待ち';

  @override
  String get what_hermes_knows_how_to_do => 'Hermesにできること';

  @override
  String get what_should_the_agent_do => 'エージェントに何をさせますか？';

  @override
  String get whatsapp_messages => 'WhatsAppのメッセージ';

  @override
  String get which_project => 'どのプロジェクト？';

  @override
  String get workspace => 'ワークスペース';

  @override
  String get wrap_lines => '折り返し';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return '最大$maxRemoteAttachmentDrafts個まで添付できます。';
  }

  @override
  String get your_answer => '回答';

  @override
  String get e_g_dashboard => '例: /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      '例: /dashboard（/api/ より前のプロキシパス）';

  @override
  String get e_g_profile_peter => '例: /profile/peter';

  @override
  String get e_g_sol => '例: sol';

  @override
  String get e_g_0_9_or_every_2h => '例: 0 9 * * * または every 2h';

  @override
  String get e_g_daily_backup => '例: 毎日のバックアップ';

  @override
  String downloaded(Object filename) {
    return '$filenameをダウンロードしました';
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
      '192.168.1.50、100.x.y.z、または hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      '例: /profile/peter（/api/ と /v1/ より前のプロキシパス）';

  @override
  String and_more(Object count) {
    return 'ほか$count件';
  }

  @override
  String chats_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'チャット$count件',
    );
    return '$_temp0';
  }

  @override
  String on_this_device_only(Object chats) {
    return '$chats · この端末のみ';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'スペース$count件',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => '新しいプロジェクトは不要';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'プロジェクトを$count件作成',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return '$linkedSessions件のチャットを移行 · $createdProjects件のプロジェクトを作成';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '$unlinkedSessions件のチャットはローカルスペースに残ります。安全に再試行できます。';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • 推奨: 小型で低コスト';
  }

  @override
  String session_meta(Object count, Object model, Object time) {
    return '$count件のメッセージ • $model • $time';
  }

  @override
  String model_scope_label(Object model, Object scope) {
    return '$model • $scope';
  }

  @override
  String get this_chat => 'このチャット';

  @override
  String get profile_default => 'プロファイルのデフォルト';

  @override
  String minutes_ago(Object count) {
    return '$count分前';
  }

  @override
  String hours_ago(Object count) {
    return '$count時間前';
  }

  @override
  String days_ago(Object count) {
    return '$count日前';
  }

  @override
  String get now_label => 'たった今';

  @override
  String get latest_label => '最新';

  @override
  String new_count_indicator(Object count) {
    return '新着$count件';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '新着メッセージ$count件',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return '$failures件失敗 • 全$total件';
  }

  @override
  String activity_completed_summary(Object count) {
    return '$count件完了';
  }

  @override
  String get hermes_is_using_a_tool => 'Hermesがツールを使用中';

  @override
  String hermes_is_using_tools(Object count) {
    return 'Hermesが$count個のツールを使用中';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return '委任タスク$count件が完了';
  }

  @override
  String delegated_tasks_active(Object count) {
    return '委任タスク$count件が実行中';
  }

  @override
  String branch_main(Object label) {
    return '$label · main';
  }

  @override
  String get you_heading => '## あなた';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => 'アクション';

  @override
  String get destination_label => '移動先';

  @override
  String get preview_label => 'プレビュー';

  @override
  String get share_action_summarize => '要約';

  @override
  String get share_action_explain => '説明';

  @override
  String get share_action_research => '調査';

  @override
  String get share_action_remember => '記憶';

  @override
  String get text_size_small => '小';

  @override
  String get text_size_default => '標準';

  @override
  String get text_size_large => '大';

  @override
  String get text_size_extra_large => '特大';

  @override
  String get text_size_use_system_description =>
      'Androidのアクセシビリティ文字サイズをそのまま使用します。';

  @override
  String text_size_percent_description(Object percent) {
    return 'Androidの文字サイズの$percent%';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return '$count件のファイルをスキップしました: 上限・サイズ・読み取り不可・機密ファイル名';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort はこのチャットのみに適用されます。';
  }

  @override
  String get reasoning_minimal => '最小';

  @override
  String get reasoning_low => '低';

  @override
  String get reasoning_medium => '中';

  @override
  String get reasoning_high => '高';

  @override
  String get reasoning_max => '最大';

  @override
  String get reasoning_ultra => 'ウルトラ';

  @override
  String get status_running => '実行中';

  @override
  String get status_failed => '失敗';

  @override
  String get status_done => '完了';

  @override
  String get status_idle => '待機中';

  @override
  String get upload_status_uploading => 'アップロード中';

  @override
  String get upload_status_uploaded => 'アップロード済み';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '添付$count件',
    );
    return '$_temp0';
  }

  @override
  String get action_create => '作成';

  @override
  String get action_rename => '名前の変更';

  @override
  String get action_archive => 'アーカイブ';

  @override
  String get action_restore => '復元';

  @override
  String get action_delete => '削除';

  @override
  String get migrate => '移行';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '割り当て済みチャット$count件',
    );
    return '$_temp0';
  }

  @override
  String get date_today => '今日';

  @override
  String get date_yesterday => '昨日';

  @override
  String get date_earlier => 'それ以前';

  @override
  String get nav_home => 'ホーム';

  @override
  String get nav_more => 'その他';

  @override
  String get status_completed => '完了';

  @override
  String get filter_all => 'すべて';

  @override
  String get filter_recent => '最近';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  キー: $status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model  \n`$provider` 経由';
  }

  @override
  String get deny => '拒否';

  @override
  String get connect => '接続';

  @override
  String get appearance => '外観';

  @override
  String get connection_section => '接続';

  @override
  String get about => 'このアプリ';

  @override
  String version_label(Object version) {
    return 'バージョン $version';
  }

  @override
  String get matched => '一致';

  @override
  String get search => '検索';

  @override
  String get on => 'オン';

  @override
  String get off => 'オフ';

  @override
  String get reasoning_off => 'オフ';

  @override
  String get hermes_response_ready => 'Hermesの応答';

  @override
  String get admin_password_needed => '管理者パスワードが必要です';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      '保留中のターミナルコマンドの実行にsudoパスワードが必要です。';

  @override
  String get sudo_password => 'sudoパスワード';

  @override
  String get secret_needed => 'シークレットが必要です';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      '保留中のスキルの実行にシークレットが必要です。';

  @override
  String get secret_value => 'シークレットの値';

  @override
  String get attached_file => '添付ファイル';
}
