# Logo Quản lý lịch học

- `project_logo_reference.png`: ảnh tham chiếu gốc người dùng cung cấp.
- `project_logo.png`: bản 1024 px xuất từ hình lịch/mũ tốt nghiệp đang dùng trong
  ứng dụng (`lib/widgets/app_logo.dart`).
- Xuất lại favicon, biểu tượng web/PWA, Android và Windows bằng:
  `flutter test tool/export_app_icons.dart`.
- Biểu tượng maskable và adaptive có khoảng đệm để giữ logo khi hệ điều hành
  áp dụng hình tròn hoặc góc bo. Không thay biểu tượng Google/Microsoft đăng nhập.

Tên hiển thị là **Quản lý lịch học**; Windows chạy bằng **QuanLyLichHoc.exe**.
Mã package Dart, Android application ID và OAuth callback vẫn giữ nguyên để
không làm mất tương thích với các bản demo và cấu hình đăng nhập đã có.
Windows chuyển bản sao tệp preferences từ tên cũ trong lần mở đầu tiên;
không xóa bản gốc và không ghi đè dữ liệu đã có dưới tên mới.
