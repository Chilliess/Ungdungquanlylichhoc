> Tài liệu cũ: trợ lý đã chuyển sang Groq. Dùng [GROQ_SETUP.md](GROQ_SETUP.md).

# Thử trợ lý tư vấn với Google Gemini

Trợ lý `study-assistant` hiện gọi Gemini. Chức năng `import-timetable` vẫn dùng
OpenAI và cấu hình riêng. Không thay đổi schema; `supabase_database.sql` vẫn là
file SQL chính và đã có bảng/hàm quota dùng chung.

## 1. Tạo key

Mở https://aistudio.google.com/apikey, đăng nhập Google, chấp nhận điều khoản,
chọn Create API key và chọn/tạo project. Sao chép key để nhập vào Supabase.
Để thử miễn phí, dùng project Free tier và model có quota miễn phí trong tài
khoản. Không chọn Set up billing/Upgrade nếu chưa muốn chuyển sang trả phí.
Không gửi key vào chat, Flutter, SQL hoặc Git.

Tại thời điểm đối chiếu tài liệu, `gemini-3.8-flash` có giá input/output miễn phí
ở Free tier. Kiểm tra lại quyền truy cập và hạn mức của chính project trong AI
Studio; không phải mọi model đều có gói miễn phí và quota có thể thay đổi.

## 2. Đặt Secrets trên Supabase

Mở project ứng dụng ở https://supabase.com/dashboard.
Vào Edge Functions → Secrets, thêm và lưu:

| Name | Value |
| --- | --- |
| GEMINI_API_KEY | Key tạo ở bước 1 |
| GEMINI_MODEL | gemini-3.8-flash, hoặc ID model hỗ trợ generateContent mà project có quyền dùng |

Không thêm dấu nháy hoặc tiền tố `models/` vào GEMINI_MODEL. Trợ lý yêu cầu
cả hai secret; không tự rơi về OpenAI. Các biến SUPABASE_URL/SUPABASE_ANON_KEY
được môi trường Supabase cung cấp sẵn.

## 3. Kiểm tra database

Chạy trong SQL Editor:

```sql
SELECT
  to_regclass('public.assistant_daily_usage') AS quota_table,
  to_regprocedure('public.consume_assistant_request()') AS quota_function,
  to_regprocedure('public.account_is_active()') AS account_function;
```

Ba giá trị phải khác NULL. Database mới dùng file chính `../supabase_database.sql`.
Database đã có bảng lịch mà thiếu quota: áp dụng nguyên khối transaction ASSISTANT_QUOTA
trong file SQL chính. Nếu thiếu account_function, áp dụng ACCOUNT_CASCADE_AUDIT và
ACCOUNT_DELETION_GRACE, rồi DATABASE_HARDENING theo thứ tự trong file chính.
Xem README.md và ACCOUNT_DELETION_SETUP.md trước khi cập nhật dữ liệu đang có.

## 4. Triển khai trợ lý

Qua Dashboard: Edge Functions → Deploy a new function → Via Editor. Đặt tên
chính xác `study-assistant`; thay nội dung index.ts bằng toàn bộ file
`functions/study-assistant/index.ts` trong dự án rồi Deploy. Nếu hàm đã có,
mở và cập nhật đúng hàm đó. Dự án sử dụng cấu hình tắt Verify JWT ở gateway;
mã hàm vẫn bắt buộc có Bearer token và xác thực bằng auth.getUser(). Không xóa
kiểm tra này. Chỉ cập nhật secret chưa đủ để thay mã OpenAI đang chạy trên server.

Hoặc từ thư mục dự án, nếu có Node.js và Supabase CLI:

```powershell
npx supabase login
.\backend\deploy.ps1 -ProjectRef MA_PROJECT_CUA_BAN -Functions study-assistant
```

Thay MA_PROJECT_CUA_BAN bằng mã từ URL Dashboard `/project/MA_PROJECT_CUA_BAN`.
Không cần triển khai lại import-timetable để thử tư vấn.

## 5. Chạy app mới và thử

Nếu Logs chỉ có `provider_http_status: 403` và `reasons: ["UNSPECIFIED"]`,
có thể kiểm tra Google trực tiếp bằng PowerShell từ thư mục gốc dự án:

```powershell
.\backend\check-gemini.ps1
```

Script yêu cầu nhập key ở chế độ ẩn, không ghi key ra file hoặc đưa vào URL,
chỉ gửi câu thử cố định "Reply with OK.". Tốn một yêu cầu Gemini, không trừ
quota trong database app. Kết quả in mã HTTP và thông báo Google đã che key;
không in phản hồi thô, header hoặc dữ liệu hội thoại. Nếu HTTP 200 chỉ xác nhận
Google chấp nhận yêu cầu từ máy này, chưa chứng minh cấu hình/quyền từ Supabase.
Script cũng in độ dài key (không in key) và Content-Type để kiểm tra lỗi dán
thiếu ký tự hoặc phản hồi không phải JSON. Thông báo dự phòng được che key,
loại bỏ thẻ HTML/ký tự điều khiển và giới hạn độ dài trước khi hiển thị.
Nếu ô nhập ẩn chỉ nhận một ký tự, chạy `.\backend\check-gemini.ps1 -FromClipboard`.
Chờ lời nhắc, rồi sang AI Studio sao chép key đầy đủ, trở lại terminal và chỉ
nhấn Enter, không dán. Script đọc clipboard vào bộ nhớ, không in hoặc lưu key.
Nếu Google trả "The Gemini API free tier is not available for this project",
project đó chưa được Google cho dùng Free tier. Đổi tên model/key trong app
không cấp quyền Free tier; xem AI Studio Billing/hỗ trợ Google hoặc chọn nhà
cung cấp khác. Nếu key đã xuất hiện trong chat/ảnh, thu hồi hoặc xoay key đó
và cập nhật secret mới nếu tiếp tục dùng Gemini.

Chạy/rebuild Flutter từ mã mới để màn hình đồng ý hiển thị Google Gemini.
Đăng nhập bằng tài khoản đang hoạt động, mở Trợ lý AI, đọc thông báo và đồng ý.
Thử: "Tôi thi Toán vào thứ sáu, mỗi ngày rảnh 2 giờ. Hãy giúp tôi lên kế hoạch ôn."
Không dùng nút Test không có session người dùng: hàm sẽ trả 401 theo thiết kế.

Nếu lỗi, vào Edge Functions → study-assistant → Invocations/Logs. Hàm chỉ trả
lỗi tổng quát, không ghi key, nội dung hội thoại hay phản hồi lỗi thô của Google.
Khi Google từ chối yêu cầu, Logs có sự kiện `gemini_request_failed` gồm mã HTTP
và mã nguyên nhân đã được lọc theo danh sách cho phép (ví dụ SERVICE_DISABLED,
API_KEY_SERVICE_BLOCKED). `UNSPECIFIED` nghĩa là chưa có mã phù hợp trong phản hồi;
không kết luận key sai chỉ từ mã này. Cần deploy lại index.ts để dùng log mới.

| Phản hồi | Kiểm tra |
| --- | --- |
| 401 Unauthorized | Đăng nhập lại; kiểm tra cấu hình gateway |
| 403 Account unavailable | Trạng thái tài khoản hoặc RPC account_is_active |
| 503 Assistant not configured | Thiếu GEMINI_API_KEY/GEMINI_MODEL hoặc model nhập sai định dạng |
| 503 Assistant quota not configured | Thiếu/lỗi hàm quota |
| 503 Gemini configuration unavailable | Key, quyền truy cập, model, khu vực hoặc yêu cầu bị Google từ chối |
| 503 Gemini model unavailable | Model không tồn tại hoặc project không được dùng model này |
| 503 Gemini key rejected | Google từ chối key, quyền hoặc khu vực của project |
| 503 Gemini request rejected | Google từ chối định dạng/tham số yêu cầu; kiểm tra mã hàm và model |
| 503 Account check unavailable | Không gọi được hàm account_is_active; kiểm tra SQL và quyền RPC |
| 429 Daily limit reached | Hết 30 lượt/người/ngày của ứng dụng |
| 429 Gemini rate limit reached | Hạn mức dùng chung của Google project |
| 502 Gemini response unavailable / Empty response | Nội dung bị chặn, phản hồi bị cắt hoặc không có văn bản |
| 502 AI service unavailable / 500 | Dịch vụ gián đoạn, timeout hoặc lỗi xử lý |

Quota app vẫn tính theo ngày UTC, đổi ngày lúc 07:00 Việt Nam. Lượt đã lấy quota
nhưng Google báo lỗi vẫn tính. Quota miễn phí Google là dùng chung theo project,
không phải 30 lượt Google cấp riêng cho từng người dùng app.

Google có thể dùng nội dung ở Free tier để cải thiện sản phẩm. Thông báo đồng ý
trong app đã nêu điều này; tránh gửi thông tin nhạy cảm. Trợ lý chỉ biết hội thoại,
chưa tự đọc lịch hoặc sửa dữ liệu. Kiểm tra lại tư vấn trước khi áp dụng.

Kiểm thử cục bộ không cần key:

```powershell
node --test backend/tests/study_assistant_groq.test.mjs
flutter test test/assistant_overlay_test.dart test/services/assistant_error_test.dart
```

Kiểm thử backend dùng Auth/DB/Gemini giả lập, không chứng minh key/model thật có
quyền truy cập. Chưa triển khai hoặc gọi Gemini thật trong phiên chỉnh sửa này.

Nguồn: https://ai.google.dev/gemini-api/docs/api-key ;
https://ai.google.dev/gemini-api/docs/pricing ;
https://ai.google.dev/api/generate-content
