import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:workmanager/workmanager.dart';

import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'services/background_service.dart';
import 'screens/main_screen.dart';

// [앱 실행 진입점]
void main() async {
  // Flutter 엔진 초기화 (비동기 플러그인 연동 전 필수 실행)
  WidgetsFlutterBinding.ensureInitialized();

  // 구글 파이어베이스 서비스 초기화 (FCM 연결 준비)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 앱이 완전히 종료되었거나 백그라운드 상태일 때 FCM 푸시 알림을 수신하는 전역 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // 로컬 알림(상단 푸시 팝업 노출용) 채널 및 권한 초기화
  await initLocalNotifications();
  
  // 30초 주기 위치 수집 백그라운드 포어그라운드 서비스 엔진 초기화 및 구동 준비
  await initializeBackgroundService();

  try {
    // 안드로이드 OS 자체 시스템 알람(WorkManager) 연동 시작 (앱이 죽었을 때 주기적 예비 작동 보장)
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      "dongbaek_dwell_task",
      "dongbaekDwellCheckTask",
      frequency: const Duration(minutes: 15), // 최소 15분 주기 안드로이드 규정 적용
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  } catch (_) {}

  // 메인 UI 앱 가동
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '동백전 방문 확인 테스트',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFE91E63), // 동백꽃 분홍색 시그니처 톤 적용
      ),
      home: const MainScreen(), // 메인 지도 스크린으로 이동
    );
  }
}