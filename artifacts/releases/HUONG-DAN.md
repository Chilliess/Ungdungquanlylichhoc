# Quản lý lịch học — Android và Windows

## Android

Chép `QuanLyLichHoc-Android.apk` sang điện thoại Android, mở tệp để cài đặt.
Đăng nhập tài khoản đang dùng để tiếp tục truy cập dữ liệu Supabase.
Đây là APK cài trực tiếp, dùng cấu hình ký thử hiện có của dự án; chưa phải gói phát hành Google Play.

## Windows x64

Giải nén toàn bộ `QuanLyLichHoc-Windows-x64.zip` vào một thư mục, rồi chạy
`QuanLyLichHoc.exe`. Giữ nguyên thư mục `data` và các tệp DLL cạnh tệp EXE.

## Chat AI

Cả hai bản dùng chung backend Supabase và Groq với bản web Cloudflare, cần Internet.
Có thể đọc lịch cá nhân, chuẩn bị tạo/xóa lịch rồi áp dụng từng mục, và chọn ảnh từ máy.
Dán ảnh trực tiếp từ clipboard hiện chỉ hỗ trợ bản web; Android/Windows dùng nút chọn ảnh.
Khả năng đọc ảnh còn phụ thuộc quyền và hạn mức model ảnh của tài khoản Groq.

Windows đã được mở kiểm tra khởi động. Android cần cài lên điện thoại để kiểm tra thực tế.

## Thông báo và trùng lịch

Chuông trên trang chủ hiển thị số thông báo chưa đọc. Mở từng thông báo hoặc
chọn “Đánh dấu tất cả đã đọc”; trạng thái lưu riêng cho từng tài khoản trên thiết bị.
Khi thêm/sửa lịch hoặc áp dụng đề xuất tạo lịch của AI, ứng dụng kiểm tra trùng
giờ với lịch học và lịch thi, kể cả các ngày lặp. Hai buổi nối tiếp nhau không bị
coi là trùng. Cảnh báo cho phép quay lại chỉnh giờ hoặc xác nhận vẫn lưu.

## Đồng bộ công việc và chat

Đăng nhập cùng tài khoản trên các thiết bị. Công việc có thể chọn môn học từ
danh sách sẵn có và lọc theo môn. Công việc, phiên học, nhật ký tập trung và lịch
sử chat tự gửi thay đổi lên tài khoản khi có mạng. Bấm **Đồng bộ** trong Công việc
hoặc mở **Lịch sử** để lấy dữ liệu mới từ thiết bị khác và gửi lại thay đổi còn chờ.
Dữ liệu cũ trên từng máy được bổ sung lên tài khoản khi mở bản mới.

Nếu cùng sửa một mục trên hai máy, bản máy chủ nhận sau cùng sẽ được giữ.
Đồng bộ trước khi tiếp tục cùng một cuộc chat ở máy khác.
