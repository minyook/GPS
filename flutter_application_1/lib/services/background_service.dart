import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';
import 'fcm_service.dart';

// 테스트 전용 고유 유저 ID
const String kUserId = "test_user_flutter";
// fastapi 백엔드 연동용 기본 ngrok 도메인 주소
const String kDefaultBaseUrl = "https://deceit-blooming-estrogen.ngrok-free.dev";

// [백그라운드 위치 측정 및 통신 서비스 시작 핸들러]
// 앱이 꺼지거나 화면이 닫혀도 이 백그라운드 격리 프로세스(Isolate)는 독립적으로 실행됩니다.
@pragma('vm:entry-point') // 백그라운드 다트 엔진 진입을 위한 컴파일 옵션
void onStart(ServiceInstance service) async {
  // 백그라운드 플러그인 레지스트리 바인딩 보장
  DartPluginRegistrant.ensureInitialized();

  String serverUrl = kDefaultBaseUrl;

  // 서비스 통신 채널 바인딩 설정
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // 앱 화면 UI에서 수정한 ngrok 서버 주소 동기화 리스너
  service.on('setServerUrl').listen((event) {
    if (event != null && event['url'] != null) {
      serverUrl = event['url'].toString();
    }
  });

  // 백그라운드 수집 서비스 정지 리스너
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // [실제 30초마다 작동되는 스마트폰 GPS 수집 및 FastAPI 서버 전송 핵심 비즈니스 함수]
  Future<void> performLocationCheck() async {
    try {
      // 1. 스마트폰 내장 GPS/위치 기능 켜짐 검증
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        service.invoke('log', {'message': '❌ 스마트폰 GPS/위치 서비스 꺼짐'});
        return;
      }

      // 2. 스마트폰 위치 권한 확인
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        service.invoke('log', {'message': '❌ 위치 권한 거부됨'});
        return;
      }

      // 3. 현재 위치 GPS 위도/경도/정확도 수집 시도 (25초 타임아웃 제한)
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

      // GPS 값이 수집되지 않은 경우 조기 반환
      if (position == null) {
        service.invoke('log', {'message': '⚠️ GPS 신호 측정 지연 (실내 제한)'});
        return;
      }

      // UI 메인 화면에 내 마커를 실시간 갱신할 수 있도록 좌표 전달
      service.invoke('updatePosition', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
      });

      service.invoke('log', {
        'message':
            '📍 [GPS 수집 완료] 위도: ${position.latitude.toStringAsFixed(5)}, 경도: ${position.longitude.toStringAsFixed(5)}, accuracy: ${position.accuracy.toStringAsFixed(1)}m'
      });

      // 4. [정밀도 필터링] GPS 오차가 지나치게 크면 (200m 초과 실내 노이즈) 서버 전송 패스 (배터리 및 트래픽 방어)
      if (position.accuracy > 200.0) {
        service.invoke('log', {
          'message':
              '⚠️ [필터링 패스] accuracy(${position.accuracy.toStringAsFixed(1)}m) > 200m -> 전송 안함'
        });
        return;
      }

      // 5. [FastAPI 서버 API 통신 전송]
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

      // HTTP POST 위치 발송 (ngrok 프리 패스 헤더 포함)
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': '69420',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        service.invoke('log', {
          'message': '✅ [FastAPI 위치 전송 성공] Status: ${response.statusCode}'
        });
      } else {
        service.invoke('log', {
          'message': '❌ [FastAPI 전송 실패] Status: ${response.statusCode}'
        });
      }
    } catch (e) {
      service.invoke('log', {'message': '❌ [백그라운드 에러] $e'});
    }
  }

  // 서비스 구동 시작 시 즉시 1회 작동
  await Future.delayed(const Duration(milliseconds: 500));
  await performLocationCheck();

  // [30초 주기 테스트 타이머 가동]
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    await performLocationCheck();
  });
}

// [안드로이드 OS WorkManager 백그라운드 태스크 콜백 수신기]
// OS가 백그라운드에서 주기적으로 해당 태스크를 가동하면 실행되는 영역입니다.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await initLocalNotifications();
      // 강제 팝업 알림 시뮬레이션
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

// [포어그라운드 백그라운드 서비스의 채널 및 알림 최소화 등록 설정]
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      autoStartOnBoot: true, // 디바이스 전원 부팅 시 자동 시작 설정
      isForegroundMode: true,
      notificationChannelId: 'silent_background_channel', // 무음 채널 연동으로 뱃지 숨김 처리
      initialNotificationTitle: '', // 빈 텍스트 지정으로 노티피케이션창 거슬림 방지
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
