# Đồng bộ công việc và lịch sử chat

Nguồn SQL duy nhất: `supabase_database.sql`, khối `WORKSPACE_CLOUD_SYNC`.
Khối này bổ sung `workspace_items` và RPC `sync_workspace_items`. Không chạy
lại toàn bộ SQL khi chỉ nâng cấp tính năng này; áp dụng riêng khối đã kiểm tra.

- Mỗi tài khoản có dữ liệu riêng. RLS chỉ cho đọc tài khoản đang hoạt động;
  RPC kiểm tra `auth.uid()` và trạng thái tài khoản trước mọi thao tác.
- Công việc liên kết với mã môn học thuộc chính tài khoản. Đổi tên môn vẫn giữ
  liên kết; xóa môn giữ công việc, bỏ liên kết và giữ nhãn cũ để người dùng sửa lại.
- Công việc, phiên học, nhật ký tập trung, mục tiêu và từng cuộc trò chuyện được
  đồng bộ riêng. Không gửi ảnh đính kèm hay API key vào lịch sử chat.
- Dữ liệu cũ trên máy được chuyển lên lần đầu theo cách chỉ bổ sung, không ghi
  đè bản đã có trên máy chủ. Các khóa lưu cũ vẫn được giữ làm bản dự phòng.
- Hàng đợi lưu trên thiết bị trước khi gửi. Mất mạng không làm mất thay đổi;
  mở lại app hoặc bấm **Đồng bộ** để thử lại. Mở **Lịch sử** cũng tải bản mới.
- Xóa tạo bản ghi đánh dấu, tránh bản sao cũ trên máy khác khôi phục dữ liệu đó.
  Xóa hẳn tài khoản sẽ xóa cả dữ liệu này qua khóa ngoại.
- Các mục khác nhau được hợp nhất. Nếu hai máy cùng sửa **một mục**, thay đổi
  được máy chủ nhận sau cùng sẽ được giữ; chưa hỗ trợ cùng sửa một cuộc chat
  theo thời gian thực. Nên đồng bộ trước khi tiếp tục cuộc chat ở máy khác.
- Trạng thái đã đọc thông báo vẫn lưu trên từng thiết bị, không nằm trong đợt này.

Kiểm tra: `test/services/workspace_sync_test.dart`, `test/task_subject_test.dart`,
`backend/tests/workspace_sync_db_test.ps1` (hoàn tác toàn bộ dữ liệu thử), và
`backend/tests/workspace_sync_live_check.py` (hai phiên Auth, tự xóa tài khoản thử).
