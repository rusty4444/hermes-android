enum GatewayApprovalChoice {
  once('once'),
  session('session'),
  always('always'),
  deny('deny');

  final String wireValue;

  const GatewayApprovalChoice(this.wireValue);

  static GatewayApprovalChoice? fromWireValue(String value) {
    for (final choice in values) {
      if (choice.wireValue == value) return choice;
    }
    return null;
  }
}

/// A command approval emitted by the Hermes Desktop gateway.
///
/// The backend is authoritative about the available scopes. Android also
/// removes unsafe combinations defensively so a malformed event cannot expose
/// a permanent approval when Hermes says it is unavailable.
class GatewayApprovalRequest {
  final String command;
  final String description;
  final bool allowPermanent;
  final bool smartDenied;
  final List<GatewayApprovalChoice> choices;
  final String? runId;
  final String? requestId;
  // Preserve malformed generation values too: they must fail closed, not
  // silently downgrade to the legacy approval contract.
  final Object? executionGeneration;
  final bool canonicalControl;

  const GatewayApprovalRequest({
    required this.command,
    required this.description,
    required this.allowPermanent,
    required this.smartDenied,
    required this.choices,
    this.runId,
    this.requestId,
    this.executionGeneration,
    this.canonicalControl = false,
  });

  factory GatewayApprovalRequest.fromEventData(Map<String, dynamic> data) {
    final smartDenied = data['smart_denied'] == true;
    final allowPermanent = data['allow_permanent'] != false && !smartDenied;
    final rawChoices = data['choices'];
    final parsedChoices = <GatewayApprovalChoice>[];

    if (rawChoices is List) {
      for (final rawChoice in rawChoices) {
        final choice = GatewayApprovalChoice.fromWireValue(
          rawChoice.toString(),
        );
        if (choice != null && !parsedChoices.contains(choice)) {
          parsedChoices.add(choice);
        }
      }
    }

    final choices = parsedChoices.isEmpty
        ? smartDenied
              ? <GatewayApprovalChoice>[
                  GatewayApprovalChoice.once,
                  GatewayApprovalChoice.deny,
                ]
              : allowPermanent
              ? <GatewayApprovalChoice>[
                  GatewayApprovalChoice.once,
                  GatewayApprovalChoice.session,
                  GatewayApprovalChoice.always,
                  GatewayApprovalChoice.deny,
                ]
              : <GatewayApprovalChoice>[
                  GatewayApprovalChoice.once,
                  GatewayApprovalChoice.session,
                  GatewayApprovalChoice.deny,
                ]
        : parsedChoices.where((choice) {
            if (smartDenied) {
              return choice == GatewayApprovalChoice.once ||
                  choice == GatewayApprovalChoice.deny;
            }
            if (!allowPermanent && choice == GatewayApprovalChoice.always) {
              return false;
            }
            return true;
          }).toList();

    if (!choices.contains(GatewayApprovalChoice.deny)) {
      choices.add(GatewayApprovalChoice.deny);
    }

    return GatewayApprovalRequest(
      command: data['command']?.toString().trim() ?? '',
      description:
          data['description']?.toString().trim() ??
          data['reason']?.toString().trim() ??
          'Hermes wants to run a command.',
      allowPermanent: allowPermanent,
      smartDenied: smartDenied,
      choices: List.unmodifiable(choices),
      runId:
          data['run_id']?.toString() ??
          data['_run_event']?['run_id']?.toString(),
      // A present canonical identity must be a string. Do not crash ingress,
      // stringify malformed IDs, or substitute an unrelated legacy identity.
      requestId: data.containsKey('prompt_id')
          ? (data['prompt_id'] is String ? data['prompt_id'] as String : null)
          : data['request_id']?.toString() ??
                data['server_request_id']?.toString(),
      executionGeneration: data['execution_generation'],
      canonicalControl:
          data.containsKey('prompt_id') ||
          data.containsKey('execution_generation'),
    );
  }
}
