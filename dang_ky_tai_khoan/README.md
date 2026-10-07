# 🔐 DangKyTaiKhoan & TaoMaoOTP - Hệ Thống Xác Thực Đăng Ký Tài Khoản qua Mã OTP Thời Gian Thực

Ứng dụng Khách hàng trong Hệ thống Xác thực Đăng ký Tài khoản và Cấp mã OTP thời gian thực.
- **Môn học:** Lập trình trên thiết bị di động
- **Dự án:** Hệ thống Tạo & Xác thực mã OTP thời gian thực

---

## 🌟 Giới thiệu Dự án

**DangKyTaiKhoan** là ứng dụng di động dành cho Khách hàng thực hiện quy trình đăng ký tài khoản bảo mật 3 bước (Thông tin cá nhân ➔ Xác thực OTP ➔ Mật khẩu). Ứng dụng tích hợp cơ chế đồng bộ đa kênh thời gian thực với Tổng đài cấp mã OTP (`TaoMaoOTP`), mang lại trải nghiệm mượt mà và an toàn.

### Tính năng nổi bật:
- **Quy trình 3 Bước Chuyên Nghiệp:** Giao diện Stepper trực quan, hướng dẫn người dùng từng bước thao tác dễ dàng.
- **Đồng bộ OTP Tự động Realtime:** Tự động lắng nghe và tải mã OTP xác thực mới từ hệ thống ngay khi được tổng đài duyệt cấp.
- **Đếm Ngược Thời Gian Hiệu Lực 60 Giây:** Hiển thị đồng hồ đếm ngược 1 phút cho mã OTP. Tự động hủy mã khi hết hạn để đảm bảo an toàn.
- **Lọc Mã OTP Cũ Thông Minh:** Tự động nhận diện và bỏ qua các mã OTP được tạo từ trước, chỉ chấp nhận mã OTP mới ứng với yêu cầu hiện tại.

---

## 🛠️ Công nghệ Sử dụng (Tech Stack)

- **Framework:** Flutter 3 (Dart 3, Null Safety)
- **UI & UX:** Material Design 3 (Form Validation, Stepper Flow, Animated Countdown)
- **`http`:** Giao tiếp RESTful API thời gian thực với Kênh Cloud Gateway & Local Gateway Server.
- **`dart:async`:** Quản lý đếm ngược thời gian thực (`Timer.periodic`) và tự động kiểm tra đồng bộ ngầm.

---

## 🚀 Hướng dẫn Cài đặt & Khởi Chạy

1. Mở thư mục `dang_ky_tai_khoan` bằng **Android Studio** hoặc **VS Code**.
2. Tải gói thư viện:
   ```bash
   flutter pub get
   ```
3. Chạy ứng dụng trên thiết bị di động:
   ```bash
   flutter run
   ```
