# Trợ lý mini và xóa tài khoản

**Trợ lý tư vấn đã chuyển sang Groq.** Làm theo
[GROQ_SETUP.md](GROQ_SETUP.md) để tạo key và triển khai `study-assistant`.
Nhập ảnh/PDF (`import-timetable`) vẫn dùng OpenAI. Không đưa API key hoặc
service-role key vào Flutter, SQL hay Git.

**Cập nhật 04/11/2026:** xóa tài khoản đã chuyển sang xác nhận `delete`, chờ 7 ngày và khôi phục có xác nhận. Bắt buộc làm theo `ACCOUNT_DELETION_SETUP.md` cho phần xóa tài khoản; không dùng luồng OTP cũ.

Frontend đã nối với hai Edge Functions. Không đưa OPENAI_API_KEY hoặc service-role key vào Flutter.

## Triển khai

1. Database mới: chạy `../supabase_database.sql`. Database đang có: xem README.md và áp dụng các khối transaction còn thiếu, đặc biệt ASSISTANT_QUOTA và ACCOUNT_CASCADE_AUDIT. Nếu có lỗi khóa ngoại, xử lý cấu trúc được báo trước khi bật xóa tài khoản.
2. Áp dụng phần thời gian chờ trong file SQL chính và cấu hình tác vụ xóa theo `ACCOUNT_DELETION_SETUP.md`. Luồng xóa tài khoản không dùng OTP nữa.
3. Với trợ lý: đặt secrets `GROQ_API_KEY` và `GROQ_MODEL` theo `GROQ_SETUP.md`. Với nhập ảnh/PDF: đặt `OPENAI_API_KEY` và `OPENAI_VISION_MODEL` riêng.
4. Trong terminal VS Code, dùng Supabase CLI đã cài:

```powershell
npx supabase login
.\backend\deploy.ps1 -ProjectRef MA_PROJECT_CUA_BAN -Functions study-assistant,delete-account
```

`--no-verify-jwt` tắt kiểm tra JWT cũ của gateway để hỗ trợ khóa publishable mới. Cả hai hàm vẫn bắt buộc xác thực access token bằng `auth.getUser()` trước mọi thao tác. Không bỏ bước xác thực này.

## Phạm vi

- AI hỏi đáp qua Groq Chat Completions, không tự đọc hay sửa lịch. Giao diện yêu cầu đồng ý gửi hội thoại cho Groq và dịch vụ tìm kiếm khi bật tra cứu web. Không ghi nội dung vào log hoặc database của ứng dụng; nhà cung cấp có chính sách xử lý dữ liệu riêng. Tra cứu web cần kiểm tra quyền/chi phí rồi bật riêng theo GROQ_SETUP.md.
- Hội thoại lưu cục bộ theo tài khoản, có lịch sử/xóa có xác nhận; không tự đồng bộ sang thiết bị khác. Giới hạn 30 yêu cầu/người/ngày UTC, mỗi lượt tối đa 12 tin. Lượt lỗi từ nhà cung cấp vẫn tính quota.
- Xóa tài khoản cần session hợp lệ và xác nhận `delete`. Hệ thống giữ dữ liệu 7 ngày; chỉ xác nhận khôi phục trước hạn mới hủy yêu cầu. Worker xóa Auth user rồi cascade sau hạn.
- Dự án hiện không có luồng lưu file Storage người dùng. Nếu bổ sung Storage, cần bổ sung chính sách xóa file trước khi quảng bá xóa toàn bộ dữ liệu; Supabase có thể chặn xóa user còn sở hữu file.

## Kiểm thử staging trước khi dùng thật

- AI: không đăng nhập → 401; thiếu cấu hình → 503; vượt quota → 429; phản hồi AI không sửa lịch.
- Tài khoản: thiếu JWT hoặc nhập sai `delete` không tạo yêu cầu; không chấp nhận ID của người khác; chưa xác nhận khôi phục thì không vào app.
- Dùng tài khoản thử để kiểm tra thời gian chờ, khôi phục, worker và cascade theo `ACCOUNT_DELETION_SETUP.md`.
- Không kiểm thử xóa bằng tài khoản thật. Chưa triển khai hoặc kiểm thử với Supabase production trong thay đổi này.

Tài liệu: https://developers.openai.com/api/docs/guides/text ; https://supabase.com/docs/reference/javascript/auth-admin-deleteuser

## Nhập ảnh/PDF và phần học tập (04/11/2026)

- Đặt thêm secret `OPENAI_VISION_MODEL` là model hỗ trợ ảnh, PDF và Structured Outputs rồi chạy `.\backend\deploy.ps1 -ProjectRef MA_PROJECT_CUA_BAN -Functions import-timetable`. Hàm này xác thực JWT bằng getUser, dùng chung quota và chỉ nhận file tối đa 5 MB. Không ghi file vào Storage. Mỗi lần đọc tối đa 50 buổi.
- Nút + ở Lịch cho chọn Lịch học / Lịch thi / Tự học / Nhập ảnh-PDF. Kết quả nhận dạng phải kiểm tra từng buổi trước khi lưu. Ngày hoặc giờ không rõ cần người dùng thiết lập; hiện chưa tự quy đổi số tiết theo trường. Import lại cùng file có thể trùng lịch, cần kiểm tra trước khi lưu.
- Công việc, phiên tự học, mục tiêu và nhật ký tập trung lưu riêng theo user trên thiết bị, chưa đồng bộ Supabase. Thuật toán xếp lịch dùng deadline gần trước, độ khó phá hòa, không trùng lịch học/thi tải từ Supabase, 50 phút/phiên, nghỉ 10 phút giữa các phiên mới, phạm vi 14 ngày. Không phải CP-SAT và không khẳng định tối ưu toàn cục.
- Thống kê Tự học dùng tuần hiện tại và thời gian được ghi nhận, không tự coi lịch đã qua là đã học. Cảnh báo dựa trên khối lượng công việc so với mục tiêu tuần, chưa phải mô hình dự báo ML.
- Báo thức Android dùng kênh âm báo riêng, cần quyền thông báo và quyền báo thức chính xác. Thử trên thiết bị thật (bao gồm khóa màn hình và khởi động lại); không chạy thử âm tự động. Lịch nhắc được cập nhật khi mở màn Nhắc nhở. Android có thể chịu hạn chế pin/DND của thiết bị. iOS dùng thông báo âm thanh thông thường; web/Windows chưa có báo thức nền.
- Chưa triển khai backend production hoặc kiểm thử âm thanh trên phần cứng trong thay đổi này.
