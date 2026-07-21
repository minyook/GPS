import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';
import 'fcm_service.dart';

const String kUserId = "test_user_flutter";
const String kDefaultBaseUrl = "https://deceit-blooming-estrogen.ngrok-free.dev";

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  String serverUrl = kDefaultBaseUrl;

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('setServerUrl').listen((event) {
    if (event != null && event['url'] != null) {
      serverUrl = event['url'].toString();
    }
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Future<void> performLocationCheck() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        service.invoke('log', {'message': '❌ 스마트폰 GPS/위치 서비스 꺼짐'});
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        service.invoke('log', {'message': '❌ 위치 권한 거부됨'});
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 25),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        service.invoke('log', {'message': '⚠️ GPS 신호 측정 지연 (실내 제한)'});
        return;
      }

      service.invoke('updatePosition', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
      });

      service.invoke('log', {
        'message':
            '📍 [GPS 수집 완료] 위도: ${position.latitude.toStringAsFixed(5)}, 경도: ${position.longitude.toStringAsFixed(5)}, accuracy: ${position.accuracy.toStringAsFixed(1)}m'
      });

      // 테스트용: 오차 200m 초과 시 전송 패스 (실내 100m 오차 허용)
      if (position.accuracy > 200.0) {
        service.invoke('log', {
          'message':
              '⚠️ [필터링 패스] accuracy(${position.accuracy.toStringAsFixed(1)}m) > 200m -> 전송 안함'
        });
        return;
      }

      final url = Uri.parse('$serverUrl/api/location');
      final payload = {
        "user_id": kUserId,
        "latitude": position.latitude,
        "longitude": position.longitude,
        "accuracy": double.parse(position.accuracy.toStringAsFixed(1)),
      };

      service.invoke('log', {
        'message': '🚀 [FastAPI 전송 중] $url\nPayload: ${jsonEncode(payload)}'
      });

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': '69420',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final resData = jsonDecode(response.body);
        final status = resData['status'];
        final matchedStore = resData['matched_store'];

        service.invoke('log', {
          'message': '✅ [FastAPI 전송 성공] Status: $status, Store: ${matchedStore?['name'] ?? "None"}'
        });

        // status가 confirmed이거나 새로 체류 확정된 경우 FCM이 안 오더라도 앱 로컬 알림으로 팝업 띄우기
        if (status == 'confirmed' || resData['is_newly_confirmed'] == true) {
          final storeName = matchedStore?['name'] ?? '동백전 가맹점';
          await flutterLocalNotificationsPlugin.show(
            DateTime.now().millisecond,
            '💳 $storeName (동백전 가맹점)',
            '현재 $storeName 가맹점 안에 계십니다! 동백전으로 결제하고 스탬프를 적립해 보세요 🎁',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'high_importance_channel',
                '체류 결제 알림 채널',
                importance: Importance.max,
                priority: Priority.high,
              ),
            ),
            payload: jsonEncode({
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
              'type': 'STAMP_PROMOTION',
              'store_id': matchedStore?['store_id'] ?? ''
            }),
          );
        }
      } else {
        service.invoke('log', {
          'message': '❌ [FastAPI 전송 실패] Status: ${response.statusCode}'
        });
      }
    } catch (e) {
      service.invoke('log', {'message': '❌ [백그라운드 에러] $e'});
    }
  }

  await Future.delayed(const Duration(milliseconds: 500));
  await performLocationCheck();

  // 30초 주기 테스트 타이머
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    await performLocationCheck();
  });
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await initLocalNotifications();
      await flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecond,
        '📍 [동백전 System Alarm] 방문 확인 안내',
        '현재 내 위치 50m 이내 매장에 방문 중입니다! 동백전으로 결제하고 혜택을 받으세요!',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            '방문 결제 알림 채널',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode({
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          'type': 'STAMP_PROMOTION',
          'store_id': 'store_999'
        }),
      );
    } catch (_) {}
    return Future.value(true);
  });
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: 'silent_background_channel',
      initialNotificationTitle: '',
      initialNotificationContent: '',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: (service) => true,
    ),
  );
}
