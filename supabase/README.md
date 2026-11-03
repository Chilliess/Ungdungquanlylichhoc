# Bật thêm/sửa lịch từ màn hình lịch học

## File SQL tổng

`../supabase_database.sql` đã gộp đầy đủ cấu trúc bảng, ghi chú, thẻ phân loại
và hai hàm lưu lịch/quản lý thẻ. Có thể chạy toàn bộ file tổng trong SQL Editor.
Hai file trong `migrations/` là lựa chọn cập nhật riêng cho dự án đã có bảng gốc;
nếu đã chạy bản SQL tổng mới thì các thay đổi này đã được áp dụng.

Trong Supabase Dashboard của dự án, mở **SQL Editor → New query**, dán toàn bộ
nội dung `migrations/20261102_calendar_editor.sql` rồi nhấn **Run** một lần.

Chạy sau khi đã tạo các bảng trong `supabase_database.sql`. Bản cập nhật bổ sung
`notes`, `category` cho lịch học/lịch kiểm tra và hàm `save_calendar_lesson`.
Không xóa dữ liệu hiện có; các chính sách quyền truy cập theo tài khoản vẫn giữ nguyên.
Hàm tạo môn học và lưu lịch trong cùng một giao dịch, chỉ cho tài khoản đã đăng nhập.
Tên môn có sẵn được dùng lại; sửa tên một lịch không đổi tên các lịch khác.

Lịch mới có `start_date = end_date` và được hiển thị đúng một ngày. Lịch lặp hiện có
được chỉnh theo cả chuỗi: đổi ngày dịch khoảng ngày và các thứ tương ứng; giữ nguyên
giảng viên và các trường không có trong form. Form hiển thị thông báo này trước khi lưu.

Phiên phát triển này không có kết nối quản trị Supabase nên chưa áp dụng migration
lên máy chủ. Nếu chưa chạy SQL, form sẽ báo rõ khi lưu; không báo lưu thành công giả.

## Thẻ phân loại

Sau bản cập nhật trên, chạy tiếp `migrations/20261102_calendar_categories.sql`.
Nhãn cũ được đưa vào danh sách thẻ. Tạo thẻ bằng cách nhập tên và chuyển tiêu điểm;
đổi tên/xóa thẻ cập nhật nhãn trên mọi lịch học và lịch kiểm tra của chính tài khoản đó.
Bỏ chọn bằng dấu × trên thẻ chỉ bỏ nhãn ở form đang mở, không xóa thẻ khỏi danh sách.

## Sửa lỗi thiếu mã môn khi thêm lịch

Nếu lưu lịch báo `null value in column "subject_code"`, chạy riêng
`migrations/20261102_calendar_subject_code.sql` trong SQL Editor rồi lưu lại lịch.
Bản sửa thay hàm lưu lịch để tự sinh mã `AUTO-...` khi tạo môn mới; môn có sẵn
được dùng lại với nguyên mã cũ. Không cập nhật hay xóa các dòng dữ liệu cũ.
SQL tổng và bản cập nhật lưu lịch ban đầu cũng đã được đồng bộ với bản sửa này.

## Màu thẻ phân loại

Chạy `migrations/20261102_calendar_category_colors.sql` sau bản cập nhật thẻ.
Bản SQL tổng cũng đã bao gồm phần này. Thẻ cũ giữ nguyên tên, được gán màu đỏ
mặc định; có thể chọn lại màu khi sửa thẻ. Màu được lưu theo tài khoản và dùng
cho thẻ trong danh sách, biểu tượng trên form và màu sự kiện được gắn nhãn.

### Quản lý môn học và lịch lặp
Chạy `migrations/20261102_subject_recurrence.sql` sau các bản cập nhật lịch và nhãn trước đó. File tổng `supabase_database.sql` đã bao gồm bản này. Migration thêm cột và hàm, không xóa hay chuyển đổi dữ liệu cũ.

Lựa chọn lặp: không lặp, hằng ngày, hằng tuần, hằng tháng, hằng năm. `end_date = NULL` là không giới hạn; giao diện lịch hỗ trợ đến 31/12/2100. Ngày không tồn tại trong tháng/năm được bỏ qua. Lịch cũ chưa có `recurrence` tiếp tục dùng các thứ đã lưu và khoảng ngày cũ. Đổi tên từ lịch hoặc quản lý môn giữ cùng mã môn và cập nhật tên ở các lịch liên quan. Xóa môn chỉ thực hiện khi người dùng xác nhận và dọn cả lịch, kiểm tra, nhắc nhở liên quan trong một giao dịch.

Form Gọn theo nhóm ở Lịch học và Quản lý môn học cùng gọi `save_subject_schedule`. Với dự án đã có dữ liệu, chỉ chạy toàn bộ file migration lịch lặp trên trong SQL Editor → New query → Run. Không cần chạy lại file SQL tổng. Có thể chạy lại migration này; việc chạy file chỉ cập nhật cấu trúc và định nghĩa hàm, không gọi hàm xóa môn học.
