// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      '一次性问题。将在 72 小时后自动归档；任何值得保留的内容都会被记住。';

  @override
  String get ai_full_text => 'AI + 全文';

  @override
  String get ai_search_model => 'AI 搜索模型';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'AI 已搜索：$aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'AI 辅助归档';

  @override
  String get api_key => 'API 密钥';

  @override
  String get api_server_key_from_hermes_env =>
      '来自 ~/.hermes/.env 的 API_SERVER_KEY';

  @override
  String get active => '活跃';

  @override
  String get activity => '活动';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      '活动功能会读取持久化轮次日志以了解 Hermes 正在执行的操作。请检查网关是否可访问，然后重试。';

  @override
  String get add => '添加';

  @override
  String get add_connection => '添加连接';

  @override
  String get add_cron_job => '添加 Cron 任务';

  @override
  String get add_gateway_connection => '添加网关连接';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      '从备份中添加和更新连接，其余保持不变。';

  @override
  String get add_attachment => '添加附件';

  @override
  String get add_new_cron_job => '添加新 Cron 任务';

  @override
  String get add_to_chat => '添加到聊天';

  @override
  String get all_chats => '所有聊天';

  @override
  String get all_stored_message_content => '所有已存储的消息内容';

  @override
  String get allow_for_this_session => '本次会话允许';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      '在此 Hermes 会话结束前允许匹配的命令。';

  @override
  String get allow_once => '允许一次';

  @override
  String get always_allow => '总是允许';

  @override
  String get apply_to_this_chat => '应用到此聊天';

  @override
  String get approval_needed => '需要审批';

  @override
  String get archive => '归档';

  @override
  String get archive_project => '归档项目';

  @override
  String archive_2(Object projectName) {
    return '归档 $projectName？';
  }

  @override
  String archive_3(Object name) {
    return '归档 $name？';
  }

  @override
  String get archived => '已归档';

  @override
  String get archived_conversations_appear_here => '已归档的对话将显示在这里。';

  @override
  String get archived_quick_chats => '已归档的快速聊天';

  @override
  String get artifacts_attachments_and_generated_media => '构件、附件和生成的内容';

  @override
  String get ask_ai_to_find_a_conversation => '让 AI 查找对话';

  @override
  String get assets => '资产';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      '资产需要在 Hermes 网关中建立服务器权威资产索引，然后才能按项目显示。';

  @override
  String get assets_unavailable => '资产不可用';

  @override
  String get attach_image_or_file => '附加图片或文件';

  @override
  String get attachment_drafts => '附件草稿';

  @override
  String attachment_of(Object index, Object total) {
    return '附件 $index / $total';
  }

  @override
  String get auto_device_default => '自动（设备默认）';

  @override
  String get auto_archives_after_72_hours => '72 小时后自动归档';

  @override
  String get automation => '自动化';

  @override
  String get autonomous_agents => '自主智能体';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      '后台恢复不可用 — 旧版传输';

  @override
  String get backup_restore => '备份与恢复';

  @override
  String backup_exported(Object destination) {
    return '备份已导出 — $destination';
  }

  @override
  String get base_url => '基础 URL';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      '二进制预览不可用。请下载文件后打开。';

  @override
  String get branch => '分支';

  @override
  String get branch_chat => '分支聊天';

  @override
  String get branch_created_in_hermes_history => '已在 Hermes 历史记录中创建分支。';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      '通过手机浏览和管理你的 Hermes Agent 会话。连接至运行在本地网络上的 Hermes 仪表盘。';

  @override
  String get browse_server_files => '浏览服务器文件';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      '浏览项目背后的 miniserver 文件夹';

  @override
  String get cancel => '取消';

  @override
  String get cancel_voice_input => '取消语音输入';

  @override
  String cannot_reach(Object host, Object port) {
    return '无法连接至 $host:$port。';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return '无法连接至 $host:$port。请检查主机和端口。';
  }

  @override
  String get change_ai_search_model => '更改 AI 搜索模型';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return '更改 $label 的默认值。在聊天中使用选择器可仅覆盖当前对话。';
  }

  @override
  String get chat_actions => '聊天操作';

  @override
  String get chats => '聊天';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      '此网关中的聊天尚未分组。分组状态将保留在此手机上，直到网关能够托管项目。';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      '此项目中的聊天将在此处显示其状态和最后活动。';

  @override
  String get chats_that_are_not_assigned_to_a_project => '未分配至项目的聊天';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      '你在此项目中发起的聊天将显示在此处，并同步到登录此 Hermes 的所有设备上。';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      '请检查网关是否正在运行且可达，然后重试。';

  @override
  String get check_the_dashboard_connection_and_try_again => '请检查仪表盘连接并重试。';

  @override
  String get check_the_connection_and_try_again => '请检查连接并重试。';

  @override
  String get choose_a_small_model_to_rewrite_queries => '选择一个小模型来重写查询';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      '请在使用 AI 搜索前选择一个 AI 搜索模型。';

  @override
  String get choose_an_active_project_next => '接下来选择一个活动项目';

  @override
  String get choose_chat_model => '选择聊天模型';

  @override
  String get choose_files => '选择文件';

  @override
  String get choose_image => '选择图片';

  @override
  String get choose_images => '选择图片';

  @override
  String get choose_its_destination_space => '选择其目标空间';

  @override
  String get clear_search => '清除搜索';

  @override
  String get close => '关闭';

  @override
  String get code_copied => '代码已复制';

  @override
  String get coming_next => '敬请期待';

  @override
  String get command => '命令';

  @override
  String get command_line_chats => '命令行聊天';

  @override
  String get compatibility_mode => '兼容模式';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      '在附加文件前，请先配置有效的 Desktop Gateway URL。';

  @override
  String get confirm_always_allow => '确认始终允许';

  @override
  String get confirm_passphrase => '确认密码短语';

  @override
  String connecting_to(Object baseUrl) {
    return '正在连接至 $baseUrl...';
  }

  @override
  String get connection_issue => '连接问题';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      '连接已切换 — 正在进行的回复将在服务器上继续，并会自动重新附加。';

  @override
  String get connection_appearance_and_device_preferences => '连接、外观和设备偏好设置';

  @override
  String context_tokens(Object effectiveContextLength) {
    return '上下文：$effectiveContextLength Token';
  }

  @override
  String get continue_label => '继续';

  @override
  String get continue_working => '继续工作';

  @override
  String get conversations_in_this_project => '此项目中的对话';

  @override
  String get copy_code => '复制代码';

  @override
  String get copy_message => '复制消息';

  @override
  String could_not_branch_chat(Object error) {
    return '无法创建聊天分支：$error';
  }

  @override
  String could_not_delete_session(Object error) {
    return '无法删除会话：$error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return '无法拒绝该命令：$error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return '无法加载 AI 搜索模型：$error';
  }

  @override
  String get could_not_load_conversations => '无法加载对话';

  @override
  String get could_not_load_files => '无法加载文件';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return '无法为该配置档案加载模型：$error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return '无法加载更多聊天：$error';
  }

  @override
  String get could_not_open_the_hermes_dashboard => '无法打开 Hermes 仪表盘。';

  @override
  String get could_not_open_this_project => '无法打开此项目';

  @override
  String get could_not_preview_file => '无法预览文件';

  @override
  String get could_not_reach_hermes => '无法连接至 Hermes';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return '无法连接/验证位于 $host:$dashboardPort 的仪表盘。请检查端口和凭据。';
  }

  @override
  String get could_not_read_activity => '无法读取活动';

  @override
  String could_not_rename_chat(Object error) {
    return '无法重命名聊天：$error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return '无法发送审批：$error';
  }

  @override
  String get could_not_skip_the_hermes_question => '无法跳过 Hermes 的问题。';

  @override
  String could_not_the_project(Object action, Object error) {
    return '无法 $action 该项目：$error';
  }

  @override
  String get couldn_t_delete_project => '无法删除项目';

  @override
  String couldn_t_load_runs(Object error) {
    return '无法加载运行记录：$error';
  }

  @override
  String get couldn_t_move_conversation => '无法移动对话';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return '无法移动至 $label：$reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files => '无法准备共享文件。';

  @override
  String get couldn_t_promote_conversation => '无法提升会话';

  @override
  String couldn_t_project(Object action) {
    return '无法 $action 项目';
  }

  @override
  String get create => '创建';

  @override
  String get create_a_project => '创建项目';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      '请先创建一个项目，聊天内容即可存放在其中。';

  @override
  String get create_a_space_to_separate_related_conversations =>
      '创建一个空间以区分相关的聊天。';

  @override
  String get create_branch => '创建分支';

  @override
  String get cron => 'Cron';

  @override
  String get cron_jobs => 'Cron 任务';

  @override
  String get cron_job_added => 'Cron 任务已添加';

  @override
  String get cron_job_updated => 'Cron 任务已更新';

  @override
  String get cron_run => 'Cron 运行';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      '跨设备排序与可撤销的批量整理';

  @override
  String get current_profile_default => '当前配置档案默认值';

  @override
  String get custom_proxy_and_dashboard_details => '自定义代理与仪表盘详情';

  @override
  String get dark => '深色';

  @override
  String get dashboard_proxy_settings => '仪表盘 / 代理设置';

  @override
  String get dashboard_password_optional => '仪表盘密码（可选）';

  @override
  String get dashboard_port => '仪表盘端口';

  @override
  String get dashboard_username_optional => '仪表盘用户名（可选）';

  @override
  String get dashboard_behind_proxy => '位于代理后的仪表盘';

  @override
  String get dashboard_path_prefix => '仪表盘路径前缀';

  @override
  String delegated_task(Object goal) {
    return '委派任务：$goal';
  }

  @override
  String get delete => '删除';

  @override
  String delete_2(Object name) {
    return '删除“$name”？';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return '从远程 Hermes 历史记录中删除“$title”？此操作不可撤销。';
  }

  @override
  String get delete_cron_job => '删除 Cron 任务';

  @override
  String get delete_connections_that_are_not_in_the_backup => '删除不在备份中的连接。';

  @override
  String delete_failed(Object error) {
    return '删除失败：$error';
  }

  @override
  String get delete_project => '删除项目';

  @override
  String get delete_session => '删除会话？';

  @override
  String delete_3(Object projectName) {
    return '删除 $projectName？';
  }

  @override
  String deleted(Object name) {
    return '已删除“$name”';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      '发送状态不确定；正在恢复且不重新发送……';

  @override
  String get desktop_gateway_url_optional => 'Desktop Gateway URL（可选）';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      '此连接未配置 Desktop Gateway。';

  @override
  String get desktop_app => '桌面应用';

  @override
  String get developer_tool_calls => '开发者工具调用';

  @override
  String get discord_chats => 'Discord 聊天';

  @override
  String get dismiss => '忽略';

  @override
  String get do_not_run_this_command => '请勿运行此命令。';

  @override
  String get documents_archives_audio_video_or_data => '文档、压缩包、音频、视频或数据';

  @override
  String get download => '下载';

  @override
  String download_failed(Object error) {
    return '下载失败：$error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you => 'Hermes 记录的关于你的持久事实';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      '项目内的持久工作内容，已与 Desktop 共享。';

  @override
  String get edit => '编辑';

  @override
  String get edit_connection => '编辑连接';

  @override
  String get edit_cron_job => '编辑 Cron 任务';

  @override
  String get edit_gateway_connection => '编辑网关连接';

  @override
  String get edit_and_resend => '编辑并重发';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      '允许通过 Desktop 远程网关发送文件附件。';

  @override
  String get enter_a_name => '输入名称';

  @override
  String get enter_a_passphrase => '请输入密码短语。';

  @override
  String get enter_the_passphrase_for_this_backup => '请输入此备份的密码短语。';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      '所有对话均已分配至某个项目。';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      '所有尚未原生支持的功能，均可在已认证的 Web 仪表盘中查看';

  @override
  String get explain_the_attached_content_clearly => '清晰解释附件内容。';

  @override
  String explain_this_content_clearly(Object text) {
    return '清晰解释此内容：\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      '显式选择将调整 Android 无障碍文字大小；选择“系统”则保持不变。';

  @override
  String get export_label => '导出';

  @override
  String get export_share => '导出 / 分享';

  @override
  String get external_api_clients => '外部 API 客户端';

  @override
  String get extra_high => '极高';

  @override
  String get extract_tasks => '提取任务';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      '从附件内容中提取决策、截止日期、负责人以及可执行的操作项。';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return '从以下内容中提取决策、截止日期、负责人以及可执行的操作项：\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return '添加任务失败：$error';
  }

  @override
  String get failed_to_load_cron_jobs => '加载 Cron 任务失败';

  @override
  String get failed_to_load_memory => '加载记忆失败';

  @override
  String get failed_to_load_messages => '加载消息失败';

  @override
  String get failed_to_load_settings => '加载设置失败';

  @override
  String get failed_to_load_skills => '加载技能失败';

  @override
  String failed_to_update_job(Object error) {
    return '更新任务失败：$error';
  }

  @override
  String failed(Object error) {
    return '失败：$error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      '已添加文件附件；文档目录注册正在等待处理。';

  @override
  String get file_reference_added_to_chat => '文件引用已添加至聊天';

  @override
  String get files => '文件';

  @override
  String get fill_from_document => '从文档填充';

  @override
  String get folder_is_empty => '文件夹为空';

  @override
  String get folders => '文件夹';

  @override
  String get full_text => '全文';

  @override
  String get gateway_api_access => '网关 API 访问';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      '网关已连接，但无法访问仪表盘或未能通过身份验证。请检查仪表盘详细信息，或清除它们以跳过。';

  @override
  String get gateway_path_prefix => '网关路径前缀';

  @override
  String get go_to_end => '转到末尾';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Android 版 Hermes Agent';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'Hermes 无法接受此回答，请重试。';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      'Hermes 无法加载你保存的连接';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'Hermes 未能接受此响应，请重试。';

  @override
  String get hermes_is_responding => 'Hermes 正在响应…';

  @override
  String get hermes_is_waiting_for_input => 'Hermes 正在等待输入…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'Hermes 保持 Android 辅助功能文字缩放处于活动状态。';

  @override
  String get hermes_needs_your_input => 'Hermes 需要你的输入';

  @override
  String get hermes_profile_optional => 'Hermes 配置档案（可选）';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'Hermes 配置档案必须是纯粹的档案名称（例如 “sol”），而不能是路径。';

  @override
  String get hermes_reasoning_details => 'Hermes 推理详情';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'Hermes 恢复不可用：$error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'Hermes 已安全停止恢复。未重新发送任何提示词。';

  @override
  String get hide_passphrase => '隐藏密码短语';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      '首页需要你最近的聊天记录来了解哪些内容值得你关注。请检查网关是否可达，然后重试。';

  @override
  String get host => '主机';

  @override
  String get image_selection_was_interrupted_try_again => '图片选择被中断，请重试。';

  @override
  String get import_label => '导入';

  @override
  String get inbox => '收件箱';

  @override
  String get inbox_is_clear => '收件箱为空';

  @override
  String get insert_a_remote_file_reference => '插入远程 @file 引用';

  @override
  String get invalid_port_number => '无效的端口号。';

  @override
  String get job_paused => '任务已暂停';

  @override
  String get job_resumed => '任务已恢复';

  @override
  String get job_triggered => '任务已触发';

  @override
  String get label => '标签';

  @override
  String last_activity(Object day, Object month, Object year) {
    return '最后活动于 $year年$month月$day日';
  }

  @override
  String last(Object lastRun) {
    return '最后运行：$lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      '留空则使用默认值（8642；使用 https 时为 443）';

  @override
  String get leave_blank_for_default_9119 => '留空则使用默认值 (9119)';

  @override
  String get light => '浅色';

  @override
  String listening(Object elapsed) {
    return '正在聆听 • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return '正在聆听，已耗时 $elapsed';
  }

  @override
  String get load_more => '加载更多…';

  @override
  String get loading => '正在加载';

  @override
  String get location => '位置';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      '请确保网关 API Server 正在运行\n(hermes gateway status)';

  @override
  String matches(Object assigned, Object name) {
    return '匹配项 $name · $assigned';
  }

  @override
  String get memory => '记忆';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      '记忆条目是 Agent 跨会话记住的事实。\n它们在 ~/.hermes/config.yaml 中进行配置';

  @override
  String get merge => '合并';

  @override
  String get message => '消息';

  @override
  String get message_hermes => '给 Hermes 发消息…';

  @override
  String get message_actions => '消息操作';

  @override
  String get message_copied => '已复制消息';

  @override
  String get migrating => '正在迁移…';

  @override
  String get migration_complete => '迁移完成';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      '迁移失败。本地空间保持不变。';

  @override
  String get migration_incomplete => '迁移未完成';

  @override
  String get migration_preview => '迁移预览';

  @override
  String get model => '模型';

  @override
  String get model_and_thinking_for_this_chat => '此聊天的模型和思考状态';

  @override
  String model_was_not_changed(Object error) {
    return '模型未更改：$error';
  }

  @override
  String get move_attachment_next => '将附件移至下一个';

  @override
  String get move_attachment_previous => '将附件移至上一个';

  @override
  String get move_chat => '移动聊天';

  @override
  String get move_conversation => '移动会话';

  @override
  String get move_to_project => '移动到项目';

  @override
  String get move_to_space => '移动到空间';

  @override
  String get moved_to_a_project => '已移动到项目';

  @override
  String moved_to(Object label) {
    return '已移动到 $label';
  }

  @override
  String get name => '名称';

  @override
  String get name_prompt_and_schedule_are_required => '名称、提示词和计划均为必填项';

  @override
  String get nav_activity => '活动';

  @override
  String get nav_projects => '项目';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Hermes 网关中需要具备支持纠错感知的文件归档契约。';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      '需要可访问的 Hermes 仪表盘。请检查此连接的主机、端口和凭据。';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Hermes 网关中需要具备服务端权威的资产索引。';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Hermes 网关中需要具备持久化的置顶排序、批量变更和撤销契约。';

  @override
  String get needs_you => '需要你';

  @override
  String get new_label => '新';

  @override
  String get new_chat => '新聊天';

  @override
  String get new_chat_2 => '新聊天';

  @override
  String new_chat_3(Object projectName) {
    return '新聊天 · $projectName';
  }

  @override
  String get new_project => '新建项目';

  @override
  String get new_space => '新建空间';

  @override
  String next(Object nextRun) {
    return '下次运行：$nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'Nginx 注入认证 — 应用发送干净请求';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      '未找到 TTS 语音。\n请安装 Google Text-to-Speech 并下载语音数据。';

  @override
  String get no_active_projects_on_this_gateway => '此网关上暂无活动项目';

  @override
  String get no_activity_yet => '暂无活动';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      '没有被阻塞、运行中或等待恢复的聊天。准备好后随时可以开始新聊天。';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return '此项目中没有与“$searchQuery”匹配的聊天。';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      '此空间暂无聊天。轻点 + 开始聊天。';

  @override
  String get no_chats_yet => '暂无聊天';

  @override
  String get no_connections => '无连接';

  @override
  String get no_conversation_matches_this_view => '没有与此视图匹配的对话。';

  @override
  String get no_cron_jobs => '暂无 Cron 任务';

  @override
  String get no_folders_yet => '暂无文件夹';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      '在此连接中未找到本地空间，因此项目已是此处的唯一组织方式。';

  @override
  String get no_matches => '无匹配项';

  @override
  String get no_memory_entries => '暂无记忆条目';

  @override
  String get no_message_content_matches => '无匹配的消息内容';

  @override
  String get no_new_messages => '暂无新消息';

  @override
  String get no_projects_yet => '暂无项目';

  @override
  String get no_runs_yet => '暂无运行记录。';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return '没有与此名称匹配的服务端项目 · $assigned';
  }

  @override
  String get no_sessions_yet => '暂无会话';

  @override
  String get no_skills_found => '未找到技能';

  @override
  String get no_spaces_on_this_device => '此设备上无空间';

  @override
  String get no_text_shared => '未共享文本';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      '没有被阻塞、进行中或最近完成的轮次。你开始的工作会显示在这里。';

  @override
  String get no_turn_needs_your_input_or_has_failed => '没有需要你输入或失败的轮次。';

  @override
  String get no_unassigned_chats => '暂无未分配的聊天。';

  @override
  String get nothing_changed_in_the_last_seven_days => '最近七天无更改。';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      '尚未移动任何内容 — 这只是迁移将执行的操作。';

  @override
  String get nothing_here => '这里什么也没有';

  @override
  String get nothing_is_running => '没有正在运行的内容';

  @override
  String get nothing_needs_you => '一切正常，无需处理';

  @override
  String get nothing_to_migrate => '无需迁移';

  @override
  String get off_no_thinking => '关闭（无思考）';

  @override
  String get offline_showing_the_last_known_activity => '离线 — 显示最后已知的活动。';

  @override
  String get offline_showing_the_last_known_chats => '离线 — 显示最后已知的聊天';

  @override
  String get offline_showing_the_last_known_projects => '离线 — 正在显示最后已知的项目。';

  @override
  String get on_this_device => '此设备上';

  @override
  String get on_device => '端侧';

  @override
  String get open_inbox => '打开收件箱';

  @override
  String open_inbox_2(Object count) {
    return '打开收件箱（$count）';
  }

  @override
  String get open_the_hermes_dashboard => '打开 Hermes 仪表盘';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      '可选。用于“记忆”、“Cron”、“技能”、“设置”标签页。留空则使用默认仪表盘端口（9119）且无需登录。';

  @override
  String get organization => '组织';

  @override
  String get other_answer => '其他回答';

  @override
  String get overview => '概览';

  @override
  String get passphrase => '密码短语';

  @override
  String get password_optional => '密码（可选）';

  @override
  String get phone_or_tablet => '手机或平板电脑';

  @override
  String get pin_batch_and_undo => '置顶、批量操作与撤销';

  @override
  String get port => '端口';

  @override
  String get preparing_attachments => '正在准备附件…';

  @override
  String get preview_truncated => '预览已截断';

  @override
  String get preview_unavailable => '预览不可用';

  @override
  String get profile => '配置档案';

  @override
  String get profile_default_model => '配置档案默认模型';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return '配置档案默认值已设为 $selectedModel。拥有独立模型的聊天将保留该覆盖设置。';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      '当仪表盘服务于多个配置档案时，为此连接的聊天指定配置档案。留空则使用独立的单配置档案仪表盘。';

  @override
  String get project => '项目';

  @override
  String get project_actions => '项目操作';

  @override
  String get project_chat => '项目聊天';

  @override
  String get project_chats_unavailable => '项目聊天不可用';

  @override
  String get projects => '项目';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      '项目将相关的聊天、文件和活动进行分组，并与你电脑上的 Hermes 保持同步。';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      '项目需要 Desktop Gateway 连接。请将 Desktop Gateway URL 添加到此连接，以便跨设备管理聊天。';

  @override
  String get projects_unavailable => '项目不可用';

  @override
  String get projects_activity_new_navigation => '项目、活动 — 新导航';

  @override
  String get promote_to_project => '提升为项目';

  @override
  String get prompt => '提示词';

  @override
  String get protect_this_backup => '保护此备份';

  @override
  String get provider => '提供方';

  @override
  String get proxy_injects_auth_app_sends_clean_requests => '代理注入认证信息；应用发送纯净请求';

  @override
  String get quick_chat => '快速聊天';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      '快速聊天将在保留期过后显示在此处。';

  @override
  String get read_aloud => '朗读';

  @override
  String get read_aloud_is_unavailable_on_this_device => '此设备不支持朗读功能';

  @override
  String get reading_response_aloud => '正在朗读回复';

  @override
  String get ready_to_upload => '准备上传';

  @override
  String get reasoning => '推理';

  @override
  String get recently_completed => '最近完成';

  @override
  String get recovering_hermes => '正在恢复 Hermes…';

  @override
  String get refresh => '刷新';

  @override
  String get regenerate_response => '重新生成回复';

  @override
  String get remove_attachment => '移除附件';

  @override
  String get rename => '重命名';

  @override
  String get rename_chat => '重命名聊天';

  @override
  String get rename_project => '重命名项目';

  @override
  String get rename_space => '重命名空间';

  @override
  String rename_2(Object projectName) {
    return '重命名 $projectName';
  }

  @override
  String rename_3(Object name) {
    return '重命名 $name';
  }

  @override
  String get replace => '替换';

  @override
  String get repositories => '代码库';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      '研究附件内容，核实重要主张并引用来源。';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return '研究此内容，核实重要主张并引用来源：\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return '重置失败：$retryError。安全存储可能需要重新安装。';
  }

  @override
  String get reset_saved_connections => '重置已保存的连接';

  @override
  String get responding => '正在响应…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return '响应已在本地关闭；网关停止失败：$error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      '响应已在本地关闭；未找到活动的网关轮次。';

  @override
  String get response_ready => '回复就绪';

  @override
  String get response_stopped => '回复已停止。';

  @override
  String get restore => '恢复';

  @override
  String get restore_configuration => '恢复配置';

  @override
  String get restore_project => '恢复项目';

  @override
  String get retry => '重试';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return '$name 重试失败。草稿和提示词已保留。';
  }

  @override
  String get retry_upload => '重试上传';

  @override
  String retrying(Object name) {
    return '正在重试 $name…';
  }

  @override
  String get review_local_spaces => '检查本地空间';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      '查看或提升超出保留期限的快速聊天';

  @override
  String get review_the_attached_content => '查看附件内容。';

  @override
  String get run_only_this_command => '仅运行此命令。';

  @override
  String get running_now => '正在运行';

  @override
  String get save => '保存';

  @override
  String get save_changes => '保存更改';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      '在 Hermes 配置中保存永久规则。';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      '将附件内容中的持久事实保存到记忆中，然后确认保留的内容。';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return '将此内容中的持久事实保存到记忆中，然后确认保留的内容：\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      '将连接与设置保存到加密文件中，以便在重新安装或在其他设备上时恢复它们。';

  @override
  String save_2(Object filename) {
    return '保存 $filename';
  }

  @override
  String get schedule => '计划';

  @override
  String get scheduled_jobs_and_their_last_runs => '计划任务及其最近运行情况';

  @override
  String get scheduled_tasks => '计划任务';

  @override
  String get script_only_no_agent => '仅脚本（无 Agent）';

  @override
  String get scroll_horizontally => '水平滚动';

  @override
  String get search_all_chats => '搜索所有聊天';

  @override
  String get search_all_message_content => '搜索所有消息内容';

  @override
  String get search_chats => '搜索聊天';

  @override
  String get search_conversations => '搜索对话';

  @override
  String get search_loaded_chats => '搜索已加载的聊天';

  @override
  String get search_mode => '搜索模式';

  @override
  String get select_one_option_or_enter_another_answer => '选择一个选项，或输入其他答案。';

  @override
  String get select_one_or_more_options_then_continue => '选择一个或多个选项，然后继续。';

  @override
  String get select_text => '选择文本';

  @override
  String get send => '发送';

  @override
  String send_failed(Object error) {
    return '发送失败：$error';
  }

  @override
  String get send_message => '发送消息';

  @override
  String get session_sources => '会话来源';

  @override
  String get session_deleted_from_remote_hermes => '已从远程 Hermes 中删除会话。';

  @override
  String session_search_failed(Object error) {
    return '会话搜索失败：$error';
  }

  @override
  String get set_profile_default => '设为默认配置档案';

  @override
  String get settings => '设置';

  @override
  String get share_to_hermes => '分享到 Hermes';

  @override
  String get show_passphrase => '显示密码短语';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      '显示工具调用、思考过程和消息元数据';

  @override
  String get signal_messages => 'Signal 消息';

  @override
  String get skills => '技能';

  @override
  String skills_2(Object count) {
    return '技能（$count）';
  }

  @override
  String get skills_and_tools => '技能与工具';

  @override
  String get skip => '跳过';

  @override
  String get slack_chats => 'Slack 聊天';

  @override
  String source(Object source) {
    return '来源：$source';
  }

  @override
  String get space_actions => '空间操作';

  @override
  String get spaces => '空间';

  @override
  String get speak_to_hermes => '对 Hermes 说话';

  @override
  String get speech_recognition_is_unavailable => '语音识别不可用';

  @override
  String get spoken_replies => '语音回复';

  @override
  String get spoken_replies_off => '语音回复已关闭';

  @override
  String get spoken_replies_on => '语音回复已开启';

  @override
  String get stalled_no_update_from_hermes => '已停滞 — 未收到来自 Hermes 的更新';

  @override
  String get start_something_new => '开启新任务';

  @override
  String get start_voice_input => '开始语音输入';

  @override
  String get starting_hermes => '正在启动 Hermes…';

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
  String get still_loading_your_projects => '正在加载你的项目。';

  @override
  String get stop => '停止';

  @override
  String get stop_response => '停止响应';

  @override
  String get stop_voice_input => '停止语音输入';

  @override
  String get submitted_waiting_for_hermes => '已提交，等待 Hermes 响应';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      '建议项目并从你的更正中学习';

  @override
  String get summarize_the_attached_content => '总结附件内容。';

  @override
  String summarize_this_content(Object text) {
    return '总结此内容：\n\n$text';
  }

  @override
  String get switch_profile => '切换配置档案';

  @override
  String get system => '系统';

  @override
  String get take_photo => '拍照';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      '点击 + 添加远程 Hermes 网关\n(API Server，端口 8642)';

  @override
  String get tap_the_button_to_start_a_new_chat => '点击 + 按钮开始新的聊天';

  @override
  String get telegram_messages => 'Telegram 消息';

  @override
  String get terminal_sessions => '终端会话';

  @override
  String get text_size => '文字大小';

  @override
  String get text_size_preview => '文字大小预览';

  @override
  String text_size_2(Object label) {
    return '文字大小：$label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely => '无法安全存储 API 密钥。';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      '该项目将移至“已归档”。其聊天和文件将保持完整，你可以随时恢复它。';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      '该项目将移至“已归档”。其聊天和文件将保持完整，你可以稍后恢复它。';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      '当前配置档案未返回任何可选模型。';

  @override
  String get the_backup_could_not_be_exported => '无法导出备份。';

  @override
  String get the_backup_could_not_be_restored => '无法恢复备份。';

  @override
  String get the_connection_could_not_be_deleted_safely => '无法安全删除连接。';

  @override
  String get the_connection_could_not_be_stored_securely => '无法安全存储连接。';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      '无法安全存储仪表盘凭据。';

  @override
  String get the_detached_reply_failed => '已分离的回复失败。';

  @override
  String the_detached_reply_failed_2(Object error) {
    return '已分离的回复失败：$error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      '该文件包含你的 API 密钥和仪表盘密码，因此已加密。没有此密码短语，备份将无法恢复。';

  @override
  String get the_last_turn_failed => '上一轮对话失败';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return '本地连接存储似乎已损坏 ($errorType)。你可以重置已保存的连接并重新开始。网关上的聊天记录不受影响。';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      '该模型仅将你的问题重写为简短的全文查询。Hermes 使用已在主机上配置的提供方凭据。';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      '服务器尚未报告此项目的文件夹。全局文件仍可在“更多”中查看。';

  @override
  String get the_turn_failed => '本轮对话失败';

  @override
  String get the_two_passphrases_do_not_match => '两次输入的密码短语不匹配。';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      '该值将直接发送至当前活动的 Hermes 网关，不会被此 Android 应用保存。';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      '此服务器文件夹中没有可见文件。';

  @override
  String get thinking_effort => '思考强度';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      '此 Hermes 网关尚不支持打开项目。请更新服务器上的 Hermes 以在手机上浏览项目。';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      '此 Hermes 网关版本旧于服务端项目功能，因此聊天仅在此设备上分组。请更新 Hermes 以在多台设备间共享相同项目。';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      '此项目没有可用于打开聊天的文件夹 —— 已默认设为未分配。请为项目添加文件夹以便对聊天进行分组。';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      '此聊天在 Desktop 会话中暂无可用消息。';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      '这将在 Hermes 中创建永久规则。确认前请仔细检查完整命令。';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      '此网关尚不支持托管项目。请更新网关以在各设备间整理聊天。';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      '这将永久删除该项目。聊天记录不会被删除；它们将返回至未分配状态。';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      '此服务器不提供后台恢复功能 —— 聊天实时运行';

  @override
  String get this_week => '本周';

  @override
  String get titles_previews_and_models => '标题、预览与模型';

  @override
  String get tool_activity => '工具活动';

  @override
  String get trigger_now => '立即触发';

  @override
  String get turn_completed => '本轮对话已完成';

  @override
  String get turn_recovery_failed => '对话恢复失败';

  @override
  String get unable_to_prepare_this_file_try_another_one => '无法准备此文件，请尝试其他文件。';

  @override
  String get unable_to_prepare_this_image_try_another_one => '无法准备此图片，请尝试其他图片。';

  @override
  String unable_to_prepare(Object name) {
    return '无法准备 $name。';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      '无法读取所选图片，已保留当前选择。';

  @override
  String get unassigned => '未分配';

  @override
  String get unassigned_chats => '未分配的聊天';

  @override
  String get untitled_chat => '未命名聊天';

  @override
  String get untitled_session => '未命名会话';

  @override
  String get update_api_key => '更新 API 密钥';

  @override
  String get upload_failed => '上传失败';

  @override
  String get upload_failed_tap_retry => '上传失败 • 点击重试';

  @override
  String uploading(Object index, Object name, Object total) {
    return '正在上传 $index/$total：$name';
  }

  @override
  String get use_as_is => '直接使用';

  @override
  String get use_at_least_8_characters => '请使用至少 8 个字符。';

  @override
  String get use_for_cron_jobs_backed_by_scripts => '用于由脚本支持的 Cron 任务。';

  @override
  String get use_on_device => '使用设备端';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      '使用附件内容识别并填写相关文档或表单字段。提交任何内容前请先询问。';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return '使用此内容识别并填写相关文档或表单字段。提交任何内容前请先询问：\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      '用于托管路径前缀以及“设置”、“记忆”、“技能”和“Cron”标签页。若需开放仪表盘，可将用户名/密码留空；若反向代理已注入仪表盘认证，请启用代理模式。';

  @override
  String get username_optional => '用户名（可选）';

  @override
  String using(Object displayName) {
    return '正在使用 $displayName…';
  }

  @override
  String get verbose_mode => '详细模式';

  @override
  String get voice => '语音';

  @override
  String voice_setup_failed(Object error) {
    return '语音设置失败：$error';
  }

  @override
  String get waiting_for_your_input => '等待你的输入';

  @override
  String get what_hermes_knows_how_to_do => 'Hermes 能够做的事情';

  @override
  String get what_should_the_agent_do => '要让 Agent 做什么？';

  @override
  String get whatsapp_messages => 'WhatsApp 消息';

  @override
  String get which_project => '哪个项目？';

  @override
  String get workspace => '工作区';

  @override
  String get wrap_lines => '自动换行';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return '最多可附加 $maxRemoteAttachmentDrafts 个项目。';
  }

  @override
  String get your_answer => '你的回答';

  @override
  String get e_g_dashboard => '例如 /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      '例如 /dashboard（/api/ 之前的代理路径）';

  @override
  String get e_g_profile_peter => '例如 /profile/peter';

  @override
  String get e_g_sol => '例如 sol';

  @override
  String get e_g_0_9_or_every_2h => '例如 0 9 * * * 或 every 2h';

  @override
  String get e_g_daily_backup => '例如每日备份';

  @override
  String downloaded(Object filename) {
    return '已下载 $filename';
  }

  @override
  String activity_name_status(Object displayName, Object statusLabel) {
    return '$displayName：$statusLabel';
  }

  @override
  String connection_status_label(Object connectionLabel, Object label) {
    return '$connectionLabel $label';
  }

  @override
  String get example_host_hint =>
      '192.168.1.50、100.x.y.z 或 hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      '例如 /profile/peter（/api/ 和 /v1/ 之前的代理路径）';

  @override
  String and_more(Object count) {
    return '以及另外 $count 个';
  }

  @override
  String chats_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个聊天',
    );
    return '$_temp0';
  }

  @override
  String on_this_device_only(Object chats) {
    return '$chats · 仅在此设备上';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个空间',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => '无需创建新项目';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 个项目待创建',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return '已迁移 $linkedSessions 个聊天 · 已创建 $createdProjects 个项目';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '$unlinkedSessions 个聊天保留在本地空间中，可安全重试。';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • 推荐：小巧且经济';
  }

  @override
  String session_meta(Object count, Object model, Object time) {
    return '$count 条消息 • $model • $time';
  }

  @override
  String model_scope_label(Object model, Object scope) {
    return '$model • $scope';
  }

  @override
  String get this_chat => '此聊天';

  @override
  String get profile_default => '配置档案默认值';

  @override
  String minutes_ago(Object count) {
    return '$count 分钟前';
  }

  @override
  String hours_ago(Object count) {
    return '$count 小时前';
  }

  @override
  String days_ago(Object count) {
    return '$count 天前';
  }

  @override
  String get now_label => '刚刚';

  @override
  String get latest_label => '最新';

  @override
  String new_count_indicator(Object count) {
    return '$count 条新消息';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条新消息',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return '$failures 个失败 • 共 $total 个';
  }

  @override
  String activity_completed_summary(Object count) {
    return '已完成 $count 个';
  }

  @override
  String get hermes_is_using_a_tool => 'Hermes 正在使用工具';

  @override
  String hermes_is_using_tools(Object count) {
    return 'Hermes 正在使用 $count 个工具';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return '已完成 $count 个委派任务';
  }

  @override
  String delegated_tasks_active(Object count) {
    return '$count 个委派任务进行中';
  }

  @override
  String branch_main(Object label) {
    return '$label · main';
  }

  @override
  String get you_heading => '## 你';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => '操作';

  @override
  String get destination_label => '目标';

  @override
  String get preview_label => '预览';

  @override
  String get share_action_summarize => '总结';

  @override
  String get share_action_explain => '解释';

  @override
  String get share_action_research => '研究';

  @override
  String get share_action_remember => '记住';

  @override
  String get text_size_small => '小';

  @override
  String get text_size_default => '默认';

  @override
  String get text_size_large => '大';

  @override
  String get text_size_extra_large => '特大';

  @override
  String get text_size_use_system_description => '完全使用 Android 辅助功能文字大小。';

  @override
  String text_size_percent_description(Object percent) {
    return 'Android 文字大小的 $percent%。';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return '已跳过 $count 个文件：超出限制、大小超限、无法读取或文件名包含敏感信息。';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort 现仅应用于此聊天。';
  }

  @override
  String get reasoning_minimal => '极简';

  @override
  String get reasoning_low => '低';

  @override
  String get reasoning_medium => '中';

  @override
  String get reasoning_high => '高';

  @override
  String get reasoning_max => '最大';

  @override
  String get reasoning_ultra => '极致';

  @override
  String get status_running => '运行中';

  @override
  String get status_failed => '已失败';

  @override
  String get status_done => '完成';

  @override
  String get status_idle => '空闲';

  @override
  String get upload_status_uploading => '正在上传';

  @override
  String get upload_status_uploaded => '已上传';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个附件',
    );
    return '$_temp0';
  }

  @override
  String get action_create => '创建';

  @override
  String get action_rename => '重命名';

  @override
  String get action_archive => '归档';

  @override
  String get action_restore => '恢复';

  @override
  String get action_delete => '删除';

  @override
  String get migrate => '迁移';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个已分配聊天',
    );
    return '$_temp0';
  }

  @override
  String get date_today => '今天';

  @override
  String get date_yesterday => '昨天';

  @override
  String get date_earlier => '更早';

  @override
  String get nav_home => '主页';

  @override
  String get nav_more => '更多';

  @override
  String get status_completed => '已完成';

  @override
  String get filter_all => '全部';

  @override
  String get filter_recent => '最近';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  密钥：$status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model  \n通过 `$provider`';
  }

  @override
  String get deny => '拒绝';

  @override
  String get connect => '连接';

  @override
  String get appearance => '外观';

  @override
  String get connection_section => '连接';

  @override
  String get about => '关于';

  @override
  String version_label(Object version) {
    return '版本 $version';
  }

  @override
  String get matched => '已匹配';

  @override
  String get search => '搜索';

  @override
  String get on => '开';

  @override
  String get off => '关';

  @override
  String get reasoning_off => '关';

  @override
  String get hermes_response_ready => 'Hermes 回复已就绪';

  @override
  String get admin_password_needed => '需要管理员密码';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      'Hermes 需要 sudo 密码来执行挂起的终端命令。';

  @override
  String get sudo_password => 'sudo 密码';

  @override
  String get secret_needed => '需要密钥';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      'Hermes 需要为待处理的技能提供一个密钥。';

  @override
  String get secret_value => '密钥值';

  @override
  String get attached_file => '已附加文件';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      '一次性问题。将在 72 小时后自动归档；任何值得保留的内容都会被记住。';

  @override
  String get ai_full_text => 'AI + 全文';

  @override
  String get ai_search_model => 'AI 搜索模型';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'AI 已搜索：$aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'AI 辅助归档';

  @override
  String get api_key => 'API 密钥';

  @override
  String get api_server_key_from_hermes_env =>
      '来自 ~/.hermes/.env 的 API_SERVER_KEY';

  @override
  String get active => '活跃';

  @override
  String get activity => '活动';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      '活动功能会读取持久化轮次日志以了解 Hermes 正在执行的操作。请检查网关是否可访问，然后重试。';

  @override
  String get add => '添加';

  @override
  String get add_connection => '添加连接';

  @override
  String get add_cron_job => '添加 Cron 任务';

  @override
  String get add_gateway_connection => '添加网关连接';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      '从备份中添加和更新连接，其余保持不变。';

  @override
  String get add_attachment => '添加附件';

  @override
  String get add_new_cron_job => '添加新 Cron 任务';

  @override
  String get add_to_chat => '添加到聊天';

  @override
  String get all_chats => '所有聊天';

  @override
  String get all_stored_message_content => '所有已存储的消息内容';

  @override
  String get allow_for_this_session => '本次会话允许';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      '在此 Hermes 会话结束前允许匹配的命令。';

  @override
  String get allow_once => '允许一次';

  @override
  String get always_allow => '总是允许';

  @override
  String get apply_to_this_chat => '应用到此聊天';

  @override
  String get approval_needed => '需要审批';

  @override
  String get archive => '归档';

  @override
  String get archive_project => '归档项目';

  @override
  String archive_2(Object projectName) {
    return '归档 $projectName？';
  }

  @override
  String archive_3(Object name) {
    return '归档 $name？';
  }

  @override
  String get archived => '已归档';

  @override
  String get archived_conversations_appear_here => '已归档的对话将显示在这里。';

  @override
  String get archived_quick_chats => '已归档的快速聊天';

  @override
  String get artifacts_attachments_and_generated_media => '构件、附件和生成的内容';

  @override
  String get ask_ai_to_find_a_conversation => '让 AI 查找对话';

  @override
  String get assets => '资产';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      '资产需要在 Hermes 网关中建立服务器权威资产索引，然后才能按项目显示。';

  @override
  String get assets_unavailable => '资产不可用';

  @override
  String get attach_image_or_file => '附加图片或文件';

  @override
  String get attachment_drafts => '附件草稿';

  @override
  String attachment_of(Object index, Object total) {
    return '附件 $index / $total';
  }

  @override
  String get auto_device_default => '自动（设备默认）';

  @override
  String get auto_archives_after_72_hours => '72 小时后自动归档';

  @override
  String get automation => '自动化';

  @override
  String get autonomous_agents => '自主智能体';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      '后台恢复不可用 — 旧版传输';

  @override
  String get backup_restore => '备份与恢复';

  @override
  String backup_exported(Object destination) {
    return '备份已导出 — $destination';
  }

  @override
  String get base_url => '基础 URL';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      '二进制预览不可用。请下载文件后打开。';

  @override
  String get branch => '分支';

  @override
  String get branch_chat => '分支聊天';

  @override
  String get branch_created_in_hermes_history => '已在 Hermes 历史记录中创建分支。';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      '通过手机浏览和管理你的 Hermes Agent 会话。连接至运行在本地网络上的 Hermes 仪表盘。';

  @override
  String get browse_server_files => '浏览服务器文件';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      '浏览项目背后的 miniserver 文件夹';

  @override
  String get cancel => '取消';

  @override
  String get cancel_voice_input => '取消语音输入';

  @override
  String cannot_reach(Object host, Object port) {
    return '无法连接至 $host:$port。';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return '无法连接至 $host:$port。请检查主机和端口。';
  }

  @override
  String get change_ai_search_model => '更改 AI 搜索模型';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return '更改 $label 的默认值。在聊天中使用选择器可仅覆盖当前对话。';
  }

  @override
  String get chat_actions => '聊天操作';

  @override
  String get chats => '聊天';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      '此网关中的聊天尚未分组。分组状态将保留在此手机上，直到网关能够托管项目。';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      '此项目中的聊天将在此处显示其状态和最后活动。';

  @override
  String get chats_that_are_not_assigned_to_a_project => '未分配至项目的聊天';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      '你在此项目中发起的聊天将显示在此处，并同步到登录此 Hermes 的所有设备上。';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      '请检查网关是否正在运行且可达，然后重试。';

  @override
  String get check_the_dashboard_connection_and_try_again => '请检查仪表盘连接并重试。';

  @override
  String get check_the_connection_and_try_again => '请检查连接并重试。';

  @override
  String get choose_a_small_model_to_rewrite_queries => '选择一个小模型来重写查询';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      '请在使用 AI 搜索前选择一个 AI 搜索模型。';

  @override
  String get choose_an_active_project_next => '接下来选择一个活动项目';

  @override
  String get choose_chat_model => '选择聊天模型';

  @override
  String get choose_files => '选择文件';

  @override
  String get choose_image => '选择图片';

  @override
  String get choose_images => '选择图片';

  @override
  String get choose_its_destination_space => '选择其目标空间';

  @override
  String get clear_search => '清除搜索';

  @override
  String get close => '关闭';

  @override
  String get code_copied => '代码已复制';

  @override
  String get coming_next => '敬请期待';

  @override
  String get command => '命令';

  @override
  String get command_line_chats => '命令行聊天';

  @override
  String get compatibility_mode => '兼容模式';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      '在附加文件前，请先配置有效的 Desktop Gateway URL。';

  @override
  String get confirm_always_allow => '确认始终允许';

  @override
  String get confirm_passphrase => '确认密码短语';

  @override
  String connecting_to(Object baseUrl) {
    return '正在连接至 $baseUrl...';
  }

  @override
  String get connection_issue => '连接问题';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      '连接已切换 — 正在进行的回复将在服务器上继续，并会自动重新附加。';

  @override
  String get connection_appearance_and_device_preferences => '连接、外观和设备偏好设置';

  @override
  String context_tokens(Object effectiveContextLength) {
    return '上下文：$effectiveContextLength Token';
  }

  @override
  String get continue_label => '继续';

  @override
  String get continue_working => '继续工作';

  @override
  String get conversations_in_this_project => '此项目中的对话';

  @override
  String get copy_code => '复制代码';

  @override
  String get copy_message => '复制消息';

  @override
  String could_not_branch_chat(Object error) {
    return '无法创建聊天分支：$error';
  }

  @override
  String could_not_delete_session(Object error) {
    return '无法删除会话：$error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return '无法拒绝该命令：$error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return '无法加载 AI 搜索模型：$error';
  }

  @override
  String get could_not_load_conversations => '无法加载对话';

  @override
  String get could_not_load_files => '无法加载文件';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return '无法为该配置档案加载模型：$error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return '无法加载更多聊天：$error';
  }

  @override
  String get could_not_open_the_hermes_dashboard => '无法打开 Hermes 仪表盘。';

  @override
  String get could_not_open_this_project => '无法打开此项目';

  @override
  String get could_not_preview_file => '无法预览文件';

  @override
  String get could_not_reach_hermes => '无法连接至 Hermes';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return '无法连接/验证位于 $host:$dashboardPort 的仪表盘。请检查端口和凭据。';
  }

  @override
  String get could_not_read_activity => '无法读取活动';

  @override
  String could_not_rename_chat(Object error) {
    return '无法重命名聊天：$error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return '无法发送审批：$error';
  }

  @override
  String get could_not_skip_the_hermes_question => '无法跳过 Hermes 的问题。';

  @override
  String could_not_the_project(Object action, Object error) {
    return '无法 $action 该项目：$error';
  }

  @override
  String get couldn_t_delete_project => '无法删除项目';

  @override
  String couldn_t_load_runs(Object error) {
    return '无法加载运行记录：$error';
  }

  @override
  String get couldn_t_move_conversation => '无法移动对话';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return '无法移动至 $label：$reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files => '无法准备共享文件。';

  @override
  String get couldn_t_promote_conversation => '无法提升会话';

  @override
  String couldn_t_project(Object action) {
    return '无法 $action 项目';
  }

  @override
  String get create => '创建';

  @override
  String get create_a_project => '创建项目';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      '请先创建一个项目，聊天内容即可存放在其中。';

  @override
  String get create_a_space_to_separate_related_conversations =>
      '创建一个空间以区分相关的聊天。';

  @override
  String get create_branch => '创建分支';

  @override
  String get cron => 'Cron';

  @override
  String get cron_jobs => 'Cron 任务';

  @override
  String get cron_job_added => 'Cron 任务已添加';

  @override
  String get cron_job_updated => 'Cron 任务已更新';

  @override
  String get cron_run => 'Cron 运行';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      '跨设备排序与可撤销的批量整理';

  @override
  String get current_profile_default => '当前配置档案默认值';

  @override
  String get custom_proxy_and_dashboard_details => '自定义代理与仪表盘详情';

  @override
  String get dark => '深色';

  @override
  String get dashboard_proxy_settings => '仪表盘 / 代理设置';

  @override
  String get dashboard_password_optional => '仪表盘密码（可选）';

  @override
  String get dashboard_port => '仪表盘端口';

  @override
  String get dashboard_username_optional => '仪表盘用户名（可选）';

  @override
  String get dashboard_behind_proxy => '位于代理后的仪表盘';

  @override
  String get dashboard_path_prefix => '仪表盘路径前缀';

  @override
  String delegated_task(Object goal) {
    return '委派任务：$goal';
  }

  @override
  String get delete => '删除';

  @override
  String delete_2(Object name) {
    return '删除“$name”？';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return '从远程 Hermes 历史记录中删除“$title”？此操作不可撤销。';
  }

  @override
  String get delete_cron_job => '删除 Cron 任务';

  @override
  String get delete_connections_that_are_not_in_the_backup => '删除不在备份中的连接。';

  @override
  String delete_failed(Object error) {
    return '删除失败：$error';
  }

  @override
  String get delete_project => '删除项目';

  @override
  String get delete_session => '删除会话？';

  @override
  String delete_3(Object projectName) {
    return '删除 $projectName？';
  }

  @override
  String deleted(Object name) {
    return '已删除“$name”';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      '发送状态不确定；正在恢复且不重新发送……';

  @override
  String get desktop_gateway_url_optional => 'Desktop Gateway URL（可选）';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      '此连接未配置 Desktop Gateway。';

  @override
  String get desktop_app => '桌面应用';

  @override
  String get developer_tool_calls => '开发者工具调用';

  @override
  String get discord_chats => 'Discord 聊天';

  @override
  String get dismiss => '忽略';

  @override
  String get do_not_run_this_command => '请勿运行此命令。';

  @override
  String get documents_archives_audio_video_or_data => '文档、压缩包、音频、视频或数据';

  @override
  String get download => '下载';

  @override
  String download_failed(Object error) {
    return '下载失败：$error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you => 'Hermes 记录的关于你的持久事实';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      '项目内的持久工作内容，已与 Desktop 共享。';

  @override
  String get edit => '编辑';

  @override
  String get edit_connection => '编辑连接';

  @override
  String get edit_cron_job => '编辑 Cron 任务';

  @override
  String get edit_gateway_connection => '编辑网关连接';

  @override
  String get edit_and_resend => '编辑并重发';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      '允许通过 Desktop 远程网关发送文件附件。';

  @override
  String get enter_a_name => '输入名称';

  @override
  String get enter_a_passphrase => '请输入密码短语。';

  @override
  String get enter_the_passphrase_for_this_backup => '请输入此备份的密码短语。';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      '所有对话均已分配至某个项目。';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      '所有尚未原生支持的功能，均可在已认证的 Web 仪表盘中查看';

  @override
  String get explain_the_attached_content_clearly => '清晰解释附件内容。';

  @override
  String explain_this_content_clearly(Object text) {
    return '清晰解释此内容：\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      '显式选择将调整 Android 无障碍文字大小；选择“系统”则保持不变。';

  @override
  String get export_label => '导出';

  @override
  String get export_share => '导出 / 分享';

  @override
  String get external_api_clients => '外部 API 客户端';

  @override
  String get extra_high => '极高';

  @override
  String get extract_tasks => '提取任务';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      '从附件内容中提取决策、截止日期、负责人以及可执行的操作项。';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return '从以下内容中提取决策、截止日期、负责人以及可执行的操作项：\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return '添加任务失败：$error';
  }

  @override
  String get failed_to_load_cron_jobs => '加载 Cron 任务失败';

  @override
  String get failed_to_load_memory => '加载记忆失败';

  @override
  String get failed_to_load_messages => '加载消息失败';

  @override
  String get failed_to_load_settings => '加载设置失败';

  @override
  String get failed_to_load_skills => '加载技能失败';

  @override
  String failed_to_update_job(Object error) {
    return '更新任务失败：$error';
  }

  @override
  String failed(Object error) {
    return '失败：$error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      '已添加文件附件；文档目录注册正在等待处理。';

  @override
  String get file_reference_added_to_chat => '文件引用已添加至聊天';

  @override
  String get files => '文件';

  @override
  String get fill_from_document => '从文档填充';

  @override
  String get folder_is_empty => '文件夹为空';

  @override
  String get folders => '文件夹';

  @override
  String get full_text => '全文';

  @override
  String get gateway_api_access => '网关 API 访问';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      '网关已连接，但无法访问仪表盘或未能通过身份验证。请检查仪表盘详细信息，或清除它们以跳过。';

  @override
  String get gateway_path_prefix => '网关路径前缀';

  @override
  String get go_to_end => '转到末尾';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Android 版 Hermes Agent';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'Hermes 无法接受此回答，请重试。';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      'Hermes 无法加载你保存的连接';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'Hermes 未能接受此响应，请重试。';

  @override
  String get hermes_is_responding => 'Hermes 正在响应…';

  @override
  String get hermes_is_waiting_for_input => 'Hermes 正在等待输入…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'Hermes 保持 Android 辅助功能文字缩放处于活动状态。';

  @override
  String get hermes_needs_your_input => 'Hermes 需要你的输入';

  @override
  String get hermes_profile_optional => 'Hermes 配置档案（可选）';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'Hermes 配置档案必须是纯粹的档案名称（例如 “sol”），而不能是路径。';

  @override
  String get hermes_reasoning_details => 'Hermes 推理详情';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'Hermes 恢复不可用：$error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'Hermes 已安全停止恢复。未重新发送任何提示词。';

  @override
  String get hide_passphrase => '隐藏密码短语';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      '首页需要你最近的聊天记录来了解哪些内容值得你关注。请检查网关是否可达，然后重试。';

  @override
  String get host => '主机';

  @override
  String get image_selection_was_interrupted_try_again => '图片选择被中断，请重试。';

  @override
  String get import_label => '导入';

  @override
  String get inbox => '收件箱';

  @override
  String get inbox_is_clear => '收件箱为空';

  @override
  String get insert_a_remote_file_reference => '插入远程 @file 引用';

  @override
  String get invalid_port_number => '无效的端口号。';

  @override
  String get job_paused => '任务已暂停';

  @override
  String get job_resumed => '任务已恢复';

  @override
  String get job_triggered => '任务已触发';

  @override
  String get label => '标签';

  @override
  String last_activity(Object day, Object month, Object year) {
    return '最后活动于 $year年$month月$day日';
  }

  @override
  String last(Object lastRun) {
    return '最后运行：$lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      '留空则使用默认值（8642；使用 https 时为 443）';

  @override
  String get leave_blank_for_default_9119 => '留空则使用默认值 (9119)';

  @override
  String get light => '浅色';

  @override
  String listening(Object elapsed) {
    return '正在聆听 • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return '正在聆听，已耗时 $elapsed';
  }

  @override
  String get load_more => '加载更多…';

  @override
  String get loading => '正在加载';

  @override
  String get location => '位置';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      '请确保网关 API Server 正在运行\n(hermes gateway status)';

  @override
  String matches(Object assigned, Object name) {
    return '匹配项 $name · $assigned';
  }

  @override
  String get memory => '记忆';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      '记忆条目是 Agent 跨会话记住的事实。\n它们在 ~/.hermes/config.yaml 中进行配置';

  @override
  String get merge => '合并';

  @override
  String get message => '消息';

  @override
  String get message_hermes => '给 Hermes 发消息…';

  @override
  String get message_actions => '消息操作';

  @override
  String get message_copied => '已复制消息';

  @override
  String get migrating => '正在迁移…';

  @override
  String get migration_complete => '迁移完成';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      '迁移失败。本地空间保持不变。';

  @override
  String get migration_incomplete => '迁移未完成';

  @override
  String get migration_preview => '迁移预览';

  @override
  String get model => '模型';

  @override
  String get model_and_thinking_for_this_chat => '此聊天的模型和思考状态';

  @override
  String model_was_not_changed(Object error) {
    return '模型未更改：$error';
  }

  @override
  String get move_attachment_next => '将附件移至下一个';

  @override
  String get move_attachment_previous => '将附件移至上一个';

  @override
  String get move_chat => '移动聊天';

  @override
  String get move_conversation => '移动会话';

  @override
  String get move_to_project => '移动到项目';

  @override
  String get move_to_space => '移动到空间';

  @override
  String get moved_to_a_project => '已移动到项目';

  @override
  String moved_to(Object label) {
    return '已移动到 $label';
  }

  @override
  String get name => '名称';

  @override
  String get name_prompt_and_schedule_are_required => '名称、提示词和计划均为必填项';

  @override
  String get nav_activity => '活动';

  @override
  String get nav_projects => '项目';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Hermes 网关中需要具备支持纠错感知的文件归档契约。';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      '需要可访问的 Hermes 仪表盘。请检查此连接的主机、端口和凭据。';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Hermes 网关中需要具备服务端权威的资产索引。';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Hermes 网关中需要具备持久化的置顶排序、批量变更和撤销契约。';

  @override
  String get needs_you => '需要你';

  @override
  String get new_label => '新';

  @override
  String get new_chat => '新聊天';

  @override
  String get new_chat_2 => '新聊天';

  @override
  String new_chat_3(Object projectName) {
    return '新聊天 · $projectName';
  }

  @override
  String get new_project => '新建项目';

  @override
  String get new_space => '新建空间';

  @override
  String next(Object nextRun) {
    return '下次运行：$nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'Nginx 注入认证 — 应用发送干净请求';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      '未找到 TTS 语音。\n请安装 Google Text-to-Speech 并下载语音数据。';

  @override
  String get no_active_projects_on_this_gateway => '此网关上暂无活动项目';

  @override
  String get no_activity_yet => '暂无活动';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      '没有被阻塞、运行中或等待恢复的聊天。准备好后随时可以开始新聊天。';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return '此项目中没有与“$searchQuery”匹配的聊天。';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      '此空间暂无聊天。轻点 + 开始聊天。';

  @override
  String get no_chats_yet => '暂无聊天';

  @override
  String get no_connections => '无连接';

  @override
  String get no_conversation_matches_this_view => '没有与此视图匹配的对话。';

  @override
  String get no_cron_jobs => '暂无 Cron 任务';

  @override
  String get no_folders_yet => '暂无文件夹';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      '在此连接中未找到本地空间，因此项目已是此处的唯一组织方式。';

  @override
  String get no_matches => '无匹配项';

  @override
  String get no_memory_entries => '暂无记忆条目';

  @override
  String get no_message_content_matches => '无匹配的消息内容';

  @override
  String get no_new_messages => '暂无新消息';

  @override
  String get no_projects_yet => '暂无项目';

  @override
  String get no_runs_yet => '暂无运行记录。';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return '没有与此名称匹配的服务端项目 · $assigned';
  }

  @override
  String get no_sessions_yet => '暂无会话';

  @override
  String get no_skills_found => '未找到技能';

  @override
  String get no_spaces_on_this_device => '此设备上无空间';

  @override
  String get no_text_shared => '未共享文本';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      '没有被阻塞、进行中或最近完成的轮次。你开始的工作会显示在这里。';

  @override
  String get no_turn_needs_your_input_or_has_failed => '没有需要你输入或失败的轮次。';

  @override
  String get no_unassigned_chats => '暂无未分配的聊天。';

  @override
  String get nothing_changed_in_the_last_seven_days => '最近七天无更改。';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      '尚未移动任何内容 — 这只是迁移将执行的操作。';

  @override
  String get nothing_here => '这里什么也没有';

  @override
  String get nothing_is_running => '没有正在运行的内容';

  @override
  String get nothing_needs_you => '一切正常，无需处理';

  @override
  String get nothing_to_migrate => '无需迁移';

  @override
  String get off_no_thinking => '关闭（无思考）';

  @override
  String get offline_showing_the_last_known_activity => '离线 — 显示最后已知的活动。';

  @override
  String get offline_showing_the_last_known_chats => '离线 — 显示最后已知的聊天';

  @override
  String get offline_showing_the_last_known_projects => '离线 — 正在显示最后已知的项目。';

  @override
  String get on_this_device => '此设备上';

  @override
  String get on_device => '端侧';

  @override
  String get open_inbox => '打开收件箱';

  @override
  String open_inbox_2(Object count) {
    return '打开收件箱（$count）';
  }

  @override
  String get open_the_hermes_dashboard => '打开 Hermes 仪表盘';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      '可选。用于“记忆”、“Cron”、“技能”、“设置”标签页。留空则使用默认仪表盘端口（9119）且无需登录。';

  @override
  String get organization => '组织';

  @override
  String get other_answer => '其他回答';

  @override
  String get overview => '概览';

  @override
  String get passphrase => '密码短语';

  @override
  String get password_optional => '密码（可选）';

  @override
  String get phone_or_tablet => '手机或平板电脑';

  @override
  String get pin_batch_and_undo => '置顶、批量操作与撤销';

  @override
  String get port => '端口';

  @override
  String get preparing_attachments => '正在准备附件…';

  @override
  String get preview_truncated => '预览已截断';

  @override
  String get preview_unavailable => '预览不可用';

  @override
  String get profile => '配置档案';

  @override
  String get profile_default_model => '配置档案默认模型';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return '配置档案默认值已设为 $selectedModel。拥有独立模型的聊天将保留该覆盖设置。';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      '当仪表盘服务于多个配置档案时，为此连接的聊天指定配置档案。留空则使用独立的单配置档案仪表盘。';

  @override
  String get project => '项目';

  @override
  String get project_actions => '项目操作';

  @override
  String get project_chat => '项目聊天';

  @override
  String get project_chats_unavailable => '项目聊天不可用';

  @override
  String get projects => '项目';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      '项目将相关的聊天、文件和活动进行分组，并与你电脑上的 Hermes 保持同步。';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      '项目需要 Desktop Gateway 连接。请将 Desktop Gateway URL 添加到此连接，以便跨设备管理聊天。';

  @override
  String get projects_unavailable => '项目不可用';

  @override
  String get projects_activity_new_navigation => '项目、活动 — 新导航';

  @override
  String get promote_to_project => '提升为项目';

  @override
  String get prompt => '提示词';

  @override
  String get protect_this_backup => '保护此备份';

  @override
  String get provider => '提供方';

  @override
  String get proxy_injects_auth_app_sends_clean_requests => '代理注入认证信息；应用发送纯净请求';

  @override
  String get quick_chat => '快速聊天';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      '快速聊天将在保留期过后显示在此处。';

  @override
  String get read_aloud => '朗读';

  @override
  String get read_aloud_is_unavailable_on_this_device => '此设备不支持朗读功能';

  @override
  String get reading_response_aloud => '正在朗读回复';

  @override
  String get ready_to_upload => '准备上传';

  @override
  String get reasoning => '推理';

  @override
  String get recently_completed => '最近完成';

  @override
  String get recovering_hermes => '正在恢复 Hermes…';

  @override
  String get refresh => '刷新';

  @override
  String get regenerate_response => '重新生成回复';

  @override
  String get remove_attachment => '移除附件';

  @override
  String get rename => '重命名';

  @override
  String get rename_chat => '重命名聊天';

  @override
  String get rename_project => '重命名项目';

  @override
  String get rename_space => '重命名空间';

  @override
  String rename_2(Object projectName) {
    return '重命名 $projectName';
  }

  @override
  String rename_3(Object name) {
    return '重命名 $name';
  }

  @override
  String get replace => '替换';

  @override
  String get repositories => '代码库';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      '研究附件内容，核实重要主张并引用来源。';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return '研究此内容，核实重要主张并引用来源：\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return '重置失败：$retryError。安全存储可能需要重新安装。';
  }

  @override
  String get reset_saved_connections => '重置已保存的连接';

  @override
  String get responding => '正在响应…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return '响应已在本地关闭；网关停止失败：$error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      '响应已在本地关闭；未找到活动的网关轮次。';

  @override
  String get response_ready => '回复就绪';

  @override
  String get response_stopped => '回复已停止。';

  @override
  String get restore => '恢复';

  @override
  String get restore_configuration => '恢复配置';

  @override
  String get restore_project => '恢复项目';

  @override
  String get retry => '重试';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return '$name 重试失败。草稿和提示词已保留。';
  }

  @override
  String get retry_upload => '重试上传';

  @override
  String retrying(Object name) {
    return '正在重试 $name…';
  }

  @override
  String get review_local_spaces => '检查本地空间';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      '查看或提升超出保留期限的快速聊天';

  @override
  String get review_the_attached_content => '查看附件内容。';

  @override
  String get run_only_this_command => '仅运行此命令。';

  @override
  String get running_now => '正在运行';

  @override
  String get save => '保存';

  @override
  String get save_changes => '保存更改';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      '在 Hermes 配置中保存永久规则。';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      '将附件内容中的持久事实保存到记忆中，然后确认保留的内容。';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return '将此内容中的持久事实保存到记忆中，然后确认保留的内容：\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      '将连接与设置保存到加密文件中，以便在重新安装或在其他设备上时恢复它们。';

  @override
  String save_2(Object filename) {
    return '保存 $filename';
  }

  @override
  String get schedule => '计划';

  @override
  String get scheduled_jobs_and_their_last_runs => '计划任务及其最近运行情况';

  @override
  String get scheduled_tasks => '计划任务';

  @override
  String get script_only_no_agent => '仅脚本（无 Agent）';

  @override
  String get scroll_horizontally => '水平滚动';

  @override
  String get search_all_chats => '搜索所有聊天';

  @override
  String get search_all_message_content => '搜索所有消息内容';

  @override
  String get search_chats => '搜索聊天';

  @override
  String get search_conversations => '搜索对话';

  @override
  String get search_loaded_chats => '搜索已加载的聊天';

  @override
  String get search_mode => '搜索模式';

  @override
  String get select_one_option_or_enter_another_answer => '选择一个选项，或输入其他答案。';

  @override
  String get select_one_or_more_options_then_continue => '选择一个或多个选项，然后继续。';

  @override
  String get select_text => '选择文本';

  @override
  String get send => '发送';

  @override
  String send_failed(Object error) {
    return '发送失败：$error';
  }

  @override
  String get send_message => '发送消息';

  @override
  String get session_sources => '会话来源';

  @override
  String get session_deleted_from_remote_hermes => '已从远程 Hermes 中删除会话。';

  @override
  String session_search_failed(Object error) {
    return '会话搜索失败：$error';
  }

  @override
  String get set_profile_default => '设为默认配置档案';

  @override
  String get settings => '设置';

  @override
  String get share_to_hermes => '分享到 Hermes';

  @override
  String get show_passphrase => '显示密码短语';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      '显示工具调用、思考过程和消息元数据';

  @override
  String get signal_messages => 'Signal 消息';

  @override
  String get skills => '技能';

  @override
  String skills_2(Object count) {
    return '技能（$count）';
  }

  @override
  String get skills_and_tools => '技能与工具';

  @override
  String get skip => '跳过';

  @override
  String get slack_chats => 'Slack 聊天';

  @override
  String source(Object source) {
    return '来源：$source';
  }

  @override
  String get space_actions => '空间操作';

  @override
  String get spaces => '空间';

  @override
  String get speak_to_hermes => '对 Hermes 说话';

  @override
  String get speech_recognition_is_unavailable => '语音识别不可用';

  @override
  String get spoken_replies => '语音回复';

  @override
  String get spoken_replies_off => '语音回复已关闭';

  @override
  String get spoken_replies_on => '语音回复已开启';

  @override
  String get stalled_no_update_from_hermes => '已停滞 — 未收到来自 Hermes 的更新';

  @override
  String get start_something_new => '开启新任务';

  @override
  String get start_voice_input => '开始语音输入';

  @override
  String get starting_hermes => '正在启动 Hermes…';

  @override
  String get still_loading_your_projects => '正在加载你的项目。';

  @override
  String get stop => '停止';

  @override
  String get stop_response => '停止响应';

  @override
  String get stop_voice_input => '停止语音输入';

  @override
  String get submitted_waiting_for_hermes => '已提交，等待 Hermes 响应';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      '建议项目并从你的更正中学习';

  @override
  String get summarize_the_attached_content => '总结附件内容。';

  @override
  String summarize_this_content(Object text) {
    return '总结此内容：\n\n$text';
  }

  @override
  String get switch_profile => '切换配置档案';

  @override
  String get system => '系统';

  @override
  String get take_photo => '拍照';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      '点击 + 添加远程 Hermes 网关\n(API Server，端口 8642)';

  @override
  String get tap_the_button_to_start_a_new_chat => '点击 + 按钮开始新的聊天';

  @override
  String get telegram_messages => 'Telegram 消息';

  @override
  String get terminal_sessions => '终端会话';

  @override
  String get text_size => '文字大小';

  @override
  String get text_size_preview => '文字大小预览';

  @override
  String text_size_2(Object label) {
    return '文字大小：$label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely => '无法安全存储 API 密钥。';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      '该项目将移至“已归档”。其聊天和文件将保持完整，你可以随时恢复它。';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      '该项目将移至“已归档”。其聊天和文件将保持完整，你可以稍后恢复它。';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      '当前配置档案未返回任何可选模型。';

  @override
  String get the_backup_could_not_be_exported => '无法导出备份。';

  @override
  String get the_backup_could_not_be_restored => '无法恢复备份。';

  @override
  String get the_connection_could_not_be_deleted_safely => '无法安全删除连接。';

  @override
  String get the_connection_could_not_be_stored_securely => '无法安全存储连接。';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      '无法安全存储仪表盘凭据。';

  @override
  String get the_detached_reply_failed => '已分离的回复失败。';

  @override
  String the_detached_reply_failed_2(Object error) {
    return '已分离的回复失败：$error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      '该文件包含你的 API 密钥和仪表盘密码，因此已加密。没有此密码短语，备份将无法恢复。';

  @override
  String get the_last_turn_failed => '上一轮对话失败';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return '本地连接存储似乎已损坏 ($errorType)。你可以重置已保存的连接并重新开始。网关上的聊天记录不受影响。';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      '该模型仅将你的问题重写为简短的全文查询。Hermes 使用已在主机上配置的提供方凭据。';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      '服务器尚未报告此项目的文件夹。全局文件仍可在“更多”中查看。';

  @override
  String get the_turn_failed => '本轮对话失败';

  @override
  String get the_two_passphrases_do_not_match => '两次输入的密码短语不匹配。';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      '该值将直接发送至当前活动的 Hermes 网关，不会被此 Android 应用保存。';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      '此服务器文件夹中没有可见文件。';

  @override
  String get thinking_effort => '思考强度';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      '此 Hermes 网关尚不支持打开项目。请更新服务器上的 Hermes 以在手机上浏览项目。';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      '此 Hermes 网关版本旧于服务端项目功能，因此聊天仅在此设备上分组。请更新 Hermes 以在多台设备间共享相同项目。';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      '此项目没有可用于打开聊天的文件夹 —— 已默认设为未分配。请为项目添加文件夹以便对聊天进行分组。';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      '此聊天在 Desktop 会话中暂无可用消息。';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      '这将在 Hermes 中创建永久规则。确认前请仔细检查完整命令。';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      '此网关尚不支持托管项目。请更新网关以在各设备间整理聊天。';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      '这将永久删除该项目。聊天记录不会被删除；它们将返回至未分配状态。';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      '此服务器不提供后台恢复功能 —— 聊天实时运行';

  @override
  String get this_week => '本周';

  @override
  String get titles_previews_and_models => '标题、预览与模型';

  @override
  String get tool_activity => '工具活动';

  @override
  String get trigger_now => '立即触发';

  @override
  String get turn_completed => '本轮对话已完成';

  @override
  String get turn_recovery_failed => '对话恢复失败';

  @override
  String get unable_to_prepare_this_file_try_another_one => '无法准备此文件，请尝试其他文件。';

  @override
  String get unable_to_prepare_this_image_try_another_one => '无法准备此图片，请尝试其他图片。';

  @override
  String unable_to_prepare(Object name) {
    return '无法准备 $name。';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      '无法读取所选图片，已保留当前选择。';

  @override
  String get unassigned => '未分配';

  @override
  String get unassigned_chats => '未分配的聊天';

  @override
  String get untitled_chat => '未命名聊天';

  @override
  String get untitled_session => '未命名会话';

  @override
  String get update_api_key => '更新 API 密钥';

  @override
  String get upload_failed => '上传失败';

  @override
  String get upload_failed_tap_retry => '上传失败 • 点击重试';

  @override
  String uploading(Object index, Object name, Object total) {
    return '正在上传 $index/$total：$name';
  }

  @override
  String get use_as_is => '直接使用';

  @override
  String get use_at_least_8_characters => '请使用至少 8 个字符。';

  @override
  String get use_for_cron_jobs_backed_by_scripts => '用于由脚本支持的 Cron 任务。';

  @override
  String get use_on_device => '使用设备端';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      '使用附件内容识别并填写相关文档或表单字段。提交任何内容前请先询问。';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return '使用此内容识别并填写相关文档或表单字段。提交任何内容前请先询问：\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      '用于托管路径前缀以及“设置”、“记忆”、“技能”和“Cron”标签页。若需开放仪表盘，可将用户名/密码留空；若反向代理已注入仪表盘认证，请启用代理模式。';

  @override
  String get username_optional => '用户名（可选）';

  @override
  String using(Object displayName) {
    return '正在使用 $displayName…';
  }

  @override
  String get verbose_mode => '详细模式';

  @override
  String get voice => '语音';

  @override
  String voice_setup_failed(Object error) {
    return '语音设置失败：$error';
  }

  @override
  String get waiting_for_your_input => '等待你的输入';

  @override
  String get what_hermes_knows_how_to_do => 'Hermes 能够做的事情';

  @override
  String get what_should_the_agent_do => '要让 Agent 做什么？';

  @override
  String get whatsapp_messages => 'WhatsApp 消息';

  @override
  String get which_project => '哪个项目？';

  @override
  String get workspace => '工作区';

  @override
  String get wrap_lines => '自动换行';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return '最多可附加 $maxRemoteAttachmentDrafts 个项目。';
  }

  @override
  String get your_answer => '你的回答';

  @override
  String get e_g_dashboard => '例如 /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      '例如 /dashboard（/api/ 之前的代理路径）';

  @override
  String get e_g_profile_peter => '例如 /profile/peter';

  @override
  String get e_g_sol => '例如 sol';

  @override
  String get e_g_0_9_or_every_2h => '例如 0 9 * * * 或 every 2h';

  @override
  String get e_g_daily_backup => '例如每日备份';

  @override
  String downloaded(Object filename) {
    return '已下载 $filename';
  }

  @override
  String activity_name_status(Object displayName, Object statusLabel) {
    return '$displayName：$statusLabel';
  }

  @override
  String connection_status_label(Object connectionLabel, Object label) {
    return '$connectionLabel $label';
  }

  @override
  String get example_host_hint =>
      '192.168.1.50、100.x.y.z 或 hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      '例如 /profile/peter（/api/ 和 /v1/ 之前的代理路径）';

  @override
  String and_more(Object count) {
    return '以及另外 $count 个';
  }

  @override
  String chats_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个聊天',
    );
    return '$_temp0';
  }

  @override
  String on_this_device_only(Object chats) {
    return '$chats · 仅在此设备上';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个空间',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => '无需创建新项目';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 个项目待创建',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return '已迁移 $linkedSessions 个聊天 · 已创建 $createdProjects 个项目';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '$unlinkedSessions 个聊天保留在本地空间中，可安全重试。';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • 推荐：小巧且经济';
  }

  @override
  String session_meta(Object count, Object model, Object time) {
    return '$count 条消息 • $model • $time';
  }

  @override
  String model_scope_label(Object model, Object scope) {
    return '$model • $scope';
  }

  @override
  String get this_chat => '此聊天';

  @override
  String get profile_default => '配置档案默认值';

  @override
  String minutes_ago(Object count) {
    return '$count 分钟前';
  }

  @override
  String hours_ago(Object count) {
    return '$count 小时前';
  }

  @override
  String days_ago(Object count) {
    return '$count 天前';
  }

  @override
  String get now_label => '刚刚';

  @override
  String get latest_label => '最新';

  @override
  String new_count_indicator(Object count) {
    return '$count 条新消息';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条新消息',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return '$failures 个失败 • 共 $total 个';
  }

  @override
  String activity_completed_summary(Object count) {
    return '已完成 $count 个';
  }

  @override
  String get hermes_is_using_a_tool => 'Hermes 正在使用工具';

  @override
  String hermes_is_using_tools(Object count) {
    return 'Hermes 正在使用 $count 个工具';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return '已完成 $count 个委派任务';
  }

  @override
  String delegated_tasks_active(Object count) {
    return '$count 个委派任务进行中';
  }

  @override
  String branch_main(Object label) {
    return '$label · main';
  }

  @override
  String get you_heading => '## 你';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => '操作';

  @override
  String get destination_label => '目标';

  @override
  String get preview_label => '预览';

  @override
  String get share_action_summarize => '总结';

  @override
  String get share_action_explain => '解释';

  @override
  String get share_action_research => '研究';

  @override
  String get share_action_remember => '记住';

  @override
  String get text_size_small => '小';

  @override
  String get text_size_default => '默认';

  @override
  String get text_size_large => '大';

  @override
  String get text_size_extra_large => '特大';

  @override
  String get text_size_use_system_description => '完全使用 Android 辅助功能文字大小。';

  @override
  String text_size_percent_description(Object percent) {
    return 'Android 文字大小的 $percent%。';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return '已跳过 $count 个文件：超出限制、大小超限、无法读取或文件名包含敏感信息。';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort 现仅应用于此聊天。';
  }

  @override
  String get reasoning_minimal => '极简';

  @override
  String get reasoning_low => '低';

  @override
  String get reasoning_medium => '中';

  @override
  String get reasoning_high => '高';

  @override
  String get reasoning_max => '最大';

  @override
  String get reasoning_ultra => '极致';

  @override
  String get status_running => '运行中';

  @override
  String get status_failed => '已失败';

  @override
  String get status_done => '完成';

  @override
  String get status_idle => '空闲';

  @override
  String get upload_status_uploading => '正在上传';

  @override
  String get upload_status_uploaded => '已上传';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个附件',
    );
    return '$_temp0';
  }

  @override
  String get action_create => '创建';

  @override
  String get action_rename => '重命名';

  @override
  String get action_archive => '归档';

  @override
  String get action_restore => '恢复';

  @override
  String get action_delete => '删除';

  @override
  String get migrate => '迁移';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个已分配聊天',
    );
    return '$_temp0';
  }

  @override
  String get date_today => '今天';

  @override
  String get date_yesterday => '昨天';

  @override
  String get date_earlier => '更早';

  @override
  String get nav_home => '主页';

  @override
  String get nav_more => '更多';

  @override
  String get status_completed => '已完成';

  @override
  String get filter_all => '全部';

  @override
  String get filter_recent => '最近';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  密钥：$status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model  \n通过 `$provider`';
  }

  @override
  String get deny => '拒绝';

  @override
  String get connect => '连接';

  @override
  String get appearance => '外观';

  @override
  String get connection_section => '连接';

  @override
  String get about => '关于';

  @override
  String version_label(Object version) {
    return '版本 $version';
  }

  @override
  String get matched => '已匹配';

  @override
  String get search => '搜索';

  @override
  String get on => '开';

  @override
  String get off => '关';

  @override
  String get reasoning_off => '关';

  @override
  String get hermes_response_ready => 'Hermes 回复已就绪';

  @override
  String get admin_password_needed => '需要管理员密码';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      'Hermes 需要 sudo 密码来执行挂起的终端命令。';

  @override
  String get sudo_password => 'sudo 密码';

  @override
  String get secret_needed => '需要密钥';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      'Hermes 需要为待处理的技能提供一个密钥。';

  @override
  String get secret_value => '密钥值';

  @override
  String get attached_file => '已附加文件';
}
