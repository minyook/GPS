import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'fcm_service.dart'; // flutterLocalNotificationsPlugin 및 채널 정보 참조

/// [화면 UI 없이 백그라운드 수집/알림 결합 전용 FCM 헬퍼 클래스]
/// 나중에 기존 메인 프로젝트에 이 파일만 그대로 가져가서 합칠 때 사용합니다.
class FcmSetupHelper {
  // 테스트용 FastAPI 백엔드 주소 (ngrok 우회 통신 지원)
  static const String serverUrl = "https://deceit-blooming-estrogen.ngrok-free.dev";
  static const String kUserId = "test_user_flutter";

  // [FCM 초기화 및 수신 핸들러 연결 통합 구동 함수]
  static Future<void> setupFcm() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;

      // 1. 디바이스 푸시 알림 수신 권한 요청
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // 2. 디바이스 고유 FCM 토큰 획득
      String? token = await messaging.getToken();
      if (token != null) {
        debugPrint("[FcmSetupHelper] 기기 토큰 획득 성공: $token");
        await _registerFcmTokenToServer(token);
      }

      // 3. 토큰이 도중에 갱신될 시 백엔드 재등록을 보장하는 리스너 등록
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint("[FcmSetupHelper] 기기 토큰 재갱신: $newToken");
        await _registerFcmTokenToServer(newToken);
      });

      // 4. [앱이 Foreground 전면에 켜져 있을 때] 구글 FCM 푸시 알림 수신 시 상단 헤드업 노출 리스너
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint("[FcmSetupHelper Foreground 수신] Data: ${message.data}");
        
        RemoteNotification? notification = message.notification;
        AndroidNotification? android = message.notification?.android;
        
        if (notification != null && android != null) {
          // 스마트폰 화면 상단 알림 팝업 노출 실행
          flutterLocalNotificationsPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                notificationChannel.id,
                notificationChannel.name,
                channelDescription: notificationChannel.description,
                icon: '@mipmap/ic_launcher',
                importance: Importance.max,
                priority: Priority.high,
              ),
            ),
            payload: jsonEncode(message.data),
          );
        }
      });

      // 5. [앱이 백그라운드에 떠 있을 때] 상단 알림창의 푸시를 클릭하고 진입했을 때 핸들러
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint("[FcmSetupHelper 백그라운드 클릭 진입] Data: ${message.data}");
        _handleNotificationClick(message.data);
      });

      // 6. [앱이 완전히 꺼져 있을 때] 푸시 알림을 터치해서 앱이 부팅/실행되었을 때 핸들러
      RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint("[FcmSetupHelper 완전종료 클릭 진입] Data: ${initialMessage.data}");
        _handleNotificationClick(initialMessage.data);
      }
      
    } catch (e) {
      debugPrint("❌ [FcmSetupHelper 셋업 오류] $e");
    }
  }

  // [획득된 FCM 기기 토큰을 FastAPI 백엔드로 즉시 전송하는 API 통신 함수]
  static Future<void> _registerFcmTokenToServer(String token) async {
    final url = Uri.parse('$serverUrl/api/user/fcm-token');
    final payload = {"user_id": kUserId, "fcm_token": token};

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': '69420', // ngrok warning 차단 헤더
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      debugPrint("[FcmSetupHelper 백엔드 저장 완료] Status: ${response.statusCode}");
    } catch (e) {
      debugPrint("❌ [FcmSetupHelper 백엔드 저장 실패] $e");
    }
  }

  // [사용자가 푸시 알림 팝업을 클릭했을 때 후처리 액션 정의 부분]
  static void _handleNotificationClick(Map<String, dynamic> data) {
    if (data.containsKey('store_id')) {
      final storeId = data['store_id'].toString();
      debugPrint("🔔 [가맹점 방문 알림 클릭 감지] 가맹점 ID: $storeId");
      
      // TODO: 차후에 실제 프로젝트 결합 시, 이곳에 포인트 적립 뷰 페이지로 이동하는 로직을 연동합니다.
    }
  }
}
