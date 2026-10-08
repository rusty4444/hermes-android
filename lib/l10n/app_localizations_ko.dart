// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get a_one_off_question_archives_itself_after_72_hours_anything =>
      '일회성 질문입니다. 72시간 후에 자동으로 보관 처리되며, 보관할 가치가 있는 내용은 기억에 유지됩니다.';

  @override
  String get ai_full_text => 'AI + 전문 검색';

  @override
  String get ai_search_model => 'AI 검색 모델';

  @override
  String ai_searched_for(Object aiRewrittenQuery) {
    return 'AI 검색어: $aiRewrittenQuery';
  }

  @override
  String get ai_assisted_filing => 'AI 지원 정리';

  @override
  String get api_key => 'API 키';

  @override
  String get api_server_key_from_hermes_env => '~/.hermes/.env의 API_SERVER_KEY';

  @override
  String get active => '활성';

  @override
  String get activity => '활동';

  @override
  String get activity_reads_the_durable_turn_journal_to_know_what_hermes =>
      '활동 기능은 영구 턴 저널을 읽어 Hermes의 작업 내용을 파악합니다. 게이트웨이 연결 상태를 확인한 후 다시 시도하세요.';

  @override
  String get add => '추가';

  @override
  String get add_connection => '연결 추가';

  @override
  String get add_cron_job => 'Cron 작업 추가';

  @override
  String get add_gateway_connection => '게이트웨이 연결 추가';

  @override
  String get add_and_update_connections_from_the_backup_keep_the_rest =>
      '백업에서 연결을 추가 및 업데이트하고 나머지는 유지합니다.';

  @override
  String get add_attachment => '첨부 파일 추가';

  @override
  String get add_new_cron_job => '새 Cron 작업 추가';

  @override
  String get add_to_chat => '채팅에 추가';

  @override
  String get all_chats => '모든 채팅';

  @override
  String get all_stored_message_content => '저장된 모든 메시지 콘텐츠';

  @override
  String get allow_for_this_session => '이번 세션 동안 허용';

  @override
  String get allow_matching_commands_until_this_hermes_session_ends =>
      '이 Hermes 세션이 끝날 때까지 일치하는 명령을 허용합니다.';

  @override
  String get allow_once => '한 번 허용';

  @override
  String get always_allow => '항상 허용';

  @override
  String get apply_to_this_chat => '이 채팅에 적용';

  @override
  String get approval_needed => '승인 필요';

  @override
  String get archive => '보관';

  @override
  String get archive_project => '프로젝트 보관';

  @override
  String archive_2(Object projectName) {
    return '$projectName을(를) 보관하시겠습니까?';
  }

  @override
  String archive_3(Object name) {
    return '$name을(를) 보관하시겠습니까?';
  }

  @override
  String get archived => '보관됨';

  @override
  String get archived_conversations_appear_here => '보관된 대화가 여기에 표시됩니다.';

  @override
  String get archived_quick_chats => '보관된 빠른 채팅';

  @override
  String get artifacts_attachments_and_generated_media =>
      '아티팩트, 첨부 파일, 생성된 미디어';

  @override
  String get ask_ai_to_find_a_conversation => 'AI에게 대화 찾기 요청';

  @override
  String get assets => '에셋';

  @override
  String get assets_need_a_server_authoritative_assets_index_in_the_hermes =>
      '에셋을 프로젝트별로 표시하려면 Hermes 게이트웨이에 서버 권한 에셋 색인이 필요합니다.';

  @override
  String get assets_unavailable => '에셋을 사용할 수 없음';

  @override
  String get attach_image_or_file => '이미지 또는 파일 첨부';

  @override
  String get attachment_drafts => '첨부 파일 초안';

  @override
  String attachment_of(Object index, Object total) {
    return '첨부 파일 $index/$total';
  }

  @override
  String get auto_device_default => '자동 (기기 기본값)';

  @override
  String get auto_archives_after_72_hours => '72시간 후 자동 보관';

  @override
  String get automation => '자동화';

  @override
  String get autonomous_agents => '자율 에이전트';

  @override
  String get background_recovery_unavailable_legacy_transport =>
      '백그라운드 복구를 사용할 수 없음 — 레거시 전송';

  @override
  String get backup_restore => '백업 및 복원';

  @override
  String backup_exported(Object destination) {
    return '백업 내보내기 완료 — $destination';
  }

  @override
  String get base_url => '기본 URL';

  @override
  String get binary_preview_is_unavailable_download_the_file_to_open_it =>
      '이진 미리보기를 사용할 수 없습니다. 파일을 다운로드하여 여세요.';

  @override
  String get branch => '분기';

  @override
  String get branch_chat => '채팅 분기';

  @override
  String get branch_created_in_hermes_history => 'Hermes 기록에 분기가 생성되었습니다.';

  @override
  String get browse_and_manage_your_hermes_agent_sessions_from_your_phone =>
      '휴대전화에서 Hermes Agent 세션을 탐색하고 관리하세요. 로컬 네트워크에서 실행 중인 Hermes 대시보드에 연결합니다.';

  @override
  String get browse_server_files => '서버 파일 찾아보기';

  @override
  String get browse_the_miniserver_folders_behind_your_projects =>
      '프로젝트 뒤에 있는 miniserver 폴더 찾아보기';

  @override
  String get cancel => '취소';

  @override
  String get cancel_voice_input => '음성 입력 취소';

  @override
  String cannot_reach(Object host, Object port) {
    return '$host:$port에 연결할 수 없습니다.';
  }

  @override
  String cannot_reach_check_the_host_and_port(Object host, Object port) {
    return '$host:$port에 연결할 수 없습니다. 호스트와 포트를 확인하세요.';
  }

  @override
  String get change_ai_search_model => 'AI 검색 모델 변경';

  @override
  String changes_the_default_for_use_the_selector_in_a_chat(Object label) {
    return '$label의 기본값을 변경합니다. 해당 대화에서만 재정의하려면 채팅 내 선택기를 사용하세요.';
  }

  @override
  String get chat_actions => '채팅 작업';

  @override
  String get chats => '채팅';

  @override
  String get chats_from_this_gateway_are_not_grouped_yet_grouping_stays =>
      '이 게이트웨이의 채팅은 아직 그룹화되지 않았습니다. 그룹화는 게이트웨이가 프로젝트를 호스팅할 수 있을 때까지 이 휴대전화에 유지됩니다.';

  @override
  String get chats_in_this_project_will_show_their_state_and_last =>
      '이 프로젝트의 채팅은 여기에 상태와 마지막 활동을 표시합니다.';

  @override
  String get chats_that_are_not_assigned_to_a_project => '프로젝트에 할당되지 않은 채팅';

  @override
  String get chats_you_start_in_this_project_will_appear_here_on =>
      '이 프로젝트에서 시작한 채팅은 이 Hermes에 로그인된 모든 기기에 여기에 표시됩니다.';

  @override
  String get check_that_the_gateway_is_running_and_reachable_then_try =>
      '게이트웨이가 실행 중이고 도달 가능한지 확인한 후 다시 시도하세요.';

  @override
  String get check_the_dashboard_connection_and_try_again =>
      '대시보드 연결을 확인하고 다시 시도하세요.';

  @override
  String get check_the_connection_and_try_again => '연결을 확인하고 다시 시도하세요.';

  @override
  String get choose_a_small_model_to_rewrite_queries => '쿼리를 재작성할 소형 모델을 선택하세요';

  @override
  String get choose_an_ai_search_model_before_using_ai_search =>
      'AI 검색을 사용하기 전에 AI 검색 모델을 선택하세요.';

  @override
  String get choose_an_active_project_next => '다음으로 활성 프로젝트 선택';

  @override
  String get choose_chat_model => '채팅 모델 선택';

  @override
  String get choose_files => '파일 선택';

  @override
  String get choose_image => '이미지 선택';

  @override
  String get choose_images => '이미지 선택';

  @override
  String get choose_its_destination_space => '대상 스페이스 선택';

  @override
  String get clear_search => '검색 지우기';

  @override
  String get close => '닫기';

  @override
  String get code_copied => '코드가 복사되었습니다';

  @override
  String get coming_next => '예정된 기능';

  @override
  String get command => '명령';

  @override
  String get command_line_chats => '명령줄 채팅';

  @override
  String get compatibility_mode => '호환성 모드';

  @override
  String get configure_a_valid_desktop_gateway_url_before_attaching_files =>
      '파일을 첨부하기 전에 올바른 Desktop Gateway URL을 설정하세요.';

  @override
  String get confirm_always_allow => '항상 허용 확인';

  @override
  String get confirm_passphrase => '패스프레이즈 확인';

  @override
  String connecting_to(Object baseUrl) {
    return '$baseUrl에 연결 중...';
  }

  @override
  String get connection_issue => '연결 문제';

  @override
  String
  get connection_switched_the_running_reply_continues_on_the_server_and =>
      '연결이 전환되었습니다. 실행 중인 응답은 서버에서 계속 진행되며 자동으로 다시 연결됩니다.';

  @override
  String get connection_appearance_and_device_preferences => '연결, 외관 및 기기 환경설정';

  @override
  String context_tokens(Object effectiveContextLength) {
    return '컨텍스트: $effectiveContextLength 토큰';
  }

  @override
  String get continue_label => '계속';

  @override
  String get continue_working => '작업 계속하기';

  @override
  String get conversations_in_this_project => '이 프로젝트의 대화';

  @override
  String get copy_code => '코드 복사';

  @override
  String get copy_message => '메시지 복사';

  @override
  String could_not_branch_chat(Object error) {
    return '채팅을 분기할 수 없습니다: $error';
  }

  @override
  String could_not_delete_session(Object error) {
    return '세션을 삭제할 수 없습니다: $error';
  }

  @override
  String could_not_deny_the_command(Object error) {
    return '명령을 거부할 수 없습니다: $error';
  }

  @override
  String could_not_load_ai_search_models(Object error) {
    return 'AI 검색 모델을 불러올 수 없습니다: $error';
  }

  @override
  String get could_not_load_conversations => '대화를 불러올 수 없습니다';

  @override
  String get could_not_load_files => '파일을 불러올 수 없습니다';

  @override
  String could_not_load_models_for_this_profile(Object error) {
    return '이 프로필의 모델을 불러올 수 없습니다: $error';
  }

  @override
  String could_not_load_more_chats(Object error) {
    return '채팅을 더 불러올 수 없습니다: $error';
  }

  @override
  String get could_not_open_the_hermes_dashboard => 'Hermes 대시보드를 열 수 없습니다.';

  @override
  String get could_not_open_this_project => '이 프로젝트를 열 수 없습니다';

  @override
  String get could_not_preview_file => '파일을 미리 볼 수 없습니다';

  @override
  String get could_not_reach_hermes => 'Hermes에 연결할 수 없습니다';

  @override
  String could_not_reach_authenticate_the_dashboard_at_check_the_port(
    Object dashboardPort,
    Object host,
  ) {
    return '$host:$dashboardPort의 대시보드에 연결하거나 인증할 수 없습니다. 포트와 자격 증명을 확인하세요.';
  }

  @override
  String get could_not_read_activity => '활동을 읽을 수 없습니다';

  @override
  String could_not_rename_chat(Object error) {
    return '채팅 이름을 변경할 수 없습니다: $error';
  }

  @override
  String could_not_send_the_approval(Object error) {
    return '승인을 보낼 수 없습니다: $error';
  }

  @override
  String get could_not_skip_the_hermes_question => 'Hermes 질문을 건너뛸 수 없습니다.';

  @override
  String could_not_the_project(Object action, Object error) {
    return '프로젝트를 $action할 수 없습니다: $error';
  }

  @override
  String get couldn_t_delete_project => '프로젝트를 삭제할 수 없습니다';

  @override
  String couldn_t_load_runs(Object error) {
    return '실행 기록을 불러올 수 없습니다: $error';
  }

  @override
  String get couldn_t_move_conversation => '대화를 이동할 수 없습니다';

  @override
  String couldn_t_move_to(Object label, Object reason) {
    return '$label(으)로 이동할 수 없습니다: $reason';
  }

  @override
  String get couldn_t_prepare_the_shared_files => '공유 파일을 준비할 수 없습니다.';

  @override
  String get couldn_t_promote_conversation => '대화를 승격할 수 없습니다';

  @override
  String couldn_t_project(Object action) {
    return '프로젝트를 $action할 수 없습니다';
  }

  @override
  String get create => '만들기';

  @override
  String get create_a_project => '프로젝트 만들기';

  @override
  String get create_a_project_first_then_chats_can_live_inside_it =>
      '프로젝트를 먼저 만들면 그 안에 채팅을 보관할 수 있습니다.';

  @override
  String get create_a_space_to_separate_related_conversations =>
      '관련 대화를 분리할 스페이스를 만드세요.';

  @override
  String get create_branch => '분기 만들기';

  @override
  String get cron => 'Cron';

  @override
  String get cron_jobs => 'Cron 작업';

  @override
  String get cron_job_added => 'Cron 작업이 추가되었습니다';

  @override
  String get cron_job_updated => 'Cron 작업이 업데이트되었습니다';

  @override
  String get cron_run => 'Cron 실행';

  @override
  String get cross_device_ordering_and_reversible_bulk_organization =>
      '기기 간 정렬 및 되돌리기 가능한 일괄 정리';

  @override
  String get current_profile_default => '현재 프로필 기본값';

  @override
  String get custom_proxy_and_dashboard_details => '사용자 정의 프록시 및 대시보드 세부 정보';

  @override
  String get dark => '다크';

  @override
  String get dashboard_proxy_settings => '대시보드 / 프록시 설정';

  @override
  String get dashboard_password_optional => '대시보드 비밀번호 (선택 사항)';

  @override
  String get dashboard_port => '대시보드 포트';

  @override
  String get dashboard_username_optional => '대시보드 사용자 이름 (선택 사항)';

  @override
  String get dashboard_behind_proxy => '프록시 뒤의 대시보드';

  @override
  String get dashboard_path_prefix => '대시보드 경로 접두사';

  @override
  String delegated_task(Object goal) {
    return '위임된 작업: $goal';
  }

  @override
  String get delete => '삭제';

  @override
  String delete_2(Object name) {
    return '\"$name\"을(를) 삭제하시겠습니까?';
  }

  @override
  String delete_from_the_remote_hermes_history_this_cannot_be_undone(
    Object title,
  ) {
    return '원격 Hermes 기록에서 \"$title\"을(를) 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.';
  }

  @override
  String get delete_cron_job => 'Cron 작업 삭제';

  @override
  String get delete_connections_that_are_not_in_the_backup =>
      '백업에 없는 연결을 삭제합니다.';

  @override
  String delete_failed(Object error) {
    return '삭제 실패: $error';
  }

  @override
  String get delete_project => '프로젝트 삭제';

  @override
  String get delete_session => '세션을 삭제하시겠습니까?';

  @override
  String delete_3(Object projectName) {
    return '$projectName을(를) 삭제하시겠습니까?';
  }

  @override
  String deleted(Object name) {
    return '\"$name\"이(가) 삭제되었습니다';
  }

  @override
  String get delivery_is_uncertain_recovering_without_resending =>
      '전송 상태가 불확실합니다. 재전송하지 않고 복구하는 중…';

  @override
  String get desktop_gateway_url_optional => 'Desktop Gateway URL (선택 사항)';

  @override
  String get desktop_gateway_is_not_configured_for_this_connection =>
      '이 연결에는 Desktop Gateway가 구성되어 있지 않습니다.';

  @override
  String get desktop_app => '데스크톱 앱';

  @override
  String get developer_tool_calls => '개발자 도구 호출';

  @override
  String get discord_chats => 'Discord 채팅';

  @override
  String get dismiss => '닫기';

  @override
  String get do_not_run_this_command => '이 명령을 실행하지 마세요.';

  @override
  String get documents_archives_audio_video_or_data =>
      '문서, 아카이브, 오디오, 비디오 또는 데이터';

  @override
  String get download => '다운로드';

  @override
  String download_failed(Object error) {
    return '다운로드 실패: $error';
  }

  @override
  String get durable_facts_hermes_keeps_about_you => 'Hermes가 기억하는 지속적인 정보';

  @override
  String get durable_work_inside_one_of_your_projects_shared_with_desktop =>
      'Desktop과 공유되는 프로젝트 내의 지속적인 작업입니다.';

  @override
  String get edit => '편집';

  @override
  String get edit_connection => '연결 편집';

  @override
  String get edit_cron_job => 'Cron 작업 편집';

  @override
  String get edit_gateway_connection => '게이트웨이 연결 편집';

  @override
  String get edit_and_resend => '편집 후 다시 보내기';

  @override
  String get enables_file_attachments_through_the_desktop_remote_gateway =>
      'Desktop 원격 게이트웨이를 통한 파일 첨부를 활성화합니다.';

  @override
  String get enter_a_name => '이름을 입력하세요';

  @override
  String get enter_a_passphrase => '패스프레이즈를 입력하세요.';

  @override
  String get enter_the_passphrase_for_this_backup => '이 백업의 패스프레이즈를 입력하세요.';

  @override
  String get every_conversation_is_already_assigned_to_a_project =>
      '모든 대화가 이미 프로젝트에 할당되어 있습니다.';

  @override
  String get everything_not_yet_native_in_the_authenticated_web_dashboard =>
      '아직 네이티브로 구현되지 않은 모든 기능은 인증된 웹 대시보드에서 확인하세요.';

  @override
  String get explain_the_attached_content_clearly => '첨부된 내용을 명확하게 설명하세요.';

  @override
  String explain_this_content_clearly(Object text) {
    return '이 내용을 명확하게 설명하세요:\n\n$text';
  }

  @override
  String
  get explicit_choices_adjust_android_accessibility_text_size_system_leaves_it =>
      '직접 선택하여 Android 접근성 텍스트 크기를 조정하거나, 시스템 설정을 따르세요.';

  @override
  String get export_label => '내보내기';

  @override
  String get export_share => '내보내기 / 공유';

  @override
  String get external_api_clients => '외부 API 클라이언트';

  @override
  String get extra_high => '매우 높음';

  @override
  String get extract_tasks => '작업 추출';

  @override
  String
  get extract_the_decisions_deadlines_owners_and_actionable_action_items_from =>
      '첨부된 내용에서 결정 사항, 마감 기한, 담당자 및 실행 가능한 작업 항목을 추출하세요.';

  @override
  String
  extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
    Object text,
  ) {
    return '이 내용에서 결정 사항, 마감 기한, 담당자 및 실행 가능한 작업 항목을 추출하세요:\n\n$text';
  }

  @override
  String failed_to_add_job(Object error) {
    return '작업 추가 실패: $error';
  }

  @override
  String get failed_to_load_cron_jobs => 'Cron 작업 불러오기 실패';

  @override
  String get failed_to_load_memory => '메모리 불러오기 실패';

  @override
  String get failed_to_load_messages => '메시지 불러오기 실패';

  @override
  String get failed_to_load_settings => '설정 불러오기 실패';

  @override
  String get failed_to_load_skills => '스킬 불러오기 실패';

  @override
  String failed_to_update_job(Object error) {
    return '작업 업데이트 실패: $error';
  }

  @override
  String failed(Object error) {
    return '실패: $error';
  }

  @override
  String get file_attached_document_catalog_registration_is_pending =>
      '파일이 첨부되었습니다. 문서 카탈로그 등록이 진행 중입니다.';

  @override
  String get file_reference_added_to_chat => '채팅에 파일 참조가 추가되었습니다';

  @override
  String get files => '파일';

  @override
  String get fill_from_document => '문서에서 채우기';

  @override
  String get folder_is_empty => '폴더가 비어 있습니다';

  @override
  String get folders => '폴더';

  @override
  String get full_text => '전체 텍스트';

  @override
  String get gateway_api_access => '게이트웨이 API 액세스';

  @override
  String get gateway_connected_but_the_dashboard_could_not_be_reached_or =>
      '게이트웨이에 연결되었으나 대시보드에 도달할 수 없거나 인증되지 않았습니다. 대시보드 세부 정보를 확인하거나, 건너뛰려면 지우세요.';

  @override
  String get gateway_path_prefix => '게이트웨이 경로 접두사';

  @override
  String get go_to_end => '끝으로 이동';

  @override
  String get hermes_agent => 'Hermes Agent';

  @override
  String get hermes_agent_for_android => 'Android용 Hermes Agent';

  @override
  String get hermes_could_not_accept_the_answer_please_try_again =>
      'Hermes가 답변을 수락하지 못했습니다. 다시 시도해 주세요.';

  @override
  String get hermes_could_not_load_your_saved_connections =>
      'Hermes가 저장된 연결을 불러올 수 없습니다';

  @override
  String get hermes_did_not_accept_the_response_please_try_again =>
      'Hermes가 응답을 수락하지 않았습니다. 다시 시도해 주세요.';

  @override
  String get hermes_is_responding => 'Hermes가 응답 중입니다…';

  @override
  String get hermes_is_waiting_for_input => 'Hermes가 입력을 기다리는 중입니다…';

  @override
  String get hermes_keeps_android_accessibility_text_scaling_active =>
      'Hermes는 Android 접근성 텍스트 크기 조정을 활성 상태로 유지합니다.';

  @override
  String get hermes_needs_your_input => 'Hermes에 입력이 필요합니다';

  @override
  String get hermes_profile_optional => 'Hermes 프로필 (선택 사항)';

  @override
  String get hermes_profile_must_be_a_plain_profile_name_such_as =>
      'Hermes 프로필은 경로가 아닌 \"sol\"과 같은 일반적인 프로필 이름이어야 합니다.';

  @override
  String get hermes_reasoning_details => 'Hermes 추론 세부 정보';

  @override
  String hermes_recovery_is_unavailable(Object error) {
    return 'Hermes 복구를 사용할 수 없습니다: $error';
  }

  @override
  String get hermes_stopped_recovery_safely_no_prompt_was_resent =>
      'Hermes가 안전하게 복구를 중단했습니다. 프롬프트가 다시 전송되지 않았습니다.';

  @override
  String get hide_passphrase => '패스프레이즈 숨기기';

  @override
  String get home_needs_your_recent_chats_to_know_what_deserves_your =>
      '홈 화면에서 주의가 필요한 항목을 파악하려면 최근 채팅이 필요합니다. 게이트웨이에 연결할 수 있는지 확인한 후 다시 시도하세요.';

  @override
  String get host => '호스트';

  @override
  String get image_selection_was_interrupted_try_again =>
      '이미지 선택이 중단되었습니다. 다시 시도하세요.';

  @override
  String get import_label => '가져오기';

  @override
  String get inbox => '받은편지함';

  @override
  String get inbox_is_clear => '받은편지함이 비어 있습니다';

  @override
  String get insert_a_remote_file_reference => '원격 @file 참조 삽입';

  @override
  String get invalid_port_number => '유효하지 않은 포트 번호입니다.';

  @override
  String get job_paused => '작업 일시 중지됨';

  @override
  String get job_resumed => '작업 재개됨';

  @override
  String get job_triggered => '작업 트리거됨';

  @override
  String get label => '라벨';

  @override
  String last_activity(Object day, Object month, Object year) {
    return '최근 활동 $year/$month/$day';
  }

  @override
  String last(Object lastRun) {
    return '마지막: $lastRun';
  }

  @override
  String get leave_blank_for_default_8642_443_with_https =>
      '기본값(8642; https 사용 시 443)을 사용하려면 비워 두세요';

  @override
  String get leave_blank_for_default_9119 => '기본값(9119)을 사용하려면 비워 두세요';

  @override
  String get light => '라이트';

  @override
  String listening(Object elapsed) {
    return '듣는 중 • $elapsed';
  }

  @override
  String listening_elapsed(Object elapsed) {
    return '듣는 중, 경과 시간 $elapsed';
  }

  @override
  String get load_more => '더 불러오기…';

  @override
  String get loading => '불러오는 중';

  @override
  String get location => '위치';

  @override
  String get make_sure_the_gateway_api_server_is_running_hermes_gateway =>
      '게이트웨이 API 서버가 실행 중인지 확인하세요\n(hermes gateway status)';

  @override
  String matches(Object assigned, Object name) {
    return '$name · $assigned 일치';
  }

  @override
  String get memory => '메모리';

  @override
  String get memory_entries_are_cross_session_facts_the_agent_remembers_they =>
      '메모리 항목은 에이전트가 기억하는 세션 간 정보입니다.\n~/.hermes/config.yaml에서 설정할 수 있습니다.';

  @override
  String get merge => '병합';

  @override
  String get message => '메시지';

  @override
  String get message_hermes => 'Hermes에게 메시지 보내기…';

  @override
  String get message_actions => '메시지 작업';

  @override
  String get message_copied => '메시지가 복사되었습니다';

  @override
  String get migrating => '마이그레이션 중…';

  @override
  String get migration_complete => '마이그레이션 완료';

  @override
  String get migration_failed_local_spaces_were_kept_unchanged =>
      '마이그레이션에 실패했습니다. 로컬 스페이스는 변경되지 않았습니다.';

  @override
  String get migration_incomplete => '마이그레이션이 완료되지 않았습니다';

  @override
  String get migration_preview => '마이그레이션 미리보기';

  @override
  String get model => '모델';

  @override
  String get model_and_thinking_for_this_chat => '이 채팅을 위한 모델 및 추론';

  @override
  String model_was_not_changed(Object error) {
    return '모델이 변경되지 않았습니다: $error';
  }

  @override
  String get move_attachment_next => '첨부 파일을 다음으로 이동';

  @override
  String get move_attachment_previous => '첨부 파일을 이전으로 이동';

  @override
  String get move_chat => '채팅 이동';

  @override
  String get move_conversation => '대화 이동';

  @override
  String get move_to_project => '프로젝트로 이동';

  @override
  String get move_to_space => '스페이스로 이동';

  @override
  String get moved_to_a_project => '프로젝트로 이동됨';

  @override
  String moved_to(Object label) {
    return '$label(으)로 이동됨';
  }

  @override
  String get name => '이름';

  @override
  String get name_prompt_and_schedule_are_required => '이름, 프롬프트, 스케줄은 필수 항목입니다';

  @override
  String get nav_activity => '활동';

  @override
  String get nav_projects => '프로젝트';

  @override
  String get needs_a_correction_aware_filing_contract_in_the_hermes_gateway =>
      'Hermes 게이트웨이에 수정 인식 파일링 계약이 필요합니다.';

  @override
  String get needs_a_reachable_hermes_dashboard_check_the_host_port_and =>
      '연결 가능한 Hermes 대시보드가 필요합니다. 이 연결의 호스트, 포트 및 자격 증명을 확인하세요.';

  @override
  String get needs_a_server_authoritative_assets_index_in_the_hermes_gateway =>
      'Hermes 게이트웨이에 서버 권한 자산 인덱스가 필요합니다.';

  @override
  String get needs_durable_pin_ordering_batch_mutation_and_undo_contracts_in =>
      'Hermes 게이트웨이에 영구 고정 순서 지정, 일괄 변경 및 실행 취소 계약이 필요합니다.';

  @override
  String get needs_you => '확인 필요';

  @override
  String get new_label => '신규';

  @override
  String get new_chat => '새 채팅';

  @override
  String get new_chat_2 => '새 채팅';

  @override
  String new_chat_3(Object projectName) {
    return '새 채팅 · $projectName';
  }

  @override
  String get new_project => '새 프로젝트';

  @override
  String get new_space => '새 스페이스';

  @override
  String next(Object nextRun) {
    return '다음: $nextRun';
  }

  @override
  String get nginx_injects_auth_app_sends_clean_requests =>
      'Nginx가 인증을 주입합니다 — 앱은 깔끔한 요청을 보냅니다';

  @override
  String get no_tts_voices_found_ninstall_google_text_to_speech_and =>
      '사용 가능한 TTS 음성이 없습니다.\nGoogle Text-to-Speech를 설치하고 음성 데이터를 다운로드하세요.';

  @override
  String get no_active_projects_on_this_gateway => '이 게이트웨이에 활성 프로젝트가 없습니다';

  @override
  String get no_activity_yet => '아직 활동이 없습니다';

  @override
  String get no_chat_is_blocked_running_or_waiting_to_be_resumed =>
      '차단되었거나 실행 중이거나 재개 대기 중인 채팅이 없습니다. 준비되면 언제든 새 채팅을 시작하세요.';

  @override
  String no_chats_in_this_project_match(Object searchQuery) {
    return '이 프로젝트에서 “$searchQuery”와(과) 일치하는 채팅이 없습니다.';
  }

  @override
  String get no_chats_in_this_space_yet_tap_to_start_one =>
      '이 스페이스에 아직 채팅이 없습니다. +를 눌러 시작하세요.';

  @override
  String get no_chats_yet => '아직 채팅이 없습니다';

  @override
  String get no_connections => '연결 없음';

  @override
  String get no_conversation_matches_this_view => '이 보기와 일치하는 대화가 없습니다.';

  @override
  String get no_cron_jobs => 'Cron 작업 없음';

  @override
  String get no_folders_yet => '아직 폴더가 없습니다';

  @override
  String get no_local_spaces_were_found_for_this_connection_so_projects =>
      '이 연결에서 로컬 스페이스를 찾지 못했으므로 프로젝트가 이미 여기서 사용되는 유일한 정리 방식입니다.';

  @override
  String get no_matches => '일치하는 항목 없음';

  @override
  String get no_memory_entries => '메모리 항목 없음';

  @override
  String get no_message_content_matches => '메시지 내용과 일치하는 항목 없음';

  @override
  String get no_new_messages => '새 메시지 없음';

  @override
  String get no_projects_yet => '아직 프로젝트가 없습니다';

  @override
  String get no_runs_yet => '아직 실행 기록이 없습니다.';

  @override
  String no_server_project_matches_this_name(Object assigned) {
    return '이 이름과 일치하는 서버 프로젝트가 없습니다 · $assigned';
  }

  @override
  String get no_sessions_yet => '아직 세션이 없습니다';

  @override
  String get no_skills_found => '스킬을 찾을 수 없습니다';

  @override
  String get no_spaces_on_this_device => '이 기기에 스페이스가 없습니다';

  @override
  String get no_text_shared => '공유된 텍스트 없음';

  @override
  String get no_turn_is_blocked_in_flight_or_recently_finished_work =>
      '차단되었거나, 진행 중이거나, 최근에 완료된 턴이 없습니다. 작업을 시작하면 여기에 표시됩니다.';

  @override
  String get no_turn_needs_your_input_or_has_failed => '입력이 필요하거나 실패한 턴이 없습니다.';

  @override
  String get no_unassigned_chats => '할당되지 않은 채팅이 없습니다.';

  @override
  String get nothing_changed_in_the_last_seven_days => '지난 7일 동안 변경된 내용이 없습니다.';

  @override
  String get nothing_has_moved_yet_this_is_only_what_a_migration =>
      '아직 이동된 항목이 없습니다 — 마이그레이션이 수행할 작업의 미리보기입니다.';

  @override
  String get nothing_here => '항목이 없습니다';

  @override
  String get nothing_is_running => '실행 중인 작업이 없습니다';

  @override
  String get nothing_needs_you => '조치가 필요한 항목이 없습니다';

  @override
  String get nothing_to_migrate => '마이그레이션할 항목이 없습니다';

  @override
  String get off_no_thinking => '끔 (추론 없음)';

  @override
  String get offline_showing_the_last_known_activity =>
      '오프라인 — 마지막으로 확인된 활동을 표시하는 중입니다.';

  @override
  String get offline_showing_the_last_known_chats =>
      '오프라인 — 마지막으로 확인된 채팅을 표시하는 중입니다';

  @override
  String get offline_showing_the_last_known_projects =>
      '오프라인 — 마지막으로 확인된 프로젝트를 표시합니다.';

  @override
  String get on_this_device => '이 기기';

  @override
  String get on_device => '온디바이스';

  @override
  String get open_inbox => '받은편지함 열기';

  @override
  String open_inbox_2(Object count) {
    return '받은편지함 열기 ($count)';
  }

  @override
  String get open_the_hermes_dashboard => 'Hermes 대시보드 열기';

  @override
  String get optional_for_the_memory_cron_skills_settings_tabs_leave_blank =>
      '선택 사항입니다. 메모리/Cron/스킬/설정 탭에 사용됩니다. 기본 대시보드 포트(9119)를 로그인 없이 사용하려면 비워 두세요.';

  @override
  String get organization => '조직';

  @override
  String get other_answer => '다른 답변';

  @override
  String get overview => '개요';

  @override
  String get passphrase => '패스프레이즈';

  @override
  String get password_optional => '비밀번호 (선택 사항)';

  @override
  String get phone_or_tablet => '휴대전화 또는 태블릿';

  @override
  String get pin_batch_and_undo => '고정, 일괄 처리 및 실행 취소';

  @override
  String get port => '포트';

  @override
  String get preparing_attachments => '첨부 파일 준비 중…';

  @override
  String get preview_truncated => '미리보기가 잘렸습니다';

  @override
  String get preview_unavailable => '미리보기를 사용할 수 없습니다';

  @override
  String get profile => '프로필';

  @override
  String get profile_default_model => '프로필 기본 모델';

  @override
  String profile_default_set_to_chats_with_their_own_model_keep(
    Object selectedModel,
  ) {
    return '프로필 기본값이 $selectedModel(으)로 설정되었습니다. 자체 모델을 사용하는 채팅은 해당 설정을 유지합니다.';
  }

  @override
  String
  get profile_this_connection_chats_as_when_the_dashboard_serves_several =>
      '대시보드가 여러 프로필을 제공할 때 이 연결이 채팅할 프로필입니다. 프로필별로 분리된 대시보드를 사용하려면 비워 두세요.';

  @override
  String get project => '프로젝트';

  @override
  String get project_actions => '프로젝트 작업';

  @override
  String get project_chat => '프로젝트 채팅';

  @override
  String get project_chats_unavailable => '프로젝트 채팅을 사용할 수 없습니다';

  @override
  String get projects => '프로젝트';

  @override
  String get projects_group_related_chats_files_and_activity_and_stay_in =>
      '프로젝트는 관련 채팅, 파일, 활동을 그룹화하며 컴퓨터의 Hermes와 동기화 상태를 유지합니다.';

  @override
  String
  get projects_need_a_desktop_gateway_connection_add_the_desktop_gateway =>
      '프로젝트를 사용하려면 Desktop Gateway 연결이 필요합니다. 기기 간 채팅을 정리하려면 이 연결에 Desktop Gateway URL을 추가하세요.';

  @override
  String get projects_unavailable => '프로젝트를 사용할 수 없습니다';

  @override
  String get projects_activity_new_navigation => '프로젝트, 활동 — 새로운 탐색';

  @override
  String get promote_to_project => '프로젝트로 승격';

  @override
  String get prompt => '프롬프트';

  @override
  String get protect_this_backup => '이 백업 보호하기';

  @override
  String get provider => '제공자';

  @override
  String get proxy_injects_auth_app_sends_clean_requests =>
      '프록시가 인증을 주입하며, 앱은 정리된 요청을 보냅니다';

  @override
  String get quick_chat => '빠른 채팅';

  @override
  String get quick_chats_appear_here_after_their_retention_period =>
      '빠른 채팅은 보관 기간이 지나면 여기에 나타납니다.';

  @override
  String get read_aloud => '소리 내어 읽기';

  @override
  String get read_aloud_is_unavailable_on_this_device =>
      '이 기기에서는 소리 내어 읽기를 사용할 수 없습니다';

  @override
  String get reading_response_aloud => '응답을 소리 내어 읽는 중';

  @override
  String get ready_to_upload => '업로드 준비 완료';

  @override
  String get reasoning => '추론';

  @override
  String get recently_completed => '최근 완료됨';

  @override
  String get recovering_hermes => 'Hermes 복구 중…';

  @override
  String get refresh => '새로고침';

  @override
  String get regenerate_response => '응답 재생성';

  @override
  String get remove_attachment => '첨부 파일 제거';

  @override
  String get rename => '이름 바꾸기';

  @override
  String get rename_chat => '채팅 이름 바꾸기';

  @override
  String get rename_project => '프로젝트 이름 바꾸기';

  @override
  String get rename_space => '스페이스 이름 바꾸기';

  @override
  String rename_2(Object projectName) {
    return '$projectName 이름 바꾸기';
  }

  @override
  String rename_3(Object name) {
    return '$name 이름 바꾸기';
  }

  @override
  String get replace => '바꾸기';

  @override
  String get repositories => '저장소';

  @override
  String
  get research_the_attached_content_verify_the_important_claims_and_cite =>
      '첨부된 콘텐츠를 조사하고, 중요한 주장을 검증한 뒤 출처를 인용하세요.';

  @override
  String research_this_content_verify_the_important_claims_and_cite_sources(
    Object text,
  ) {
    return '이 콘텐츠를 조사하고, 중요한 주장을 검증한 뒤 출처를 인용하세요:\n\n$text';
  }

  @override
  String reset_failed_the_secure_storage_may_need_reinstall(Object retryError) {
    return '재설정 실패: $retryError. 보안 저장소를 재설치해야 할 수도 있습니다.';
  }

  @override
  String get reset_saved_connections => '저장된 연결 재설정';

  @override
  String get responding => '응답 중…';

  @override
  String response_closed_locally_gateway_stop_failed(Object error) {
    return '로컬에서 응답이 종료되었습니다. 게이트웨이 중지 실패: $error';
  }

  @override
  String get response_closed_locally_no_active_gateway_turn_was_found =>
      '로컬에서 응답이 종료되었습니다. 활성 게이트웨이 턴을 찾을 수 없습니다.';

  @override
  String get response_ready => '응답 준비 완료';

  @override
  String get response_stopped => '응답이 중단되었습니다.';

  @override
  String get restore => '복원';

  @override
  String get restore_configuration => '구성 복원';

  @override
  String get restore_project => '프로젝트 복원';

  @override
  String get retry => '재시도';

  @override
  String retry_failed_for_the_draft_and_prompt_were_kept(Object name) {
    return '$name 재시도에 실패했습니다. 초안과 프롬프트는 유지되었습니다.';
  }

  @override
  String get retry_upload => '업로드 재시도';

  @override
  String retrying(Object name) {
    return '$name 재시도 중…';
  }

  @override
  String get review_local_spaces => '로컬 스페이스 검토';

  @override
  String get review_or_promote_quick_chats_past_their_retention_period =>
      '보존 기간이 지난 빠른 채팅을 검토하거나 승격하세요';

  @override
  String get review_the_attached_content => '첨부된 콘텐츠를 검토하세요.';

  @override
  String get run_only_this_command => '이 명령만 실행하세요.';

  @override
  String get running_now => '실행 중';

  @override
  String get save => '저장';

  @override
  String get save_changes => '변경 사항 저장';

  @override
  String get save_a_permanent_rule_in_the_hermes_configuration =>
      'Hermes 구성에 영구 규칙을 저장하세요.';

  @override
  String get save_the_durable_facts_from_the_attached_content_to_memory =>
      '첨부된 콘텐츠에서 지속적인 사실을 메모리에 저장한 다음, 무엇이 보존되었는지 확인하세요.';

  @override
  String save_the_durable_facts_from_this_content_to_memory_then(Object text) {
    return '이 콘텐츠에서 지속적인 사실을 메모리에 저장한 다음, 무엇이 보존되었는지 확인하세요:\n\n$text';
  }

  @override
  String get save_your_connections_and_settings_to_an_encrypted_file_then =>
      '연결 및 설정을 암호화된 파일로 저장한 후, 재설치 시 또는 다른 기기에서 복원하세요.';

  @override
  String save_2(Object filename) {
    return '$filename 저장';
  }

  @override
  String get schedule => '일정';

  @override
  String get scheduled_jobs_and_their_last_runs => '예약된 작업 및 마지막 실행 기록';

  @override
  String get scheduled_tasks => '예약된 작업';

  @override
  String get script_only_no_agent => '스크립트 전용 (에이전트 없음)';

  @override
  String get scroll_horizontally => '가로로 스크롤';

  @override
  String get search_all_chats => '모든 채팅 검색';

  @override
  String get search_all_message_content => '모든 메시지 내용 검색';

  @override
  String get search_chats => '채팅 검색';

  @override
  String get search_conversations => '대화 검색';

  @override
  String get search_loaded_chats => '불러온 채팅 검색';

  @override
  String get search_mode => '검색 모드';

  @override
  String get select_one_option_or_enter_another_answer =>
      '옵션 중 하나를 선택하거나 다른 답변을 입력하세요.';

  @override
  String get select_one_or_more_options_then_continue =>
      '하나 이상의 옵션을 선택한 후 계속하세요.';

  @override
  String get select_text => '텍스트 선택';

  @override
  String get send => '보내기';

  @override
  String send_failed(Object error) {
    return '전송 실패: $error';
  }

  @override
  String get send_message => '메시지 보내기';

  @override
  String get session_sources => '세션 소스';

  @override
  String get session_deleted_from_remote_hermes => '원격 Hermes에서 세션이 삭제되었습니다.';

  @override
  String session_search_failed(Object error) {
    return '세션 검색 실패: $error';
  }

  @override
  String get set_profile_default => '프로필 기본값으로 설정';

  @override
  String get settings => '설정';

  @override
  String get share_to_hermes => 'Hermes에 공유';

  @override
  String get show_passphrase => '패스프레이즈 표시';

  @override
  String get show_tool_calls_thinking_and_message_metadata =>
      '도구 호출, 추론 및 메시지 메타데이터 표시';

  @override
  String get signal_messages => 'Signal 메시지';

  @override
  String get skills => '스킬';

  @override
  String skills_2(Object count) {
    return '스킬 ($count)';
  }

  @override
  String get skills_and_tools => '스킬 및 도구';

  @override
  String get skip => '건너뛰기';

  @override
  String get slack_chats => 'Slack 채팅';

  @override
  String source(Object source) {
    return '소스: $source';
  }

  @override
  String get space_actions => '스페이스 작업';

  @override
  String get spaces => '스페이스';

  @override
  String get speak_to_hermes => 'Hermes에게 말하기';

  @override
  String get speech_recognition_is_unavailable => '음성 인식 기능을 사용할 수 없습니다';

  @override
  String get spoken_replies => '음성 응답';

  @override
  String get spoken_replies_off => '음성 답변 끄기';

  @override
  String get spoken_replies_on => '음성 답변 켜기';

  @override
  String get stalled_no_update_from_hermes => '지연됨 — Hermes에서 업데이트가 없습니다';

  @override
  String get start_something_new => '새로운 작업 시작하기';

  @override
  String get start_voice_input => '음성 입력 시작';

  @override
  String get starting_hermes => 'Hermes 시작 중…';

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
  String get still_loading_your_projects => '프로젝트를 불러오는 중입니다.';

  @override
  String get stop => '중지';

  @override
  String get stop_response => '응답 중지';

  @override
  String get stop_voice_input => '음성 입력 중지';

  @override
  String get submitted_waiting_for_hermes => '전송됨, Hermes 대기 중';

  @override
  String get suggest_projects_and_learn_from_your_corrections =>
      '프로젝트 제안 및 수정 사항 학습';

  @override
  String get summarize_the_attached_content => '첨부된 콘텐츠 요약하기';

  @override
  String summarize_this_content(Object text) {
    return '다음 콘텐츠 요약:\n\n$text';
  }

  @override
  String get switch_profile => '프로필 전환';

  @override
  String get system => '시스템';

  @override
  String get take_photo => '사진 촬영';

  @override
  String get tap_to_add_a_remote_hermes_gateway_api_server_port =>
      '+를 눌러 원격 Hermes 게이트웨이 추가\n(API 서버, 포트 8642)';

  @override
  String get tap_the_button_to_start_a_new_chat => '+ 버튼을 눌러 새 채팅 시작하기';

  @override
  String get telegram_messages => 'Telegram 메시지';

  @override
  String get terminal_sessions => '터미널 세션';

  @override
  String get text_size => '텍스트 크기';

  @override
  String get text_size_preview => '텍스트 크기 미리보기';

  @override
  String text_size_2(Object label) {
    return '텍스트 크기: $label';
  }

  @override
  String get the_api_key_could_not_be_stored_securely =>
      'API 키를 안전하게 저장할 수 없습니다.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files =>
      '프로젝트가 \'보관됨\'으로 이동합니다. 채팅과 파일은 그대로 유지되며 언제든지 복원할 수 있습니다.';

  @override
  String get the_project_will_move_to_archived_its_chats_and_files_2 =>
      '프로젝트가 \'보관됨\'으로 이동합니다. 채팅과 파일은 그대로 유지되며 나중에 복원할 수 있습니다.';

  @override
  String get the_active_profile_did_not_return_any_selectable_models =>
      '활성 프로필에서 선택 가능한 모델을 찾을 수 없습니다.';

  @override
  String get the_backup_could_not_be_exported => '백업을 내보낼 수 없습니다.';

  @override
  String get the_backup_could_not_be_restored => '백업을 복원할 수 없습니다.';

  @override
  String get the_connection_could_not_be_deleted_safely =>
      '연결을 안전하게 삭제할 수 없습니다.';

  @override
  String get the_connection_could_not_be_stored_securely =>
      '연결 정보를 안전하게 저장할 수 없습니다.';

  @override
  String get the_dashboard_credentials_could_not_be_stored_securely =>
      '대시보드 자격 증명을 안전하게 저장할 수 없습니다.';

  @override
  String get the_detached_reply_failed => '분리된 응답에 실패했습니다.';

  @override
  String the_detached_reply_failed_2(Object error) {
    return '분리된 응답에 실패했습니다: $error';
  }

  @override
  String get the_file_contains_your_api_keys_and_dashboard_password_so =>
      '이 파일에는 API 키와 대시보드 비밀번호가 포함되어 있어 암호화되어 있습니다. 이 패스프레이즈 없이는 백업을 복원할 수 없습니다.';

  @override
  String get the_last_turn_failed => '마지막 턴이 실패했습니다';

  @override
  String the_local_connection_store_looks_damaged_you_can_reset_the(
    Object errorType,
  ) {
    return '로컬 연결 저장소가 손상된 것으로 보입니다 ($errorType). 저장된 연결을 초기화하고 새로 시작할 수 있습니다. 게이트웨이의 채팅은 영향을 받지 않습니다.';
  }

  @override
  String get the_model_only_rewrites_your_question_into_a_short_full =>
      '모델이 질문을 짧은 전체 텍스트 쿼리로 다시 작성하기만 합니다. Hermes는 호스트에 이미 구성된 제공자 자격 증명을 사용합니다.';

  @override
  String get the_server_has_not_reported_folders_for_this_project_yet =>
      '서버가 아직 이 프로젝트의 폴더를 보고하지 않았습니다. \'더 보기\'에서 전체 파일을 계속 사용할 수 있습니다.';

  @override
  String get the_turn_failed => '턴이 실패했습니다';

  @override
  String get the_two_passphrases_do_not_match => '두 패스프레이즈가 일치하지 않습니다.';

  @override
  String get the_value_is_sent_directly_to_the_active_hermes_gateway =>
      '이 값은 활성 Hermes 게이트웨이로 직접 전송되며 이 Android 앱에는 저장되지 않습니다.';

  @override
  String get there_are_no_visible_files_in_this_server_folder =>
      '이 서버 폴더에 표시되는 파일이 없습니다.';

  @override
  String get thinking_effort => '추론 수준';

  @override
  String get this_hermes_gateway_does_not_support_opening_a_project_yet =>
      '이 Hermes 게이트웨이는 아직 프로젝트 열기를 지원하지 않습니다. 휴대폰에서 프로젝트를 탐색하려면 서버의 Hermes를 업데이트하세요.';

  @override
  String get this_hermes_gateway_is_older_than_server_side_projects_so =>
      '이 Hermes 게이트웨이는 서버 측 프로젝트보다 구버전이므로 채팅이 이 기기에만 그룹화됩니다. 기기 간에 동일한 프로젝트를 공유하려면 Hermes를 업데이트하세요.';

  @override
  String get this_project_has_no_folder_to_open_the_chat_in =>
      '이 프로젝트에 채팅을 열 폴더가 없습니다. 미할당 상태로 열렸습니다. 채팅을 그룹화하려면 프로젝트에 폴더를 추가하세요.';

  @override
  String get this_chat_has_no_messages_available_in_the_desktop_session =>
      '이 채팅에는 아직 Desktop 세션에서 사용할 수 있는 메시지가 없습니다.';

  @override
  String get this_creates_a_permanent_rule_in_hermes_review_the_full =>
      '이 작업은 Hermes에 영구적인 규칙을 생성합니다. 확인하기 전에 전체 명령을 검토하세요.';

  @override
  String get this_gateway_does_not_host_projects_yet_update_the_gateway =>
      '이 게이트웨이는 아직 프로젝트를 호스팅하지 않습니다. 기기 간에 채팅을 정리하려면 게이트웨이를 업데이트하세요.';

  @override
  String get this_permanently_deletes_the_project_chats_will_not_be_deleted =>
      '이 프로젝트를 영구적으로 삭제합니다. 채팅은 삭제되지 않으며 미할당 상태로 돌아갑니다.';

  @override
  String get this_server_doesn_t_offer_background_recovery_chats_run_live =>
      '이 서버는 백그라운드 복구를 제공하지 않습니다 — 채팅이 실시간으로 실행됩니다';

  @override
  String get this_week => '이번 주';

  @override
  String get titles_previews_and_models => '제목, 미리보기 및 모델';

  @override
  String get tool_activity => '도구 활동';

  @override
  String get trigger_now => '지금 트리거';

  @override
  String get turn_completed => '턴 완료';

  @override
  String get turn_recovery_failed => '턴 복구 실패';

  @override
  String get unable_to_prepare_this_file_try_another_one =>
      '이 파일을 준비할 수 없습니다. 다른 파일을 시도하세요.';

  @override
  String get unable_to_prepare_this_image_try_another_one =>
      '이 이미지를 준비할 수 없습니다. 다른 이미지를 시도하세요.';

  @override
  String unable_to_prepare(Object name) {
    return '$name을(를) 준비할 수 없습니다.';
  }

  @override
  String get unable_to_read_the_selected_image_the_selection_was_kept =>
      '선택한 이미지를 읽을 수 없습니다. 선택 항목은 유지되었습니다.';

  @override
  String get unassigned => '미할당';

  @override
  String get unassigned_chats => '미할당 채팅';

  @override
  String get untitled_chat => '제목 없는 채팅';

  @override
  String get untitled_session => '제목 없는 세션';

  @override
  String get update_api_key => 'API 키 업데이트';

  @override
  String get upload_failed => '업로드 실패';

  @override
  String get upload_failed_tap_retry => '업로드 실패 • 탭하여 재시도';

  @override
  String uploading(Object index, Object name, Object total) {
    return '업로드 중 $index/$total: $name';
  }

  @override
  String get use_as_is => '있는 그대로 사용';

  @override
  String get use_at_least_8_characters => '8자 이상 사용하세요.';

  @override
  String get use_for_cron_jobs_backed_by_scripts => '스크립트 기반 Cron 작업에 사용하세요.';

  @override
  String get use_on_device => '기기 내 사용';

  @override
  String get use_the_attached_content_to_identify_and_fill_the_relevant =>
      '첨부된 콘텐츠를 사용하여 관련 문서 또는 양식 필드를 식별하고 채우세요. 제출하기 전에 확인하세요.';

  @override
  String use_this_content_to_identify_and_fill_the_relevant_document(
    Object text,
  ) {
    return '이 콘텐츠를 사용하여 관련 문서 또는 양식 필드를 식별하고 채우세요. 제출하기 전에 확인하세요:\n\n$text';
  }

  @override
  String get used_for_hosted_path_prefixes_and_for_the_settings_memory =>
      '호스팅된 경로 접두사와 설정, 메모리, 스킬 및 Cron 탭에 사용됩니다. 대시보드를 공개하려면 사용자 이름/비밀번호를 비워두거나, 리버스 프록시가 대시보드 인증을 주입할 때 프록시 모드를 활성화하세요.';

  @override
  String get username_optional => '사용자 이름 (선택 사항)';

  @override
  String using(Object displayName) {
    return '$displayName 사용 중…';
  }

  @override
  String get verbose_mode => '상세 모드';

  @override
  String get voice => '음성';

  @override
  String voice_setup_failed(Object error) {
    return '음성 설정 실패: $error';
  }

  @override
  String get waiting_for_your_input => '입력을 기다리는 중';

  @override
  String get what_hermes_knows_how_to_do => 'Hermes가 할 수 있는 작업';

  @override
  String get what_should_the_agent_do => '에이전트가 무엇을 해야 하나요?';

  @override
  String get whatsapp_messages => 'WhatsApp 메시지';

  @override
  String get which_project => '어떤 프로젝트인가요?';

  @override
  String get workspace => '워크스페이스';

  @override
  String get wrap_lines => '줄 바꿈';

  @override
  String you_can_attach_up_to_items(Object maxRemoteAttachmentDrafts) {
    return '최대 $maxRemoteAttachmentDrafts개까지 첨부할 수 있습니다.';
  }

  @override
  String get your_answer => '답변';

  @override
  String get e_g_dashboard => '예: /dashboard';

  @override
  String get e_g_dashboard_proxy_path_before_api =>
      '예: /dashboard (/api/ 이전의 프록시 경로)';

  @override
  String get e_g_profile_peter => '예: /profile/peter';

  @override
  String get e_g_sol => '예: sol';

  @override
  String get e_g_0_9_or_every_2h => '예: 0 9 * * * 또는 every 2h';

  @override
  String get e_g_daily_backup => '예: 일일 백업';

  @override
  String downloaded(Object filename) {
    return '$filename 다운로드 완료';
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
      '192.168.1.50, 100.x.y.z 또는 hermes-machine.tailnet.ts.net';

  @override
  String get example_profile_prefix_hint_full =>
      '예: /profile/peter (/api/ 및 /v1/ 이전의 프록시 경로)';

  @override
  String and_more(Object count) {
    return '외 $count개';
  }

  @override
  String chats_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '채팅 $count개',
    );
    return '$_temp0';
  }

  @override
  String on_this_device_only(Object chats) {
    return '$chats · 이 기기에서만';
  }

  @override
  String spaces_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '스페이스 $count개',
    );
    return '$_temp0';
  }

  @override
  String get no_new_projects_needed => '새 프로젝트 불필요';

  @override
  String projects_to_create(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '생성할 프로젝트 $count개',
    );
    return '$_temp0';
  }

  @override
  String chats_migrated_projects_created(
    Object createdProjects,
    Object linkedSessions,
  ) {
    return '채팅 $linkedSessions개 마이그레이션됨 · 프로젝트 $createdProjects개 생성됨';
  }

  @override
  String chats_stayed_in_local_spaces(Object unlinkedSessions) {
    return '채팅 $unlinkedSessions개가 로컬 스페이스에 유지되었으며 안전하게 재시도할 수 있습니다.';
  }

  @override
  String model_recommended(Object provider) {
    return '$provider • 추천: 작고 저렴함';
  }

  @override
  String session_meta(Object count, Object model, Object time) {
    return '메시지 $count개 • $model • $time';
  }

  @override
  String model_scope_label(Object model, Object scope) {
    return '$model • $scope';
  }

  @override
  String get this_chat => '현재 채팅';

  @override
  String get profile_default => '프로필 기본값';

  @override
  String minutes_ago(Object count) {
    return '$count분 전';
  }

  @override
  String hours_ago(Object count) {
    return '$count시간 전';
  }

  @override
  String days_ago(Object count) {
    return '$count일 전';
  }

  @override
  String get now_label => '지금';

  @override
  String get latest_label => '최신';

  @override
  String new_count_indicator(Object count) {
    return '새 항목 $count개';
  }

  @override
  String new_messages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '새 메시지 $count개',
    );
    return '$_temp0';
  }

  @override
  String activity_failed_summary(Object failures, Object total) {
    return '$failures개 실패 • 총 $total개';
  }

  @override
  String activity_completed_summary(Object count) {
    return '$count개 완료';
  }

  @override
  String get hermes_is_using_a_tool => 'Hermes가 도구를 사용 중입니다';

  @override
  String hermes_is_using_tools(Object count) {
    return 'Hermes가 $count개의 도구를 사용 중입니다';
  }

  @override
  String delegated_tasks_completed(Object count) {
    return '위임된 작업 $count개 완료';
  }

  @override
  String delegated_tasks_active(Object count) {
    return '위임된 작업 $count개 진행 중';
  }

  @override
  String branch_main(Object label) {
    return '$label · main';
  }

  @override
  String get you_heading => '## 사용자';

  @override
  String get hermes_heading => '## Hermes';

  @override
  String get action_label => '작업';

  @override
  String get destination_label => '대상';

  @override
  String get preview_label => '미리보기';

  @override
  String get share_action_summarize => '요약';

  @override
  String get share_action_explain => '설명';

  @override
  String get share_action_research => '조사';

  @override
  String get share_action_remember => '기억';

  @override
  String get text_size_small => '작게';

  @override
  String get text_size_default => '기본';

  @override
  String get text_size_large => '크게';

  @override
  String get text_size_extra_large => '아주 크게';

  @override
  String get text_size_use_system_description =>
      'Android 접근성 텍스트 크기를 그대로 사용합니다.';

  @override
  String text_size_percent_description(Object percent) {
    return 'Android 텍스트 크기의 $percent%.';
  }

  @override
  String text_size_label_description(Object description, Object label) {
    return '$label — $description';
  }

  @override
  String files_skipped(Object count) {
    return '파일 $count개를 건너뛰었습니다: 제한 초과, 크기, 읽을 수 없음 또는 민감한 파일명.';
  }

  @override
  String model_scope_applied(Object effort, Object model) {
    return '$model • $effort 이 채팅에만 적용됩니다.';
  }

  @override
  String get reasoning_minimal => '최소';

  @override
  String get reasoning_low => '낮음';

  @override
  String get reasoning_medium => '보통';

  @override
  String get reasoning_high => '높음';

  @override
  String get reasoning_max => '최대';

  @override
  String get reasoning_ultra => '울트라';

  @override
  String get status_running => '실행 중';

  @override
  String get status_failed => '실패';

  @override
  String get status_done => '완료';

  @override
  String get status_idle => '대기 중';

  @override
  String get upload_status_uploading => '업로드 중';

  @override
  String get upload_status_uploaded => '업로드 완료';

  @override
  String attachment_count(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '첨부 파일 $count개',
    );
    return '$_temp0';
  }

  @override
  String get action_create => '생성';

  @override
  String get action_rename => '이름 변경';

  @override
  String get action_archive => '보관';

  @override
  String get action_restore => '복원';

  @override
  String get action_delete => '삭제';

  @override
  String get migrate => '마이그레이션';

  @override
  String assigned_chats(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '할당된 채팅 $count개',
    );
    return '$_temp0';
  }

  @override
  String get date_today => '오늘';

  @override
  String get date_yesterday => '어제';

  @override
  String get date_earlier => '이전';

  @override
  String get nav_home => '홈';

  @override
  String get nav_more => '더 보기';

  @override
  String get status_completed => '완료됨';

  @override
  String get filter_all => '전체';

  @override
  String get filter_recent => '최근';

  @override
  String connection_address_key(Object address, Object status) {
    return '$address  •  키: $status';
  }

  @override
  String model_via_provider(Object model, Object provider) {
    return '$model  \n`$provider` 경유';
  }

  @override
  String get deny => '거부';

  @override
  String get connect => '연결';

  @override
  String get appearance => '모양';

  @override
  String get connection_section => '연결';

  @override
  String get about => '정보';

  @override
  String version_label(Object version) {
    return '버전 $version';
  }

  @override
  String get matched => '일치함';

  @override
  String get search => '검색';

  @override
  String get on => '켜짐';

  @override
  String get off => '꺼짐';

  @override
  String get reasoning_off => '꺼짐';

  @override
  String get hermes_response_ready => 'Hermes 응답 준비 완료';

  @override
  String get admin_password_needed => '관리자 비밀번호 필요';

  @override
  String get hermes_needs_a_sudo_password_for_the_pending_terminal_command =>
      '대기 중인 터미널 명령을 실행하려면 Hermes에 sudo 비밀번호가 필요합니다.';

  @override
  String get sudo_password => 'sudo 비밀번호';

  @override
  String get secret_needed => '시크릿 필요';

  @override
  String get hermes_needs_a_secret_for_the_pending_skill =>
      'Hermes가 보류 중인 스킬을 위해 시크릿이 필요합니다.';

  @override
  String get secret_value => '시크릿 값';

  @override
  String get attached_file => '첨부 파일';
}
