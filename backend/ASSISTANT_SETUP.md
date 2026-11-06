# Trợ lý AI, nhập lịch và phần học tập

Trợ lý hiện dùng **Groq**. Không còn dùng Gemini hoặc công cụ tra cứu web.
Mã máy chủ nằm trong `backend/functions/`; file SQL duy nhất là
`../supabase_database.sql`.

## Cấu hình các chức năng

| Hàm | Cấu hình cần thiết | Vai trò |
| --- | --- | --- |
| `study-assistant` | `GROQ_API_KEY`, `GROQ_MODEL`; ảnh tùy `GROQ_VISION_MODEL` | Hỏi đáp, đọc lịch liên quan, đề xuất tạo/xóa lịch |
| `import-timetable` | `OPENAI_API_KEY`, `OPENAI_VISION_MODEL` | Đọc ảnh/PDF tối đa 5 MB, trả tối đa 50 buổi để kiểm tra |
| `delete-account` | Cấu hình Supabase và SQL vòng đời tài khoản | Yêu cầu xóa sau 7 ngày, có xác nhận |
| `purge-accounts` | Service-role/worker secret theo tài liệu riêng | Xóa tài khoản hết hạn từ tác vụ máy chủ |

Đặt giá trị bí mật trong **Supabase Edge Functions → Secrets**. Không đưa key,
mật khẩu hay service-role key vào Flutter, SQL hoặc Git. Xem `GROQ_SETUP.md`
và `ACCOUNT_DELETION_SETUP.md` cho từng chức năng.

## Triển khai

1. Database mới: chạy SQL chính. Database đã có dữ liệu: kiểm tra và áp dụng
   các khối transaction còn thiếu theo `README.md` và `DATABASE_CHECKS.md`.
2. Đăng nhập Supabase CLI rồi chạy từ thư mục gốc:

```powershell
npx supabase login
.\backend\deploy.ps1 -ProjectRef MA_PROJECT_CUA_BAN -Functions study-assistant,import-timetable,delete-account,purge-accounts
```

Script dựng bố cục Supabase CLI trong thư mục tạm, không nhân đôi mã nguồn.
Gateway dùng Verify JWT tắt để hỗ trợ khóa publishable; từng hàm vẫn xác thực
người gọi và quyền tài khoản trong mã. Không bỏ các kiểm tra này.

## Hành vi trong ứng dụng

- Bật **Lịch của tôi** để gửi phần lịch liên quan của chính tài khoản cho Groq.
  Tắt tùy chọn này thì không đọc dữ liệu lịch làm ngữ cảnh.
- AI chỉ trả đề xuất. Người dùng bấm **Áp dụng** từng mục; RPC kiểm tra chủ sở
  hữu và chống áp dụng lặp cùng request ID. Xóa chuỗi lặp phải được trình bày rõ.
- Mỗi yêu cầu chat dùng ngữ cảnh có giới hạn, không phải bộ nhớ vô hạn. Ảnh
  trong chat tối đa 3 MB, không lưu ảnh vào lịch sử.
- Lịch sử chat, công việc, phiên tự học, nhật ký và mục tiêu đồng bộ theo tài
  khoản; dữ liệu ngoại tuyến có hàng đợi. Xem `WORKSPACE_SYNC.md` về xung đột.
- Hạn mức ứng dụng: 30 yêu cầu/tài khoản/ngày máy chủ, kiểm tra trong SQL. Lượt
  lỗi từ nhà cung cấp sau khi lấy quota vẫn tính lượt. Hạn mức Groq độc lập.
- Bộ tự xếp lịch xét hạn nộp, độ khó và lịch bận trong 14 ngày; tối đa 50 phút
  mỗi phiên, nghỉ 10 phút. Người dùng xem trước và xác nhận lưu.
- Android có thông báo/báo thức theo quyền hệ điều hành; web/Windows có danh
  sách thông báo trong app, chưa có báo thức nền. Mở Nhắc nhở để cập nhật lịch
  báo sau khi sửa lịch. Kiểm tra trên thiết bị thật trước khi demo.
- Xóa tài khoản cần xác nhận `delete`, chờ 7 ngày và khôi phục có xác nhận;
  không dùng luồng OTP cũ. Worker/Cron cần cấu hình riêng.

## Kiểm tra

```powershell
flutter test
node --test backend/tests/study_assistant_groq.test.mjs
.\backend\tests\check_groq_parser_test.ps1
```

Các lệnh trên dùng dữ liệu giả. Script `*_db_test.ps1` và `*_live_check.py`
trong `tests/` kết nối project Supabase đã liên kết; chỉ chạy khi hiểu môi
trường đích. Script database dùng giao dịch hoàn tác; script Auth dùng tài
khoản tạm và tự dọn. Không thay bằng tài khoản thật để thử xóa.

Để dựng lại từ GitHub sau khi xóa bản trên máy, xem
`../docs/KHOI_PHUC_DU_AN.md`.
