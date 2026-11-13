// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get fallback_title => '备用模型';

  @override
  String get fallback_notice => '主模型不可用时按顺序尝试。更改仅适用于此配置；请明确保存完整列表。';

  @override
  String get fallback_unavailable => '备用设置不可用或无效。请检查连接、所选配置和主机版本，然后重试。';

  @override
  String get fallback_discovery_unavailable =>
      '无法获取提供商列表。现有条目会保留；重试后可选择提供商和模型。';

  @override
  String get fallback_empty => '此备用列表中没有条目。';

  @override
  String get fallback_incomplete => '保存前，请为每个条目选择提供商和模型，或删除未完成的条目。';

  @override
  String get fallback_add => '添加备用模型';

  @override
  String get fallback_save => '保存备用列表';

  @override
  String get fallback_save_failed => '无法验证已保存的备用列表。草稿已保留。请重新保存，或刷新以重新加载主机设置。';

  @override
  String get fallback_saved => '备用列表已保存并验证。';

  @override
  String get fallback_legacy_title => '旧版备用设置（只读）';

  @override
  String get fallback_legacy_notice =>
      '主机还会在此列表之后使用 fallback_model，并跳过重复路由。即使上方列表为空，这些旧版条目也会保留。请在主机上编辑。';

  @override
  String fallback_priority(String position) {
    return '优先级 $position';
  }

  @override
  String get fallback_move_up => '上移';

  @override
  String get fallback_move_down => '下移';

  @override
  String get fallback_routing_read_only =>
      '路由详情或未列出的提供商已保留。请在主机上编辑此提供商／模型；此处仍可调整顺序或删除条目。';

  @override
  String get cron_model_default => '使用默认设置';

  @override
  String get cron_model_notice =>
      '仅适用于此 cron 任务。未固定模型时，Hermes 先使用 cron 默认模型，再使用主模型。请在主机上管理自定义模型。';

  @override
  String get model_management_unavailable => '无法加载或保存模型设置。请刷新后重试。';

  @override
  String get model_management_subtitle => '此配置的主模型、备用模型和辅助模型';

  @override
  String get usage => '用量';

  @override
  String get nous_portal => 'Nous Portal';

  @override
  String get portal_menu_subtitle => '网关状态和已记录用量';

  @override
  String get portal_read_only =>
      '网关只读数据。请在 Hermes 主机上管理 Nous 身份验证。这些端点不提供订阅余额或积分。';

  @override
  String get portal_status => '网关 Portal 状态';

  @override
  String get portal_free_tier => '免费层访问（未登录账户）';

  @override
  String get portal_signed_in => '已登录';

  @override
  String get portal_signed_out => '未登录';

  @override
  String get portal_account_tier => '账户等级';

  @override
  String get portal_recorded_usage => '已记录用量';

  @override
  String get portal_all_providers => '所选网关配置中的所有提供商。记录费用为零并不表示模型免费。';

  @override
  String portal_period(String days) {
    return '最近 $days 天';
  }

  @override
  String get portal_sessions => '会话';

  @override
  String get portal_input => '输入令牌';

  @override
  String get portal_output => '输出令牌';

  @override
  String get portal_estimated => '已记录的预估费用';

  @override
  String get portal_actual => '已记录的实际费用';

  @override
  String get portal_recorded_models => '已记录模型';

  @override
  String get portal_no_models => '没有已记录模型。';

  @override
  String get portal_unavailable => '不可用。请检查连接、所选配置和网关版本，然后重试。';

  @override
  String get paste_attachment_failed_text_kept => '无法将粘贴的文本添加为附件。文本已保留在消息中。';

  @override
  String get background_task_report => '后台任务';

  @override
  String get background_process_report => '后台进程';

  @override
  String get background_report_issues => '已报告问题，展开查看详情。';

  @override
  String get background_report_expand => '展开报告';

  @override
  String get background_report_collapse => '收起报告';

  @override
  String get hands_free_title => '免提对话';

  @override
  String get hands_free_start => '开始免提';

  @override
  String get hands_free_stop => '停止免提';

  @override
  String get hands_free_preparing => '正在准备语音 — 请稍候';

  @override
  String get hands_free_listening => '请说 Hey Hermes';

  @override
  String get hands_free_recording => '已就绪 — 请说话';

  @override
  String get hands_free_waiting => '等待 Hermes 回复';

  @override
  String get hands_free_speaking => '正在朗读 — 麦克风已关闭';

  @override
  String hands_free_followup(int seconds) {
    return '最多聆听 $seconds 秒';
  }

  @override
  String get hands_free_error => '免提已停止';

  @override
  String get hands_free_setup => '免提设置';

  @override
  String hands_free_preview(String transcript) {
    return '语音预览：$transcript';
  }

  @override
  String get hands_free_short_disclosure =>
      '仅在此聊天于前台打开时运行。唤醒检测离线；语音可能使用网络。会消耗电量。';

  @override
  String get hands_free_error_action =>
      '请检查麦克风权限、语音服务、回复声音和连接，再点击停止并重新开始。不会自动重发。';

  @override
  String get hands_free_disclosure =>
      '唤醒检测在 CPU 上离线运行。Android 语音识别、所选声音和网关可能使用网络。聆听会消耗电量，也可能误触发。聊天被遮挡、关闭或离开前台时停止，返回后不会自动重启。手动听写仍是可编辑的草稿。';

  @override
  String get hands_free_ready_cue =>
      '说“Hey Hermes”，等待就绪提示后再说话。不支持一口气连续输入或预录音。如果授权对话框使应用离开前台，授权后请再次点击开始。';

  @override
  String get hands_free_settings_title => '免提语音';

  @override
  String get hands_free_settings_subtitle =>
      '在聊天中显示“Hey Hermes”启动控件。关闭会停止正在进行的免提会话。';

  @override
  String get hands_free_timing_limit =>
      '后续聆听时间是上限，不是下限。Android 可能提前结束。无语音时返回本地唤醒检测，不会反复重启识别。';

  @override
  String get hands_free_followup_off => '后续聆听已关闭 — 每次提问请说 Hey Hermes';

  @override
  String get hands_free_start_blocked =>
      '需要空草稿、无附件、空闲且已连接的聊天，并启用语音回复。请先结束手动语音操作。';

  @override
  String get hands_free_setup_complete => '麦克风设置完成。请再次点击开始。';

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
  String get stop_and_send => '停止并发送';

  @override
  String get message_queued_for_running_turn => '消息已加入当前运行的队列。';

  @override
  String get running_message_not_accepted =>
      'Hermes 无法接受此消息。草稿已保留；请停止回复或等待，然后重新发送。';

  @override
  String get running_message_delivery_unknown =>
      '无法确认消息是否送达。草稿已保留。请先检查聊天记录，再重试。';

  @override
  String get attachment_tap_to_preview => '点按以预览';

  @override
  String get attachment_save => '保存';

  @override
  String get attachment_share => '分享';

  @override
  String get attachment_saved => '文件已保存';

  @override
  String get attachment_save_cancelled => '已取消保存';

  @override
  String get attachment_save_failed => '无法保存此文件，请重试。';

  @override
  String get attachment_share_failed => '无法分享此文件，请重试。';

  @override
  String get attachment_download_failed => '无法加载此文件，请检查连接后重试。';

  @override
  String get attachment_no_inline_preview =>
      '此文件类型不支持内嵌预览。请保存或分享原始文件，以便在其他应用中打开。';

  @override
  String get attachment_image_failed => '无法解码此图片。您仍可保存或分享原始文件。';

  @override
  String get attachment_text_truncated => '预览内容已截短。请保存或分享文件以阅读完整内容。';

  @override
  String get attachment_text_unavailable => '无法将此文件显示为文本。请保存或分享原始文件。';

  @override
  String get attachment_pdf_failed => '无法预览此 PDF。请保存或分享原始文件。';

  @override
  String get attachment_pdf_unavailable => 'PDF 预览仅在 Android 上可用。您仍可保存或分享此文件。';

  @override
  String attachment_pdf_page(int page, int total) {
    return '第 $page 页，共 $total 页';
  }

  @override
  String get attachment_previous_page => '上一页';

  @override
  String get attachment_next_page => '下一页';

  @override
  String get attachment_loading => '正在加载预览…';

  @override
  String get attachment_document_text_notice => '文本预览。布局、图片和格式可能与原文件不同。';

  @override
  String get attachment_document_failed => '无法预览此文档。请保存或分享原始文件。';

  @override
  String get attachment_document_empty => '此文档中未找到可读文本。';

  @override
  String get attachment_video_failed => '无法播放此视频。其格式或编解码器可能不受支持。请保存或分享原始文件。';

  @override
  String get attachment_video_play => '播放';

  @override
  String get attachment_video_pause => '暂停';

  @override
  String get attachment_video_mute => '静音';

  @override
  String get attachment_video_unmute => '取消静音';

  @override
  String get attachment_video_seek => '视频进度';

  @override
  String get attachment_close => '关闭预览';

  @override
  String get attachment_retry => '重试';

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
  String get theme_palette => '颜色主题';

  @override
  String get theme_palette_gold => '金色';

  @override
  String get theme_palette_purple => '紫色';

  @override
  String get theme_palette_orange => '橙色';

  @override
  String get theme_palette_green => '绿色';

  @override
  String get theme_palette_blue => '蓝色';

  @override
  String get theme_palette_red => '红色';

  @override
  String get theme_palette_teal => '青绿色';

  @override
  String get theme_palette_pink => '粉色';

  @override
  String get theme_palette_indigo => '靛蓝色';

  @override
  String get theme_palette_cyan => '青色';

  @override
  String get assets_recent_subtitle => '查找 Hermes 在已保存的聊天中分享的文件';

  @override
  String get assets_scope_notice =>
      '仅显示 Hermes 在已保存的回复中明确分享的已生成文件。这里只展示部分聊天历史，并非完整的文件或附件目录。引用的文件可能已不存在。';

  @override
  String get assets_download_limit =>
      '文件仅在点按时加载。预览和下载的单个文件大小上限均为 25 MiB；更大的文件请通过仪表盘获取。';

  @override
  String get assets_search_hint => '搜索找到的文件或来源聊天';

  @override
  String get assets_all => '全部';

  @override
  String get assets_images => '图片';

  @override
  String get assets_audio => '音频';

  @override
  String get assets_video => '视频';

  @override
  String get assets_documents => '文档和其他文件';

  @override
  String get assets_empty => '在已扫描的消息中未找到资产';

  @override
  String get assets_empty_detail =>
      '扫描更多聊天或更早的消息，以查看更早的历史。普通附件和未链接的文件不会在此建立索引。';

  @override
  String get assets_no_matches => '未找到匹配的资产';

  @override
  String get assets_load_more_chats => '扫描更多聊天';

  @override
  String get assets_load_older_messages => '扫描更早的消息';

  @override
  String get assets_load_failed => '部分历史记录无法读取。结果不完整。请检查仪表盘连接并重试。';

  @override
  String get assets_retry_failed => '重试读取失败的历史记录';

  @override
  String get assets_partial => '服务器报告历史记录不完整。请检查仪表盘后刷新。';

  @override
  String assets_scan_summary(int files, int chats) {
    return '已扫描 $chats 个聊天，找到 $files 处文件引用';
  }

  @override
  String assets_open_chat(String title) {
    return '打开聊天：$title';
  }

  @override
  String get assets_file_too_large => '此文件超出下载大小上限。请打开仪表盘进行下载。';

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      '一次性问题。将在 72 小时后自动归档；任何值得保留的内容都会被记住。';

  @override
  String get archive_chat => '归档聊天';

  @override
  String get unarchive_chat => '取消归档聊天';

  @override
  String get chat_archived => '聊天已归档';

  @override
  String get chat_unarchived => '聊天已取消归档';

  @override
  String could_not_update_chat_archive(Object error) {
    return '无法更新聊天归档状态：$error';
  }

  @override
  String get quick_chat_description => '一次性问题。';

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
  String get approval_needed_description => '有命令正在等待你的批准或拒绝。';

  @override
  String get approve => '批准';

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
  String get archived_conversations_appear_here =>
      '这里只显示已归档的对话。旧聊天仍保留在“所有聊天”中。';

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
  String get agent => '智能体';

  @override
  String get autonomous_agents => '自主智能体';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      '后台恢复不可用 — 旧版传输';

  @override
  String get background_task_completed => '后台任务完成';

  @override
  String get background_task_completed_description => '后台终端命令已完成。';

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
  String get code_format => 'Code';

  @override
  String get coming_next => '敬请期待';

  @override
  String get command => '命令';

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
  String get could_not_open_link => '无法打开此链接。';

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
  String get credit_notifications => '额度通知';

  @override
  String get credit_notifications_description => '额度使用已停止或恢复。';

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
  String get cron_jobs => 'Cron 任务';

  @override
  String cron_schedule_timezone(Object zone) {
    return '排程时区：$zone';
  }

  @override
  String get crons_upcoming => '即将运行';

  @override
  String get crons_history => '运行历史';

  @override
  String cron_time_with_zone(Object time, Object zone) {
    return '$time（$zone）';
  }

  @override
  String cron_time_zone_unknown(Object time) {
    return '$time（时区未知）';
  }

  @override
  String get cron_no_next_run => '未安排下次运行';

  @override
  String get cron_status_scheduled => '已排程';

  @override
  String get cron_status_paused => '已暂停';

  @override
  String cron_delivers_to(Object target) {
    return '投递至 $target';
  }

  @override
  String get cron_upcoming_empty_title => '暂无已排程任务';

  @override
  String get cron_upcoming_empty_message =>
      '当前没有待运行的任务。请在 Cron 任务中创建，或让智能体安排一个。';

  @override
  String get cron_upcoming_unavailable => '无法显示已排程任务';

  @override
  String get cron_upcoming_needs_dashboard =>
      '已排程任务需要仪表盘连接。此地址不提供 Cron 排程。请检查仪表盘地址和主机支持情况。';

  @override
  String get cron_upcoming_needs_dashboard_auth =>
      '已排程任务需要仪表盘认证。请为此连接添加仪表盘用户名和密码，或启用代理模式。';

  @override
  String get cron_upcoming_dashboard_unreachable =>
      '无法连接到仪表盘。请检查主机、仪表盘端口和网络，然后重试。';

  @override
  String get cron_upcoming_load_failed => '无法读取已排程任务。请检查仪表盘连接并重试。';

  @override
  String get cron_upcoming_refresh_failed => '无法刷新排程。正在显示上次成功读取的结果。';

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
  String get enable_notifications => '启用通知';

  @override
  String get enable_notifications_description => '关闭后将禁用以下所有通知。';

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
  String get input_needed => '需要输入';

  @override
  String get input_needed_description => 'Hermes 提出了问题，或需要密码或密钥。';

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
  String get memory_about_you => '关于你';

  @override
  String get memory_agent_notes => '助手笔记';

  @override
  String get memory_builtin_scope =>
      '此配置档案的 USER.md 和 MEMORY.md 中保存的事实。这里不显示外部记忆服务（包括 MemPalace）的内容。';

  @override
  String get memory_read_only => '仅供查看。可在聊天中请 Hermes 更正或忘记某条事实。';

  @override
  String get memory_unavailable =>
      '此网关或配置档案无法提供已保存的事实。请检查所选配置档案，并在需要时更新 Hermes。';

  @override
  String get memory_load_error => '请检查仪表盘连接和身份验证，然后重试。';

  @override
  String get memory_read_full_fact => '阅读完整事实';

  @override
  String get memory_full_fact_requires_update =>
      '查看完整事实需要更新的 Hermes 网关。请更新 Hermes 并刷新列表。';

  @override
  String get memory_fact_detail_error => '无法加载完整事实。它可能已更改；请刷新列表后重试。';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'Hermes 记住的事实会显示在这里。';

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
  String get notifications => '通知';

  @override
  String get notifications_permission_denied =>
      '系统已阻止通知。请在 Android 设置中允许此应用发送通知。';

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
  String get plugin_notifications => '插件通知';

  @override
  String get plugin_notifications_description => '应用在后台时，网关发来了通知。';

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
  String get recently_active => '最近活跃';

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
  String get response_complete => '响应完成';

  @override
  String get response_complete_description => '应用在后台时，一轮对话已完成。';

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
  String send_failed_api_only_permission_denied(Object error) {
    return '发送失败：$error。服务器拒绝了 API 密钥主体的此次写入。如果该会话归 Dashboard 所有，为此连接添加 Dashboard 用户名和密码可能即可发送；服务器也可能是有意拒绝。';
  }

  @override
  String get send_message => '发送消息';

  @override
  String get send_test_notification => '发送测试通知';

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
  String get test_notification_body => '如果你能看到这条通知，说明通知功能正常。';

  @override
  String get test_notification_sent => '已发送测试通知。';

  @override
  String get test_notification_title => 'Hermes 通知测试';

  @override
  String get test_notification_unsupported => '无法发送通知——请检查系统是否允许通知。';

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
      '此项目需要先添加文件夹才能在其中开始聊天。添加文件夹后请重试。';

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
  String get received_outcome_unknown => '本轮对话已结束 — 结果未确认';

  @override
  String get turn_completed => '本轮对话已完成';

  @override
  String get turn_failed => '对话失败';

  @override
  String get turn_failed_description => '后台对话以错误结束。';

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
  String get message_metadata => 'Message details';

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
  String tool_start_observed(Object time) {
    return '观察到开始 $time（本地时间）';
  }

  @override
  String tool_last_observed(Object time) {
    return '最后观察时间 $time（本地时间）';
  }

  @override
  String tool_result_recorded(Object time) {
    return '结果记录时间 $time（本地时间）';
  }

  @override
  String get tool_time_unavailable => '时间不可用';

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

  @override
  String get pin_chat => '置顶聊天';

  @override
  String get unpin_chat => '取消置顶';

  @override
  String get pinned_chats => '已置顶';

  @override
  String could_not_update_chat_pin(Object error) {
    return '无法更新聊天置顶：$error';
  }

  @override
  String get could_not_save_chat_spaces => '无法在此设备上保存聊天空间';

  @override
  String get update_available => '有可用更新';

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
      'GitHub 上已有更新的 Hermes Android 版本。';

  @override
  String get release_notes => '发行说明';

  @override
  String get view_release => '查看发行版';

  @override
  String get skip_this_version => '跳过此版本';

  @override
  String get later => '稍后';

  @override
  String get check_for_updates => '检查更新';

  @override
  String get check_for_updates_on_launch => '启动时检查更新';

  @override
  String get you_re_on_the_latest_version => '已是最新版本。';

  @override
  String get couldn_t_check_for_updates => '无法检查更新。';

  @override
  String get chat_density => '聊天密度';

  @override
  String chat_density_2(Object label) {
    return '聊天密度：$label';
  }

  @override
  String get chat_density_comfortable => '舒适';

  @override
  String get chat_density_compact => '紧凑';

  @override
  String get chat_density_comfortable_description => '每条消息上方带有发送者标签的更宽松气泡。';

  @override
  String get chat_density_compact_description => '更紧凑的无标签气泡，屏幕上可以显示更多消息。';

  @override
  String chat_density_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String
  get compact_removes_the_you_and_hermes_labels_and_trims_bubble_padding_spacing_and_side_margins =>
      '紧凑模式会去掉 You 和 Hermes 标签，并缩小气泡内边距、间距和两侧边距。';

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
  String get background_work => '后台运行';

  @override
  String get keep_chats_active_in_background => '在后台保持聊天连接';

  @override
  String get background_work_description =>
      '应用在后台时，保持用户发起的聊天连接。空闲连接可能会断开。此功能会增加电量和流量消耗。关闭后不会停止服务器上的任务。';

  @override
  String get background_work_limits =>
      'Android 仍可能在 Doze 模式下暂停连接或结束应用进程。进程结束后的通知需要单独设置推送。不支持强行停止后的通知。';

  @override
  String get background_work_disclosure => '后台保护开启时，即使关闭了可选的聊天通知，仍会显示必需的服务通知。';

  @override
  String get battery_optimisation_settings => '电池优化设置';

  @override
  String get battery_optimisation_description =>
      '打开 Android 设置以查看电池限制。不会自动申请豁免，更改设置也不能保证通知送达。';

  @override
  String get battery_settings_unavailable => '无法在此设备上打开电池设置。';

  @override
  String get background_work_save_failed => '无法保存后台运行设置。';

  @override
  String get ongoing_chat_channel_name => '进行中的聊天';

  @override
  String get ongoing_chat_channel_description => '用户发起的未完成聊天的静默状态更新';

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
  String get activity_status_unconfirmed => '状态未确认';

  @override
  String get activity_recently_updated => '最近更新';

  @override
  String get activity_reconnecting => '正在重新连接 — 正在检查轮次状态';

  @override
  String get activity_outcome_unknown => '无法确认本轮对话的结果。请打开聊天查看。';

  @override
  String get activity_chat_updated_detail => '网关已记录聊天活动；无法获取轮次的实时状态。';

  @override
  String get activity_updated => '已更新';

  @override
  String get activity_empty_title => '暂无近期活动';

  @override
  String get activity_empty_detail => '在此应用中启动的轮次，以及过去7天内更新的网关聊天都会显示在这里。';

  @override
  String get activity_read_error => '活动功能无法读取轮次记录或网关聊天。请检查连接后重试。';

  @override
  String get activity_chat_unavailable => '此聊天已不可用，或无法连接到网关。';

  @override
  String get activity_partial_title => '活动已部分加载';

  @override
  String get activity_partial_detail => '目前仅显示网关活动的有限范围。可能还有更多聊天，请下拉刷新。';

  @override
  String get provider_usage => '使用记录';

  @override
  String get provider_usage_notice =>
      'Hermes最近30天的使用量，并非账户余额或模型定价。请在Hermes服务器配置凭据；此应用不保存提供商API密钥。';

  @override
  String get provider_usage_failed => '无法加载使用记录。';

  @override
  String get provider_usage_empty => '此提供商暂无使用记录。';

  @override
  String provider_usage_counts(String sessions, String input, String output) {
    return '$sessions 个会话 · 输入：$input · 输出：$output';
  }

  @override
  String provider_usage_costs(String estimated, String actual) {
    return '估算：$estimated · 报告：$actual';
  }

  @override
  String get provider_quota_codex => 'OpenAI Codex 订阅';

  @override
  String get provider_quota_claude => 'Claude 订阅';

  @override
  String get provider_quota_openai_api => 'OpenAI API 已记录用量';

  @override
  String get provider_quota_notice =>
      '由提供商报告的订阅用量周期，与 Hermes 记录的用量及 API 计费分开显示。各账户单独列出；达到模型限额并不代表整个账户的配额已耗尽。';

  @override
  String get provider_quota_windows_notice =>
      'Codex 和 Claude 订阅设有五小时会话限额和每周限额。仅显示提供商报告的周期；未报告的限额和重置时间仍不可用。每周限额可能适用于整个账户或特定模型。';

  @override
  String get provider_quota_five_hour_session => '5小时会话';

  @override
  String get provider_quota_unavailable => '订阅配额不可用。';

  @override
  String get provider_quota_failed => '无法刷新订阅配额。保留的数值来自上次查询。';

  @override
  String get provider_quota_account => '账户';

  @override
  String get provider_quota_unknown => '未知';

  @override
  String provider_quota_state(String state) {
    return '账户状态：$state';
  }

  @override
  String provider_quota_scope(String scope) {
    return '适用范围：$scope';
  }

  @override
  String provider_quota_percent(String used, String remaining) {
    return '已用 $used% · 剩余 $remaining%';
  }

  @override
  String provider_quota_reset(String reset) {
    return '重置时间：$reset';
  }

  @override
  String get provider_quota_reset_unknown => '重置时间不可用。';

  @override
  String get auxiliary_models => '辅助模型';

  @override
  String get auxiliary_notice => '为各任务选择模型。自定义端点必须在服务器管理。自动模式遵循任务的继承规则。';

  @override
  String get auxiliary_inherit => '自动（继承）';

  @override
  String get auxiliary_unavailable => '辅助设置不可用。';

  @override
  String get provider_oauth_title => '提供商登录';

  @override
  String get provider_oauth_more_subtitle => '管理 Hermes 主机上的提供商登录';

  @override
  String get provider_oauth_settings_subtitle =>
      '在 Hermes 主机上登录；提供商令牌不会保存在此设备上';

  @override
  String get provider_oauth_intro =>
      '在外部浏览器中登录提供商。令牌仅存储在 Hermes 主机上，不会保存在此设备上。登录不会选择此应用中的聊天模型。';

  @override
  String get provider_oauth_defaults_notice =>
      '某些主机流程（包括替换 Nous 免费套餐账户）可能会更新主机默认设置。登录后请检查主机设置。';

  @override
  String get provider_oauth_transport_init_failed =>
      '无法初始化所选的安全仪表板连接。请检查其 TLS 身份和连接设置。';

  @override
  String get provider_oauth_https_required => '提供商登录需要通过 HTTPS 连接到 Hermes 仪表板。';

  @override
  String get provider_oauth_auth_required => '登录前请配置仪表板密码验证或可信代理。';

  @override
  String get provider_oauth_catalog_failed =>
      '此主机不支持提供商登录。请检查仪表板身份验证；如果主机不支持提供商 OAuth，请更新主机。';

  @override
  String get provider_oauth_expired => '登录已过期。请重新开始。';

  @override
  String get provider_oauth_start_failed => '无法启动安全的提供商登录。请重试。';

  @override
  String get provider_oauth_denied => '登录被拒绝。请重新开始。';

  @override
  String get provider_oauth_cancelled => '登录已取消。';

  @override
  String get provider_oauth_host_failed => '主机无法完成登录。请重新开始。';

  @override
  String get provider_oauth_poll_failed => '无法检查登录状态。请重新开始。';

  @override
  String provider_oauth_cancellation_unconfirmed(String message) {
    return '$message 无法确认取消；主机会话可能会持续到过期为止。';
  }

  @override
  String get provider_oauth_browser_failed => '无法打开外部浏览器。请重试或取消登录。';

  @override
  String get provider_oauth_retry => '重试';

  @override
  String provider_oauth_complete(String provider) {
    return '完成 $provider 的登录';
  }

  @override
  String get provider_oauth_code_instruction => '请在提供商页面输入此临时代码：';

  @override
  String get provider_oauth_waiting => '正在等待批准。此会话将自动过期。';

  @override
  String get provider_oauth_open_browser => '在浏览器中打开提供商';

  @override
  String get provider_oauth_cancel => '取消登录';

  @override
  String get provider_oauth_signed_out => '未在主机上登录';

  @override
  String get provider_oauth_sign_in_again => '重新登录';

  @override
  String get provider_oauth_sign_in => '登录';

  @override
  String get provider_oauth_cli_required =>
      '请在 Hermes 主机上使用提供商 CLI 登录。此主机不支持该提供商的应用内登录。';

  @override
  String get provider_oauth_checking_account => '已收到授权。正在检查主机账户…';

  @override
  String get provider_oauth_verification_unavailable =>
      '已收到授权；无法验证账户。请打开用量页面以刷新账户用量。';

  @override
  String provider_oauth_verified_account(String email) {
    return '已在 Hermes 主机上以 $email 登录。请打开用量页面以刷新账户用量。';
  }

  @override
  String get provider_oauth_credentials_unverified => '主机报告凭据可用；账户身份尚未验证。';

  @override
  String get provider_oauth_account_status_unknown => '无法获取主机账户状态。';

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
  String get projects_root_title => '服务器上的项目文件夹';

  @override
  String get projects_root_more_subtitle => '服务器上新建项目文件夹的位置';

  @override
  String get projects_root_description =>
      '在此手机上创建的项目会在这里获得文件夹。将其指向 Hermes 自身使用的文件夹，手机和服务器就能共享同一批项目。';

  @override
  String get projects_root_label => '项目根路径';

  @override
  String projects_root_default_hint(String path) {
    return '服务器默认值：$path';
  }

  @override
  String get projects_root_locked_title => '由服务器设定';

  @override
  String get projects_root_locked_explanation =>
      '此服务器将文件访问限制在单一根目录内，因此无法在应用中更改项目文件夹。';

  @override
  String get projects_root_saved => '已保存项目文件夹。';

  @override
  String get projects_root_reset => '使用服务器默认值';

  @override
  String get projects_root_invalid_empty => '请输入文件夹路径。';

  @override
  String get projects_root_invalid_absolute => '请输入以斜杠开头的绝对路径。';

  @override
  String get projects_root_invalid_segments => '请从路径中移除点号片段和控制字符。';

  @override
  String get projects_root_unsupported =>
      '此连接不支持。读取或更改服务器上的项目文件夹需要具有仪表板访问权限的 Desktop Gateway 连接。';

  @override
  String get projects_root_unavailable => '无法读取服务器上的项目文件夹。请检查仪表板连接后重试。';

  @override
  String get adopt_folder_action => '添加现有文件夹';

  @override
  String adopt_folder_description(String root) {
    return '$root 下尚未注册为项目的文件夹。';
  }

  @override
  String adopt_folder_registered(String name) {
    return '已是项目：$name';
  }

  @override
  String get adopt_folder_none => '此路径下的所有文件夹都已是项目。';

  @override
  String get adopt_folder_unsupported => '此连接无法列出服务器文件夹。请改为输入现有文件夹的绝对路径。';

  @override
  String adopt_folder_failed(String error) {
    return '无法列出服务器文件夹：$error';
  }

  @override
  String get adopt_folder_manual_label => '现有文件夹路径';

  @override
  String get adopt_folder_name_label => '项目名称';

  @override
  String get adopt_folder_add => '添加为项目';

  @override
  String adopt_folder_added(String name, String path) {
    return '$name 现在使用 $path';
  }

  @override
  String adopt_folder_error(String error) {
    return '无法添加该文件夹：$error';
  }

  @override
  String adopt_folder_folderless(String name) {
    return '已创建 $name，但未关联文件夹。请在服务器上的 Hermes 中关联。';
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
  String get nextgen_toggle => 'NextGen 界面';

  @override
  String get nextgen_toggle_subtitle => '全新设计：一次登录、实时聊天和网络发现。你的网关和聊天与此界面共享。';

  @override
  String get nextgen_single_login => '使用单一登录';

  @override
  String get nextgen_single_login_subtitle => '只需仪表板地址和一次登录即可添加网关。';

  @override
  String get ng_allow_this_command => '允许执行此命令？';

  @override
  String ng_hermes_wants_to_run_this_with(Object tool) {
    return 'Hermes 想使用 $tool 执行此操作。';
  }

  @override
  String get ng_hermes_wants_to_run_this => 'Hermes 想执行此操作。';

  @override
  String get ng_hermes_has_a_question => 'Hermes 有一个问题';

  @override
  String get ng_hermes_has_questions => 'Hermes 有几个问题';

  @override
  String get ng_password_for_sudo => 'sudo 密码';

  @override
  String get ng_hermes_needs_your_sudo_password_to =>
      'Hermes 需要你的 sudo 密码来运行此命令。';

  @override
  String get ng_a_secret_value => '机密值';

  @override
  String ng_value_for(Object variable) {
    return '$variable 的值';
  }

  @override
  String get ng_your_password_manager => '你的密码管理器';

  @override
  String ng_unlock(Object name) {
    return '解锁 $name';
  }

  @override
  String ng_hermes_needs_unlocked_to_sign_in(Object name) {
    return 'Hermes 需要先解锁 $name，才能为你登录。';
  }

  @override
  String get ng_sign_in_code => '登录验证码';

  @override
  String get ng_enter_the_sign_in_code => '输入登录验证码。';

  @override
  String ng_enter_the_sign_in_code_for(Object site) {
    return '输入 $site 的登录验证码。';
  }

  @override
  String get ng_save_a_login => '保存登录信息？';

  @override
  String ng_save_your_login(Object site) {
    return '保存你的 $site 登录信息？';
  }

  @override
  String ng_couldn_t_load_this_chat(Object error) {
    return '无法加载此聊天：$error';
  }

  @override
  String ng_live_updates_are_unavailable(Object error) {
    return '实时更新不可用：$error';
  }

  @override
  String ng_preparing(Object name) {
    return '正在准备 $name…';
  }

  @override
  String get ng_the_turn_failed => '本轮对话失败。';

  @override
  String ng_couldn_t_stop(Object error) {
    return '无法停止：$error';
  }

  @override
  String get ng_server_access => '服务器访问';

  @override
  String get ng_sign_in => '登录';

  @override
  String get ng_live_connection => '实时连接';

  @override
  String get ng_check_that_tailscale_is_on_on => '请确认此手机和服务器上的 Tailscale 均已开启。';

  @override
  String get ng_check_the_address_and_that_the => '请检查地址，并确认代理已转发到仪表盘。';

  @override
  String get ng_use_the_same_network_as_the =>
      '请使用与服务器相同的网络，并使用 --host 0.0.0.0 启动仪表盘，以便其他设备访问。';

  @override
  String get ng_check_the_address_vpn_or_tailscale =>
      '请检查地址、VPN 或 Tailscale 连接。';

  @override
  String get ng_not_checked_yet => '尚未检查。';

  @override
  String get ng_checking => '正在检查…';

  @override
  String ng_hermes_answers_at(Object version, Object address) {
    return 'Hermes $version 可通过 $address 访问。';
  }

  @override
  String get ng_something_answered_but_not_a_hermes => '有服务响应，但不是 Hermes 仪表盘。';

  @override
  String ng_something_answered_http_but_not_a(Object status) {
    return '有服务响应（HTTP $status），但不是 Hermes 仪表盘。';
  }

  @override
  String get ng_use_the_dashboard_s_address_and =>
      '请使用仪表盘的地址和端口（默认为 9119），而不是 API 服务器的地址和端口。';

  @override
  String get ng_cloudflare_access_turned_the_service_token =>
      'Cloudflare Access 拒绝了服务令牌。';

  @override
  String get ng_cloudflare_access_is_in_front_of =>
      '此地址前方配置了 Cloudflare Access。';

  @override
  String get ng_check_the_service_token_and_its => '请检查服务令牌及其 Service Auth 策略。';

  @override
  String get ng_add_a_cloudflare_access_service_token =>
      '为此地址添加 Cloudflare Access 服务令牌。';

  @override
  String get ng_the_server_asks_for_a_client => '服务器要求提供客户端证书。';

  @override
  String get ng_pick_the_client_certificate_for_this => '为此网关选择客户端证书，然后再次测试。';

  @override
  String get ng_needs_server_access_first => '请先连接服务器。';

  @override
  String get ng_needs_a_sign_in_first => '请先登录。';

  @override
  String ng_signed_in_as(Object name) {
    return '已登录为 $name。';
  }

  @override
  String get ng_this_dashboard_doesn_t_need_a => '此仪表盘无需登录。';

  @override
  String get ng_the_saved_sign_in_has_expired => '已保存的登录信息已过期。';

  @override
  String get ng_sign_in_again => '重新登录。';

  @override
  String get ng_too_many_sign_in_attempts => '登录尝试次数过多。';

  @override
  String get ng_wait_a_minute_then_check_again => '请稍等一分钟后再试。';

  @override
  String ng_the_gateway_answered(Object message) {
    return '网关返回：$message。';
  }

  @override
  String get ng_sign_in_again_or_update_hermes => '请重新登录，或更新 Hermes。';

  @override
  String ng_couldn_t_check_the_sign_in(Object error) {
    return '无法检查登录状态：$error';
  }

  @override
  String ng_the_gateway_wouldn_t_issue_a(Object message) {
    return '网关无法签发聊天凭证（$message）。';
  }

  @override
  String get ng_the_chat_connection_opened_and_the => '聊天连接已建立，网关已确认就绪。';

  @override
  String get ng_the_gateway_never_said_it_was => '网关始终未确认就绪。';

  @override
  String get ng_check_that_the_agent_is_running => '请确认服务器上的代理正在运行。';

  @override
  String get ng_the_gateway_refused_the_chat_connection =>
      '网关拒绝了聊天连接（HTTP 403）。';

  @override
  String get ng_this_dashboard_has_no_chat_endpoint => '此仪表盘没有聊天端点（/api/ws）。';

  @override
  String ng_the_chat_connection_failed(Object detail) {
    return '聊天连接失败：$detail';
  }

  @override
  String get ng_use_the_exact_address_the_dashboard => '请使用仪表盘配置的完整地址。';

  @override
  String get ng_update_hermes => '更新 Hermes。';

  @override
  String get ng_make_sure_the_proxy_allows_websocket =>
      '请确认代理允许在 /api/ws 上进行 WebSocket 升级。';

  @override
  String get ng_offline => '离线';

  @override
  String get ng_connecting => '正在连接…';

  @override
  String get ng_connected => '已连接';

  @override
  String get ng_reconnecting => '正在重新连接…';

  @override
  String get ng_signed_out => '已退出登录';

  @override
  String get ng_connection_failed => '连接失败';

  @override
  String get ng_rate_limited_by_gateway => '已触发网关限流';

  @override
  String ng_couldn_t_open_the_chat_connection(Object message) {
    return '无法建立聊天连接：$message';
  }

  @override
  String get ng_the_gateway_returned_no_websocket_ticket =>
      '网关未返回 WebSocket 票据。';

  @override
  String get ng_connection_lost => '连接已断开';

  @override
  String get ng_this_dashboard_has_no_chat_endpoint_2 =>
      '此仪表板没有聊天端点（/api/ws）。请更新 Hermes。';

  @override
  String get ng_the_gateway_refused_the_chat_connection_2 =>
      '网关拒绝了聊天连接。请检查地址是否与仪表板配置的主机匹配，并确认已启用嵌入式聊天。';

  @override
  String ng_the_gateway_refused(Object method) {
    return '网关拒绝了 $method。';
  }

  @override
  String ng_couldn_t_read_your_saved_gateways(Object error) {
    return '无法读取已保存的网关：$error';
  }

  @override
  String get ng_applies_to_new_chats => '仅应用于新聊天';

  @override
  String ng_couldn_t_change(Object label, Object error) {
    return '无法更改$label：$error';
  }

  @override
  String get ng_capabilities => '功能';

  @override
  String get ng_skills => '技能';

  @override
  String get ng_toolsets => '工具集';

  @override
  String get ng_search => '搜索';

  @override
  String get ng_couldn_t_load => '无法加载';

  @override
  String get ng_try_again => '重试';

  @override
  String get ng_no_skills => '没有技能';

  @override
  String get ng_no_toolsets => '没有工具集';

  @override
  String get ng_no_mcp_servers => '没有 MCP 服务器';

  @override
  String get ng_that_file_is_too_large_to => '该文件太大，无法作为证书使用。';

  @override
  String ng_the_certificate_couldn_t_be_imported(Object error) {
    return '无法导入证书：$error';
  }

  @override
  String get ng_now_pick_its_private_key => '现在选择对应的私钥。';

  @override
  String get ng_now_pick_its_certificate => '现在选择对应的证书。';

  @override
  String get ng_that_file_isn_t_a_certificate => '该文件不是证书或私钥。';

  @override
  String get ng_if_a_proxy_in_front_of =>
      '如果此地址前的代理要求客户端证书，请在此选择证书，以便测试、登录和聊天时都能出示。';

  @override
  String get ng_client_certificates_are_only_used_with =>
      '客户端证书仅用于 https:// 地址。';

  @override
  String get ng_remove => '移除';

  @override
  String get ng_certificate_password => '证书密码';

  @override
  String get ng_importing => '正在导入…';

  @override
  String get ng_pick_certificate => '选择证书';

  @override
  String get ng_pick_a_different_certificate => '选择其他证书';

  @override
  String get ng_accepts_p12_pfx_or_pem_certificate =>
      '支持 .p12/.pfx 文件，或 PEM 证书和密钥文件。密钥会保存在此应用的私有存储空间中。';

  @override
  String get ng_photos => '照片';

  @override
  String get ng_camera => '相机';

  @override
  String get ng_files => '文件';

  @override
  String ng_you_can_attach_up_to_files(Object count) {
    return '最多可附加 $count 个文件。';
  }

  @override
  String ng_couldn_t_read(Object name) {
    return '无法读取 $name。';
  }

  @override
  String ng_couldn_t_prepare_that_file(Object error) {
    return '无法处理该文件：$error';
  }

  @override
  String get ng_hermes_is_still_working => 'Hermes 仍在处理中';

  @override
  String get ng_steer => '引导';

  @override
  String get ng_adds_this_to_the_running_turn => '在当前轮次的下一步中添加此内容';

  @override
  String get ng_queue => '排队';

  @override
  String get ng_sends_it_when_the_turn_finishes => '当前轮次结束后发送';

  @override
  String get ng_stop_and_send => '停止并发送';

  @override
  String get ng_stops_the_turn_then_sends_this => '停止当前轮次，然后发送此内容';

  @override
  String ng_dictation_stopped(Object message) {
    return '听写已停止：$message';
  }

  @override
  String get ng_speech_recognition_isn_t_available => '语音识别不可用。';

  @override
  String get ng_working => '处理中';

  @override
  String get ng_ready => '就绪';

  @override
  String get ng_chats => '聊天';

  @override
  String get ng_new_chat => '新建聊天';

  @override
  String get ng_usage => '用量';

  @override
  String get ng_rename_chat => '重命名聊天';

  @override
  String ng_couldn_t_rename(Object error) {
    return '无法重命名：$error';
  }

  @override
  String get ng_this_chat => '此聊天';

  @override
  String get ng_input_tokens => '输入 Token';

  @override
  String get ng_output_tokens => '输出 Token';

  @override
  String get ng_reasoning_tokens => '推理 Token';

  @override
  String get ng_cache_reads => '缓存读取';

  @override
  String get ng_api_calls => 'API 调用';

  @override
  String get ng_cost => '费用';

  @override
  String get ng_context => '上下文';

  @override
  String get ng_your_sign_in_expired => '登录已过期。';

  @override
  String get ng_sign_in_2 => '登录';

  @override
  String get ng_retry => '重试';

  @override
  String get ng_what_should_we_work_on => '我们要做些什么？';

  @override
  String get ng_ask_hermes_anything_it_can_run =>
      '向 Hermes 提问。它可以运行工具、浏览网页，还能处理服务器上的文件。';

  @override
  String ng_working_2(Object frame) {
    return '正在处理 · $frame';
  }

  @override
  String get ng_default_model => '默认模型';

  @override
  String get ng_listening => '正在聆听…';

  @override
  String get ng_steer_or_queue_a_message => '发送指示或排队发送消息';

  @override
  String get ng_message_hermes => '给 Hermes 发消息';

  @override
  String get ng_attach => '添加附件';

  @override
  String get ng_stop_dictation => '停止听写';

  @override
  String get ng_dictate => '语音输入';

  @override
  String get ng_stop => '停止';

  @override
  String get ng_send => '发送';

  @override
  String get ng_steered => '已调整指示';

  @override
  String get ng_copied => '已复制';

  @override
  String ng_not_sent(Object reason) {
    return '未发送：$reason';
  }

  @override
  String get ng_thinking => '正在思考…';

  @override
  String get ng_thought => '思考';

  @override
  String ng_used(Object name) {
    return '已使用 $name';
  }

  @override
  String ng_used_tools(Object count) {
    return '已使用 $count 个工具';
  }

  @override
  String get ng_copy => '复制';

  @override
  String get ng_the_gateway_connection_dropped_try_again => '网关连接已断开，请重试。';

  @override
  String get ng_allow_once => '允许一次';

  @override
  String get ng_allow_for_this_chat => '在此聊天中允许';

  @override
  String get ng_always_allow => '始终允许';

  @override
  String get ng_deny => '拒绝';

  @override
  String get ng_your_answer => '你的回答';

  @override
  String get ng_or_type_an_answer => '或输入回答';

  @override
  String get ng_skip => '跳过';

  @override
  String get ng_answer => '回答';

  @override
  String get ng_cancel => '取消';

  @override
  String get ng_username_or_email => '用户名或邮箱';

  @override
  String get ng_password => '密码';

  @override
  String get ng_not_now => '暂不';

  @override
  String get ng_save => '保存';

  @override
  String get ng_enter_both_the_client_id_and =>
      '请同时填写 Client ID 和 Client Secret，或都留空。';

  @override
  String get ng_enter_your_username_and_password => '请输入用户名和密码。';

  @override
  String ng_couldn_t_save_the_sign_in(Object error) {
    return '无法保存登录信息：$error';
  }

  @override
  String get ng_wrong_username_or_password => '用户名或密码错误。';

  @override
  String get ng_too_many_attempts_wait_a_moment => '尝试次数过多，请稍等片刻再试。';

  @override
  String get ng_welcome_to_hermes => '欢迎使用 Hermes';

  @override
  String get ng_add_a_gateway => '添加网关';

  @override
  String get ng_connect_to_your_hermes_agent_dashboard =>
      '连接到你的 Hermes Agent 控制面板。使用一个地址和一次登录，即可访问聊天、工具和设置。登录前不会发送任何内容。';

  @override
  String get ng_connect_to_another_hermes_agent_dashboard =>
      '连接到另一个 Hermes Agent 控制面板。你仍会登录已保存的控制面板。';

  @override
  String get ng_dashboard_address => '控制面板地址';

  @override
  String get ng_testing => '正在测试…';

  @override
  String get ng_test => '测试';

  @override
  String get ng_where_your_hermes_dashboard_runs_lan =>
      '你的 Hermes 控制面板所在的位置：局域网、Tailscale 或 HTTPS。';

  @override
  String get ng_find_on_my_network => '在我的网络中查找';

  @override
  String get ng_which_address_do_i_use => '我应该使用哪个地址？';

  @override
  String get ng_behind_cloudflare_access => '使用 Cloudflare Access 保护？';

  @override
  String get ng_need_a_client_certificate => '需要客户端证书？';

  @override
  String get ng_this_address_isn_t_private_and =>
      '此地址不是私有地址，且未使用 https://，因此你的密码和聊天内容会以未加密的形式通过互联网传输。请改用 https://、Tailscale 或你自己的网络。';

  @override
  String get ng_continue_to_sign_in => '继续登录';

  @override
  String get ng_use_the_classic_interface_instead => '改用经典界面';

  @override
  String get ng_if_cloudflare_access_protects_this_address =>
      '如果此地址受 Cloudflare Access 保护，请在 Cloudflare Zero Trust（Access，Service credentials）中创建服务令牌，并为对应的 Access 应用添加 Service Auth 策略。';

  @override
  String get ng_a_service_token_is_saved_for => '已为此地址保存服务令牌';

  @override
  String get ng_forget => '移除';

  @override
  String get ng_client_id => 'Client ID';

  @override
  String get ng_client_secret => 'Client Secret';

  @override
  String get ng_stored_encrypted_on_this_phone_and => '加密存储在此手机上，且只发送到此地址。';

  @override
  String get ng_hermes_is_reachable => '已连接到 Hermes';

  @override
  String ng_hermes_is_reachable_2(Object version) {
    return '已连接到 Hermes $version';
  }

  @override
  String get ng_sign_in_is_tested_next_then => '接下来测试登录，然后测试聊天';

  @override
  String get ng_agent_gateway => 'Agent 网关';

  @override
  String get ng_running => '运行中';

  @override
  String get ng_stopped => '已停止';

  @override
  String get ng_username_password => '用户名和密码';

  @override
  String get ng_browser => '浏览器';

  @override
  String get ng_in_the_browser_sso => '在浏览器中（SSO）';

  @override
  String get ng_profiles => '配置文件';

  @override
  String get ng_this_dashboard_offers_neither_a_username =>
      '此控制面板既未提供用户名和密码登录，也未提供浏览器登录。请更新 Hermes，或在服务器上配置用户名和密码登录。';

  @override
  String get ng_the_auth_gate_is_off_on =>
      '此控制面板未启用身份验证。任何能访问它的人都可以使用你的 Agent。';

  @override
  String get ng_couldn_t_reach_the_dashboard => '无法连接到控制面板';

  @override
  String ng_check_the_address_and_port_9119(Object reason) {
    return '$reason\n\n请检查地址和端口（默认为 9119）。如果控制面板尚未运行，请在服务器上执行：\nhermes dashboard --host 0.0.0.0';
  }

  @override
  String get ng_that_isn_t_a_hermes_dashboard => '这不是 Hermes 控制面板';

  @override
  String get ng_something_answered_but_not_a_hermes_2 =>
      '服务器有响应，但不是 Hermes 控制面板。请使用控制面板的地址，而不是 API 服务器的地址（端口 8642）。';

  @override
  String ng_something_answered_http_but_not_a_2(Object status) {
    return '服务器有响应（HTTP $status），但不是 Hermes 控制面板。请使用控制面板的地址，而不是 API 服务器的地址（端口 8642）。';
  }

  @override
  String get ng_cloudflare_access_stopped_the_request =>
      'Cloudflare Access 已拦截此请求';

  @override
  String ng_cloudflare_access_turned_down_the_service(Object status) {
    return 'Cloudflare Access 拒绝了服务令牌（HTTP $status）。请检查客户端 ID、密钥和 Service Auth 策略。';
  }

  @override
  String get ng_add_a_cloudflare_access_service_token_2 =>
      '请在下方添加 Cloudflare Access 服务令牌，然后重新测试。';

  @override
  String get ng_a_client_certificate_is_needed => '需要客户端证书';

  @override
  String get ng_this_server_asks_for_a_client =>
      '此服务器要求先提供客户端证书。请在下方选择服务器提供的证书，然后重新测试。';

  @override
  String get ng_this_dashboard_doesn_t_ask_for => '此控制面板不需要登录。';

  @override
  String ng_use_the_dashboard_username_and_password(Object address) {
    return '请使用 $address 上配置的控制面板用户名和密码，或在浏览器中登录。';
  }

  @override
  String ng_use_the_dashboard_username_and_password_2(Object address) {
    return '请使用 $address 上配置的控制面板用户名和密码。';
  }

  @override
  String ng_sign_in_to_in_your_browser(Object address) {
    return '请在浏览器中登录 $address，并使用该控制面板所用的账号。';
  }

  @override
  String ng_gateway(Object address) {
    return '网关 $address';
  }

  @override
  String get ng_profile => '配置文件';

  @override
  String get ng_server_default => '服务器默认设置';

  @override
  String get ng_continue => '继续';

  @override
  String get ng_username => '用户名';

  @override
  String get ng_signing_in => '正在登录…';

  @override
  String get ng_waiting_for_the_browser => '正在等待浏览器…';

  @override
  String get ng_sign_in_with_browser => '使用浏览器登录';

  @override
  String get ng_finish_signing_in_on_the_page =>
      '请在打开的页面上完成登录。完成后 Hermes 会自动返回。';

  @override
  String get ng_use_a_different_gateway => '使用其他网关';

  @override
  String get ng_same_wi_fi_or_local_network => '同一 Wi-Fi 或本地网络';

  @override
  String get ng_use_the_server_s_local_address =>
      '使用服务器的本地地址和端口，例如 192.168.1.20:9119。启动控制面板时请添加 --host 0.0.0.0，以便其他设备访问。';

  @override
  String get ng_tailscale => 'Tailscale';

  @override
  String get ng_turn_on_tailscale_on_this_phone =>
      '在这部手机上启用 Tailscale，然后使用服务器的 Tailscale 地址，例如 100.64.0.1:9119 或其 .ts.net 域名。离开家也能使用。';

  @override
  String get ng_use_your_https_address_when_the =>
      '如果控制面板位于带证书的代理后面，请使用你的 https:// 地址。代理还必须支持 /api/ws 上的 WebSocket 升级。';

  @override
  String get ng_start_the_dashboard_on_the_server => '在服务器上启动控制面板：';

  @override
  String get ng_enter_a_port_from_1_to => '请输入 1 到 65535 之间的端口。';

  @override
  String get ng_looks_for_hermes_dashboards_on_port =>
      '在此 Wi-Fi 网络上搜索端口 9119 的 Hermes 控制面板，并检查已保存的电脑。';

  @override
  String ng_looks_for_hermes_dashboards_on_ports(Object port) {
    return '在此 Wi-Fi 网络上搜索端口 9119 和 $port 的 Hermes 控制面板，并检查已保存的电脑。';
  }

  @override
  String get ng_other_port_optional => '其他端口（可选）';

  @override
  String get ng_no_dashboards_answered_start_one_with =>
      '没有控制面板响应。请运行 hermes dashboard --host 0.0.0.0 启动，或输入其地址。';

  @override
  String get ng_using_tailscale_or_a_vpn_those =>
      '正在使用 Tailscale 或 VPN？无法搜索这些网络。请改为输入电脑的 100.x 地址或 .ts.net 域名。';

  @override
  String get ng_search_again => '重新搜索';

  @override
  String get ng_insights => '数据洞察';

  @override
  String get ng_couldn_t_load_insights => '无法加载数据洞察';

  @override
  String get ng_sessions => '会话';

  @override
  String get ng_tokens => '令牌';

  @override
  String get ng_est_cost => '预估费用';

  @override
  String get ng_daily_tokens => '每日令牌用量';

  @override
  String get ng_models => '模型';

  @override
  String get ng_tools => '工具';

  @override
  String get ng_hermes_is_waiting_for_you => 'Hermes 正在等你。';

  @override
  String get ng_hermes_replied => 'Hermes 已回复';

  @override
  String get ng_the_turn_finished => '本轮已完成。';

  @override
  String get ng_off => '关闭';

  @override
  String get ng_minimal => '最低';

  @override
  String get ng_low => '低';

  @override
  String get ng_medium => '中';

  @override
  String get ng_high => '高';

  @override
  String get ng_extra_high => '极高';

  @override
  String get ng_max => '最高';

  @override
  String get ng_ultra => '超强';

  @override
  String get ng_default => '默认';

  @override
  String ng_couldn_t_switch_model(Object error) {
    return '无法切换模型：$error';
  }

  @override
  String get ng_model => '模型';

  @override
  String get ng_thinking_2 => '思考';

  @override
  String get ng_search_models => '搜索模型';

  @override
  String ng_couldn_t_load_models(Object error) {
    return '无法加载模型：$error';
  }

  @override
  String get ng_no_providers_are_set_up_on => '此网关尚未设置任何提供商。';

  @override
  String get ng_starred => '已加星标';

  @override
  String get ng_recent => '最近';

  @override
  String get ng_more => '更多';

  @override
  String get ng_archived_chats => '已归档聊天';

  @override
  String get ng_projects => '项目';

  @override
  String get ng_chats_grouped_by_project_and_workspace => '按项目和工作区分组的聊天';

  @override
  String get ng_agent => '智能体';

  @override
  String get ng_memory => '记忆';

  @override
  String get ng_what_hermes_remembers_about_you => 'Hermes 对你的记忆';

  @override
  String get ng_skills_library => '技能库';

  @override
  String get ng_browse_and_read_installed_skills => '浏览并阅读已安装的技能';

  @override
  String get ng_cron_editor => 'Cron 编辑器';

  @override
  String get ng_edit_schedules_prompts_and_delivery => '编辑计划、提示词和发送方式';

  @override
  String get ng_config_file => '配置文件';

  @override
  String get ng_edit_config_yaml_on_the_gateway => '在网关上编辑 config.yaml';

  @override
  String get ng_models_and_providers => '模型和提供商';

  @override
  String get ng_model_management => '模型管理';

  @override
  String get ng_default_fallback_and_auxiliary_models => '默认、备用和辅助模型';

  @override
  String get ng_provider_sign_in => '提供商登录';

  @override
  String get ng_connect_provider_accounts_with_oauth => '通过 OAuth 连接提供商账号';

  @override
  String get ng_nous_portal => 'Nous Portal';

  @override
  String get ng_subscription_credits_and_usage => '订阅、额度和使用情况';

  @override
  String get ng_interface => '界面';

  @override
  String get ng_switch_to_the_classic_interface => '切换到经典界面';

  @override
  String get ng_turns_nextgen_off_you_can_turn => '关闭 NextGen。你可以在设置中重新开启。';

  @override
  String get ng_restored => '已恢复';

  @override
  String get ng_archived => '已归档';

  @override
  String get ng_couldn_t_load_archived_chats => '无法加载已归档的聊天';

  @override
  String get ng_nothing_archived => '没有已归档的内容';

  @override
  String get ng_restore => '恢复';

  @override
  String get ng_saved_new_chats_use_it => '已保存。新聊天将使用此设置。';

  @override
  String ng_couldn_t_save(Object error) {
    return '无法保存：$error';
  }

  @override
  String get ng_saving => '正在保存…';

  @override
  String ng_today(Object time) {
    return '今天 $time';
  }

  @override
  String get ng_mon => '周一';

  @override
  String get ng_tue => '周二';

  @override
  String get ng_wed => '周三';

  @override
  String get ng_thu => '周四';

  @override
  String get ng_fri => '周五';

  @override
  String get ng_sat => '周六';

  @override
  String get ng_sun => '周日';

  @override
  String get ng_scheduled => '计划任务';

  @override
  String get ng_new_job => '新建任务';

  @override
  String get ng_couldn_t_load_scheduled_jobs => '无法加载计划任务';

  @override
  String get ng_nothing_scheduled => '没有计划任务';

  @override
  String get ng_ask_hermes_to_do_something_on => '让 Hermes 按计划执行任务，或在此处添加任务。';

  @override
  String get ng_active => '运行中';

  @override
  String get ng_paused => '已暂停';

  @override
  String ng_next(Object when) {
    return '下次 $when';
  }

  @override
  String ng_last(Object when) {
    return '上次 $when';
  }

  @override
  String ng_last_2(Object when, Object result) {
    return '上次 $when · $result';
  }

  @override
  String ng_job(Object id) {
    return '任务 $id';
  }

  @override
  String get ng_delete => '删除';

  @override
  String get ng_delete_this_job => '删除此任务？';

  @override
  String get ng_it_stops_running_past_runs_stay => '删除后将停止运行。以往的运行记录仍会保留在聊天中。';

  @override
  String ng_next_run(Object when) {
    return '下次运行：$when';
  }

  @override
  String ng_delivers_to(Object target) {
    return '发送至 $target';
  }

  @override
  String get ng_run_now => '立即运行';

  @override
  String get ng_started => '已启动';

  @override
  String get ng_pause => '暂停';

  @override
  String get ng_resume => '继续';

  @override
  String get ng_resumed => '已继续';

  @override
  String get ng_prompt => '提示词';

  @override
  String get ng_runs => '运行记录';

  @override
  String get ng_no_runs_yet => '暂无运行记录。';

  @override
  String get ng_enter_a_schedule_and_a_prompt => '请填写计划和提示词。';

  @override
  String get ng_name_optional => '名称（可选）';

  @override
  String get ng_schedule => '计划';

  @override
  String get ng_every_1h_0_9_or_30m => 'every 1h, 0 9 * * *, or 30m';

  @override
  String get ng_create => '创建';

  @override
  String get ng_unpin => '取消置顶';

  @override
  String get ng_pin => '置顶';

  @override
  String get ng_rename => '重命名';

  @override
  String get ng_archive => '归档';

  @override
  String get ng_delete_this_chat => '删除此聊天？';

  @override
  String get ng_it_is_removed_from_the_gateway => '此聊天会从网关中删除，并从所有设备上移除。';

  @override
  String get ng_search_chats => '搜索聊天';

  @override
  String get ng_pinned => '已置顶';

  @override
  String get ng_no_chats_match => '没有匹配的聊天。';

  @override
  String get ng_no_chats_yet => '暂无聊天。';

  @override
  String get ng_nothing_is_running => '暂无运行中的任务。';

  @override
  String get ng_nothing_is_waiting_on_you => '暂无待你处理的事项。';

  @override
  String get ng_settings => '设置';

  @override
  String get ng_all => '全部';

  @override
  String ng_needs_you(Object count) {
    return '需要你处理 · $count';
  }

  @override
  String get ng_needs_you_2 => '需要你处理';

  @override
  String get ng_gateways => '网关';

  @override
  String ng_classic_connection(Object address) {
    return '$address · 经典连接';
  }

  @override
  String get ng_gateway_2 => '网关';

  @override
  String get ng_signed_in => '已登录';

  @override
  String get ng_classic_connection_2 => '经典连接';

  @override
  String get ng_in_the_browser => '在浏览器中';

  @override
  String ng_in_the_browser_as(Object name) {
    return '以 $name 身份在浏览器中';
  }

  @override
  String get ng_not_required => '无需操作';

  @override
  String get ng_test_connection => '测试连接';

  @override
  String get ng_sign_in_again_2 => '重新登录';

  @override
  String get ng_sign_out => '退出登录';

  @override
  String get ng_saved_gateways => '已保存的网关';

  @override
  String get ng_in_use => '使用中';

  @override
  String get ng_appearance => '外观';

  @override
  String get ng_theme => '主题';

  @override
  String get ng_system => '跟随系统';

  @override
  String get ng_light => '浅色';

  @override
  String get ng_dark => '深色';

  @override
  String get ng_accent => '强调色';

  @override
  String get ng_pure_black => '纯黑';

  @override
  String get ng_dark_theme_uses_true_black_oled => '深色主题使用纯黑（OLED）';

  @override
  String get ng_glow => '光晕';

  @override
  String get ng_soft_accent_light_behind_each_screen => '每个页面背后的柔和强调色光效';

  @override
  String get ng_the_new_interface_turn_off_to => '新版界面。关闭后可切回经典界面；网关和聊天记录会共用。';

  @override
  String get ng_more_settings => '更多设置';

  @override
  String get ng_voice_notifications_language_backups_and_the =>
      '语音、通知、语言、备份和网关配置';

  @override
  String get ng_licences => '许可证';

  @override
  String ng_sign_out_of(Object name) {
    return '要退出 $name 吗？';
  }

  @override
  String get ng_this_gateway_and_its_saved_sign =>
      '此网关及其已保存的登录信息会从这部手机的两个界面中移除。聊天记录仍保留在网关上。';

  @override
  String get ng_password_or_browser => '密码或浏览器';

  @override
  String get ng_unsupported => '不支持';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');

  @override
  String get fallback_title => '备用模型';

  @override
  String get fallback_notice => '主模型不可用时按顺序尝试。更改仅适用于此配置；请明确保存完整列表。';

  @override
  String get fallback_unavailable => '备用设置不可用或无效。请检查连接、所选配置和主机版本，然后重试。';

  @override
  String get fallback_discovery_unavailable =>
      '无法获取提供商列表。现有条目会保留；重试后可选择提供商和模型。';

  @override
  String get fallback_empty => '此备用列表中没有条目。';

  @override
  String get fallback_incomplete => '保存前，请为每个条目选择提供商和模型，或删除未完成的条目。';

  @override
  String get fallback_add => '添加备用模型';

  @override
  String get fallback_save => '保存备用列表';

  @override
  String get fallback_save_failed => '无法验证已保存的备用列表。草稿已保留。请重新保存，或刷新以重新加载主机设置。';

  @override
  String get fallback_saved => '备用列表已保存并验证。';

  @override
  String get fallback_legacy_title => '旧版备用设置（只读）';

  @override
  String get fallback_legacy_notice =>
      '主机还会在此列表之后使用 fallback_model，并跳过重复路由。即使上方列表为空，这些旧版条目也会保留。请在主机上编辑。';

  @override
  String fallback_priority(String position) {
    return '优先级 $position';
  }

  @override
  String get fallback_move_up => '上移';

  @override
  String get fallback_move_down => '下移';

  @override
  String get fallback_routing_read_only =>
      '路由详情或未列出的提供商已保留。请在主机上编辑此提供商／模型；此处仍可调整顺序或删除条目。';

  @override
  String get cron_model_default => '使用默认设置';

  @override
  String get cron_model_notice =>
      '仅适用于此 cron 任务。未固定模型时，Hermes 先使用 cron 默认模型，再使用主模型。请在主机上管理自定义模型。';

  @override
  String get model_management_unavailable => '无法加载或保存模型设置。请刷新后重试。';

  @override
  String get model_management_subtitle => '此配置的主模型、备用模型和辅助模型';

  @override
  String get usage => '用量';

  @override
  String get nous_portal => 'Nous Portal';

  @override
  String get portal_menu_subtitle => '网关状态和已记录用量';

  @override
  String get portal_read_only =>
      '网关只读数据。请在 Hermes 主机上管理 Nous 身份验证。这些端点不提供订阅余额或积分。';

  @override
  String get portal_status => '网关 Portal 状态';

  @override
  String get portal_free_tier => '免费层访问（未登录账户）';

  @override
  String get portal_signed_in => '已登录';

  @override
  String get portal_signed_out => '未登录';

  @override
  String get portal_account_tier => '账户等级';

  @override
  String get portal_recorded_usage => '已记录用量';

  @override
  String get portal_all_providers => '所选网关配置中的所有提供商。记录费用为零并不表示模型免费。';

  @override
  String portal_period(String days) {
    return '最近 $days 天';
  }

  @override
  String get portal_sessions => '会话';

  @override
  String get portal_input => '输入令牌';

  @override
  String get portal_output => '输出令牌';

  @override
  String get portal_estimated => '已记录的预估费用';

  @override
  String get portal_actual => '已记录的实际费用';

  @override
  String get portal_recorded_models => '已记录模型';

  @override
  String get portal_no_models => '没有已记录模型。';

  @override
  String get portal_unavailable => '不可用。请检查连接、所选配置和网关版本，然后重试。';

  @override
  String get paste_attachment_failed_text_kept => '无法将粘贴的文本添加为附件。文本已保留在消息中。';

  @override
  String get background_task_report => '后台任务';

  @override
  String get background_process_report => '后台进程';

  @override
  String get background_report_issues => '已报告问题，展开查看详情。';

  @override
  String get background_report_expand => '展开报告';

  @override
  String get background_report_collapse => '收起报告';

  @override
  String get hands_free_title => '免提对话';

  @override
  String get hands_free_start => '开始免提';

  @override
  String get hands_free_stop => '停止免提';

  @override
  String get hands_free_preparing => '正在准备语音 — 请稍候';

  @override
  String get hands_free_listening => '请说 Hey Hermes';

  @override
  String get hands_free_recording => '已就绪 — 请说话';

  @override
  String get hands_free_waiting => '等待 Hermes 回复';

  @override
  String get hands_free_speaking => '正在朗读 — 麦克风已关闭';

  @override
  String hands_free_followup(int seconds) {
    return '最多聆听 $seconds 秒';
  }

  @override
  String get hands_free_error => '免提已停止';

  @override
  String get hands_free_setup => '免提设置';

  @override
  String hands_free_preview(String transcript) {
    return '语音预览：$transcript';
  }

  @override
  String get hands_free_short_disclosure =>
      '仅在此聊天于前台打开时运行。唤醒检测离线；语音可能使用网络。会消耗电量。';

  @override
  String get hands_free_error_action =>
      '请检查麦克风权限、语音服务、回复声音和连接，再点击停止并重新开始。不会自动重发。';

  @override
  String get hands_free_disclosure =>
      '唤醒检测在 CPU 上离线运行。Android 语音识别、所选声音和网关可能使用网络。聆听会消耗电量，也可能误触发。聊天被遮挡、关闭或离开前台时停止，返回后不会自动重启。手动听写仍是可编辑的草稿。';

  @override
  String get hands_free_ready_cue =>
      '说“Hey Hermes”，等待就绪提示后再说话。不支持一口气连续输入或预录音。如果授权对话框使应用离开前台，授权后请再次点击开始。';

  @override
  String get hands_free_settings_title => '免提语音';

  @override
  String get hands_free_settings_subtitle =>
      '在聊天中显示“Hey Hermes”启动控件。关闭会停止正在进行的免提会话。';

  @override
  String get hands_free_timing_limit =>
      '后续聆听时间是上限，不是下限。Android 可能提前结束。无语音时返回本地唤醒检测，不会反复重启识别。';

  @override
  String get hands_free_followup_off => '后续聆听已关闭 — 每次提问请说 Hey Hermes';

  @override
  String get hands_free_start_blocked =>
      '需要空草稿、无附件、空闲且已连接的聊天，并启用语音回复。请先结束手动语音操作。';

  @override
  String get hands_free_setup_complete => '麦克风设置完成。请再次点击开始。';

  @override
  String get stop_and_send => '停止并发送';

  @override
  String get message_queued_for_running_turn => '消息已加入当前运行的队列。';

  @override
  String get running_message_not_accepted =>
      'Hermes 无法接受此消息。草稿已保留；请停止回复或等待，然后重新发送。';

  @override
  String get running_message_delivery_unknown =>
      '无法确认消息是否送达。草稿已保留。请先检查聊天记录，再重试。';

  @override
  String get attachment_tap_to_preview => '点按以预览';

  @override
  String get attachment_save => '保存';

  @override
  String get attachment_share => '分享';

  @override
  String get attachment_saved => '文件已保存';

  @override
  String get attachment_save_cancelled => '已取消保存';

  @override
  String get attachment_save_failed => '无法保存此文件，请重试。';

  @override
  String get attachment_share_failed => '无法分享此文件，请重试。';

  @override
  String get attachment_download_failed => '无法加载此文件，请检查连接后重试。';

  @override
  String get attachment_no_inline_preview =>
      '此文件类型不支持内嵌预览。请保存或分享原始文件，以便在其他应用中打开。';

  @override
  String get attachment_image_failed => '无法解码此图片。您仍可保存或分享原始文件。';

  @override
  String get attachment_text_truncated => '预览内容已截短。请保存或分享文件以阅读完整内容。';

  @override
  String get attachment_text_unavailable => '无法将此文件显示为文本。请保存或分享原始文件。';

  @override
  String get attachment_pdf_failed => '无法预览此 PDF。请保存或分享原始文件。';

  @override
  String get attachment_pdf_unavailable => 'PDF 预览仅在 Android 上可用。您仍可保存或分享此文件。';

  @override
  String attachment_pdf_page(int page, int total) {
    return '第 $page 页，共 $total 页';
  }

  @override
  String get attachment_previous_page => '上一页';

  @override
  String get attachment_next_page => '下一页';

  @override
  String get attachment_loading => '正在加载预览…';

  @override
  String get attachment_document_text_notice => '文本预览。布局、图片和格式可能与原文件不同。';

  @override
  String get attachment_document_failed => '无法预览此文档。请保存或分享原始文件。';

  @override
  String get attachment_document_empty => '此文档中未找到可读文本。';

  @override
  String get attachment_video_failed => '无法播放此视频。其格式或编解码器可能不受支持。请保存或分享原始文件。';

  @override
  String get attachment_video_play => '播放';

  @override
  String get attachment_video_pause => '暂停';

  @override
  String get attachment_video_mute => '静音';

  @override
  String get attachment_video_unmute => '取消静音';

  @override
  String get attachment_video_seek => '视频进度';

  @override
  String get attachment_close => '关闭预览';

  @override
  String get attachment_retry => '重试';

  @override
  String get theme_palette => '颜色主题';

  @override
  String get theme_palette_gold => '金色';

  @override
  String get theme_palette_purple => '紫色';

  @override
  String get theme_palette_orange => '橙色';

  @override
  String get theme_palette_green => '绿色';

  @override
  String get theme_palette_blue => '蓝色';

  @override
  String get theme_palette_red => '红色';

  @override
  String get theme_palette_teal => '青绿色';

  @override
  String get theme_palette_pink => '粉色';

  @override
  String get theme_palette_indigo => '靛蓝色';

  @override
  String get theme_palette_cyan => '青色';

  @override
  String get assets_recent_subtitle => '查找 Hermes 在已保存的聊天中分享的文件';

  @override
  String get assets_scope_notice =>
      '仅显示 Hermes 在已保存的回复中明确分享的已生成文件。这里只展示部分聊天历史，并非完整的文件或附件目录。引用的文件可能已不存在。';

  @override
  String get assets_download_limit =>
      '文件仅在点按时加载。预览和下载的单个文件大小上限均为 25 MiB；更大的文件请通过仪表盘获取。';

  @override
  String get assets_search_hint => '搜索找到的文件或来源聊天';

  @override
  String get assets_all => '全部';

  @override
  String get assets_images => '图片';

  @override
  String get assets_audio => '音频';

  @override
  String get assets_video => '视频';

  @override
  String get assets_documents => '文档和其他文件';

  @override
  String get assets_empty => '在已扫描的消息中未找到资产';

  @override
  String get assets_empty_detail =>
      '扫描更多聊天或更早的消息，以查看更早的历史。普通附件和未链接的文件不会在此建立索引。';

  @override
  String get assets_no_matches => '未找到匹配的资产';

  @override
  String get assets_load_more_chats => '扫描更多聊天';

  @override
  String get assets_load_older_messages => '扫描更早的消息';

  @override
  String get assets_load_failed => '部分历史记录无法读取。结果不完整。请检查仪表盘连接并重试。';

  @override
  String get assets_retry_failed => '重试读取失败的历史记录';

  @override
  String get assets_partial => '服务器报告历史记录不完整。请检查仪表盘后刷新。';

  @override
  String assets_scan_summary(int files, int chats) {
    return '已扫描 $chats 个聊天，找到 $files 处文件引用';
  }

  @override
  String assets_open_chat(String title) {
    return '打开聊天：$title';
  }

  @override
  String get assets_file_too_large => '此文件超出下载大小上限。请打开仪表盘进行下载。';

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      '一次性问题。将在 72 小时后自动归档；任何值得保留的内容都会被记住。';

  @override
  String get archive_chat => '归档聊天';

  @override
  String get unarchive_chat => '取消归档聊天';

  @override
  String get chat_archived => '聊天已归档';

  @override
  String get chat_unarchived => '聊天已取消归档';

  @override
  String could_not_update_chat_archive(Object error) {
    return '无法更新聊天归档状态：$error';
  }

  @override
  String get quick_chat_description => '一次性问题。';

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
  String get approval_needed_description => '有命令正在等待你的批准或拒绝。';

  @override
  String get approve => '批准';

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
  String get archived_conversations_appear_here =>
      '这里只显示已归档的对话。旧聊天仍保留在“所有聊天”中。';

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
  String get agent => '智能体';

  @override
  String get autonomous_agents => '自主智能体';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      '后台恢复不可用 — 旧版传输';

  @override
  String get background_task_completed => '后台任务完成';

  @override
  String get background_task_completed_description => '后台终端命令已完成。';

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
  String get could_not_open_link => '无法打开此链接。';

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
  String get credit_notifications => '额度通知';

  @override
  String get credit_notifications_description => '额度使用已停止或恢复。';

  @override
  String get cron => 'Cron';

  @override
  String get cron_jobs => 'Cron 任务';

  @override
  String cron_schedule_timezone(Object zone) {
    return '排程时区：$zone';
  }

  @override
  String get crons_upcoming => '即将运行';

  @override
  String get crons_history => '运行历史';

  @override
  String cron_time_with_zone(Object time, Object zone) {
    return '$time（$zone）';
  }

  @override
  String cron_time_zone_unknown(Object time) {
    return '$time（时区未知）';
  }

  @override
  String get cron_no_next_run => '未安排下次运行';

  @override
  String get cron_status_scheduled => '已排程';

  @override
  String get cron_status_paused => '已暂停';

  @override
  String cron_delivers_to(Object target) {
    return '投递至 $target';
  }

  @override
  String get cron_upcoming_empty_title => '暂无已排程任务';

  @override
  String get cron_upcoming_empty_message =>
      '当前没有待运行的任务。请在 Cron 任务中创建，或让智能体安排一个。';

  @override
  String get cron_upcoming_unavailable => '无法显示已排程任务';

  @override
  String get cron_upcoming_needs_dashboard =>
      '已排程任务需要仪表盘连接。此地址不提供 Cron 排程。请检查仪表盘地址和主机支持情况。';

  @override
  String get cron_upcoming_needs_dashboard_auth =>
      '已排程任务需要仪表盘认证。请为此连接添加仪表盘用户名和密码，或启用代理模式。';

  @override
  String get cron_upcoming_dashboard_unreachable =>
      '无法连接到仪表盘。请检查主机、仪表盘端口和网络，然后重试。';

  @override
  String get cron_upcoming_load_failed => '无法读取已排程任务。请检查仪表盘连接并重试。';

  @override
  String get cron_upcoming_refresh_failed => '无法刷新排程。正在显示上次成功读取的结果。';

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
  String get enable_notifications => '启用通知';

  @override
  String get enable_notifications_description => '关闭后将禁用以下所有通知。';

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
  String get input_needed => '需要输入';

  @override
  String get input_needed_description => 'Hermes 提出了问题，或需要密码或密钥。';

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
  String get memory_about_you => '关于你';

  @override
  String get memory_agent_notes => '助手笔记';

  @override
  String get memory_builtin_scope =>
      '此配置档案的 USER.md 和 MEMORY.md 中保存的事实。这里不显示外部记忆服务（包括 MemPalace）的内容。';

  @override
  String get memory_read_only => '仅供查看。可在聊天中请 Hermes 更正或忘记某条事实。';

  @override
  String get memory_unavailable =>
      '此网关或配置档案无法提供已保存的事实。请检查所选配置档案，并在需要时更新 Hermes。';

  @override
  String get memory_load_error => '请检查仪表盘连接和身份验证，然后重试。';

  @override
  String get memory_read_full_fact => '阅读完整事实';

  @override
  String get memory_full_fact_requires_update =>
      '查看完整事实需要更新的 Hermes 网关。请更新 Hermes 并刷新列表。';

  @override
  String get memory_fact_detail_error => '无法加载完整事实。它可能已更改；请刷新列表后重试。';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      'Hermes 记住的事实会显示在这里。';

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
  String get notifications => '通知';

  @override
  String get notifications_permission_denied =>
      '系统已阻止通知。请在 Android 设置中允许此应用发送通知。';

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
  String get plugin_notifications => '插件通知';

  @override
  String get plugin_notifications_description => '应用在后台时，网关发来了通知。';

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
  String get recently_active => '最近活跃';

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
  String get response_complete => '响应完成';

  @override
  String get response_complete_description => '应用在后台时，一轮对话已完成。';

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
  String send_failed_api_only_permission_denied(Object error) {
    return '发送失败：$error。服务器拒绝了 API 密钥主体的此次写入。如果该会话归 Dashboard 所有，为此连接添加 Dashboard 用户名和密码可能即可发送；服务器也可能是有意拒绝。';
  }

  @override
  String get send_message => '发送消息';

  @override
  String get send_test_notification => '发送测试通知';

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
  String get test_notification_body => '如果你能看到这条通知，说明通知功能正常。';

  @override
  String get test_notification_sent => '已发送测试通知。';

  @override
  String get test_notification_title => 'Hermes 通知测试';

  @override
  String get test_notification_unsupported => '无法发送通知——请检查系统是否允许通知。';

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
      '此项目需要先添加文件夹才能在其中开始聊天。添加文件夹后请重试。';

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
  String get received_outcome_unknown => '本轮对话已结束 — 结果未确认';

  @override
  String get turn_completed => '本轮对话已完成';

  @override
  String get turn_failed => '对话失败';

  @override
  String get turn_failed_description => '后台对话以错误结束。';

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
  String tool_start_observed(Object time) {
    return '观察到开始 $time（本地时间）';
  }

  @override
  String tool_last_observed(Object time) {
    return '最后观察时间 $time（本地时间）';
  }

  @override
  String tool_result_recorded(Object time) {
    return '结果记录时间 $time（本地时间）';
  }

  @override
  String get tool_time_unavailable => '时间不可用';

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

  @override
  String get pin_chat => '置顶聊天';

  @override
  String get unpin_chat => '取消置顶';

  @override
  String get pinned_chats => '已置顶';

  @override
  String could_not_update_chat_pin(Object error) {
    return '无法更新聊天置顶：$error';
  }

  @override
  String get could_not_save_chat_spaces => '无法在此设备上保存聊天空间';

  @override
  String get update_available => '有可用更新';

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
      'GitHub 上已有更新的 Hermes Android 版本。';

  @override
  String get release_notes => '发行说明';

  @override
  String get view_release => '查看发行版';

  @override
  String get skip_this_version => '跳过此版本';

  @override
  String get later => '稍后';

  @override
  String get check_for_updates => '检查更新';

  @override
  String get check_for_updates_on_launch => '启动时检查更新';

  @override
  String get you_re_on_the_latest_version => '已是最新版本。';

  @override
  String get couldn_t_check_for_updates => '无法检查更新。';

  @override
  String get chat_density => '聊天密度';

  @override
  String chat_density_2(Object label) {
    return '聊天密度：$label';
  }

  @override
  String get chat_density_comfortable => '舒适';

  @override
  String get chat_density_compact => '紧凑';

  @override
  String get chat_density_comfortable_description => '每条消息上方带有发送者标签的更宽松气泡。';

  @override
  String get chat_density_compact_description => '更紧凑的无标签气泡，屏幕上可以显示更多消息。';

  @override
  String chat_density_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String
  get compact_removes_the_you_and_hermes_labels_and_trims_bubble_padding_spacing_and_side_margins =>
      '紧凑模式会去掉 You 和 Hermes 标签，并缩小气泡内边距、间距和两侧边距。';

  @override
  String get background_work => '后台运行';

  @override
  String get keep_chats_active_in_background => '在后台保持聊天连接';

  @override
  String get background_work_description =>
      '应用在后台时，保持用户发起的聊天连接。空闲连接可能会断开。此功能会增加电量和流量消耗。关闭后不会停止服务器上的任务。';

  @override
  String get background_work_limits =>
      'Android 仍可能在 Doze 模式下暂停连接或结束应用进程。进程结束后的通知需要单独设置推送。不支持强行停止后的通知。';

  @override
  String get background_work_disclosure => '后台保护开启时，即使关闭了可选的聊天通知，仍会显示必需的服务通知。';

  @override
  String get battery_optimisation_settings => '电池优化设置';

  @override
  String get battery_optimisation_description =>
      '打开 Android 设置以查看电池限制。不会自动申请豁免，更改设置也不能保证通知送达。';

  @override
  String get battery_settings_unavailable => '无法在此设备上打开电池设置。';

  @override
  String get background_work_save_failed => '无法保存后台运行设置。';

  @override
  String get ongoing_chat_channel_name => '进行中的聊天';

  @override
  String get ongoing_chat_channel_description => '用户发起的未完成聊天的静默状态更新';

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
  String get activity_status_unconfirmed => '状态未确认';

  @override
  String get activity_recently_updated => '最近更新';

  @override
  String get activity_reconnecting => '正在重新连接 — 正在检查轮次状态';

  @override
  String get activity_outcome_unknown => '无法确认本轮对话的结果。请打开聊天查看。';

  @override
  String get activity_chat_updated_detail => '网关已记录聊天活动；无法获取轮次的实时状态。';

  @override
  String get activity_updated => '已更新';

  @override
  String get activity_empty_title => '暂无近期活动';

  @override
  String get activity_empty_detail => '在此应用中启动的轮次，以及过去7天内更新的网关聊天都会显示在这里。';

  @override
  String get activity_read_error => '活动功能无法读取轮次记录或网关聊天。请检查连接后重试。';

  @override
  String get activity_chat_unavailable => '此聊天已不可用，或无法连接到网关。';

  @override
  String get activity_partial_title => '活动已部分加载';

  @override
  String get activity_partial_detail => '目前仅显示网关活动的有限范围。可能还有更多聊天，请下拉刷新。';

  @override
  String get provider_usage => '使用记录';

  @override
  String get provider_usage_notice =>
      'Hermes最近30天的使用量，并非账户余额或模型定价。请在Hermes服务器配置凭据；此应用不保存提供商API密钥。';

  @override
  String get provider_usage_failed => '无法加载使用记录。';

  @override
  String get provider_usage_empty => '此提供商暂无使用记录。';

  @override
  String provider_usage_counts(String sessions, String input, String output) {
    return '$sessions 个会话 · 输入：$input · 输出：$output';
  }

  @override
  String provider_usage_costs(String estimated, String actual) {
    return '估算：$estimated · 报告：$actual';
  }

  @override
  String get provider_quota_codex => 'OpenAI Codex 订阅';

  @override
  String get provider_quota_claude => 'Claude 订阅';

  @override
  String get provider_quota_openai_api => 'OpenAI API 已记录用量';

  @override
  String get provider_quota_notice =>
      '由提供商报告的订阅用量周期，与 Hermes 记录的用量及 API 计费分开显示。各账户单独列出；达到模型限额并不代表整个账户的配额已耗尽。';

  @override
  String get provider_quota_windows_notice =>
      'Codex 和 Claude 订阅设有五小时会话限额和每周限额。仅显示提供商报告的周期；未报告的限额和重置时间仍不可用。每周限额可能适用于整个账户或特定模型。';

  @override
  String get provider_quota_five_hour_session => '5小时会话';

  @override
  String get provider_quota_unavailable => '订阅配额不可用。';

  @override
  String get provider_quota_failed => '无法刷新订阅配额。保留的数值来自上次查询。';

  @override
  String get provider_quota_account => '账户';

  @override
  String get provider_quota_unknown => '未知';

  @override
  String provider_quota_state(String state) {
    return '账户状态：$state';
  }

  @override
  String provider_quota_scope(String scope) {
    return '适用范围：$scope';
  }

  @override
  String provider_quota_percent(String used, String remaining) {
    return '已用 $used% · 剩余 $remaining%';
  }

  @override
  String provider_quota_reset(String reset) {
    return '重置时间：$reset';
  }

  @override
  String get provider_quota_reset_unknown => '重置时间不可用。';

  @override
  String get auxiliary_models => '辅助模型';

  @override
  String get auxiliary_notice => '为各任务选择模型。自定义端点必须在服务器管理。自动模式遵循任务的继承规则。';

  @override
  String get auxiliary_inherit => '自动（继承）';

  @override
  String get auxiliary_unavailable => '辅助设置不可用。';

  @override
  String get provider_oauth_title => '提供商登录';

  @override
  String get provider_oauth_more_subtitle => '管理 Hermes 主机上的提供商登录';

  @override
  String get provider_oauth_settings_subtitle =>
      '在 Hermes 主机上登录；提供商令牌不会保存在此设备上';

  @override
  String get provider_oauth_intro =>
      '在外部浏览器中登录提供商。令牌仅存储在 Hermes 主机上，不会保存在此设备上。登录不会选择此应用中的聊天模型。';

  @override
  String get provider_oauth_defaults_notice =>
      '某些主机流程（包括替换 Nous 免费套餐账户）可能会更新主机默认设置。登录后请检查主机设置。';

  @override
  String get provider_oauth_transport_init_failed =>
      '无法初始化所选的安全仪表板连接。请检查其 TLS 身份和连接设置。';

  @override
  String get provider_oauth_https_required => '提供商登录需要通过 HTTPS 连接到 Hermes 仪表板。';

  @override
  String get provider_oauth_auth_required => '登录前请配置仪表板密码验证或可信代理。';

  @override
  String get provider_oauth_catalog_failed =>
      '此主机不支持提供商登录。请检查仪表板身份验证；如果主机不支持提供商 OAuth，请更新主机。';

  @override
  String get provider_oauth_expired => '登录已过期。请重新开始。';

  @override
  String get provider_oauth_start_failed => '无法启动安全的提供商登录。请重试。';

  @override
  String get provider_oauth_denied => '登录被拒绝。请重新开始。';

  @override
  String get provider_oauth_cancelled => '登录已取消。';

  @override
  String get provider_oauth_host_failed => '主机无法完成登录。请重新开始。';

  @override
  String get provider_oauth_poll_failed => '无法检查登录状态。请重新开始。';

  @override
  String provider_oauth_cancellation_unconfirmed(String message) {
    return '$message 无法确认取消；主机会话可能会持续到过期为止。';
  }

  @override
  String get provider_oauth_browser_failed => '无法打开外部浏览器。请重试或取消登录。';

  @override
  String get provider_oauth_retry => '重试';

  @override
  String provider_oauth_complete(String provider) {
    return '完成 $provider 的登录';
  }

  @override
  String get provider_oauth_code_instruction => '请在提供商页面输入此临时代码：';

  @override
  String get provider_oauth_waiting => '正在等待批准。此会话将自动过期。';

  @override
  String get provider_oauth_open_browser => '在浏览器中打开提供商';

  @override
  String get provider_oauth_cancel => '取消登录';

  @override
  String get provider_oauth_signed_out => '未在主机上登录';

  @override
  String get provider_oauth_sign_in_again => '重新登录';

  @override
  String get provider_oauth_sign_in => '登录';

  @override
  String get provider_oauth_cli_required =>
      '请在 Hermes 主机上使用提供商 CLI 登录。此主机不支持该提供商的应用内登录。';

  @override
  String get provider_oauth_checking_account => '已收到授权。正在检查主机账户…';

  @override
  String get provider_oauth_verification_unavailable =>
      '已收到授权；无法验证账户。请打开用量页面以刷新账户用量。';

  @override
  String provider_oauth_verified_account(String email) {
    return '已在 Hermes 主机上以 $email 登录。请打开用量页面以刷新账户用量。';
  }

  @override
  String get provider_oauth_credentials_unverified => '主机报告凭据可用；账户身份尚未验证。';

  @override
  String get provider_oauth_account_status_unknown => '无法获取主机账户状态。';

  @override
  String get projects_root_title => '服务器上的项目文件夹';

  @override
  String get projects_root_more_subtitle => '服务器上新建项目文件夹的位置';

  @override
  String get projects_root_description =>
      '在此手机上创建的项目会在这里获得文件夹。将其指向 Hermes 自身使用的文件夹，手机和服务器就能共享同一批项目。';

  @override
  String get projects_root_label => '项目根路径';

  @override
  String projects_root_default_hint(String path) {
    return '服务器默认值：$path';
  }

  @override
  String get projects_root_locked_title => '由服务器设定';

  @override
  String get projects_root_locked_explanation =>
      '此服务器将文件访问限制在单一根目录内，因此无法在应用中更改项目文件夹。';

  @override
  String get projects_root_saved => '已保存项目文件夹。';

  @override
  String get projects_root_reset => '使用服务器默认值';

  @override
  String get projects_root_invalid_empty => '请输入文件夹路径。';

  @override
  String get projects_root_invalid_absolute => '请输入以斜杠开头的绝对路径。';

  @override
  String get projects_root_invalid_segments => '请从路径中移除点号片段和控制字符。';

  @override
  String get projects_root_unsupported =>
      '此连接不支持。读取或更改服务器上的项目文件夹需要具有仪表板访问权限的 Desktop Gateway 连接。';

  @override
  String get projects_root_unavailable => '无法读取服务器上的项目文件夹。请检查仪表板连接后重试。';

  @override
  String get adopt_folder_action => '添加现有文件夹';

  @override
  String adopt_folder_description(String root) {
    return '$root 下尚未注册为项目的文件夹。';
  }

  @override
  String adopt_folder_registered(String name) {
    return '已是项目：$name';
  }

  @override
  String get adopt_folder_none => '此路径下的所有文件夹都已是项目。';

  @override
  String get adopt_folder_unsupported => '此连接无法列出服务器文件夹。请改为输入现有文件夹的绝对路径。';

  @override
  String adopt_folder_failed(String error) {
    return '无法列出服务器文件夹：$error';
  }

  @override
  String get adopt_folder_manual_label => '现有文件夹路径';

  @override
  String get adopt_folder_name_label => '项目名称';

  @override
  String get adopt_folder_add => '添加为项目';

  @override
  String adopt_folder_added(String name, String path) {
    return '$name 现在使用 $path';
  }

  @override
  String adopt_folder_error(String error) {
    return '无法添加该文件夹：$error';
  }

  @override
  String adopt_folder_folderless(String name) {
    return '已创建 $name，但未关联文件夹。请在服务器上的 Hermes 中关联。';
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
  String get nextgen_toggle => 'NextGen 界面';

  @override
  String get nextgen_toggle_subtitle => '全新设计：一次登录、实时聊天和网络发现。你的网关和聊天与此界面共享。';

  @override
  String get nextgen_single_login => '使用单一登录';

  @override
  String get nextgen_single_login_subtitle => '只需仪表板地址和一次登录即可添加网关。';

  @override
  String get ng_allow_this_command => '允许执行此命令？';

  @override
  String ng_hermes_wants_to_run_this_with(Object tool) {
    return 'Hermes 想使用 $tool 执行此操作。';
  }

  @override
  String get ng_hermes_wants_to_run_this => 'Hermes 想执行此操作。';

  @override
  String get ng_hermes_has_a_question => 'Hermes 有一个问题';

  @override
  String get ng_hermes_has_questions => 'Hermes 有几个问题';

  @override
  String get ng_password_for_sudo => 'sudo 密码';

  @override
  String get ng_hermes_needs_your_sudo_password_to =>
      'Hermes 需要你的 sudo 密码来运行此命令。';

  @override
  String get ng_a_secret_value => '机密值';

  @override
  String ng_value_for(Object variable) {
    return '$variable 的值';
  }

  @override
  String get ng_your_password_manager => '你的密码管理器';

  @override
  String ng_unlock(Object name) {
    return '解锁 $name';
  }

  @override
  String ng_hermes_needs_unlocked_to_sign_in(Object name) {
    return 'Hermes 需要先解锁 $name，才能为你登录。';
  }

  @override
  String get ng_sign_in_code => '登录验证码';

  @override
  String get ng_enter_the_sign_in_code => '输入登录验证码。';

  @override
  String ng_enter_the_sign_in_code_for(Object site) {
    return '输入 $site 的登录验证码。';
  }

  @override
  String get ng_save_a_login => '保存登录信息？';

  @override
  String ng_save_your_login(Object site) {
    return '保存你的 $site 登录信息？';
  }

  @override
  String ng_couldn_t_load_this_chat(Object error) {
    return '无法加载此聊天：$error';
  }

  @override
  String ng_live_updates_are_unavailable(Object error) {
    return '实时更新不可用：$error';
  }

  @override
  String ng_preparing(Object name) {
    return '正在准备 $name…';
  }

  @override
  String get ng_the_turn_failed => '本轮对话失败。';

  @override
  String ng_couldn_t_stop(Object error) {
    return '无法停止：$error';
  }

  @override
  String get ng_server_access => '服务器访问';

  @override
  String get ng_sign_in => '登录';

  @override
  String get ng_live_connection => '实时连接';

  @override
  String get ng_check_that_tailscale_is_on_on => '请确认此手机和服务器上的 Tailscale 均已开启。';

  @override
  String get ng_check_the_address_and_that_the => '请检查地址，并确认代理已转发到仪表盘。';

  @override
  String get ng_use_the_same_network_as_the =>
      '请使用与服务器相同的网络，并使用 --host 0.0.0.0 启动仪表盘，以便其他设备访问。';

  @override
  String get ng_check_the_address_vpn_or_tailscale =>
      '请检查地址、VPN 或 Tailscale 连接。';

  @override
  String get ng_not_checked_yet => '尚未检查。';

  @override
  String get ng_checking => '正在检查…';

  @override
  String ng_hermes_answers_at(Object version, Object address) {
    return 'Hermes $version 可通过 $address 访问。';
  }

  @override
  String get ng_something_answered_but_not_a_hermes => '有服务响应，但不是 Hermes 仪表盘。';

  @override
  String ng_something_answered_http_but_not_a(Object status) {
    return '有服务响应（HTTP $status），但不是 Hermes 仪表盘。';
  }

  @override
  String get ng_use_the_dashboard_s_address_and =>
      '请使用仪表盘的地址和端口（默认为 9119），而不是 API 服务器的地址和端口。';

  @override
  String get ng_cloudflare_access_turned_the_service_token =>
      'Cloudflare Access 拒绝了服务令牌。';

  @override
  String get ng_cloudflare_access_is_in_front_of =>
      '此地址前方配置了 Cloudflare Access。';

  @override
  String get ng_check_the_service_token_and_its => '请检查服务令牌及其 Service Auth 策略。';

  @override
  String get ng_add_a_cloudflare_access_service_token =>
      '为此地址添加 Cloudflare Access 服务令牌。';

  @override
  String get ng_the_server_asks_for_a_client => '服务器要求提供客户端证书。';

  @override
  String get ng_pick_the_client_certificate_for_this => '为此网关选择客户端证书，然后再次测试。';

  @override
  String get ng_needs_server_access_first => '请先连接服务器。';

  @override
  String get ng_needs_a_sign_in_first => '请先登录。';

  @override
  String ng_signed_in_as(Object name) {
    return '已登录为 $name。';
  }

  @override
  String get ng_this_dashboard_doesn_t_need_a => '此仪表盘无需登录。';

  @override
  String get ng_the_saved_sign_in_has_expired => '已保存的登录信息已过期。';

  @override
  String get ng_sign_in_again => '重新登录。';

  @override
  String get ng_too_many_sign_in_attempts => '登录尝试次数过多。';

  @override
  String get ng_wait_a_minute_then_check_again => '请稍等一分钟后再试。';

  @override
  String ng_the_gateway_answered(Object message) {
    return '网关返回：$message。';
  }

  @override
  String get ng_sign_in_again_or_update_hermes => '请重新登录，或更新 Hermes。';

  @override
  String ng_couldn_t_check_the_sign_in(Object error) {
    return '无法检查登录状态：$error';
  }

  @override
  String ng_the_gateway_wouldn_t_issue_a(Object message) {
    return '网关无法签发聊天凭证（$message）。';
  }

  @override
  String get ng_the_chat_connection_opened_and_the => '聊天连接已建立，网关已确认就绪。';

  @override
  String get ng_the_gateway_never_said_it_was => '网关始终未确认就绪。';

  @override
  String get ng_check_that_the_agent_is_running => '请确认服务器上的代理正在运行。';

  @override
  String get ng_the_gateway_refused_the_chat_connection =>
      '网关拒绝了聊天连接（HTTP 403）。';

  @override
  String get ng_this_dashboard_has_no_chat_endpoint => '此仪表盘没有聊天端点（/api/ws）。';

  @override
  String ng_the_chat_connection_failed(Object detail) {
    return '聊天连接失败：$detail';
  }

  @override
  String get ng_use_the_exact_address_the_dashboard => '请使用仪表盘配置的完整地址。';

  @override
  String get ng_update_hermes => '更新 Hermes。';

  @override
  String get ng_make_sure_the_proxy_allows_websocket =>
      '请确认代理允许在 /api/ws 上进行 WebSocket 升级。';

  @override
  String get ng_offline => '离线';

  @override
  String get ng_connecting => '正在连接…';

  @override
  String get ng_connected => '已连接';

  @override
  String get ng_reconnecting => '正在重新连接…';

  @override
  String get ng_signed_out => '已退出登录';

  @override
  String get ng_connection_failed => '连接失败';

  @override
  String get ng_rate_limited_by_gateway => '已触发网关限流';

  @override
  String ng_couldn_t_open_the_chat_connection(Object message) {
    return '无法建立聊天连接：$message';
  }

  @override
  String get ng_the_gateway_returned_no_websocket_ticket =>
      '网关未返回 WebSocket 票据。';

  @override
  String get ng_connection_lost => '连接已断开';

  @override
  String get ng_this_dashboard_has_no_chat_endpoint_2 =>
      '此仪表板没有聊天端点（/api/ws）。请更新 Hermes。';

  @override
  String get ng_the_gateway_refused_the_chat_connection_2 =>
      '网关拒绝了聊天连接。请检查地址是否与仪表板配置的主机匹配，并确认已启用嵌入式聊天。';

  @override
  String ng_the_gateway_refused(Object method) {
    return '网关拒绝了 $method。';
  }

  @override
  String ng_couldn_t_read_your_saved_gateways(Object error) {
    return '无法读取已保存的网关：$error';
  }

  @override
  String get ng_applies_to_new_chats => '仅应用于新聊天';

  @override
  String ng_couldn_t_change(Object label, Object error) {
    return '无法更改$label：$error';
  }

  @override
  String get ng_capabilities => '功能';

  @override
  String get ng_skills => '技能';

  @override
  String get ng_toolsets => '工具集';

  @override
  String get ng_search => '搜索';

  @override
  String get ng_couldn_t_load => '无法加载';

  @override
  String get ng_try_again => '重试';

  @override
  String get ng_no_skills => '没有技能';

  @override
  String get ng_no_toolsets => '没有工具集';

  @override
  String get ng_no_mcp_servers => '没有 MCP 服务器';

  @override
  String get ng_that_file_is_too_large_to => '该文件太大，无法作为证书使用。';

  @override
  String ng_the_certificate_couldn_t_be_imported(Object error) {
    return '无法导入证书：$error';
  }

  @override
  String get ng_now_pick_its_private_key => '现在选择对应的私钥。';

  @override
  String get ng_now_pick_its_certificate => '现在选择对应的证书。';

  @override
  String get ng_that_file_isn_t_a_certificate => '该文件不是证书或私钥。';

  @override
  String get ng_if_a_proxy_in_front_of =>
      '如果此地址前的代理要求客户端证书，请在此选择证书，以便测试、登录和聊天时都能出示。';

  @override
  String get ng_client_certificates_are_only_used_with =>
      '客户端证书仅用于 https:// 地址。';

  @override
  String get ng_remove => '移除';

  @override
  String get ng_certificate_password => '证书密码';

  @override
  String get ng_importing => '正在导入…';

  @override
  String get ng_pick_certificate => '选择证书';

  @override
  String get ng_pick_a_different_certificate => '选择其他证书';

  @override
  String get ng_accepts_p12_pfx_or_pem_certificate =>
      '支持 .p12/.pfx 文件，或 PEM 证书和密钥文件。密钥会保存在此应用的私有存储空间中。';

  @override
  String get ng_photos => '照片';

  @override
  String get ng_camera => '相机';

  @override
  String get ng_files => '文件';

  @override
  String ng_you_can_attach_up_to_files(Object count) {
    return '最多可附加 $count 个文件。';
  }

  @override
  String ng_couldn_t_read(Object name) {
    return '无法读取 $name。';
  }

  @override
  String ng_couldn_t_prepare_that_file(Object error) {
    return '无法处理该文件：$error';
  }

  @override
  String get ng_hermes_is_still_working => 'Hermes 仍在处理中';

  @override
  String get ng_steer => '引导';

  @override
  String get ng_adds_this_to_the_running_turn => '在当前轮次的下一步中添加此内容';

  @override
  String get ng_queue => '排队';

  @override
  String get ng_sends_it_when_the_turn_finishes => '当前轮次结束后发送';

  @override
  String get ng_stop_and_send => '停止并发送';

  @override
  String get ng_stops_the_turn_then_sends_this => '停止当前轮次，然后发送此内容';

  @override
  String ng_dictation_stopped(Object message) {
    return '听写已停止：$message';
  }

  @override
  String get ng_speech_recognition_isn_t_available => '语音识别不可用。';

  @override
  String get ng_working => '处理中';

  @override
  String get ng_ready => '就绪';

  @override
  String get ng_chats => '聊天';

  @override
  String get ng_new_chat => '新建聊天';

  @override
  String get ng_usage => '用量';

  @override
  String get ng_rename_chat => '重命名聊天';

  @override
  String ng_couldn_t_rename(Object error) {
    return '无法重命名：$error';
  }

  @override
  String get ng_this_chat => '此聊天';

  @override
  String get ng_input_tokens => '输入 Token';

  @override
  String get ng_output_tokens => '输出 Token';

  @override
  String get ng_reasoning_tokens => '推理 Token';

  @override
  String get ng_cache_reads => '缓存读取';

  @override
  String get ng_api_calls => 'API 调用';

  @override
  String get ng_cost => '费用';

  @override
  String get ng_context => '上下文';

  @override
  String get ng_your_sign_in_expired => '登录已过期。';

  @override
  String get ng_sign_in_2 => '登录';

  @override
  String get ng_retry => '重试';

  @override
  String get ng_what_should_we_work_on => '我们要做些什么？';

  @override
  String get ng_ask_hermes_anything_it_can_run =>
      '向 Hermes 提问。它可以运行工具、浏览网页，还能处理服务器上的文件。';

  @override
  String ng_working_2(Object frame) {
    return '正在处理 · $frame';
  }

  @override
  String get ng_default_model => '默认模型';

  @override
  String get ng_listening => '正在聆听…';

  @override
  String get ng_steer_or_queue_a_message => '发送指示或排队发送消息';

  @override
  String get ng_message_hermes => '给 Hermes 发消息';

  @override
  String get ng_attach => '添加附件';

  @override
  String get ng_stop_dictation => '停止听写';

  @override
  String get ng_dictate => '语音输入';

  @override
  String get ng_stop => '停止';

  @override
  String get ng_send => '发送';

  @override
  String get ng_steered => '已调整指示';

  @override
  String get ng_copied => '已复制';

  @override
  String ng_not_sent(Object reason) {
    return '未发送：$reason';
  }

  @override
  String get ng_thinking => '正在思考…';

  @override
  String get ng_thought => '思考';

  @override
  String ng_used(Object name) {
    return '已使用 $name';
  }

  @override
  String ng_used_tools(Object count) {
    return '已使用 $count 个工具';
  }

  @override
  String get ng_copy => '复制';

  @override
  String get ng_the_gateway_connection_dropped_try_again => '网关连接已断开，请重试。';

  @override
  String get ng_allow_once => '允许一次';

  @override
  String get ng_allow_for_this_chat => '在此聊天中允许';

  @override
  String get ng_always_allow => '始终允许';

  @override
  String get ng_deny => '拒绝';

  @override
  String get ng_your_answer => '你的回答';

  @override
  String get ng_or_type_an_answer => '或输入回答';

  @override
  String get ng_skip => '跳过';

  @override
  String get ng_answer => '回答';

  @override
  String get ng_cancel => '取消';

  @override
  String get ng_username_or_email => '用户名或邮箱';

  @override
  String get ng_password => '密码';

  @override
  String get ng_not_now => '暂不';

  @override
  String get ng_save => '保存';

  @override
  String get ng_enter_both_the_client_id_and =>
      '请同时填写 Client ID 和 Client Secret，或都留空。';

  @override
  String get ng_enter_your_username_and_password => '请输入用户名和密码。';

  @override
  String ng_couldn_t_save_the_sign_in(Object error) {
    return '无法保存登录信息：$error';
  }

  @override
  String get ng_wrong_username_or_password => '用户名或密码错误。';

  @override
  String get ng_too_many_attempts_wait_a_moment => '尝试次数过多，请稍等片刻再试。';

  @override
  String get ng_welcome_to_hermes => '欢迎使用 Hermes';

  @override
  String get ng_add_a_gateway => '添加网关';

  @override
  String get ng_connect_to_your_hermes_agent_dashboard =>
      '连接到你的 Hermes Agent 控制面板。使用一个地址和一次登录，即可访问聊天、工具和设置。登录前不会发送任何内容。';

  @override
  String get ng_connect_to_another_hermes_agent_dashboard =>
      '连接到另一个 Hermes Agent 控制面板。你仍会登录已保存的控制面板。';

  @override
  String get ng_dashboard_address => '控制面板地址';

  @override
  String get ng_testing => '正在测试…';

  @override
  String get ng_test => '测试';

  @override
  String get ng_where_your_hermes_dashboard_runs_lan =>
      '你的 Hermes 控制面板所在的位置：局域网、Tailscale 或 HTTPS。';

  @override
  String get ng_find_on_my_network => '在我的网络中查找';

  @override
  String get ng_which_address_do_i_use => '我应该使用哪个地址？';

  @override
  String get ng_behind_cloudflare_access => '使用 Cloudflare Access 保护？';

  @override
  String get ng_need_a_client_certificate => '需要客户端证书？';

  @override
  String get ng_this_address_isn_t_private_and =>
      '此地址不是私有地址，且未使用 https://，因此你的密码和聊天内容会以未加密的形式通过互联网传输。请改用 https://、Tailscale 或你自己的网络。';

  @override
  String get ng_continue_to_sign_in => '继续登录';

  @override
  String get ng_use_the_classic_interface_instead => '改用经典界面';

  @override
  String get ng_if_cloudflare_access_protects_this_address =>
      '如果此地址受 Cloudflare Access 保护，请在 Cloudflare Zero Trust（Access，Service credentials）中创建服务令牌，并为对应的 Access 应用添加 Service Auth 策略。';

  @override
  String get ng_a_service_token_is_saved_for => '已为此地址保存服务令牌';

  @override
  String get ng_forget => '移除';

  @override
  String get ng_client_id => 'Client ID';

  @override
  String get ng_client_secret => 'Client Secret';

  @override
  String get ng_stored_encrypted_on_this_phone_and => '加密存储在此手机上，且只发送到此地址。';

  @override
  String get ng_hermes_is_reachable => '已连接到 Hermes';

  @override
  String ng_hermes_is_reachable_2(Object version) {
    return '已连接到 Hermes $version';
  }

  @override
  String get ng_sign_in_is_tested_next_then => '接下来测试登录，然后测试聊天';

  @override
  String get ng_agent_gateway => 'Agent 网关';

  @override
  String get ng_running => '运行中';

  @override
  String get ng_stopped => '已停止';

  @override
  String get ng_username_password => '用户名和密码';

  @override
  String get ng_browser => '浏览器';

  @override
  String get ng_in_the_browser_sso => '在浏览器中（SSO）';

  @override
  String get ng_profiles => '配置文件';

  @override
  String get ng_this_dashboard_offers_neither_a_username =>
      '此控制面板既未提供用户名和密码登录，也未提供浏览器登录。请更新 Hermes，或在服务器上配置用户名和密码登录。';

  @override
  String get ng_the_auth_gate_is_off_on =>
      '此控制面板未启用身份验证。任何能访问它的人都可以使用你的 Agent。';

  @override
  String get ng_couldn_t_reach_the_dashboard => '无法连接到控制面板';

  @override
  String ng_check_the_address_and_port_9119(Object reason) {
    return '$reason\n\n请检查地址和端口（默认为 9119）。如果控制面板尚未运行，请在服务器上执行：\nhermes dashboard --host 0.0.0.0';
  }

  @override
  String get ng_that_isn_t_a_hermes_dashboard => '这不是 Hermes 控制面板';

  @override
  String get ng_something_answered_but_not_a_hermes_2 =>
      '服务器有响应，但不是 Hermes 控制面板。请使用控制面板的地址，而不是 API 服务器的地址（端口 8642）。';

  @override
  String ng_something_answered_http_but_not_a_2(Object status) {
    return '服务器有响应（HTTP $status），但不是 Hermes 控制面板。请使用控制面板的地址，而不是 API 服务器的地址（端口 8642）。';
  }

  @override
  String get ng_cloudflare_access_stopped_the_request =>
      'Cloudflare Access 已拦截此请求';

  @override
  String ng_cloudflare_access_turned_down_the_service(Object status) {
    return 'Cloudflare Access 拒绝了服务令牌（HTTP $status）。请检查客户端 ID、密钥和 Service Auth 策略。';
  }

  @override
  String get ng_add_a_cloudflare_access_service_token_2 =>
      '请在下方添加 Cloudflare Access 服务令牌，然后重新测试。';

  @override
  String get ng_a_client_certificate_is_needed => '需要客户端证书';

  @override
  String get ng_this_server_asks_for_a_client =>
      '此服务器要求先提供客户端证书。请在下方选择服务器提供的证书，然后重新测试。';

  @override
  String get ng_this_dashboard_doesn_t_ask_for => '此控制面板不需要登录。';

  @override
  String ng_use_the_dashboard_username_and_password(Object address) {
    return '请使用 $address 上配置的控制面板用户名和密码，或在浏览器中登录。';
  }

  @override
  String ng_use_the_dashboard_username_and_password_2(Object address) {
    return '请使用 $address 上配置的控制面板用户名和密码。';
  }

  @override
  String ng_sign_in_to_in_your_browser(Object address) {
    return '请在浏览器中登录 $address，并使用该控制面板所用的账号。';
  }

  @override
  String ng_gateway(Object address) {
    return '网关 $address';
  }

  @override
  String get ng_profile => '配置文件';

  @override
  String get ng_server_default => '服务器默认设置';

  @override
  String get ng_continue => '继续';

  @override
  String get ng_username => '用户名';

  @override
  String get ng_signing_in => '正在登录…';

  @override
  String get ng_waiting_for_the_browser => '正在等待浏览器…';

  @override
  String get ng_sign_in_with_browser => '使用浏览器登录';

  @override
  String get ng_finish_signing_in_on_the_page =>
      '请在打开的页面上完成登录。完成后 Hermes 会自动返回。';

  @override
  String get ng_use_a_different_gateway => '使用其他网关';

  @override
  String get ng_same_wi_fi_or_local_network => '同一 Wi-Fi 或本地网络';

  @override
  String get ng_use_the_server_s_local_address =>
      '使用服务器的本地地址和端口，例如 192.168.1.20:9119。启动控制面板时请添加 --host 0.0.0.0，以便其他设备访问。';

  @override
  String get ng_tailscale => 'Tailscale';

  @override
  String get ng_turn_on_tailscale_on_this_phone =>
      '在这部手机上启用 Tailscale，然后使用服务器的 Tailscale 地址，例如 100.64.0.1:9119 或其 .ts.net 域名。离开家也能使用。';

  @override
  String get ng_use_your_https_address_when_the =>
      '如果控制面板位于带证书的代理后面，请使用你的 https:// 地址。代理还必须支持 /api/ws 上的 WebSocket 升级。';

  @override
  String get ng_start_the_dashboard_on_the_server => '在服务器上启动控制面板：';

  @override
  String get ng_enter_a_port_from_1_to => '请输入 1 到 65535 之间的端口。';

  @override
  String get ng_looks_for_hermes_dashboards_on_port =>
      '在此 Wi-Fi 网络上搜索端口 9119 的 Hermes 控制面板，并检查已保存的电脑。';

  @override
  String ng_looks_for_hermes_dashboards_on_ports(Object port) {
    return '在此 Wi-Fi 网络上搜索端口 9119 和 $port 的 Hermes 控制面板，并检查已保存的电脑。';
  }

  @override
  String get ng_other_port_optional => '其他端口（可选）';

  @override
  String get ng_no_dashboards_answered_start_one_with =>
      '没有控制面板响应。请运行 hermes dashboard --host 0.0.0.0 启动，或输入其地址。';

  @override
  String get ng_using_tailscale_or_a_vpn_those =>
      '正在使用 Tailscale 或 VPN？无法搜索这些网络。请改为输入电脑的 100.x 地址或 .ts.net 域名。';

  @override
  String get ng_search_again => '重新搜索';

  @override
  String get ng_insights => '数据洞察';

  @override
  String get ng_couldn_t_load_insights => '无法加载数据洞察';

  @override
  String get ng_sessions => '会话';

  @override
  String get ng_tokens => '令牌';

  @override
  String get ng_est_cost => '预估费用';

  @override
  String get ng_daily_tokens => '每日令牌用量';

  @override
  String get ng_models => '模型';

  @override
  String get ng_tools => '工具';

  @override
  String get ng_hermes_is_waiting_for_you => 'Hermes 正在等你。';

  @override
  String get ng_hermes_replied => 'Hermes 已回复';

  @override
  String get ng_the_turn_finished => '本轮已完成。';

  @override
  String get ng_off => '关闭';

  @override
  String get ng_minimal => '最低';

  @override
  String get ng_low => '低';

  @override
  String get ng_medium => '中';

  @override
  String get ng_high => '高';

  @override
  String get ng_extra_high => '极高';

  @override
  String get ng_max => '最高';

  @override
  String get ng_ultra => '超强';

  @override
  String get ng_default => '默认';

  @override
  String ng_couldn_t_switch_model(Object error) {
    return '无法切换模型：$error';
  }

  @override
  String get ng_model => '模型';

  @override
  String get ng_thinking_2 => '思考';

  @override
  String get ng_search_models => '搜索模型';

  @override
  String ng_couldn_t_load_models(Object error) {
    return '无法加载模型：$error';
  }

  @override
  String get ng_no_providers_are_set_up_on => '此网关尚未设置任何提供商。';

  @override
  String get ng_starred => '已加星标';

  @override
  String get ng_recent => '最近';

  @override
  String get ng_more => '更多';

  @override
  String get ng_archived_chats => '已归档聊天';

  @override
  String get ng_projects => '项目';

  @override
  String get ng_chats_grouped_by_project_and_workspace => '按项目和工作区分组的聊天';

  @override
  String get ng_agent => '智能体';

  @override
  String get ng_memory => '记忆';

  @override
  String get ng_what_hermes_remembers_about_you => 'Hermes 对你的记忆';

  @override
  String get ng_skills_library => '技能库';

  @override
  String get ng_browse_and_read_installed_skills => '浏览并阅读已安装的技能';

  @override
  String get ng_cron_editor => 'Cron 编辑器';

  @override
  String get ng_edit_schedules_prompts_and_delivery => '编辑计划、提示词和发送方式';

  @override
  String get ng_config_file => '配置文件';

  @override
  String get ng_edit_config_yaml_on_the_gateway => '在网关上编辑 config.yaml';

  @override
  String get ng_models_and_providers => '模型和提供商';

  @override
  String get ng_model_management => '模型管理';

  @override
  String get ng_default_fallback_and_auxiliary_models => '默认、备用和辅助模型';

  @override
  String get ng_provider_sign_in => '提供商登录';

  @override
  String get ng_connect_provider_accounts_with_oauth => '通过 OAuth 连接提供商账号';

  @override
  String get ng_nous_portal => 'Nous Portal';

  @override
  String get ng_subscription_credits_and_usage => '订阅、额度和使用情况';

  @override
  String get ng_interface => '界面';

  @override
  String get ng_switch_to_the_classic_interface => '切换到经典界面';

  @override
  String get ng_turns_nextgen_off_you_can_turn => '关闭 NextGen。你可以在设置中重新开启。';

  @override
  String get ng_restored => '已恢复';

  @override
  String get ng_archived => '已归档';

  @override
  String get ng_couldn_t_load_archived_chats => '无法加载已归档的聊天';

  @override
  String get ng_nothing_archived => '没有已归档的内容';

  @override
  String get ng_restore => '恢复';

  @override
  String get ng_saved_new_chats_use_it => '已保存。新聊天将使用此设置。';

  @override
  String ng_couldn_t_save(Object error) {
    return '无法保存：$error';
  }

  @override
  String get ng_saving => '正在保存…';

  @override
  String ng_today(Object time) {
    return '今天 $time';
  }

  @override
  String get ng_mon => '周一';

  @override
  String get ng_tue => '周二';

  @override
  String get ng_wed => '周三';

  @override
  String get ng_thu => '周四';

  @override
  String get ng_fri => '周五';

  @override
  String get ng_sat => '周六';

  @override
  String get ng_sun => '周日';

  @override
  String get ng_scheduled => '计划任务';

  @override
  String get ng_new_job => '新建任务';

  @override
  String get ng_couldn_t_load_scheduled_jobs => '无法加载计划任务';

  @override
  String get ng_nothing_scheduled => '没有计划任务';

  @override
  String get ng_ask_hermes_to_do_something_on => '让 Hermes 按计划执行任务，或在此处添加任务。';

  @override
  String get ng_active => '运行中';

  @override
  String get ng_paused => '已暂停';

  @override
  String ng_next(Object when) {
    return '下次 $when';
  }

  @override
  String ng_last(Object when) {
    return '上次 $when';
  }

  @override
  String ng_last_2(Object when, Object result) {
    return '上次 $when · $result';
  }

  @override
  String ng_job(Object id) {
    return '任务 $id';
  }

  @override
  String get ng_delete => '删除';

  @override
  String get ng_delete_this_job => '删除此任务？';

  @override
  String get ng_it_stops_running_past_runs_stay => '删除后将停止运行。以往的运行记录仍会保留在聊天中。';

  @override
  String ng_next_run(Object when) {
    return '下次运行：$when';
  }

  @override
  String ng_delivers_to(Object target) {
    return '发送至 $target';
  }

  @override
  String get ng_run_now => '立即运行';

  @override
  String get ng_started => '已启动';

  @override
  String get ng_pause => '暂停';

  @override
  String get ng_resume => '继续';

  @override
  String get ng_resumed => '已继续';

  @override
  String get ng_prompt => '提示词';

  @override
  String get ng_runs => '运行记录';

  @override
  String get ng_no_runs_yet => '暂无运行记录。';

  @override
  String get ng_enter_a_schedule_and_a_prompt => '请填写计划和提示词。';

  @override
  String get ng_name_optional => '名称（可选）';

  @override
  String get ng_schedule => '计划';

  @override
  String get ng_every_1h_0_9_or_30m => 'every 1h, 0 9 * * *, or 30m';

  @override
  String get ng_create => '创建';

  @override
  String get ng_unpin => '取消置顶';

  @override
  String get ng_pin => '置顶';

  @override
  String get ng_rename => '重命名';

  @override
  String get ng_archive => '归档';

  @override
  String get ng_delete_this_chat => '删除此聊天？';

  @override
  String get ng_it_is_removed_from_the_gateway => '此聊天会从网关中删除，并从所有设备上移除。';

  @override
  String get ng_search_chats => '搜索聊天';

  @override
  String get ng_pinned => '已置顶';

  @override
  String get ng_no_chats_match => '没有匹配的聊天。';

  @override
  String get ng_no_chats_yet => '暂无聊天。';

  @override
  String get ng_nothing_is_running => '暂无运行中的任务。';

  @override
  String get ng_nothing_is_waiting_on_you => '暂无待你处理的事项。';

  @override
  String get ng_settings => '设置';

  @override
  String get ng_all => '全部';

  @override
  String ng_needs_you(Object count) {
    return '需要你处理 · $count';
  }

  @override
  String get ng_needs_you_2 => '需要你处理';

  @override
  String get ng_gateways => '网关';

  @override
  String ng_classic_connection(Object address) {
    return '$address · 经典连接';
  }

  @override
  String get ng_gateway_2 => '网关';

  @override
  String get ng_signed_in => '已登录';

  @override
  String get ng_classic_connection_2 => '经典连接';

  @override
  String get ng_in_the_browser => '在浏览器中';

  @override
  String ng_in_the_browser_as(Object name) {
    return '以 $name 身份在浏览器中';
  }

  @override
  String get ng_not_required => '无需操作';

  @override
  String get ng_test_connection => '测试连接';

  @override
  String get ng_sign_in_again_2 => '重新登录';

  @override
  String get ng_sign_out => '退出登录';

  @override
  String get ng_saved_gateways => '已保存的网关';

  @override
  String get ng_in_use => '使用中';

  @override
  String get ng_appearance => '外观';

  @override
  String get ng_theme => '主题';

  @override
  String get ng_system => '跟随系统';

  @override
  String get ng_light => '浅色';

  @override
  String get ng_dark => '深色';

  @override
  String get ng_accent => '强调色';

  @override
  String get ng_pure_black => '纯黑';

  @override
  String get ng_dark_theme_uses_true_black_oled => '深色主题使用纯黑（OLED）';

  @override
  String get ng_glow => '光晕';

  @override
  String get ng_soft_accent_light_behind_each_screen => '每个页面背后的柔和强调色光效';

  @override
  String get ng_the_new_interface_turn_off_to => '新版界面。关闭后可切回经典界面；网关和聊天记录会共用。';

  @override
  String get ng_more_settings => '更多设置';

  @override
  String get ng_voice_notifications_language_backups_and_the =>
      '语音、通知、语言、备份和网关配置';

  @override
  String get ng_licences => '许可证';

  @override
  String ng_sign_out_of(Object name) {
    return '要退出 $name 吗？';
  }

  @override
  String get ng_this_gateway_and_its_saved_sign =>
      '此网关及其已保存的登录信息会从这部手机的两个界面中移除。聊天记录仍保留在网关上。';

  @override
  String get ng_password_or_browser => '密码或浏览器';

  @override
  String get ng_unsupported => '不支持';
}
