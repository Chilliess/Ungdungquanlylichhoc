import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Only show known messages; never display raw server/provider error bodies.
String assistantErrorMessage(Object error) {
  if (error is TimeoutException) {
    return 'Trợ lý phản hồi quá lâu. Vui lòng thử lại sau.';
  }
  if (error is FunctionException) {
    final details = error.details;
    final code = details is Map ? details['error'] : null;
    const messages = {
      'Assistant not configured': 'Trợ lý chưa được cấu hình trên máy chủ.',
      'Assistant quota not configured': 'Máy chủ chưa sẵn sàng kiểm tra lượt dùng trợ lý.',
      'Account check unavailable': 'Chưa kiểm tra được trạng thái tài khoản. Vui lòng thử lại sau.',
      'Account unavailable': 'Tài khoản hiện chưa được phép sử dụng trợ lý.',
      'Daily limit reached': 'Bạn đã dùng hết 30 lượt hôm nay. Lượt mới bắt đầu lúc 07:00 ngày mai.',
      'Gemini rate limit reached': 'Dịch vụ Gemini đã đạt hạn mức dùng chung. Vui lòng thử lại sau.',
      'Gemini configuration unavailable': 'Gemini từ chối cấu hình kết nối trên máy chủ.',
      'Gemini model unavailable': 'Model Gemini đã cấu hình không khả dụng.',
      'Gemini key rejected': 'Gemini từ chối khóa API hoặc quyền truy cập của máy chủ.',
      'Gemini request rejected': 'Gemini không chấp nhận yêu cầu từ máy chủ.',
      'Gemini response unavailable': 'Gemini chưa trả được câu trả lời hoàn chỉnh. Hãy thử diễn đạt lại.',
      'Empty response': 'Trợ lý trả về câu trả lời trống. Vui lòng thử lại sau.',
      'Groq rate limit reached': 'Dịch vụ Groq đã đạt hạn mức dùng chung. Vui lòng thử lại sau.',
      'Groq model unavailable': 'Model Groq đã cấu hình không khả dụng.',
      'Groq key rejected': 'Groq từ chối khóa API hoặc quyền truy cập của máy chủ.',
      'Groq request rejected': 'Groq không chấp nhận yêu cầu. Hãy kiểm tra model và quyền tra cứu web.',
      'Groq response unavailable': 'Groq chưa trả được câu trả lời hoàn chỉnh. Hãy thử rút ngắn câu hỏi.',
      'Web search unavailable': 'Tra cứu web chưa được bật trên máy chủ. Bạn có thể tắt Tra cứu web để tiếp tục tư vấn.',
      'Invalid messages': 'Tin nhắn không hợp lệ hoặc quá dài. Hãy rút ngắn nội dung.',
      'Request too large': 'Nội dung quá dài. Hãy rút ngắn tin nhắn.',
    };
    if (messages.containsKey(code)) return messages[code]!;
    switch (error.status) {
      case 401:
        return 'Phiên đăng nhập hoặc xác thực trợ lý không hợp lệ (401). Hãy đăng nhập lại.';
      case 404:
        return 'Chưa tìm thấy dịch vụ trợ lý trên máy chủ (404).';
      case 429:
        return 'Dịch vụ trợ lý đang giới hạn lượt dùng (429). Vui lòng thử lại sau.';
      default:
        return 'Dịch vụ trợ lý gặp lỗi (${error.status}). Vui lòng thử lại sau.';
    }
  }
  return 'Chưa kết nối được trợ lý. Kiểm tra mạng hoặc cấu hình dịch vụ AI rồi thử lại.';
}
