# Trợ lý tư vấn bằng Groq Free Plan

Trợ lý hiện dùng `openai/gpt-oss-120b` do Groq phục vụ. Dù model ID có chữ
`openai`, key cần tạo trên Groq, không phải OpenAI. Không cần credit OpenAI/Gemini.
Nhập ảnh/PDF vẫn là chức năng riêng dùng OpenAI; đổi trợ lý không làm chức năng
đó trở thành miễn phí. File SQL chính vẫn là `../supabase_database.sql`;
thay nhà cung cấp không thay schema hay quota 30 lượt/người/ngày.

## 1. Kiểm tra tài khoản miễn phí trước

1. Đăng ký/đăng nhập https://console.groq.com/.
2. Kiểm tra tài khoản ở Free Plan; chưa nâng cấp Developer nếu muốn thử miễn phí.
3. Vào API Keys: https://console.groq.com/keys, chọn Create API Key, đặt tên và
   sao chép key. Không gửi key vào chat hay lưu trong Flutter/SQL/Git.
4. Mở Limits của tài khoản để kiểm tra model `openai/gpt-oss-120b` có quyền dùng.
   Tài liệu hiện liệt kê Free Plan: 30 yêu cầu/phút, 1.000 yêu cầu/ngày,
   8.000 token/phút, 200.000 token/ngày. Đây là hạn mức dùng chung theo tổ chức;
   Limits của tài khoản mới là giá trị thực tế, không bảo đảm mọi tài khoản giống nhau.
5. Từ terminal tại thư mục gốc, chạy trước khi đặt key lên Supabase:

```powershell
.\backend\check-groq.ps1 -FromClipboard
```

Chờ lời nhắc, sang Groq sao chép key đầy đủ, quay lại terminal và chỉ nhấn Enter,
không dán key vào ô lời nhắc. Công cụ không in/lưu key. Nó gửi một câu thử ngắn,
tốn một lượt Groq, không trừ quota app. HTTP 200 chỉ xác nhận yêu cầu trực tiếp
được chấp nhận từ máy này, chưa chứng minh cấu hình Supabase hoặc chất lượng câu trả lời.
Nếu bị từ chối, gửi HTTP và thông báo đã che key; chưa cấu hình tiếp Supabase.
Nếu bạn dán key trực tiếp vào ô ẩn ở chế độ FromClipboard, công cụ cũng nhận
giá trị đó. Nếu ô ẩn chỉ nhận một ký tự thì dùng clipboard. Công cụ phát hiện
trường hợp copy nhầm dòng lệnh và báo riêng lỗi khoảng trắng bên trong key;
không tự xóa khoảng trắng để biến một nội dung không phải key thành yêu cầu API.

## 2. Secrets và triển khai

Supabase Dashboard → đúng project của app → Edge Functions → Secrets:

| Name | Value |
| --- | --- |
| GROQ_API_KEY | Key từ Groq |
| GROQ_MODEL | openai/gpt-oss-120b |

Có thể đổi model thành `openai/gpt-oss-20b` nếu tài khoản cho dùng; backend giới
hạn vào hai model GPT-OSS này để giữ đúng khả năng reasoning/browser search.
Các secret Gemini cũ không còn được trợ lý đọc. Thu hồi key Gemini từng bị lộ.

Mở Edge Functions → study-assistant → Code, thay toàn bộ index.ts bằng file
`functions/study-assistant/index.ts` rồi Deploy. Cấu hình gateway của dự án dùng
Verify JWT tắt; trong mã vẫn bắt buộc Bearer token, auth.getUser() và account_is_active().

Hoặc với Node.js đã cài, từ thư mục gốc:

```powershell
npx supabase login
.\backend\deploy.ps1 -ProjectRef MA_PROJECT_CUA_BAN -Functions study-assistant
```

Thay MA_PROJECT_CUA_BAN bằng project ref trong URL Dashboard. Rebuild/chạy lại
Flutter để thông báo đồng ý ghi đúng Groq, đọc thông báo trước khi gửi dữ liệu.

## 3. Tư vấn và thu thập thông tin

Tư vấn thông thường không bật công cụ ngoài, dùng model trong hạn mức Free Plan.
Trợ lý được chỉ dẫn hỏi khi thiếu dữ kiện, phân biệt suy luận/đề xuất, không bịa
nguồn hoặc quy định và không giả vờ đã đọc lịch cá nhân. Hãy đánh giá bằng câu hỏi
thật; không model nào được bảo đảm trả lời chính xác tuyệt đối.

Nút "Tra cứu web" là lựa chọn riêng trên app. Backend mặc định chặn tra cứu web
để tránh tự bật công cụ có chi phí/quyền chưa được xác nhận. Groq hỗ trợ
browser_search cho GPT-OSS, do Exa cung cấp; tài liệu công cụ chưa xác nhận mọi
tài khoản Free Plan đều được sử dụng miễn phí. Trước khi bật, kiểm tra quyền,
giá và Usage của chính tài khoản. Không quảng bá tính năng này là miễn phí vô hạn.

Sau khi đã kiểm tra điều kiện, thêm secret `GROQ_ENABLE_SEARCH=true`. Người dùng
cũng phải chọn "Tra cứu web"; backend mới gửi browser_search với tool_choice=required.
Nếu chưa bật secret, app báo rõ và có thể tắt lựa chọn để tiếp tục tư vấn. Không
tự rơi về câu trả lời không tra cứu khi người dùng đã yêu cầu kiểm chứng trên web.
Kết quả tra cứu vẫn cần kiểm tra nguồn, ngày và mức phù hợp; model có thể trích dẫn sai.

Hội thoại trước đó được gửi để giữ ngữ cảnh. Khi bật tra cứu, dịch vụ có thể dùng
ngữ cảnh đó tạo truy vấn gửi tới Exa. Không gửi dữ liệu nhạy cảm. Trợ lý vẫn chưa
có quyền đọc/sửa bảng lịch hay tài khoản, không có công cụ thực thi mã.

## 4. Xử lý lỗi

| Thông báo | Cần kiểm tra |
| --- | --- |
| Assistant not configured | Hai secrets, tên model và project Supabase |
| Groq key rejected | Key bị thu hồi, sai hoặc tài khoản chưa được cấp quyền |
| Groq model unavailable | Tên model và quyền của tổ chức |
| Groq rate limit reached | Limits, độ dài hội thoại, chờ theo hạn mức; không gửi liên tục |
| Groq request rejected | Quyền dùng browser_search, định dạng/tham số và model |
| Web search unavailable | Chưa bật điều kiện máy chủ cho tra cứu; có thể tắt nút để tư vấn |
| Daily limit reached | 30 lượt/ngày của app, đổi ngày lúc 07:00 Việt Nam |
| Groq response unavailable | Nội dung bị chặn hoặc bị cắt; thử câu hỏi ngắn hơn |

Logs có `groq_request_failed` và provider_http_status. Không log key, dữ liệu
hội thoại hay phản hồi lỗi thô từ nhà cung cấp. Quota app được lấy trước khi gọi
Groq; lỗi nhà cung cấp vẫn tính lượt. Cần bảng assistant_daily_usage và các RPC
consume_assistant_request/account_is_active trong SQL chính.

## Kiểm thử cục bộ

```powershell
node --test backend/tests/study_assistant_groq.test.mjs
.\backend\tests\check_groq_parser_test.ps1
flutter test test/assistant_overlay_test.dart test/services/assistant_error_test.dart
```

Các kiểm thử trên dùng dữ liệu giả, không gọi Groq thật. Chưa có key Groq và chưa
triển khai Supabase trong phiên chuyển đổi này. Bước kiểm tra trực tiếp ở mục 1
cần chạy bằng tài khoản của người vận hành.

Tài liệu chính thức:
- https://console.groq.com/docs/models
- https://console.groq.com/docs/rate-limits
- https://console.groq.com/docs/tool-use/built-in-tools/browser-search
- https://console.groq.com/docs/your-data
