# 🔐 TaoMaoOTP & DangKyTaiKhoan - Hệ Thống Xác Thực Đăng Ký Tài Khoản qua Mã OTP Thời Gian Thực

Giải pháp xác thực OTP 2 chiều khép kín giữa Ứng dụng Khách hàng và Hệ thống Tổng đài Cấp mã OTP.
- **Môn học:** Lập trình trên thiết bị di động
- **Dự án:** Hệ thống Tạo & Xác thực mã OTP thời gian thực

---

## 🌟 Giới thiệu Dự án

**TaoMaoOTP & DangKyTaiKhoan** là hệ thống đăng ký tài khoản và cấp mã xác thực OTP thời gian thực được thiết kế chuyên biệt cho quy trình đăng ký người dùng bảo mật trên môi trường di động. Dự án giải quyết bài toán giao tiếp 2 chiều giữa thiết bị Khách hàng và Hệ thống Tổng đài xác thực với các giải pháp công nghệ nổi bật:

- **Đồng bộ Realtime Đa Kênh (Multi-Channel Cloud Sync):** Sử dụng cơ chế truyền tải song song qua các Kênh Cloud Gateway RESTful APIs (`KVDB.io` + `Restful-API Cloud`), triệt tiêu độ trễ truyền tin và đảm bảo 100% tỷ lệ nhận yêu cầu xác thực.
- **Cổng Kết Nối Nội Bộ (Local Gateway Server):** Tích hợp trực tiếp `HttpServer` (mã nguồn mở `dart:io`) chạy ngầm trên cổng 8080, cho phép truyền tải dữ liệu trực tiếp 0.01s trong mạng Wi-Fi/LAN hoặc qua kết nối cáp USB (`adb forward`).
- **Quản lý Vòng đời & Hạn Mã OTP (OTP Lifetime & Timestamp Filter):** Mã OTP có hiệu lực chính xác **1 phút (60 giây)** kèm đồng hồ đếm ngược trực quan. Tự động lọc bỏ mã cũ từ các phiên làm việc trước, chỉ chấp nhận mã OTP được tạo sau thời điểm phát sinh yêu cầu mới.
- **Nhật ký Hệ thống Thời gian thực (Live Debug Console):** Tích hợp bảng console theo dõi nhật ký hoạt động trực tiếp trên app Tổng đài, giúp quan sát và kiểm vết mọi sự kiện kết nối thời gian thực.

---

## 🛠️ Công nghệ Sử dụng (Tech Stack)

### 📱 Frontend & Mobile Apps (Flutter)

- **Framework:** Flutter 3 (Dart 3, Null Safety)
- **Material Design 3:** Thiết kế giao diện phẳng, tối ưu hóa trải nghiệm người dùng với quy trình 3 bước (Stepper Flow).
- **`http`:** Quản lý kết nối RESTful API và giao tiếp dữ liệu đa kênh thời gian thực.
- **`url_launcher` & `flutter_sms`:** Tương tác với ứng dụng Tin nhắn (SMS) mặc định của thiết bị.
- **`dart:io` (`HttpServer` & `NetworkInterface`):** Xây dựng Cổng kết nối HTTP Gateway trực tiếp trên thiết bị di động.
- **`dart:async` (`Timer` & `Polling`):** Quản lý đồng hồ đếm ngược 60s và cơ chế tự động quét yêu cầu thời gian thực.

---

## 🚀 Hướng dẫn Cài đặt & Chạy Ứng dụng

### 1. Cài đặt và Chạy Tổng Đài Cấp Mã (`TaoMaoOTP`)

1. Mở thư mục dự án `taomaotp` trong **Android Studio** hoặc **VS Code**.
2. Tải các thư viện phụ thuộc:
   ```bash
   flutter pub get
   ```
3. Khởi chạy ứng dụng Tổng đài trên máy ảo hoặc thiết bị test:
   ```bash
   flutter run
   ```

### 2. Cài đặt và Chạy App Khách Hàng (`DangKyTaiKhoan`)

1. Mở thư mục dự án `dang_ky_tai_khoan` trong **Android Studio** hoặc **VS Code**.
2. Tải các thư viện phụ thuộc:
   ```bash
   flutter pub get
   ```
3. Khởi chạy ứng dụng Khách hàng trên thiết bị di động thật:
   ```bash
   flutter run
   ```

---

## 👥 Hướng dẫn Luồng Demo (User Flow)

1. **Khách hàng gửi yêu cầu:** 
   - Trên app Khách hàng (`DangKyTaiKhoan`), nhập **Họ tên** và **Số điện thoại đăng ký** (ví dụ: `0901234567`).
   - Bấm **"Yêu Cầu Gửi Mã OTP"**. Màn hình tự động chuyển sang Bước 2 và bật chế độ chờ mã.
2. **Tổng đài nhận & cấp mã OTP:**
   - Trên app Tổng đài (`TaoMaoOTP`), danh sách sẽ tự động quét và hiển thị SĐT yêu cầu mới `0901234567` với nhãn màu đỏ: **"🔴 YÊU CẦU MỚI"**.
   - Admin/Tổng đài bấm **"Cấp & Gửi Mã OTP"**. Mã OTP ngẫu nhiên 6 chữ số (ví dụ: `839210`) sẽ được sinh ra và đồng bộ tức thì.
3. **Khách hàng nhận mã & Hoàn tất đăng ký:**
   - App Khách hàng tự động đồng bộ mã OTP `839210` mới nhất và điền vào ô OTP (kèm đồng hồ đếm ngược 60 giây).
   - Bấm **"Xác Nhận Mã OTP"** ➔ Chuyển sang Bước 3 tạo Mật khẩu ➔ Bấm **"Hoàn tất Đăng ký"** để kết thúc quá trình!
