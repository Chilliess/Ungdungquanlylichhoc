# Ứng Dụng Quản Lý Lịch Học & Thời Khóa Biểu (Flutter & Supabase)

Ứng dụng di động được xây dựng bằng **Flutter** kết hợp với **Supabase** làm Backend-as-a-Service, giúp học sinh/sinh viên dễ dàng quản lý lịch học, môn học, thời khóa biểu cá nhân và tự động phát hiện xung đột thời gian (trùng lịch học).

---

## Các Tính Năng Chính

* **Quản lý tài khoản bảo mật:** Đăng nhập, đăng ký, đổi mật khẩu và cập nhật thông tin cá nhân (Tên người dùng) liên kết chặt chẽ với hệ thống Supabase Auth và bảng `profiles`.
* **Quản lý môn học & Lịch học linh hoạt:** Thêm mới, chỉnh sửa thông tin môn học, phòng học, giảng viên và các khung giờ học trong tuần.
* **Thuật toán chống trùng lịch thông minh (Conflict Detection):**
    * Tự động kiểm tra chéo các khung giờ học mới thêm xem có bị đá chân nhau hay không.
    * Đối chiếu trực tiếp với các lịch học đã có sẵn trong cơ sở dữ liệu dựa trên khoảng thời gian (`date overlap`) và ngày trong tuần (`days of week`) bằng logic tối ưu.
* **Thống kê & Theo dõi:** Thống kê các buổi học trực quan.
* **Giao diện thân thiện:** Thiết kế hiện đại, mượt mà, hỗ trợ xử lý trạng thái tải (`loading`) và thông báo lỗi trực quan qua `SnackBar`.

---

## Công Nghệ Sử Dụng

* **Frontend:** Flutter (Dart)
* **Backend & Database:** Supabase (PostgreSQL, Supabase Auth, Row Level Security - RLS)

---

## Cấu Trúc Thư Mục Dự Án

```text
lib/
│
├── auth/                 # Màn hình đăng nhập, đăng ký
├── screen/               # Các màn hình chính của ứng dụng
│   ├── account_screen.dart          # Quản lý tài khoản & đổi mật khẩu
│   ├── home_screen.dart             # Màn hình chính & chào người dùng
│   ├── schedule_management_screen.dart # Thêm/Sửa lịch học & thuật toán chống trùng
│   ├── subject_management_screen.dart  # Quản lý môn học
│   ├── view_schedule_screen.dart    # Xem lịch học tổng quan
│   └── statistical.dart             # Thống kê buổi học
│
└── main.dart             # Khởi chạy ứng dụng và cấu hình Supabase
```

---

## Hướng Dẫn Cài Đặt & Chạy Dự Án

1. **Clone repository về máy:**
   ```bash
   git clone https://github.com/Chilliess/Ungdungquanlylichhoc.git
   ```
2. **Cài đặt các gói phụ thuộc (Dependencies):**
   ```bash
   flutter pub get
   ```
3. **Cấu hình Supabase:**
    * Tạo một dự án mới trên [Supabase](https://supabase.com).
    * Mở file supabase_database.sql có trong project rồi copy và chạy trên Supabase.
    * Chỉnh lại đường dẫn url và anonKey ở main.dart theo database trên Supabase của bạn.
4. **Chạy ứng dụng:**
   ```bash
   flutter run
   ```

---

## Tác Giả & Phát Triển
Dự án được phát triển bởi:
* **Đỗ Việt Dũng - 23010547**.
* **Phạm Tiến Chiêu - 23010526**.