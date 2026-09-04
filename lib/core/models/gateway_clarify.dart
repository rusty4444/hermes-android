/// A request-ID keyed clarification prompt emitted by Hermes.
///
/// Stock Hermes gateways emit clarification prompts in two wire shapes:
///
/// * Flat (single question, legacy):
///   `{"request_id": ..., "question": ..., "choices": [...], "multi_select": ...}`
/// * Batch (current Hermes agent builds, even for a single question):
///   `{"request_id": ..., "questions": [{"qid": ..., "question": ..., "choices": [...], "multi_select": ...}]}`
///
/// Batch responses must echo the per-question `qid` back as `question_id` so
/// the gateway can lock each answer independently.
class GatewayClarifyRequest {
  final String requestId;

  /// The per-question id inside a batch `questions[]` payload. Null for the
  /// flat single-question shape.
  final String? questionId;
  final String question;
  final List<String> choices;
  final bool multiSelect;

  const GatewayClarifyRequest({
    required this.requestId,
    required this.question,
    required this.choices,
    required this.multiSelect,
    this.questionId,
  });

  bool get hasChoices => choices.isNotEmpty;

  /// Parses a `clarify.request` event payload into zero or more prompts.
  ///
  /// Batch payloads expand to one prompt per question (each carrying its own
  /// `questionId`); flat payloads expand to a single prompt with no
  /// `questionId`. Questions missing a usable `qid` in a batch are dropped,
  /// since the gateway cannot correlate an answer without one.
  static List<GatewayClarifyRequest> fromEventDataList(
    Map<String, dynamic> data,
  ) {
    final requestId = data['request_id']?.toString().trim() ?? '';
    if (requestId.isEmpty) return const [];

    final rawQuestions = data['questions'];
    if (rawQuestions is List) {
      final requests = <GatewayClarifyRequest>[];
      for (final rawQuestion in rawQuestions) {
        if (rawQuestion is! Map) continue;
        final qid = rawQuestion['qid']?.toString().trim() ?? '';
        if (qid.isEmpty) continue;
        final choices = _normalizeChoices(rawQuestion['choices']);
        requests.add(
          GatewayClarifyRequest(
            requestId: requestId,
            questionId: qid,
            question: _normalizeQuestion(
              rawQuestion['question']?.toString(),
            ),
            choices: choices,
            multiSelect:
                rawQuestion['multi_select'] == true && choices.isNotEmpty,
          ),
        );
      }
      return requests;
    }

    final flat = fromEventData(data);
    return flat == null ? const [] : [flat];
  }

  /// Parses the legacy flat single-question payload.
  static GatewayClarifyRequest? fromEventData(Map<String, dynamic> data) {
    final requestId = data['request_id']?.toString().trim() ?? '';
    if (requestId.isEmpty) return null;

    final choices = _normalizeChoices(data['choices']);
    final question = _normalizeQuestion(data['question']?.toString());

    return GatewayClarifyRequest(
      requestId: requestId,
      question: question.isEmpty
          ? 'Hermes needs more information to continue.'
          : question,
      choices: choices,
      multiSelect: data['multi_select'] == true && choices.isNotEmpty,
    );
  }

  static List<String> _normalizeChoices(Object? rawChoices) {
    if (rawChoices is! List) return const <String>[];
    return rawChoices
        .whereType<String>()
        .where(
          (choice) =>
              choice.trim().isNotEmpty &&
              choice.length <= 200 &&
              !choice.contains('\n') &&
              !choice.contains('\r'),
        )
        .toList(growable: false);
  }

  static String _normalizeQuestion(String? rawQuestion) =>
      rawQuestion?.trim() ?? '';

  /// Identity key for queue de-duplication: two prompts are the same prompt
  /// only when both the gateway request id and the per-question id agree.
  String get identityKey => questionId == null
      ? requestId
      : '$requestId::$questionId';
}
