# Tải lại và dựng dự án từ GitHub

## Những gì được giữ trong Git

Mã Flutter, mã Edge Functions, `supabase_database.sql`, kiểm thử, logo, sơ đồ
trong `so_do/`, cấu hình nền tảng và tài liệu. Giữ `pubspec.lock` để dùng lại
các phiên bản thư viện đã kiểm tra. Bộ nhớ đệm, build, APK/ZIP và thông tin đăng
nhập của CLI không nằm trong Git; có thể tạo lại.

Môi trường đã kiểm tra: Flutter **3.47.5**, Dart **3.13.4**, JDK **17**.
Android dùng compile SDK 35; Gradle/AGP/Kotlin được ghi trong cấu hình dự án.
Windows cần Visual Studio có workload **Desktop development with C++** và
Windows SDK. Node.js/npm cần khi triển khai Cloudflare hoặc Supabase CLI.

## 1. Tải lại mã nguồn

```powershell
git clone https://github.com/Chilliess/Ungdungquanlylichhoc.git
cd Ungdungquanlylichhoc
flutter doctor -v
flutter pub get
flutter analyze
flutter test
node --test backend/tests/study_assistant_groq.test.mjs backend/tests/import_timetable_groq.test.mjs
```

Thiết lập `JAVA_HOME` hoặc JDK của Flutter trên máy mới nếu cần. Không đặt đường
dẫn JDK cá nhân vào `android/gradle.properties` và không commit `local.properties`.
Mở thư mục gốc bằng VS Code với extension Flutter/Dart hoặc dùng `flutter run`.

## 2. Dữ liệu và dịch vụ đang chạy

**Xóa thư mục mã nguồn trên máy không xóa Supabase hoặc Cloudflare.** Nếu tiếp
tục dùng project hiện tại, URL và publishable key trong `lib/main.dart` vẫn
trỏ đến dữ liệu trên máy chủ. Publishable/anon key là cấu hình client công khai;
không thay bằng `service_role` hoặc secret key.

Nếu tạo Supabase project mới:

1. Chạy `supabase_database.sql` trong SQL Editor của project **mới**.
2. Đổi Project URL và publishable key trong `lib/main.dart`.
3. Triển khai các hàm cần dùng bằng `backend/deploy.ps1`.
4. Cấu hình Edge Function Secrets và OAuth theo các tài liệu trong `backend/`.
5. Nếu dùng tự động xóa tài khoản sau hạn, cấu hình worker/Vault/Cron theo
   `backend/ACCOUNT_DELETION_SETUP.md`; chạy SQL không tự bật lịch Cron.

Với database **đã có dữ liệu**, đọc `backend/DATABASE_CHECKS.md`, sao lưu và chỉ
áp dụng khối nâng cấp còn thiếu; không chạy lại tùy tiện toàn bộ SQL.

Các dữ liệu sau **không được Git sao lưu**:

- Tài khoản, lịch và dữ liệu trong Supabase: cần bản sao lưu database riêng nếu
  muốn phòng trường hợp mất project/dữ liệu máy chủ.
- API key, OAuth client secret, mật khẩu database và Vault secrets: quản lý ở
  nhà cung cấp hoặc kho mật khẩu riêng. Không đưa vào repository công khai.
- Thay đổi công việc/chat còn chờ đồng bộ và trạng thái đọc thông báo trên thiết
  bị: đồng bộ thành công trước khi xóa dữ liệu trình duyệt hay gỡ ứng dụng.
- Khóa ký Android: demo đang dùng debug key, thường ở `%USERPROFILE%\.android\debug.keystore`,
  ngoài thư mục dự án. Muốn giữ khả năng cập nhật đè cùng ứng dụng khi đổi máy
  phải giữ khóa ký riêng an toàn. Không commit keystore.

## 3. Tạo lại bản demo

```powershell
flutter build web --release
flutter build windows --release
flutter build apk --release
```

Chạy lệnh phù hợp với nền tảng đang dùng. Kết quả:

| Bản | Vị trí |
| --- | --- |
| Web | `build/web/` |
| Windows | `build/windows/x64/runner/Release/QuanLyLichHoc.exe` |
| Android | `build/app/outputs/flutter-apk/app-release.apk` |

Windows cần **toàn bộ** thư mục Release, gồm `data/` và DLL, không chỉ tệp EXE.
Máy nhận cần Visual C++ Runtime x64, hoặc các DLL runtime được phép phân phối
đi kèm như bộ demo cũ. APK hiện để cài thử trực tiếp, chưa phải bản Google Play.

Logo đã có sẵn trong Git. Khi sửa hình vẽ trong `lib/widgets/app_logo.dart`,
xuất lại biểu tượng bằng `flutter test tool/export_app_icons.dart` rồi build lại.

## 4. Đăng nhập công cụ và triển khai lại khi cần

```powershell
npx supabase login
npx supabase link --project-ref MA_PROJECT_CUA_BAN
.\backend\deploy.ps1 -ProjectRef MA_PROJECT_CUA_BAN -Functions study-assistant,import-timetable,delete-account,purge-accounts

npx wrangler login
flutter build web --release
npx wrangler deploy
```

Thay `MA_PROJECT_CUA_BAN` bằng project ref. Xem lại tên Worker trong
`wrangler.jsonc` nếu triển khai sang tài khoản mới. Những lệnh deploy làm thay đổi
dịch vụ đang chạy; chỉ thực hiện khi thực sự muốn cập nhật. `.wrangler/` và
`supabase/.temp/` được công cụ tạo lại sau đăng nhập/liên kết, không cần commit.

Trợ lý cần `GROQ_API_KEY`, `GROQ_MODEL`; ảnh trong chat tùy cấu hình
`GROQ_VISION_MODEL`. Nhập ảnh/PDF qua `import-timetable` cũng dùng
`GROQ_API_KEY` và vision model này; PDF được kết xuất thành ảnh trên thiết bị
(tối đa 15 trang, 5 MB). Không cần OpenAI key cho chức năng AI. Các giá trị bí
mật đã đặt trên Supabase vẫn ở đó sau khi xóa thư mục code; không đưa chúng vào Git.

## 5. Trước khi xóa bản trên máy

1. Xác nhận `git status -sb` không còn thay đổi cần giữ và không còn `ahead`.
2. Kiểm tra commit mới đã xuất hiện trên GitHub.
3. Đảm bảo công việc/chat đã đồng bộ; lưu riêng dữ liệu hoặc khóa ký cần giữ.
4. Giữ quyền truy cập tài khoản GitHub, Supabase, Cloudflare và nhà cung cấp AI.

Repository có mã cho Linux/macOS nhưng các bản demo hiện kiểm tra và đóng gói
cho web, Android, Windows. Không coi các thư mục nền tảng khác là bản phát hành
đã được kiểm thử.
