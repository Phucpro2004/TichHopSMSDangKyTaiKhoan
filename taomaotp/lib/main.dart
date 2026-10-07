import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tổng Đài Quản Lý & Cấp Mã OTP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const DeviceRegistrationScreen(),
    );
  }
}

class OtpRequest {
  final String id;
  final String fullName;
  final String phoneNumber;
  String? generatedOtp;
  DateTime requestTime;
  bool isApproved;

  OtpRequest({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.generatedOtp,
    required this.requestTime,
    this.isApproved = false,
  });
}

class DeviceRegistrationScreen extends StatefulWidget {
  const DeviceRegistrationScreen({super.key});

  @override
  State<DeviceRegistrationScreen> createState() =>
      _DeviceRegistrationScreenState();
}

class _DeviceRegistrationScreenState extends State<DeviceRegistrationScreen> {
  final List<OtpRequest> _requests = [];
  final List<String> _logs = [];
  bool _isFetching = false;
  bool _isSendingOtp = false;
  OtpRequest? _selectedRequest;
  Timer? _autoRefreshTimer;
  HttpServer? _localServer;
  String _localIp = 'Đang quét IP...';
  String _networkStatus = 'Đang khởi tạo hệ thống...';

  // Cấu hình IP Trung Gian
  static const String _pcHostIp = '172.20.10.4';
  static const int _serverPort = 8080;

  // Key KVDB Bucket
  static const String _kvdbBucket = 'KjYiVofyAsNGPKCVd7kvyd';

  @override
  void initState() {
    super.initState();
    _startLocalHttpServer();
    _fetchRequestsFromCloud();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchRequestsFromCloud(isBackground: true);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _localServer?.close();
    super.dispose();
  }

  void _addLog(String msg) {
    final timeStr = DateTime.now().toString().split('.').first.split(' ').last;
    if (mounted) {
      setState(() {
        _logs.insert(0, "[$timeStr] $msg");
        if (_logs.length > 40) _logs.removeLast();
      });
    }
  }

  Future<void> _startLocalHttpServer() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            _localIp = addr.address;
            break;
          }
        }
      }

      _localServer = await HttpServer.bind(InternetAddress.anyIPv4, _serverPort);
      _addLog("🟢 Gateway Server: Local IP $_localIp (Port $_serverPort)");
      _addLog("💻 Cổng Kết Nối Khách Hàng: $_pcHostIp:$_serverPort");

      _localServer!.listen((HttpRequest request) async {
        final path = request.uri.path;
        final params = request.uri.queryParameters;

        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        if (path == '/ping') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(json.encode({
              "status": "ok",
              "server": "XacThucOTP",
              "message": "Kết nối thành công tới Hệ thống Cấp mã OTP!"
            }));
          await request.response.close();
          return;
        }

        if (path == '/request-otp') {
          final phone = params['phone'] ?? '';
          final name = params['name'] ?? 'Khách Hàng Local';

          if (phone.isNotEmpty) {
            _addLog("📲 Nhận yêu cầu từ Khách hàng: $phone ($name)");
            _addOrUpdatePhoneRequest(phone, name);

            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(json.encode({"success": true}));
          }
        } else if (path == '/get-otp') {
          final phone = params['phone'] ?? '';
          final found = _requests.firstWhere(
            (r) => r.phoneNumber == phone && r.isApproved,
            orElse: () => OtpRequest(
              id: '',
              fullName: '',
              phoneNumber: '',
              requestTime: DateTime.now(),
            ),
          );

          if (found.generatedOtp != null) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(json.encode({
                "phone": phone,
                "otp": found.generatedOtp,
                "approved": true
              }));
          } else {
            request.response
              ..statusCode = HttpStatus.notFound
              ..headers.contentType = ContentType.json
              ..write(json.encode({"error": "Pending"}));
          }
        }
        await request.response.close();
      });
    } catch (e) {
      _addLog("⚠️ Local Gateway Server $_serverPort: $e");
    }
  }

  void _addOrUpdatePhoneRequest(String phone, String fullName) {
    int index = _requests.indexWhere((r) => r.phoneNumber == phone);
    if (index < 0) {
      setState(() {
        _requests.insert(
          0,
          OtpRequest(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            fullName: fullName,
            phoneNumber: phone,
            requestTime: DateTime.now(),
          ),
        );
      });
    }
  }

  // Quét đa kênh Cloud (KVDB + Restful-API)
  Future<void> _fetchRequestsFromCloud({bool isBackground = false}) async {
    if (!isBackground) {
      setState(() {
        _isFetching = true;
      });
    }

    bool foundAny = false;

    // 1. Quét kênh KVDB
    try {
      final kvdbUrl = Uri.parse('https://kvdb.io/$_kvdbBucket/latest_request');
      final res = await http.get(kvdbUrl).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final Map<String, dynamic> data = json.decode(res.body);
        final phone = data['phone']?.toString();
        final name = data['fullName']?.toString() ?? 'Khách Hàng KVDB';

        if (phone != null && phone.isNotEmpty) {
          _addOrUpdatePhoneRequest(phone, name);
          foundAny = true;
        }
      }
    } catch (_) {}

    // 2. Quét kênh Restful-API
    try {
      final cloudUrl = Uri.parse('https://api.restful-api.dev/objects');
      final res = await http.get(cloudUrl).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final List<dynamic> list = json.decode(res.body);
        for (var item in list) {
          final name = item['name']?.toString() ?? '';
          if (name.startsWith('TAOMAOTP_REQ_') && item['data'] != null) {
            final data = item['data'];
            final phone = data['phone']?.toString();
            final fullName = data['fullName']?.toString() ?? 'Khách Hàng Cloud';

            if (phone != null && phone.isNotEmpty) {
              _addOrUpdatePhoneRequest(phone, fullName);
              foundAny = true;
            }
          }
        }
      }
    } catch (e) {
      if (!isBackground) {
        _addLog("⚠️ Scan error: $e");
      }
    } finally {
      if (mounted) {
        setState(() {
          _networkStatus = foundAny || _requests.isNotEmpty
              ? "🟢 Đã kết nối Cloud & sẵn sàng nhận yêu cầu"
              : "🟡 Đang chờ yêu cầu xác thực từ khách hàng...";
          if (!isBackground) _isFetching = false;
        });
      }
    }
  }

  String _generateOtp() {
    final random = Random();
    final otpInt = random.nextInt(900000) + 100000;
    return otpInt.toString();
  }

  // Duyệt & Cấp mã OTP đa kênh
  Future<void> _approveAndSendOtp(OtpRequest req) async {
    setState(() {
      _isSendingOtp = true;
      _selectedRequest = req;
    });

    final otpCode = _generateOtp();
    _addLog("⚙️ Đang cấp mã OTP [$otpCode] cho SĐT ${req.phoneNumber}...");

    // 1. Đẩy lên Kênh KVDB
    try {
      final kvdbUrl = Uri.parse('https://kvdb.io/$_kvdbBucket/otp_${req.phoneNumber}');
      await http.post(
        kvdbUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "phone": req.phoneNumber,
          "otp": otpCode,
          "approved": true,
          "timestamp": DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      _addLog("Lỗi phát KVDB: $e");
    }

    // 2. Đẩy lên Kênh Restful-API
    try {
      final cloudUrl = Uri.parse('https://api.restful-api.dev/objects');
      await http.post(
        cloudUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "name": "TAOMAOTP_OTP_${req.phoneNumber}",
          "data": {
            "phone": req.phoneNumber,
            "otp": otpCode,
            "approved": true,
            "timestamp": DateTime.now().millisecondsSinceEpoch,
          }
        }),
      );
    } catch (e) {
      _addLog("Lỗi phát Cloud Restful: $e");
    }

    setState(() {
      req.generatedOtp = otpCode;
      req.isApproved = true;
      _isSendingOtp = false;
    });

    _addLog("🎉 ĐÃ PHÁT MÃ OTP [$otpCode] CHO KHÁCH HÀNG ${req.phoneNumber}!");

    // 3. Mở App SMS
    final message =
        '[XacThucOTP] Ma OTP xac thuc dang ky tai khoan cua quy khach la: $otpCode. Ma co hieu luc trong 1 phut.';
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: req.phoneNumber,
      queryParameters: <String, String>{'body': message},
    );

    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        await sendSMS(message: message, recipients: [req.phoneNumber]);
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🎉 Đã duyệt & cấp mã OTP [$otpCode] thành công cho SĐT ${req.phoneNumber}!',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _addManualPhone() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm Số Điện Thoại Khách Hàng'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Số điện thoại nhận OTP',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final phone = controller.text.trim();
              if (phone.isNotEmpty) {
                _addOrUpdatePhoneRequest(phone, 'Khách Hàng (Nhập tay)');
                _addLog("➕ Đã thêm SĐT khách hàng: $phone");
                Navigator.pop(context);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  // Xóa toàn bộ lịch sử để sẵn sàng cho buổi thuyết trình
  Future<void> _clearAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.red),
            SizedBox(width: 8),
            Text('Xóa Lịch Sử?'),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa toàn bộ danh sách yêu cầu OTP và nhật ký để bắt đầu phiên mới?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa toàn bộ'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _requests.clear();
        _selectedRequest = null;
        _logs.clear();
      });

      try {
        final kvdbUrl = Uri.parse('https://kvdb.io/$_kvdbBucket/latest_request');
        await http.delete(kvdbUrl).timeout(const Duration(seconds: 2));
      } catch (_) {}

      try {
        final cloudUrl = Uri.parse('https://api.restful-api.dev/objects');
        final res = await http.get(cloudUrl).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final List<dynamic> list = json.decode(res.body);
          for (var item in list) {
            final name = item['name']?.toString() ?? '';
            if (name.startsWith('TAOMAOTP_REQ_')) {
              final id = item['id'];
              if (id != null) {
                // Don't await so it doesn't block the UI unnecessarily
                http.delete(Uri.parse('https://api.restful-api.dev/objects/$id')).timeout(const Duration(seconds: 2)).catchError((_) => http.Response('', 500));
              }
            }
          }
        }
      } catch (_) {}

      _addLog('🗑️ Đã xóa sạch toàn bộ lịch sử yêu cầu & nhật ký.');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🧹 Đã làm sạch dữ liệu phiên làm việc!'),
            backgroundColor: Colors.blueGrey,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showNetworkGuideDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.hub, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('Cấu Hình Hệ Thống Cấp Mã', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '1. Cấu hình Cổng Gateway:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepPurple.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• Cổng Gateway: 8080 (Listening)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                    SizedBox(height: 4),
                    Text('• Hệ thống đồng bộ tự động 2 chiều qua Cloud.', style: TextStyle(fontSize: 13, color: Colors.black87)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '2. Lệnh hỗ trợ kết nối:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const SelectableText(
                  'adb forward tcp:8080 tcp:8080',
                  style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '3. Sao lưu đa kênh (Cloud Sync):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text('Hệ thống đồng thời tích hợp đồng bộ tự động qua KVDB & Restful-API Cloud để đảm bảo 100% không bị sót yêu cầu từ khách hàng.', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tổng Đài Quản Lý Mã OTP'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Cấu hình hệ thống',
            onPressed: _showNetworkGuideDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Xóa toàn bộ lịch sử',
            onPressed: _clearAllHistory,
          ),
          IconButton(
            icon: _isFetching
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Tải lại',
            onPressed: _fetchRequestsFromCloud,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRequestsFromCloud,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bảng Trạng Thái Mạng
              Card(
                elevation: 2,
                color: Colors.deepPurple.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.deepPurple.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_tethering, color: Colors.deepPurple, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _networkStatus,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Danh sách Yêu cầu Mã OTP',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        tooltip: 'Xóa lịch sử',
                        onPressed: _clearAllHistory,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_call),
                        tooltip: 'Thêm SĐT khách hàng',
                        onPressed: _addManualPhone,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_requests.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.phonelink_ring, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'Đang chờ yêu cầu xác thực từ khách hàng...',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _addManualPhone,
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm SĐT Khách Hàng Thủ Công'),
                      ),
                    ],
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _requests.length,
                  itemBuilder: (context, index) {
                    final req = _requests[index];
                    final isSelected = _selectedRequest?.id == req.id;

                    return Card(
                      elevation: req.isApproved ? 1 : 4,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: req.isApproved ? Colors.green : Colors.orange,
                          width: 1.5,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: req.isApproved
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                          child: Icon(
                            req.isApproved ? Icons.check_circle : Icons.mark_chat_unread,
                            color: req.isApproved ? Colors.green : Colors.orange,
                          ),
                        ),
                        title: Text(
                          '${req.fullName} (${req.phoneNumber})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              req.isApproved
                                  ? 'Đã duyệt cấp mã OTP: ${req.generatedOtp}'
                                  : '🔴 YÊU CẦU MỚI: Bấm nút để cấp & gửi mã OTP!',
                              style: TextStyle(
                                color: req.isApproved ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        trailing: _isSendingOtp && isSelected
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: req.isApproved ? Colors.grey.shade200 : Colors.blue,
                                  foregroundColor: req.isApproved ? Colors.black87 : Colors.white,
                                ),
                                onPressed: () => _approveAndSendOtp(req),
                                icon: Icon(req.isApproved ? Icons.refresh : Icons.send, size: 16),
                                label: Text(req.isApproved ? 'Gửi lại OTP' : 'Cấp & Gửi OTP'),
                              ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 16),

              if (_selectedRequest != null && _selectedRequest!.generatedOtp != null) ...[
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.verified, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(
                              'Đã cấp mã cho SĐT ${_selectedRequest!.phoneNumber}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Mã OTP xác thực: ${_selectedRequest!.generatedOtp}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '(Mã này đã được đồng bộ tự động tới thiết bị khách hàng để hoàn tất đăng ký!)',
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Live Logs Console
              const Text(
                'Nhật ký hoạt động hệ thống (Live Logs):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Container(
                height: 150,
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _logs.isEmpty
                    ? const Text('Chưa có nhật ký nào...', style: TextStyle(color: Colors.grey, fontSize: 12))
                    : ListView.builder(
                        itemCount: _logs.length,
                        itemBuilder: (context, index) => Text(
                          _logs[index],
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
//Phuc da sua