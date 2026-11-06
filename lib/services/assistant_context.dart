import 'dart:convert';

/// Preserve older user facts without resending long assistant answers.
List<String> assistantEarlierMessages(
    List<Map<String, String>> messages, List<Map<String, String>> recent) {
  final earlier = <String>[];
  for (final message in messages.take(messages.length - recent.length)) {
    if (message['role'] != 'user') continue;
    final content = message['content']!;
    if (content.length > 2000 ||
        earlier.length == 40 ||
        jsonEncode([...earlier, content]).length > 8000) {
      break;
    }
    earlier.add(content);
  }
  return earlier;
}

/// Keep complete recent turns within the Edge Function's JSON size limit.
/// The full conversation remains in local history.
List<Map<String, String>> assistantContext(List<Map<String, String>> messages,
    {bool webSearch = false}) {
  final result = <Map<String, String>>[];
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    // A request must begin with a user turn and end with the current question.
    final candidate = [Map<String, String>.from(message), ...result];
    if (candidate.length > 12 ||
        message['content']!.length > 6000 ||
        jsonEncode({'messages': candidate, 'web_search': webSearch}).length >
            29000) {
      break;
    }
    result.insert(0, candidate.first);
  }
  while (result.isNotEmpty && result.first['role'] != 'user') {
    result.removeAt(0);
  }
  return result;
}
