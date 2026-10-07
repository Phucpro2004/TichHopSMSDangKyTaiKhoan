import 'dart:io';

void main() async {
  const targetPort = 8080;
  const bridgeIp = '172.20.10.4';

  print('Khởi động Trạm Trung Chuyển (PC Bridge) trên $bridgeIp:$targetPort...');
  try {
    final server = await HttpServer.bind(bridgeIp, targetPort);
    print('🟢 PC Bridge đang hoạt động trên http://$bridgeIp:$targetPort');
    print('-> Chuyển tiếp toàn bộ yêu cầu sang Máy Ảo qua http://127.0.0.1:$targetPort');

    final client = HttpClient();

    server.listen((HttpRequest req) async {
      final forwardUri = Uri.parse('http://127.0.0.1:$targetPort${req.uri.path}${req.uri.hasQuery ? '?${req.uri.query}' : ''}');
      print('📥 [Nhận từ Máy Thật] ${req.method} ${req.uri.path} -> Chuyển tiếp tới Máy Ảo...');

      try {
        final forwardReq = await client.openUrl(req.method, forwardUri);
        req.headers.forEach((name, values) {
          if (name.toLowerCase() != 'host') {
            for (var val in values) {
              forwardReq.headers.add(name, val);
            }
          }
        });

        await forwardReq.addStream(req);
        final forwardRes = await forwardReq.close();

        req.response.statusCode = forwardRes.statusCode;
        forwardRes.headers.forEach((name, values) {
          for (var val in values) {
            req.response.headers.add(name, val);
          }
        });
        await req.response.addStream(forwardRes);
        await req.response.close();
        print('✅ [Thành công] Đã chuyển tiếp phản hồi từ Máy Ảo về Máy Thật (Status: ${forwardRes.statusCode})');
      } catch (e) {
        print('⚠️ Lỗi chuyển tiếp tới 127.0.0.1:$targetPort: $e');
        req.response.statusCode = HttpStatus.badGateway;
        req.response.write('Bridge error: $e');
        await req.response.close();
      }
    });
  } catch (e) {
    print('❌ Lỗi khởi động Bridge: $e');
  }
}
