import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// 설명 보완
const AndroidNotificationChannel notificationChannel = AndroidNotificationChannel(
  'high_importance_channel',
  '동백전 가맹점 알림 채널',
  description: '매장 방문 확인 및 동백전 결제 유도 푸시 알림에 사용됩니다.',
  importance: Importance.high,
);

const AndroidNotificationChannel silentChannel = AndroidNotificationChannel(
  'silent_background_channel',
  '백그라운드 서비스 채널',
  description: '상단 뱃지 노출 없이 조용히 백그라운드 위치를 수집합니다.',
  importance: Importance.min,
  showBadge: false,
);

// VS Code 터미널 출력 전용 로그 함수
void logToConsole(String tag, String message) {
  final now = DateTime.now();
  final timeStr =
      "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
  debugPrint("[$timeStr] [$tag] $message");
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("[FCM Background] 수신 메시지 ID: ${message.messageId}");
  debugPrint("[FCM Background] Data: ${message.data}");

  if (message.data.containsKey('store_id')) {
    debugPrint(
        "[FCM Background] 🌺 동백전 방문 매장 감지 (store_id): ${message.data['store_id']}");
  }
}

Future<void> initLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      if (details.payload != null) {
        logToConsole("LOCAL_NOTIF", "Clicked Payload: ${details.payload}");
      }
    },
  );

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(notificationChannel);
  await androidPlugin?.createNotificationChannel(silentChannel);
}
