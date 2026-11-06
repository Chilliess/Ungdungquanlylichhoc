# Ứng Dụng Quản Lý Lịch Học & Thời Khóa Biểu

Ứng dụng Flutter hỗ trợ sinh viên quản lý môn học, thời khóa biểu, lịch kiểm tra và thời gian tự học. Ứng dụng dùng Supabase để xác thực tài khoản và lưu dữ liệu; lịch được tổng hợp theo ngày, có thể xem theo ngày/tháng/năm, tìm kiếm, phân loại và đặt nhắc nhở.

## Mục lục

- [Tính năng](#tính-năng)
- [Luồng sử dụng](#luồng-sử-dụng)
- [Công nghệ](#công-nghệ)
- [Cấu trúc dự án](#cấu-trúc-dự-án)
- [Dữ liệu và cách ứng dụng hoạt động](#dữ-liệu-và-cách-ứng-dụng-hoạt-động)
- [Tải và cài ứng dụng](#tải-và-cài-ứng-dụng)
- [Tải lại dự án từ GitHub](docs/KHOI_PHUC_DU_AN.md)
- [Yêu cầu và cài đặt](#yêu-cầu-và-cài-đặt)
- [Cấu hình Supabase](#cấu-hình-supabase)
- [Nhập lịch từ CSV](#nhập-lịch-từ-csv)
- [Kiểm thử](#kiểm-thử)
- [Lưu ý](#lưu-ý)
- [Tác giả](#tác-giả)

## Tính năng

### Tài khoản

- Đăng ký và đăng nhập bằng email/mật khẩu qua Supabase Auth.
- Đăng nhập và đăng ký bằng Google hoặc Microsoft qua Supabase OAuth sau khi cấu hình provider.
- Cập nhật tên hiển thị và đổi mật khẩu trong màn hình tài khoản.
- Gửi email khôi phục mật khẩu qua Supabase Auth.
- Nếu project bật xác nhận email, người dùng cần xác minh email trước khi đăng nhập.
- Google và Microsoft dùng OAuth của Supabase; xem hướng dẫn cấu hình bên dưới.

### Trang chủ

- Chào người dùng theo tên hồ sơ và hiển thị ngày hiện tại.
- Tổng hợp lịch học và lịch kiểm tra trong ngày theo thứ tự thời gian.
- Hiển thị các sự kiện sắp tới, môn học và thông tin như phòng học, giảng viên.
- Truy cập nhanh đến lịch, tài khoản và phần cài đặt nhắc nhở.

### Môn học và thời khóa biểu

- Tạo và chỉnh sửa môn học cùng buổi học, thời gian, phòng và khoảng ngày áp dụng.
- Chọn nhiều ngày học trong tuần; tìm kiếm môn theo tên hoặc mã.
- Kiểm tra thời gian kết thúc, khoảng ngày và xung đột giữa lịch học/lịch kiểm tra trong luồng quản lý thời khóa biểu.
- Chỉnh sửa lịch theo nhóm từ màn hình lịch hoặc quản lý môn học. Các thay đổi được lưu qua hàm Supabase `save_subject_schedule`.
- Xóa môn học cần xác nhận; thao tác cơ sở dữ liệu dọn các lịch học, lịch kiểm tra và nhắc nhở liên quan.

### Lịch học, lịch kiểm tra và lịch lặp

- Lịch tổng hợp có chế độ xem ngày, tháng và năm; hỗ trợ tìm kiếm, mở chi tiết và chỉnh sửa sự kiện.
- Tạo lịch kiểm tra theo ngày cụ thể; có thể bổ sung ghi chú và nhãn phân loại.
- Lịch học lặp theo ngày, tuần, tháng hoặc năm; đặt ngày kết thúc hoặc để trống để không giới hạn.
- Lịch tuần dùng các thứ đã chọn. Lịch tháng/năm bỏ qua ngày không tồn tại (ví dụ ngày 31 trong tháng không có 31).
- Lịch cũ chưa có trường quy tắc lặp tiếp tục dùng ngày trong tuần và khoảng ngày đã lưu.

### Nhãn, nhắc nhở và thống kê

- Tạo nhãn phân loại có màu; dùng nhãn cho lịch học và lịch kiểm tra.
- Đổi tên hoặc xóa nhãn cập nhật những sự kiện đang gắn nhãn đó. Bỏ nhãn khỏi một sự kiện không xóa nhãn khỏi danh sách.
- Cấu hình nhắc cho lịch học/lịch kiểm tra; các mốc nhắc gồm 5, 10, 15, 30, 60 và 120 phút trước sự kiện.
- Tùy chọn giao diện sáng/tối được lưu trên thiết bị.
- Xem thống kê số buổi và tổng thời lượng theo tuần hoặc tháng, gồm phân tích theo môn và theo ngày. Lịch lặp được tính theo những ngày thực sự diễn ra trong khoảng thống kê.
- Trợ lý AI đọc lịch khi bật **Lịch của tôi**, trả lời qua Groq và chuẩn bị đề xuất tạo/xóa lịch; người dùng phải kiểm tra rồi bấm **Áp dụng** từng mục. Không có tra cứu web.
- Chuông thông báo hiển thị nhắc nhở đến hạn và lịch sắp tới trong 7 ngày; hỗ trợ đánh dấu đã đọc. Trạng thái đọc lưu trên từng thiết bị.

### Công việc, tự học và đồng bộ

- Công việc có hạn nộp, thời lượng, độ khó, trạng thái hoàn thành và liên kết với môn học; có bộ lọc theo môn.
- Tự xếp lịch trong 14 ngày, xét lịch học/thi và hạn nộp; phiên tối đa 50 phút, nghỉ 10 phút; xem trước rồi xác nhận lưu.
- Ghi nhận thời gian thực học bằng chế độ Tập trung.
- Công việc, phiên học, nhật ký, mục tiêu và lịch sử chat đồng bộ theo tài khoản Supabase; có hàng đợi lưu trên máy khi mất mạng.
- Bấm **Đồng bộ** trong Công việc hoặc mở **Lịch sử** trong Chat AI để tải dữ liệu mới và gửi lại thay đổi còn chờ. Nếu cùng sửa một mục ở hai máy, bản máy chủ nhận sau cùng được giữ.
- Nhập ảnh trong chat dùng Groq vision nếu tài khoản/model hỗ trợ; nhập ảnh/PDF từ menu lịch dùng Edge Function riêng, hiện cần cấu hình OpenAI.

## Luồng sử dụng

1. Tạo tài khoản hoặc đăng nhập. Tên hiển thị được lưu trong hồ sơ người dùng.
2. Tạo môn học và các buổi học, hoặc nhập các buổi học từ CSV.
3. Mở lịch để xem thời khóa biểu/lịch kiểm tra; dùng nhãn màu, ghi chú và quy tắc lặp khi cần.
4. Thiết lập nhắc nhở cho các sự kiện và xem thống kê học tập theo tuần/tháng.

## Công nghệ

- **Ứng dụng:** Flutter, Dart, Material.
- **Xác thực và dữ liệu:** Supabase Auth, PostgreSQL, Row Level Security (RLS).
- **Lịch và tiện ích:** `calendar_view`, `intl`, `flutter_local_notifications`, `timezone`, `shared_preferences`, `file_picker` và `csv`.

## Cấu trúc dự án

```text
lib/
├── auth/       # Đăng nhập, đăng ký, khôi phục mật khẩu và thành phần xác thực
├── models/     # Mô hình dữ liệu trang chủ, quy tắc lịch lặp, thống kê
├── screen/     # Các màn hình lịch, môn học, tài khoản, cài đặt, nhắc nhở
├── services/   # Tải và tổng hợp dữ liệu trang chủ
├── splash/     # Khởi động và kiểm tra phiên đăng nhập
├── theme/      # Màu sắc giao diện
├── widgets/    # Widget và thông báo dùng chung
├── homescreen.dart
└── main.dart   # Khởi tạo Supabase, ngôn ngữ và chủ đề

backend/
├── functions/  # Mã máy chủ: Groq, nhập lịch, xóa tài khoản
├── deploy.ps1  # Triển khai hàm từ thư mục backend
├── tests/      # Kiểm tra backend giả lập
└── README.md   # Hướng dẫn database và cấu hình dịch vụ

supabase_database.sql # Schema và các hàm SQL tổng hợp
test/                  # Kiểm thử widget, model, service và luồng giao diện
```

### Một số màn hình và thành phần chính

| Tệp | Trách nhiệm |
|---|---|
| `lib/homescreen.dart` | Trang chủ, lịch hôm nay và sự kiện sắp tới |
| `lib/screen/view_schedule_screen.dart` | Lịch tổng hợp theo ngày/tháng/năm |
| `lib/screen/lesson_editor.dart` | Form tạo/sửa lịch, ghi chú, nhãn và lịch lặp |
| `lib/screen/subject_management_screen.dart` | Quản lý môn học và lịch lặp theo nhóm |
| `lib/screen/schedule_announcement.dart` | Thiết lập thông báo nhắc lịch |
| `lib/screen/statistical.dart` | Thống kê theo tuần/tháng |
| `lib/screen/settings.dart` | Cài đặt, giao diện và nhập lịch CSV |
| `lib/screen/tasks_screen.dart` | Công việc, môn học liên kết, tự xếp lịch và tập trung |
| `lib/widgets/assistant_overlay.dart` | Chat AI và trợ lý mini dùng chung lịch sử |
| `lib/services/workspace_sync.dart` | Đồng bộ từng mục, lưu ngoại tuyến và đánh dấu xóa |
| `lib/services/home_service.dart` | Đọc và tổng hợp dữ liệu Supabase cho trang chủ |
| `lib/models/schedule_recurrence.dart` | Quy tắc ngày diễn ra dùng chung giữa lịch, trang chủ và thống kê |

## Dữ liệu và cách ứng dụng hoạt động

### Các bảng chính

| Bảng | Dữ liệu |
|---|---|
| `profiles` | Tên hiển thị gắn với tài khoản Supabase Auth |
| `subjects` | Môn học, mã môn và màu môn |
| `schedules` | Buổi học, thời gian, thứ trong tuần, khoảng ngày; các cột bổ sung lưu quy tắc lặp, ghi chú và nhãn |
| `schedule_exams` | Lịch kiểm tra theo ngày cụ thể, kèm thời gian, phòng và giám thị |
| `reminders` | Cài đặt nhắc, thời điểm nhắc và loại sự kiện (lịch học hoặc lịch kiểm tra) |
| `calendar_categories` | Tên và màu nhãn do từng tài khoản quản lý |
| `workspace_items` | Công việc, phiên học, nhật ký, mục tiêu và lịch sử chat theo tài khoản |
| `assistant_daily_usage` | Hạn mức AI được kiểm tra trên máy chủ |
| `account_deletion_requests` | Yêu cầu xóa tài khoản và thời hạn khôi phục |
| `assistant_calendar_actions` | Chống áp dụng lặp cùng một thao tác AI |

Môn học liên kết với lịch học và lịch kiểm tra qua `subject_id`. Những bản ghi cá nhân có `user_id` được giới hạn bằng chính sách RLS; các màn hình lấy dữ liệu theo tài khoản đang đăng nhập. Hàm SQL như `save_subject_schedule`, `save_calendar_lesson` và `delete_calendar_subject` xử lý các thao tác cần cập nhật nhiều bản ghi cùng nhau.

### Từ dữ liệu đến giao diện

`HomeService` tải hồ sơ, môn học, lịch học, lịch kiểm tra và cài đặt nhắc của tài khoản hiện tại. Các model trong `lib/models/` chuẩn hóa thứ trong tuần, xác định ngày xuất hiện của lịch lặp và tính số buổi/tổng phút cho thống kê. Các màn hình lịch sử dụng dữ liệu đó để hiển thị sự kiện theo ngày, tháng hoặc năm.

Lịch học theo tuần cũ lưu các ngày đã chọn trong `day_of_week`. Lịch lặp mới dùng thêm `recurrence` với các giá trị `none`, `daily`, `weekly`, `monthly` hoặc `yearly`; `end_date` để trống biểu thị không đặt ngày kết thúc. Quy tắc lặp được dùng chung khi dựng lịch, tính sự kiện trang chủ và tổng hợp thống kê.

## Tải và cài ứng dụng

## Tải trực tiếp

- **[Tải ứng dụng Android (APK)](https://github.com/Chilliess/Ungdungquanlylichhoc/releases/latest/download/QuanLyLichHoc-Android.apk):** mở tệp trên điện thoại và cho phép cài ứng dụng từ nguồn này nếu Android yêu cầu. Đây là APK cài trực tiếp, chưa được phát hành trên Google Play.
- **[Tải ứng dụng Windows x64 (ZIP)](https://github.com/Chilliess/Ungdungquanlylichhoc/releases/latest/download/QuanLyLichHoc-Windows-x64.zip):** giải nén toàn bộ vào một thư mục rồi chạy `QuanLyLichHoc.exe`. Giữ các tệp DLL và thư mục `data` cạnh tệp EXE.

Đăng nhập bằng tài khoản ứng dụng để sử dụng dữ liệu đã lưu. Xem [tất cả bản phát hành](https://github.com/Chilliess/Ungdungquanlylichhoc/releases) nếu muốn chọn phiên bản khác.

## Yêu cầu và cài đặt

Nếu tải lại sau khi xóa bản trên máy, làm theo **[hướng dẫn khôi phục dự án](docs/KHOI_PHUC_DU_AN.md)**. Tài liệu nêu môi trường đã kiểm tra, lệnh build và những dữ liệu/khóa cần giữ ngoài Git.

- Flutter SDK có Dart tương thích với ràng buộc trong `pubspec.yaml` (`^3.5.4` trở lên).
- Git và một project Supabase.

Kiểm tra môi trường Flutter:

```bash
flutter doctor
```

Clone nhánh `main`:

```bash
git clone --branch main --single-branch https://github.com/Chilliess/Ungdungquanlylichhoc.git
cd Ungdungquanlylichhoc
flutter pub get
```

Sau khi cấu hình Supabase, chạy ứng dụng trên thiết bị hoặc emulator đã kết nối:

```bash
flutter run
```

## Cấu hình Supabase

### Database mới

1. Tạo project trên [Supabase](https://supabase.com/).
2. Mở **SQL Editor → New query** trong Supabase Dashboard.
3. Chạy toàn bộ `supabase_database.sql` một lần để tạo các bảng, chính sách RLS và hàm SQL mà ứng dụng sử dụng.

### Database đã tồn tại

Đọc [`backend/README.md`](backend/README.md), kiểm tra schema hiện tại và áp dụng
các khối transaction còn thiếu trong `supabase_database.sql`. Đây là file SQL duy
nhất của dự án. Các truy vấn kiểm tra nằm trong [`backend/DATABASE_CHECKS.md`](backend/DATABASE_CHECKS.md).
Không chạy lại các định nghĩa cũ sau các bản cập nhật ở cuối file.

### Kết nối ứng dụng

Ứng dụng khởi tạo Supabase trong `lib/main.dart`. Cập nhật `url` và `anonKey` bằng Project URL và publishable key (hoặc anon key) của project Supabase bạn vừa tạo, sau đó chạy lại ứng dụng.

Ứng dụng Flutter là client công khai: **không** đặt `service_role` key, database password hoặc secret key trong mã ứng dụng. Kiểm tra RLS trước khi dùng dữ liệu thật; trong SQL tổng hiện tại, các bảng lịch, môn, nhắc và nhãn giới hạn truy cập theo chủ sở hữu, và `profiles` chỉ cho phép người dùng đọc hồ sơ của chính mình. Nếu bật xác nhận email hoặc khôi phục mật khẩu, cấu hình email và URL chuyển hướng tương ứng trong Supabase Auth.

### Đăng nhập Google và Microsoft

1. Trong Supabase Dashboard, bật Google và Azure (Microsoft) ở **Authentication → Providers** và nhập thông tin OAuth của từng nhà cung cấp.
2. Thêm URL callback hiển thị trong Supabase vào danh sách redirect URI của Google/Azure.
3. Thêm `com.example.untitled://login-callback/` vào **Authentication → URL Configuration → Redirect URLs**. Khi đổi Android `applicationId`, cập nhật đồng thời scheme trong `AndroidManifest.xml` và URL này.
4. Với bản Windows, ứng dụng tự đăng ký callback `com.example.untitled://login-callback/` cho tài khoản Windows hiện tại. Với bản web, thêm domain triển khai vào danh sách redirect URLs. Callback hiện hỗ trợ Android, Windows và web. Không đưa client secret của Google/Azure vào ứng dụng.

## Nhập lịch từ CSV

Tính năng nhập nằm trong phần cài đặt. Tệp cần có dòng tiêu đề ở dòng đầu tiên; ứng dụng đọc các cột theo vị trí từ A đến J:

| Cột | Nội dung | Ví dụ |
|---|---|---|
| A | Mã môn học | `INT101` |
| B | Tên môn học | `Lập trình C` |
| C | Màu Hex (có thể để trống) | `#3B82F6` |
| D | Phòng học | `P.302` |
| E | Giảng viên | `Nguyễn Văn A` |
| F | Ngày trong tuần | `2,4` hoặc `[2,4]` |
| G | Giờ bắt đầu | `07:00` |
| H | Giờ kết thúc | `09:30` |
| I | Ngày bắt đầu | `2026-01-01` hoặc `01/01/2026` |
| J | Ngày kết thúc | `2026-06-30` hoặc `30/06/2026` |

Quy ước ngày trong tuần: Thứ hai = `2`, Thứ ba = `3`, ..., Thứ bảy = `7`, Chủ nhật = `8`. Tệp có thể dùng dấu phẩy hoặc dấu chấm phẩy làm dấu phân cách. Khi lưu từ Excel, chọn **CSV UTF-8** để giữ tiếng Việt.

Ví dụ dòng tiêu đề và một buổi học:

```csv
Mã môn học,Tên môn học,Màu,Phòng học,Giảng viên,Ngày trong tuần,Giờ bắt đầu,Giờ kết thúc,Ngày bắt đầu,Ngày kết thúc
INT101,Lập trình C,#3B82F6,P.302,Nguyễn Văn A,"2,4",07:00,09:30,2026-01-01,2026-06-30
```

## Kiểm thử

Chạy toàn bộ kiểm thử Flutter:

```bash
flutter test
node --test backend/tests/study_assistant_groq.test.mjs
```

Các kiểm thử hiện có bao phủ quy tắc lịch lặp, thống kê, service trang chủ, tài khoản, biên tập lịch, nhãn phân loại và tương tác giao diện.

Kiểm tra phân tích mã Dart:
```bash
flutter analyze
```
## Lưu ý

- Thông báo nền/báo thức hiện hỗ trợ Android; web/Windows có danh sách thông báo trong app. Sau khi thay đổi lịch, mở Nhắc nhở và làm mới để cập nhật lịch nhắc trên thiết bị.
- Google/Microsoft OAuth cần được bật và cấu hình trong Supabase trước khi sử dụng.
- Khi thêm hoặc nâng cấp chức năng Supabase, cần cập nhật schema tương ứng bằng SQL tổng cho database mới hoặc migration cho database hiện có.

## Tác giả

- Đỗ Việt Dũng - 23010547
- Phạm Tiến Chiêu - 23010526
