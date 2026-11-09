# Backend ứng dụng quản lý lịch học

Mã máy chủ nằm trong `backend/functions/`. Tên dịch vụ vẫn là Supabase;
đổi tên thư mục không đổi URL, tên hàm hoặc nơi lưu dữ liệu trên máy chủ.

## Cấu trúc

- `../supabase_database.sql`: file SQL duy nhất, chứa bảng, RLS, RPC, index,
  trigger, quota và mục tùy chọn hẹn giờ xóa tài khoản.
- `functions/`: study-assistant và import-timetable (Groq),
  delete-account và purge-accounts.
- `deploy.ps1`: triển khai từ thư mục backend bằng Supabase CLI.
- `tests/`: kiểm tra backend giả lập cho Groq chat và nhập thời khóa biểu.
- `GROQ_SETUP.md`: tạo key, kiểm tra Free Plan và thử trợ lý tư vấn.
- `ASSISTANT_SETUP.md`: cấu hình các chức năng AI và học tập.
- `ACCOUNT_DELETION_SETUP.md`: thời gian chờ, worker, Vault và Cron.
- `DATABASE_CHECKS.md`: truy vấn kiểm tra dữ liệu và kiểm thử SQL trên staging.
- `WORKSPACE_SYNC.md`: đồng bộ công việc/chat, chuyển dữ liệu cũ và giới hạn xử lý xung đột.
- `../docs/KHOI_PHUC_DU_AN.md`: tải lại repo, dựng app và đăng nhập lại công cụ triển khai.

## Database

### Đồng bộ trang chủ, môn học và lịch

File SQL chính có khối `APP_DATA_SYNC`. Database đang có có thể chọn
nguyên khối BEGIN..COMMIT đó để áp dụng: chỉ giữ khóa ngoại tổng hợp theo chủ
sở hữu cho lịch → môn, bỏ khóa ngoại đơn trùng lặp gây mơ hồ khi nhúng quan hệ
trong Supabase. Khối này cũng tạo hồ sơ theo tên đăng ký cho tài khoản mới và
điền hồ sơ/tên còn thiếu của tài khoản cũ, không ghi đè tên đã chỉnh sửa.

Ứng dụng đọc các bảng theo tài khoản và ghép môn bằng ID qua `study_data.dart`,
không phụ thuộc quan hệ nhúng dễ gây lỗi khi database còn hai FK. Các thao tác
lưu/xóa lịch, môn, nhãn, nhập CSV và sửa tên hồ sơ thông báo để trang chủ tải
lại. Trang chủ cũng tải lại khi quay về từ màn hình con hoặc app trở lại hoạt động;
yêu cầu tải cũ không được ghi đè kết quả mới hơn. Dữ liệu lỗi không được hiển thị
như một lịch trống. Đây chưa phải cơ chế đồng bộ realtime giữa các thiết bị.

Thống kê nằm trong Quản lý trên trang chủ. Tab Chat AI và nút robot mở cùng
một trạng thái hội thoại/lịch sử theo tài khoản, không tạo hai
bản chat. Lịch sử đồng bộ qua Supabase theo WORKSPACE_SYNC.md. Khi người dùng bật "Lịch của tôi" và hỏi về lịch, study-assistant
chỉ đọc các mục liên quan thuộc tài khoản đã xác thực qua RLS rồi gửi cho Groq;
AI chuẩn bị đề xuất tạo/xóa; chỉ khi người dùng bấm Áp dụng thì RPC mới lưu thao tác theo quyền của tài khoản. Lịch lặp được kiểm tra theo ngày diễn ra thực tế;
ngữ cảnh gồm buổi tiếp theo trong 90 ngày tới và lịch thi sắp tới trong cùng
khoảng thời gian.

Database mới: chạy `../supabase_database.sql` trong Supabase SQL Editor.
Database đang có: sao lưu, xem schema hiện tại và chỉ chọn các khối transaction
còn thiếu trong file chính; không chạy riêng đoạn giữa BEGIN/COMMIT.
Không chạy các định nghĩa cũ ở đầu file sau các bản mới ở cuối file.

Các phần đáng chú ý: ASSISTANT_QUOTA, ACCOUNT_CASCADE_AUDIT,
ACCOUNT_DELETION_GRACE, DATABASE_HARDENING, AI_CALENDAR_ACTIONS, ACCOUNT_RESTORE_HINT,
WORKSPACE_CLOUD_SYNC, CALENDAR_EXAM_CREATE_FIX và OPTIONAL_ACCOUNT_PURGE_CRON.
Hardening giữ nguyên dữ liệu cũ; CHECK/FK NOT VALID vẫn kiểm tra dữ liệu khi
INSERT/UPDATE. Đọc mục hardening_preflight trong DATABASE_CHECKS.md trước khi
cập nhật. Không tự sửa hoặc xóa dữ liệu không hợp lệ.

Cron nằm dưới OPTIONAL_ACCOUNT_PURGE_CRON ở cuối file chính và được comment
để không tự bật khi chạy setup. Chỉ sao chép phần SQL bên trong mục đó, bỏ
một tiền tố `-- ` ở mỗi dòng rồi chạy riêng sau khi đã cấu hình worker/Vault.

## Triển khai hàm

Có thể tạo/cập nhật hàm qua Supabase Dashboard → Edge Functions → Via Editor,
sao chép `functions/TEN_HAM/index.ts`, đặt đúng tên hàm rồi Deploy.
Giữ kiểm tra đăng nhập/secret có sẵn trong mã. Cấu hình gateway của dự án
sử dụng Verify JWT tắt, vì mã hàm tự xác thực người gọi.

Hoặc từ thư mục gốc dự án với Node.js đã cài:

```powershell
npx supabase login
.\backend\deploy.ps1 -ProjectRef MA_PROJECT_CUA_BAN -Functions study-assistant
```

Để triển khai nhiều hàm:

```powershell
.\backend\deploy.ps1 -ProjectRef MA_PROJECT_CUA_BAN -Functions study-assistant,import-timetable,delete-account,purge-accounts
```

Thay MA_PROJECT_CUA_BAN bằng mã project trong URL Dashboard. Script tạo cấu
trúc mặc định của CLI trong thư mục tạm, chạy deploy rồi dọn thư mục tạm;
không tạo lại thư mục supabase trong dự án. Không chạy lệnh deploy cũ trực tiếp
ở thư mục gốc vì CLI mặc định tìm supabase/functions.

## Kiểm tra

```powershell
node --test backend/tests/study_assistant_groq.test.mjs backend/tests/import_timetable_groq.test.mjs
flutter test test/assistant_overlay_test.dart
```

Kiểm thử giả lập không gọi Groq/Supabase thật. Sau triển khai vẫn cần thử
bằng tài khoản đang hoạt động. Giữ API key trong Edge Functions Secrets,
không ghi vào Flutter, SQL, script triển khai hoặc Git.
