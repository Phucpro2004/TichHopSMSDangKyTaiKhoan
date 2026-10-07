import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

// Model lưu thông tin người dùng đã đăng ký thành công
class UserAccount {
  final String fullName;
  final String phoneNumber;
  final String password;

  UserAccount({
    required this.fullName,
    required this.phoneNumber,
    required this.password,
  });
}

class UserDatabase {
  static final List<UserAccount> registeredUsers = [];
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Đăng Ký & Đăng Nhập OTP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

// ============================================================================
// 1. MÀN HÌNH ĐĂNG NHẬP
// ============================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _errorMessage = "";

  void _handleLogin() {
    String phone = _phoneController.text.trim();
    String password = _passwordController.text.trim();

    if (phone.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = "Vui lòng nhập đầy đủ số điện thoại và mật khẩu!";
      });
      return;
    }

    UserAccount? user;
    try {
      user = UserDatabase.registeredUsers.firstWhere(
        (u) => u.phoneNumber == phone && u.password == password,
      );
    } catch (e) {
      user = null;
    }

    if (user != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(user: user!),
        ),
      );
    } else {
      setState(() {
        _errorMessage = "Số điện thoại hoặc mật khẩu không chính xác!";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đăng Nhập Tài Khoản'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Icon(Icons.account_circle, size: 90, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'Chào mừng quay trở lại!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),

            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _handleLogin,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              child: const Text('Đăng Nhập'),
            ),

            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
              ),
            ],

            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Chưa có tài khoản? '),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const RegisterScreen()),
                    );
                  },
                  child: const Text(
                    'Đăng ký ngay',
                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 2. MÀN HÌNH ĐĂNG KÝ KHÁCH HÀNG
// ============================================================================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _currentStep = 1; // 1: Thông tin, 2: OTP, 3: Mật khẩu

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  static const String defaultServerIp = '172.20.10.4:8080';
  final TextEditingController _serverIpController = TextEditingController(text: defaultServerIp);

  String _normalizeServerUrl(String input) {
    String url = input.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  bool _isLoading = false;
  String _generatedOtp = "";
  String _statusMessage = "";
  Timer? _otpCheckTimer;
  Timer? _countdownTimer;
  int _secondsRemaining = 60;
  DateTime? _requestTimestamp;

  static const String _kvdbBucket = 'KjYiVofyAsNGPKCVd7kvyd';

  @override
  void dispose() {
    _otpCheckTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _secondsRemaining = 60;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (_secondsRemaining > 0) {
          setState(() {
            _secondsRemaining--;
          });
        } else {
          timer.cancel();
          _otpCheckTimer?.cancel();
          setState(() {
            _generatedOtp = "";
            _statusMessage = "⚠️ Mã OTP đã hết hạn (quá 1 phút). Vui lòng yêu cầu gửi mã OTP mới!";
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  // BƯỚC 1: Đẩy Yêu cầu Đăng ký lên tổng đài
  Future<void> _requestOtpFromEmulator() async {
    String fullName = _fullNameController.text.trim();
    String phone = _phoneController.text.trim();

    if (fullName.isEmpty || phone.isEmpty || phone.length < 9) {
      setState(() {
        _statusMessage = "Vui lòng nhập đầy đủ Họ tên và Số điện thoại hợp lệ!";
      });
      return;
    }

    bool phoneExists = UserDatabase.registeredUsers.any((u) => u.phoneNumber == phone);
    if (phoneExists) {
      setState(() {
        _statusMessage = "Số điện thoại này đã được đăng ký trước đó!";
      });
      return;
    }

    // Xóa mã cũ và ghi nhận thời gian yêu cầu mới
    _requestTimestamp = DateTime.now();
    _generatedOtp = "";
    _otpController.clear();

    setState(() {
      _isLoading = true;
      _statusMessage = "Đang kết nối tổng đài để gửi yêu cầu xác thực SĐT $phone...";
    });

    bool isSuccess = false;
    String serverIp = _serverIpController.text.trim();

    // 1. Gửi tới Local IP Server nếu có
    final localUrlBase = _normalizeServerUrl(serverIp);
    if (localUrlBase.isNotEmpty) {
      try {
        final localUrl = Uri.parse('$localUrlBase/request-otp?phone=$phone&name=${Uri.encodeComponent(fullName)}');
        final res = await http.get(localUrl).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) isSuccess = true;
      } catch (_) {}
    }

    // 2. Gửi tới KVDB Store
    try {
      final kvdbUrl = Uri.parse('https://kvdb.io/$_kvdbBucket/latest_request');
      final res = await http.post(
        kvdbUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "fullName": fullName,
          "phone": phone,
          "timestamp": DateTime.now().millisecondsSinceEpoch,
        }),
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 || res.statusCode == 201) isSuccess = true;
    } catch (_) {}

    // 3. Gửi tới Restful-API Cloud
    try {
      final cloudUrl = Uri.parse('https://api.restful-api.dev/objects');
      await http.post(
        cloudUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "name": "TAOMAOTP_REQ_$phone",
          "data": {
            "fullName": fullName,
            "phone": phone,
            "timestamp": DateTime.now().millisecondsSinceEpoch,
          }
        }),
      ).timeout(const Duration(seconds: 4));
      isSuccess = true;
    } catch (_) {}

    if (isSuccess) {
      setState(() {
        _isLoading = false;
        _currentStep = 2;
        _statusMessage = "🎉 YÊU CẦU GỬI MÃ XÁC THỰC THÀNH CÔNG!\nHệ thống đang tạo mã OTP mới cho SĐT $phone (Hiệu lực: 1 phút).";
      });

      _startCountdownTimer();

      // Tự động quét kiểm tra mã OTP mới mỗi 2 giây
      _otpCheckTimer?.cancel();
      _otpCheckTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
        _fetchOtpFromCloud(isBackground: true);
      });

      _fetchOtpFromCloud();
    } else {
      setState(() {
        _isLoading = false;
        _statusMessage = "❌ Không gửi được yêu cầu xác thực! Vui lòng kiểm tra lại kết nối mạng.";
      });
    }
  }

  // BƯỚC 2: Kiểm tra xem tổng đài đã phát mã OTP mới chưa (Loại bỏ mã cũ)
  Future<void> _fetchOtpFromCloud({bool isBackground = false}) async {
    if (_secondsRemaining <= 0) return; // Nếu hết hạn 1 phút thì ngưng nhận

    String phone = _phoneController.text.trim();
    String serverIp = _serverIpController.text.trim();

    if (!isBackground) {
      setState(() {
        _isLoading = true;
        _statusMessage = "Đang nhận mã OTP xác thực...";
      });
    }

    String? foundOtp;
    int? foundTimestampMs;

    // 1. Quét Local IP Server
    final localUrlBase = _normalizeServerUrl(serverIp);
    if (localUrlBase.isNotEmpty) {
      try {
        final localUrl = Uri.parse('$localUrlBase/get-otp?phone=$phone');
        final res = await http.get(localUrl).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          foundOtp = data['otp']?.toString();
          foundTimestampMs = data['timestamp'] as int?;
        }
      } catch (_) {}
    }

    // 2. Quét KVDB Store
    if (foundOtp == null) {
      try {
        final kvdbUrl = Uri.parse('https://kvdb.io/$_kvdbBucket/otp_$phone');
        final res = await http.get(kvdbUrl).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          final data = json.decode(res.body);
          foundOtp = data['otp']?.toString();
          foundTimestampMs = data['timestamp'] as int?;
        }
      } catch (_) {}
    }

    // 3. Quét Restful-API Cloud
    if (foundOtp == null) {
      try {
        final cloudUrl = Uri.parse('https://api.restful-api.dev/objects');
        final res = await http.get(cloudUrl).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final List<dynamic> list = json.decode(res.body);
          final targetName = "TAOMAOTP_OTP_$phone";

          for (var item in list.reversed) {
            if (item['name'] == targetName && item['data'] != null) {
              foundOtp = item['data']['otp']?.toString();
              foundTimestampMs = item['data']['timestamp'] as int?;
              if (foundOtp != null) break;
            }
          }
        }
      } catch (_) {}
    }

    // Kiểm tra lọc bỏ mã cũ tạo trước yêu cầu hiện tại
    if (foundOtp != null && foundOtp.isNotEmpty) {
      if (foundTimestampMs != null) {
        final otpCreatedTime = DateTime.fromMillisecondsSinceEpoch(foundTimestampMs);
        // Nếu mã OTP cũ tạo TRƯỚC thời điểm bấm gửi yêu cầu này -> Bỏ qua mã cũ!
        if (_requestTimestamp != null && otpCreatedTime.isBefore(_requestTimestamp!.subtract(const Duration(seconds: 2)))) {
          if (!isBackground) {
            setState(() {
              _statusMessage = "⏳ Mã OTP cũ đã hết hạn. Đang chờ hệ thống tạo mã OTP mới...";
            });
          }
          if (!isBackground && mounted) setState(() => _isLoading = false);
          return;
        }
      }

      _otpCheckTimer?.cancel();

      setState(() {
        _generatedOtp = foundOtp!;
        _otpController.text = foundOtp;
        _statusMessage = "🎉 THÀNH CÔNG! Đã nhận mã OTP xác thực mới [$foundOtp]!";
      });
    } else {
      if (!isBackground) {
        setState(() {
          _statusMessage = "⏳ Hệ thống đang xử lý mã OTP cho SĐT $phone.\nVui lòng chờ trong giây lát!";
        });
      }
    }

    if (!isBackground && mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // BƯỚC 2: XÁC THỰC MÃ OTP
  void _verifyOtp() {
    if (_secondsRemaining <= 0) {
      setState(() {
        _statusMessage = "❌ Mã OTP đã hết hạn (quá 1 phút). Vui lòng bấm gửi lại yêu cầu mã OTP mới!";
      });
      return;
    }

    String enteredOtp = _otpController.text.trim();

    if (enteredOtp.isEmpty) {
      setState(() {
        _statusMessage = "Vui lòng nhập mã OTP 6 số!";
      });
      return;
    }

    if (enteredOtp.length == 6) {
      if (_generatedOtp.isNotEmpty && enteredOtp != _generatedOtp) {
        setState(() {
          _statusMessage = "❌ Mã OTP nhập vào không chính xác với mã đã cấp!";
        });
        return;
      }
      _otpCheckTimer?.cancel();
      _countdownTimer?.cancel();
      setState(() {
        _currentStep = 3;
        _statusMessage = "✅ Xác nhận mã OTP thành công! Vui lòng tạo mật khẩu.";
      });
    } else {
      setState(() {
        _statusMessage = "❌ Mã OTP phải đủ 6 chữ số!";
      });
    }
  }

  // BƯỚC 3: THIẾT LẬP MẬT KHẨU & HOÀN TẤT ĐĂNG KÝ
  void _completeRegistration() {
    String password = _passwordController.text.trim();
    String confirmPassword = _confirmPasswordController.text.trim();

    if (password.isEmpty || password.length < 6) {
      setState(() {
        _statusMessage = "Mật khẩu phải có ít nhất 6 ký tự!";
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        _statusMessage = "Mật khẩu nhập lại không trùng khớp!";
      });
      return;
    }

    UserAccount newUser = UserAccount(
      fullName: _fullNameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      password: password,
    );
    UserDatabase.registeredUsers.add(newUser);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Đăng ký thành công'),
          ],
        ),
        content: Text(
          'Chúc mừng ${newUser.fullName}!\n'
          'Tài khoản với số điện thoại ${newUser.phoneNumber} đã được tạo thành công.\n'
          'Bấm OK để quay lại giao diện đăng nhập.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('OK - Đến Đăng Nhập'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentStep == 1
            ? 'Đăng Ký - Bước 1/3'
            : _currentStep == 2
                ? 'Đăng Ký - Bước 2/3'
                : 'Đăng Ký - Bước 3/3'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thanh tiến trình các bước
            Row(
              children: [
                _buildStepIndicator(1, "Gửi yêu cầu", _currentStep >= 1),
                _buildStepDivider(_currentStep >= 2),
                _buildStepIndicator(2, "Nhận OTP", _currentStep >= 2),
                _buildStepDivider(_currentStep >= 3),
                _buildStepIndicator(3, "Mật khẩu", _currentStep >= 3),
              ],
            ),
            const SizedBox(height: 30),

            // BƯỚC 1: NHẬP HỌ TÊN & SỐ ĐIỆN THOẠI
            if (_currentStep == 1) ...[
              const Text(
                'Nhập thông tin đăng ký',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'Họ và tên',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại đăng ký (vd: 0901234567)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _requestOtpFromEmulator,
                icon: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_to_mobile),
                label: Text(_isLoading ? 'Đang gửi yêu cầu...' : 'Yêu Cầu Gửi Mã OTP'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],

            // BƯỚC 2: NHẬP MÃ OTP
            if (_currentStep == 2) ...[
              const Text(
                'Xác nhận mã OTP',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'SĐT nhận mã: ${_phoneController.text}',
                style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Bảng Đếm Ngược 1 Phút (60 Giây)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _secondsRemaining > 0 ? Colors.orange.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _secondsRemaining > 0 ? Colors.orange.shade300 : Colors.red.shade300,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _secondsRemaining > 0 ? Icons.timer : Icons.timer_off,
                      color: _secondsRemaining > 0 ? Colors.orange.shade900 : Colors.red,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _secondsRemaining > 0
                          ? 'Mã OTP có hiệu lực trong: $_secondsRemaining giây'
                          : '⚠️ Mã OTP đã hết hạn (quá 1 phút)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _secondsRemaining > 0 ? Colors.orange.shade900 : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: _isLoading || _secondsRemaining <= 0 ? null : () => _fetchOtpFromCloud(isBackground: false),
                icon: _isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_download),
                label: Text(_isLoading ? 'Đang nhận mã...' : 'Kiểm Tra Tin Nhắn OTP'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Nhập mã OTP 6 số mới',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_clock),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _secondsRemaining > 0 ? _verifyOtp : null,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Xác Nhận Mã OTP'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: _secondsRemaining > 0 ? Colors.blue : Colors.grey,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () {
                        _requestOtpFromEmulator();
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Yêu Cầu Gửi Mã OTP Mới'),
              ),
              TextButton(
                onPressed: () {
                  _otpCheckTimer?.cancel();
                  _countdownTimer?.cancel();
                  setState(() {
                    _currentStep = 1;
                  });
                },
                child: const Text('Đổi số điện thoại khác'),
              ),
            ],

            // BƯỚC 3: NHẬP MẬT KHẨU
            if (_currentStep == 3) ...[
              const Text(
                'Tạo mật khẩu cho tài khoản',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu (tối thiểu 6 ký tự)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nhập lại mật khẩu',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _completeRegistration,
                icon: const Icon(Icons.check_circle),
                label: const Text('Hoàn tất Đăng ký'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],

            const SizedBox(height: 30),
            if (_statusMessage.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, String title, bool isActive) {
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: isActive ? Colors.blue : Colors.grey.shade300,
          child: Text(
            '$step',
            style: TextStyle(
              color: isActive ? Colors.white : Colors.black54,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.blue : Colors.grey,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider(bool isActive) {
    return Expanded(
      child: Container(
        height: 2,
        color: isActive ? Colors.blue : Colors.grey.shade300,
        margin: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

// ============================================================================
// 3. GIAO DIỆN APP SAU KHI ĐĂNG NHẬP THÀNH CÔNG (HOME SCREEN)
// ============================================================================
class HomeScreen extends StatelessWidget {
  final UserAccount user;

  const HomeScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trang Chủ Ứng Dụng'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified, size: 80, color: Colors.green),
              const SizedBox(height: 20),
              Text(
                'Xin chào, ${user.fullName}!',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Số điện thoại: ${user.phoneNumber}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                child: const Column(
                  children: [
                    Icon(Icons.dashboard_customize, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'Giao diện ứng dụng chính (Đã đăng ký thành công)',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
