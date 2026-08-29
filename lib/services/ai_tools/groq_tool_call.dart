/// Wire-shape structures for OpenAI-compatible tool calling on Groq.
///
/// The router and the tool executor both speak this vocabulary — the
/// router parses `delta.tool_calls` from the SSE stream and hands a
/// [List<GroqToolCall]> back to `AiChatService`, which then feeds it
/// to `tool_executor.dart`.
///
/// Fields are `String?` / `dynamic` because the Groq wire format
/// dribbles each `function.arguments` JSON chunk across many frames;
/// the executor waits until the final assembled `arguments` string
/// is non-empty before parsing.
library;

class GroqToolCall {
  GroqToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  /// Server-side id, e.g. "call_xyz123". Echoed back as
  /// `tool_call_id` on the corresponding tool-result message.
  final String id;

  /// Function name, e.g. "create_medicine". Matches the
  /// `function.name` field of the matching [AiTool] in the registry.
  final String name;

  /// Raw JSON string for the function arguments, exactly as the model
  /// emitted it (NOT yet parsed). Empty string while the stream is
  /// still dribbling fragments.
  final String argumentsJson;

  Map<String, dynamic> toWireMap() => {
        'id': id,
        'type': 'function',
        'function': {
          'name': name,
          'arguments': argumentsJson,
        },
      };

  GroqToolCall copyWith({String? argumentsJson}) => GroqToolCall(
        id: id,
        name: name,
        argumentsJson: argumentsJson ?? this.argumentsJson,
      );
}