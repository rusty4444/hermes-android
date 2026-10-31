import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/notification_approval_authority.dart';

/// A: explicit origin plumbing for synthetic route/service fixtures. Production
/// root tests use the real manager's physical credential refresh instead.
NotificationApprovalAuthority fixtureApprovalAuthority(
  SavedConnection connection,
) {
  final origin = NotificationApprovalAuthority.origin(connection);
  return NotificationApprovalAuthority.capture(
    connection: connection,
    accountBinding: origin['approvalAccount'],
    originMutation: origin['approvalMutation'],
    owner: connection,
    ownerIsCurrent: () => true,
    refresh: () async => true,
  )!;
}

SavedConnection fixtureApprovalConnection(String id) => SavedConnection(
  id: id,
  label: id,
  host: 'approval.fixture',
  port: 1,
  apiKey: 'fixture',
);
