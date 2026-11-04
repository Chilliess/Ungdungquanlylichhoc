# Xóa tài khoản có thời gian chờ 7 ngày

Thay thế hoàn toàn luồng OTP/xóa ngay trước đây.

1. Bấm Đồng ý → nhập chính xác `delete` → Yêu cầu xóa sau 7 ngày.
2. Máy chủ tạo hạn cố định 7 × 24 giờ từ lúc nhận yêu cầu. Retry không gia hạn. App đăng xuất, giữ dữ liệu để có thể khôi phục.
3. Đăng nhập trong thời hạn: màn chặn yêu cầu chọn Khôi phục tài khoản hoặc Đăng xuất. Chỉ đăng nhập, đọc trạng thái hoặc từ chối khôi phục không hủy yêu cầu xóa.
4. Sau hạn: không khôi phục nữa; worker mỗi phút xóa Auth user và dữ liệu qua cascade. Không hứa xóa đúng từng giây nếu máy chủ/tác vụ gặp lỗi; worker chạy lại các yêu cầu lỗi.

## Triển khai theo thứ tự

- Kiểm tra phần ACCOUNT_CASCADE_AUDIT trong `../supabase_database.sql` (khóa ngoại cascade).
- Database đang có dữ liệu: kiểm tra schema rồi áp dụng các khối transaction ACCOUNT_DELETION_GRACE và DATABASE_HARDENING còn thiếu trong file SQL chính theo thứ tự. Không chạy lại các định nghĩa cũ sau bản mới.
- Database mới: `../supabase_database.sql` đã gộp phần chờ xóa 7 ngày, không cần chạy lại migration trên. File tổng không tự kích hoạt tác vụ xóa; vẫn cần triển khai các bước Edge Functions/Vault/Cron bên dưới.
- Đặt Edge secret `ACCOUNT_DELETION_CRON_SECRET` là một chuỗi ngẫu nhiên mạnh, không đưa vào Flutter/git.
- Deploy lại `delete-account`, `study-assistant`, `import-timetable` và deploy mới `purge-accounts` với `.\backend\deploy.ps1 -ProjectRef MA_PROJECT_CUA_BAN -Functions study-assistant,import-timetable,delete-account,purge-accounts`.
- Trong Supabase Vault tạo `account_purge_url` (URL hàm purge-accounts) và `account_purge_secret` (cùng giá trị Edge secret trên).
- Trong file SQL chính, tìm OPTIONAL_ACCOUNT_PURGE_CRON, sao chép phần SQL của mục đó, bỏ một tiền tố `-- ` mỗi dòng và chạy riêng sau khi Vault đã sẵn sàng. Theo dõi Cron/Edge logs và kết quả HTTP; HTTP được xếp hàng không đồng nghĩa đã xóa thành công.
- Sau đó phát hành app mới. Nếu chưa chạy migration, app mới sẽ chặn đăng nhập vì không kiểm tra được trạng thái, thay vì bỏ qua bảo vệ.

## Bảo vệ dữ liệu

- Các bảng lịch, môn, nhãn, nhắc nhở và hồ sơ có policy RESTRICTIVE chặn tài khoản đang chờ xóa, kể cả JWT cũ trên thiết bị khác. AI/import cũng kiểm tra trạng thái.
- Flutter kiểm tra ở cấp ứng dụng khi có phiên đăng nhập, khi trở lại ứng dụng và mỗi 30 giây. Không vào app trong lúc chưa kiểm tra xong hoặc khi kiểm tra thất bại.
- Khôi phục và worker khóa cùng hàng; hết hạn hoặc đã được worker nhận thì không thể khôi phục. Worker không nhận ID tài khoản từ người dùng.
- Không tự xóa lịch sử/công việc lưu cục bộ khi mới yêu cầu xóa, để người dùng có thể khôi phục. Dữ liệu cục bộ trên thiết bị offline không thể được máy chủ xóa từ xa; phạm vi xóa tự động là tài khoản và dữ liệu Supabase.
- Nếu bổ sung Storage, cần bổ sung xử lý file thuộc user; Auth có thể từ chối xóa nếu còn file. Worker ghi số lỗi để người quản trị xử lý, không báo đã xóa khi thất bại.

## Kiểm chứng trước production

Dùng tài khoản thử và môi trường staging: từ chối xác nhận, chữ sai, gửi lặp, đăng nhập không khôi phục, khôi phục trước hạn, từ chối khi bằng/sau hạn, JWT cũ không đọc/ghi được bảng, worker không có secret bị từ chối, cạnh tranh restore/worker và retry worker lỗi. Không rút ngắn hạn của tài khoản thật để thử.

Mục account_deletion_grace trong `DATABASE_CHECKS.md` kiểm tra trạng thái trong transaction rollback trên database thử. UI có widget tests riêng. SQL/worker chưa được chạy trên Supabase production trong thay đổi này.

Tài liệu: https://supabase.com/docs/guides/functions/schedule-functions
