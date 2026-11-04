import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/services/assistant_error.dart';

void main() {
  test('Groq errors and search capability have actionable explanations', () {
    expect(assistantErrorMessage(const FunctionException(status: 429,
        details: {'error': 'Groq rate limit reached'})), contains('dùng chung'));
    expect(assistantErrorMessage(const FunctionException(status: 503,
        details: {'error': 'Groq key rejected'})), contains('quyền truy cập'));
    expect(assistantErrorMessage(const FunctionException(status: 503,
        details: {'error': 'Web search unavailable'})), contains('tắt Tra cứu web'));
  });
  test('app quota and shared provider quota have different explanations', () {
    expect(assistantErrorMessage(const FunctionException(status: 429,
        details: {'error': 'Daily limit reached'})), contains('30 lượt'));
    expect(assistantErrorMessage(const FunctionException(status: 429,
        details: {'error': 'Gemini rate limit reached'})), contains('dùng chung'));
  });
  test('model, credentials and missing configuration remain distinguishable', () {
    expect(assistantErrorMessage(const FunctionException(status: 503,
        details: {'error': 'Gemini model unavailable'})), contains('Model Gemini'));
    expect(assistantErrorMessage(const FunctionException(status: 503,
        details: {'error': 'Gemini key rejected'})), contains('quyền truy cập'));
    expect(assistantErrorMessage(const FunctionException(status: 503,
        details: {'error': 'Assistant not configured'})), contains('chưa được cấu hình'));
  });
  test('gateway errors and non-JSON bodies never expose raw details', () {
    for (final details in [
      {'error': 'PRIVATE_KEY', 'message': 'PRIVATE_KEY'},
      'PRIVATE_KEY', null,
    ]) {
      final message = assistantErrorMessage(FunctionException(status: 401, details: details));
      expect(message, contains('401'));
      expect(message, isNot(contains('PRIVATE_KEY')));
    }
    expect(assistantErrorMessage(const FunctionException(status: 404)), contains('404'));
  });
  test('timeouts and network errors have a safe explanation', () {
    expect(assistantErrorMessage(TimeoutException('private')), contains('quá lâu'));
    expect(assistantErrorMessage(StateError('private')), isNot(contains('private')));
  });
}
