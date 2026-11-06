# Ứng dụng Quản lý Lịch học (Mobile)

## 1. Giới thiệu

Ứng dụng Quản lý Lịch học là ứng dụng di động được xây dựng bằng Flutter, hướng tới sinh viên cần quản lý thời khóa biểu, lịch kiểm tra, công việc và kế hoạch tự học trong cùng một nơi. Ứng dụng kết nối Supabase để xác thực người dùng và lưu dữ liệu trực tuyến; người dùng có thể xem lịch theo ngày, tháng hoặc năm, tìm kiếm sự kiện, đặt nhắc nhở và theo dõi tiến độ học tập.

Tài liệu này mô tả ứng dụng di động, chức năng, kiến trúc, dữ liệu, cấu hình môi trường và cách kiểm thử để hỗ trợ cài đặt, bảo trì và làm báo cáo dự án.

## 2. Mục tiêu

- Tập trung thời khóa biểu, lịch kiểm tra, công việc và hoạt động tự học trong một ứng dụng.
- Giúp người dùng nhận biết lịch sắp tới, hạn nộp và thời gian dành cho từng môn.
- Hỗ trợ nhiều tài khoản, lưu dữ liệu trên máy chủ và giới hạn quyền truy cập theo chủ sở hữu.
- Cung cấp nhắc nhở trên thiết bị di động để giảm nguy cơ bỏ lỡ buổi học hoặc lịch kiểm tra.
- Hỗ trợ lập kế hoạch học tập có thể xem lại và xác nhận trước khi lưu.

## 3. Đối tượng và phạm vi

Đối tượng sử dụng chính là sinh viên có lịch học theo tuần, lịch kiểm tra theo ngày và nhiều công việc cần theo dõi. Phạm vi tài liệu và hướng dẫn trong README này tập trung vào ứng dụng di động, không mô tả các bản web hoặc máy tính.

Ứng dụng cần kết nối Internet để đăng nhập, tải/lưu dữ liệu Supabase và sử dụng các chức năng AI. Một số tùy chọn giao diện được lưu trên thiết bị. Hàng đợi đồng bộ của khu vực công việc và hội thoại giúp giữ các thay đổi đang chờ gửi khi mất mạng; đây không phải cơ chế đồng bộ thời gian thực.

## 4. Chức năng

### 4.1. Tài khoản

- Đăng ký và đăng nhập bằng email, mật khẩu qua Supabase Auth.
- Đăng nhập/đăng ký bằng Google hoặc Microsoft khi nhà cung cấp OAuth đã được cấu hình.
- Cập nhật tên hiển thị và đổi mật khẩu.
- Gửi yêu cầu khôi phục mật khẩu qua email.
- Yêu cầu xóa tài khoản có thời gian chờ 7 ngày; người dùng có thể đăng nhập để khôi phục trong thời gian chờ. Việc xóa vĩnh viễn phụ thuộc vào worker/Cron và Vault trên Supabase.
- Mật khẩu mới khi đăng ký hoặc đổi mật khẩu cần tối thiểu 8 ký tự. Đăng nhập giữ nguyên nội dung mật khẩu người dùng nhập, không tự loại bỏ khoảng trắng ở đầu/cuối.

### 4.2. Trang chủ

- Hiển thị lời chào, ngày hiện tại và dữ liệu tài khoản.
- Tổng hợp lịch học, lịch kiểm tra trong ngày theo thời gian.
- Hiển thị sự kiện sắp tới, môn học và thông tin như phòng học hoặc giảng viên khi có dữ liệu.
- Cung cấp lối tắt đến lịch, quản lý môn học, tài khoản, nhắc nhở và các công cụ học tập.

### 4.3. Môn học và thời khóa biểu

- Tạo, chỉnh sửa và xóa môn học.
- Lưu mã môn, tên môn và màu nhận diện.
- Tạo các buổi học với ngày trong tuần, giờ bắt đầu/kết thúc, phòng học, giảng viên và khoảng ngày áp dụng.
- Chọn nhiều ngày học trong tuần, tìm môn theo tên hoặc mã và kiểm tra một số điều kiện thời gian/xung đột trong luồng biên tập.
- Chỉnh sửa sự kiện từ màn hình lịch; có thể xóa một sự kiện từ phần chi tiết. Với buổi học lặp, thao tác xóa áp dụng cho cả chuỗi lịch.
- Khi xóa môn học, các lịch học, lịch kiểm tra và nhắc nhở liên quan được dọn theo quy tắc cơ sở dữ liệu.

### 4.4. Lịch học và lịch kiểm tra

- Xem lịch tổng hợp theo ngày, tháng và năm; tìm kiếm, mở chi tiết và chỉnh sửa sự kiện.
- Tạo lịch kiểm tra theo ngày cụ thể, có thể ghi phòng, giám thị, ghi chú và nhãn.
- Hỗ trợ quy tắc lặp không lặp, hằng ngày, hằng tuần, hằng tháng hoặc hằng năm.
- Cho phép đặt ngày kết thúc hoặc để trống để không giới hạn ngày kết thúc.
- Lịch lặp theo tháng/năm bỏ qua ngày không tồn tại, ví dụ ngày 31 trong tháng chỉ có 30 ngày.
- Lịch cũ chưa có quy tắc lặp mới tiếp tục dùng các ngày trong tuần và khoảng ngày đã lưu.

### 4.5. Nhãn, giao diện và nhắc nhở

- Tạo nhãn có màu để phân loại sự kiện; đổi tên hoặc xóa nhãn cập nhật các sự kiện liên quan.
- Chọn giao diện sáng/tối; tùy chọn chủ đề và một số thiết lập hiển thị được lưu trên thiết bị.
- Cấu hình nhắc trước sự kiện theo các mốc 5, 10, 15, 30, 60 hoặc 120 phút.
- Ứng dụng dùng thông báo cục bộ trên thiết bị; quyền thông báo có thể cần được cấp trong hệ điều hành.
- Cơ chế thông báo cần các quyền hệ điều hành tương ứng để gửi thông báo đã lên lịch và khôi phục chúng sau khi thiết bị khởi động lại.
- Danh sách thông báo trong ứng dụng có thể hiển thị nhắc nhở đến hạn và sự kiện trong 7 ngày tới; trạng thái đã đọc được lưu trên thiết bị.

### 4.6. Công việc và tự học

- Tạo công việc có hạn nộp, thời lượng, độ khó, trạng thái hoàn thành và liên kết môn học.
- Lọc công việc theo môn học.
- Tự xếp lịch trong 14 ngày, xét lịch học/lịch kiểm tra và hạn nộp; một phiên tối đa 50 phút, có thời gian nghỉ 10 phút.
- Xem trước kế hoạch trước khi xác nhận lưu.
- Dùng chế độ Tập trung để ghi nhận thời gian thực học.
- Công việc, phiên học, nhật ký, mục tiêu và lịch sử chat có thể đồng bộ theo tài khoản; các thay đổi chờ gửi được lưu để đồng bộ lại.

### 4.7. Thống kê và trợ lý AI

- Thống kê số buổi và tổng thời lượng theo tuần hoặc tháng, có phân tích theo môn và ngày.
- Việc tính lịch lặp dựa trên những ngày lịch thực sự diễn ra trong khoảng thống kê.
- Trợ lý AI có thể trả lời câu hỏi; khi bật **Lịch của tôi**, trợ lý được cung cấp ngữ cảnh lịch của tài khoản để hỗ trợ tư vấn.
- AI có thể chuẩn bị đề xuất tạo/xóa lịch. Người dùng phải xem xét và bấm **Áp dụng** trước khi thay đổi được ghi vào dữ liệu.
- Nhập ảnh trong hội thoại cần dịch vụ/model Groq hỗ trợ. Nhập ảnh/PDF từ chức năng nhập lịch cần Edge Function và cấu hình OpenAI riêng.
- AI không thực hiện tra cứu web.

## 5. Luồng sử dụng chính

1. Cài ứng dụng, mở ứng dụng và đăng ký hoặc đăng nhập.
2. Tạo môn học, sau đó thêm các buổi học; có thể nhập dữ liệu thời khóa biểu bằng CSV.
3. Mở màn hình Lịch để xem lịch học và lịch kiểm tra; thêm ghi chú, nhãn hoặc quy tắc lặp khi cần.
4. Thiết lập nhắc nhở và cấp quyền thông báo cho ứng dụng trong phần cài đặt thiết bị.
5. Tạo công việc, xem đề xuất tự xếp lịch và xác nhận kế hoạch phù hợp.
6. Theo dõi thống kê hoặc dùng trợ lý AI; kiểm tra kỹ các đề xuất lịch trước khi áp dụng.

## 6. Công nghệ và kiến trúc

### 6.1. Công nghệ sử dụng

- **Ứng dụng di động:** Flutter và Dart, giao diện Material.
- **Xác thực, cơ sở dữ liệu:** Supabase Auth, PostgreSQL, Row Level Security (RLS) và các hàm SQL/RPC.
- **Thông báo cục bộ:** `flutter_local_notifications`, `timezone`, `flutter_timezone`.
- **Liên kết OAuth:** `app_links`.
- **Lịch và ngày giờ:** `calendar_view`, `intl`.
- **Lưu cài đặt trên máy:** `shared_preferences`.
- **Nhập tệp và CSV:** `file_picker`, `csv`.
- **Backend bổ trợ:** Supabase Edge Functions cho trợ lý AI, nhập ảnh/PDF và vòng đời tài khoản.

### 6.2. Các lớp chính

1. **Giao diện:** các màn hình trong `lib/screen/`, `lib/auth/` và widget trong `lib/widgets/` nhận thao tác và hiển thị trạng thái.
2. **Model:** `lib/models/` biểu diễn dữ liệu lịch, quy tắc lặp, thống kê và dữ liệu dùng chung.
3. **Service:** `lib/services/` tập trung truy cập dữ liệu, tùy chọn, đồng bộ và xử lý nghiệp vụ dùng chung.
4. **Supabase:** Auth xác định người dùng; PostgreSQL lưu dữ liệu; RLS/RPC kiểm soát quyền và các thao tác cần cập nhật nhiều bản ghi.
5. **Edge Functions:** xử lý các chức năng cần bí mật hoặc logic phía máy chủ. Khóa dịch vụ không được đặt trong ứng dụng di động.

### 6.3. Cấu trúc thư mục liên quan

```text
lib/
├── auth/       # Đăng nhập, đăng ký, OAuth và khôi phục mật khẩu
├── models/     # Mô hình dữ liệu lịch, thông báo và thống kê
├── screen/     # Màn hình lịch, môn học, tài khoản, công việc và cài đặt
├── services/   # Supabase, dữ liệu học tập, đồng bộ và tùy chọn
├── splash/     # Khởi động và kiểm tra phiên đăng nhập
├── theme/      # Chủ đề giao diện
├── widgets/    # Widget dùng chung, chat và thông báo
└── main.dart   # Khởi tạo Supabase, locale, tùy chọn và ứng dụng

android/
├── app/        # Cấu hình nền tảng di động, quyền và callback OAuth
└── gradle/     # Gradle Wrapper

backend/
├── functions/  # Edge Functions
└── tests/      # Kiểm thử backend giả lập

supabase_database.sql # Schema, RLS, RPC, trigger và cấu hình database
test/                  # Kiểm thử Flutter
```

### 6.4. Các tệp quan trọng

| Tệp | Trách nhiệm |
|---|---|
| `lib/main.dart` | Khởi tạo Flutter, Supabase, locale và tùy chọn ứng dụng |
| `lib/homescreen.dart` | Trang chủ và lịch tổng hợp trong ngày |
| `lib/screen/view_schedule_screen.dart` | Hiển thị và thao tác với lịch |
| `lib/screen/lesson_editor.dart` | Tạo/sửa sự kiện, ghi chú, nhãn và lịch lặp |
| `lib/screen/subject_management_screen.dart` | Quản lý môn học và lịch theo nhóm |
| `lib/screen/schedule_announcement.dart` | Cài đặt và lên lịch nhắc nhở trên thiết bị |
| `lib/screen/tasks_screen.dart` | Công việc, kế hoạch tự học và chế độ tập trung |
| `lib/screen/statistical.dart` | Thống kê học tập |
| `lib/widgets/assistant_overlay.dart` | Giao diện trợ lý AI |
| `lib/services/study_data.dart` | Tải dữ liệu học tập theo chủ sở hữu |
| `lib/services/workspace_sync.dart` | Đồng bộ dữ liệu công việc và workspace |
| `lib/models/schedule_recurrence.dart` | Quy tắc xuất hiện của lịch lặp |
| `android/app/src/main/AndroidManifest.xml` | Cấu hình nền tảng mobile, quyền hệ điều hành và OAuth callback |
| `supabase_database.sql` | Cấu trúc và logic cơ sở dữ liệu Supabase |

## 7. Dữ liệu và bảo vệ quyền truy cập

### 7.1. Các bảng dữ liệu chính

| Bảng | Nội dung |
|---|---|
| `profiles` | Tên hiển thị gắn với tài khoản Supabase Auth |
| `subjects` | Môn học, mã môn và màu |
| `schedules` | Buổi học, thời gian, ngày trong tuần, khoảng ngày và thông tin lặp |
| `schedule_exams` | Lịch kiểm tra theo ngày cụ thể |
| `reminders` | Cấu hình và loại sự kiện được nhắc |
| `calendar_categories` | Nhãn và màu do tài khoản quản lý |
| `workspace_items` | Công việc, phiên học, nhật ký, mục tiêu và lịch sử chat |
| `assistant_daily_usage` | Hạn mức sử dụng AI phía máy chủ |
| `account_deletion_requests` | Yêu cầu xóa tài khoản và thời hạn khôi phục |
| `assistant_calendar_actions` | Biên nhận ngăn áp dụng lặp thao tác lịch do AI đề xuất |

### 7.2. Quan hệ và đồng bộ

- Lịch học và lịch kiểm tra liên kết với môn học qua `subject_id`.
- Dữ liệu cá nhân được gắn với `user_id`; chính sách RLS giới hạn quyền đọc/ghi theo tài khoản.
- Các thao tác nhiều bước như lưu thời khóa biểu hoặc xóa môn dùng RPC/trigger để duy trì quan hệ dữ liệu.
- Dữ liệu công việc và hội thoại được đồng bộ theo tài khoản. Khi xung đột, chiến lược hiện tại là bản ghi cập nhật sau cùng được giữ; ứng dụng chưa cung cấp đồng bộ realtime.
- Một số cài đặt, trạng thái thông báo và tùy chọn giao diện lưu trên thiết bị thay vì trong các bảng cloud.

### 7.3. Quy tắc lịch

- Các thứ trong tuần được lưu theo quy ước của ứng dụng: Thứ hai = `2`, ..., Thứ bảy = `7`, Chủ nhật = `8`.
- Lịch tuần dùng tập ngày đã chọn. Quy tắc lặp mới lưu `recurrence` với giá trị `none`, `daily`, `weekly`, `monthly` hoặc `yearly`.
- `end_date` để trống nghĩa là lịch không có ngày kết thúc được đặt trước.
- Cùng quy tắc lặp được dùng khi dựng lịch, tổng hợp trang chủ và tính thống kê.

## 8. Cài đặt và chạy ứng dụng di động

### 8.1. Yêu cầu môi trường phát triển

- Flutter SDK và Dart tương thích với khai báo trong `pubspec.yaml` (`^3.5.4` trở lên, dưới Dart 4).
- Flutter SDK và bộ công cụ build cho nền tảng di động mục tiêu.
- Thiết bị di động hoặc trình giả lập tương ứng được kết nối với máy phát triển.
- Project Supabase đã được cấu hình nếu cần đăng nhập và lưu dữ liệu thật.

Kiểm tra Flutter và thiết bị:

```bash
flutter doctor
flutter devices
```

### 8.2. Tải mã nguồn và cài dependency

```bash
git clone --branch main --single-branch https://github.com/Chilliess/Ungdungquanlylichhoc.git
cd Ungdungquanlylichhoc
flutter pub get
```

### 8.3. Cấu hình Supabase

1. Tạo project trong [Supabase](https://supabase.com/).
2. Với database mới, chạy `supabase_database.sql` trong **SQL Editor**. Với database đang sử dụng, đọc `backend/README.md` và chỉ áp dụng các khối cập nhật còn thiếu.
3. Cấu hình Project URL và publishable key (hoặc anon key) trong phần khởi tạo Supabase của `lib/main.dart`.
4. Kiểm tra các chính sách RLS và cấu hình Auth trước khi dùng dữ liệu thật.
5. Chỉ đưa key công khai dành cho client vào ứng dụng. Không đưa `service_role`, mật khẩu database, khóa OpenAI/Groq hoặc secret của Edge Function vào mã Flutter.

Các luồng cơ bản cần Supabase Auth và database. Trợ lý AI, nhập ảnh/PDF và xóa tài khoản sau thời gian chờ còn cần triển khai Edge Functions, secrets và tác vụ máy chủ tương ứng. Tham khảo `backend/README.md`, `backend/ASSISTANT_SETUP.md` và `backend/ACCOUNT_DELETION_SETUP.md`.

### 8.4. Cấu hình đăng nhập Google/Microsoft

1. Bật Google và Azure (Microsoft) trong **Supabase Dashboard → Authentication → Providers**.
2. Cấu hình OAuth client ở nhà cung cấp và thêm callback URL Supabase theo hướng dẫn của Dashboard.
3. Thêm `com.example.untitled://login-callback/` vào **Authentication → URL Configuration → Redirect URLs**.
4. Đảm bảo callback được khai báo trong cấu hình nền tảng di động và URI trong `lib/services/social_auth.dart` cùng khớp với cấu hình Supabase.
5. Không đưa client secret của Google/Microsoft vào ứng dụng.

Scheme callback là cấu hình deep link riêng, không bắt buộc phải trùng mã định danh ứng dụng. Nếu đổi scheme, phải cập nhật đồng bộ cấu hình nền tảng, mã OAuth và Redirect URLs trên Supabase.

### 8.5. Chạy và đóng gói ứng dụng

Chạy ứng dụng trên thiết bị hoặc trình giả lập đã kết nối:

```bash
flutter run
```

Lệnh build và định dạng gói cài đặt phụ thuộc nền tảng mục tiêu đã cấu hình trong dự án. Cấu hình hiện có tạo APK release bằng lệnh:

```bash
flutter build apk --release
```

Tệp cài đặt được tạo tại:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Có thể tải bản cài đặt đã phát hành từ [GitHub Releases](https://github.com/Chilliess/Ungdungquanlylichhoc/releases/latest). Cách cài đặt phụ thuộc định dạng gói và thiết bị; bản tải trực tiếp không đồng nghĩa với việc ứng dụng đã được phát hành qua cửa hàng ứng dụng.

## 9. Nhập thời khóa biểu bằng CSV

Tính năng nhập lịch nằm trong phần cài đặt. Tệp cần có dòng tiêu đề ở dòng đầu tiên; ứng dụng đọc các cột theo vị trí A đến J:

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

Tệp có thể dùng dấu phẩy hoặc dấu chấm phẩy làm dấu phân cách. Bộ nhận diện dấu phân cách xem dòng tiêu đề và bỏ qua dấu nằm trong trường được đặt trong dấu ngoặc kép. Khi xuất từ Excel, nên chọn **CSV UTF-8** để giữ đúng tiếng Việt.

Ví dụ:

```csv
Mã môn học,Tên môn học,Màu,Phòng,Giảng viên,Ngày trong tuần,Giờ bắt đầu,Giờ kết thúc,Ngày bắt đầu,Ngày kết thúc
INT101,Lập trình C,#3B82F6,P.302,Nguyễn Văn A,"2,4",07:00,09:30,2026-01-01,2026-06-30
```

## 10. Kiểm thử và kiểm tra chất lượng

Chạy kiểm thử Flutter:

```bash
flutter test
```

Phân tích mã Dart:

```bash
flutter analyze
```

Kiểm thử backend giả lập:

```bash
node --test backend/tests/study_assistant_groq.test.mjs
```

Kiểm thử Flutter bao phủ các phần như quy tắc lịch lặp, thống kê, đồng bộ, xác thực, tài khoản, biên tập lịch và tương tác giao diện. Kiểm thử backend giả lập không gọi dịch vụ Supabase/Groq thật; các luồng tích hợp vẫn cần được kiểm tra trên project staging với tài khoản thử nghiệm.

## 11. Giới hạn và công việc cần lưu ý

- Thông báo lịch cục bộ phụ thuộc khả năng và quyền mà hệ điều hành trên thiết bị cung cấp. Hiện việc làm mới toàn bộ lịch nhắc được thực hiện khi mở màn hình **Nhắc nhở**; thay đổi lịch ở màn hình khác có thể chưa được phản ánh ngay cho tới khi làm mới.
- Quyền thông báo và quyền lên lịch chính xác phụ thuộc phiên bản hệ điều hành, thiết lập của người dùng và chính sách của thiết bị.
- OAuth chỉ hoạt động sau khi cấu hình đúng provider, callback URL và deep link.
- Xóa tài khoản sau 7 ngày chỉ hoàn tất khi worker/Cron và Vault đã được cấu hình. Chỉ gửi yêu cầu trên ứng dụng không đảm bảo dữ liệu đã được xóa vĩnh viễn khỏi máy chủ.
- Trợ lý AI và nhập ảnh/PDF cần cấu hình dịch vụ máy chủ; các tính năng này không hoạt động đầy đủ chỉ bằng cách chạy SQL.
- Chiến lược xử lý xung đột workspace là bản cập nhật sau cùng thắng; chưa có giao diện hợp nhất xung đột.
- Cấu hình nền tảng mobile hiện dùng mã định danh `com.example.untitled`; cần đổi sang định danh riêng và cập nhật deep link tương ứng trước khi phát hành chính thức.
- Cấu hình build hiện có dùng debug signing. Gói hiện tại phù hợp cho kiểm thử/cài đặt nội bộ; cần thiết lập khóa ký phát hành riêng và bảo vệ khóa trước khi phân phối chính thức qua cửa hàng ứng dụng.
- Không commit secret, keystore hoặc mật khẩu ký vào Git.

## 12. Tác giả

- Đỗ Việt Dũng - 23010547
- Phạm Tiến Chiêu - 23010526
