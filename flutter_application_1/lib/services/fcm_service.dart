import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';

// [로컬 푸시 알림 컨트롤러] - 디바이스 상단에 푸시 팝업을 직접 노출시키는 객체
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// [1. 일반 가맹점 혜택 푸시 알림 채널] (상단 헤드업 팝업 & 소리 작동)
const AndroidNotificationChannel notificationChannel = AndroidNotificationChannel(
  'high_importance_channel',
  '동백전 가맹점 알림 채널',
  description: '매장 방문 확인 및 동백전 결제 유도 푸시 알림에 사용됩니다.',
  importance: Importance.high, // 중요도 High 설정으로 상단 팝업 무조건 노출
);

// [2. 백그라운드 수집 서비스 전용 무음 채널] (무음 / 숨김 처리 ⭐)
// 사용자가 요청한 "위치 측정 대기 중..." 알림 뱃지를 숨겨서 보이지 않게 가려주는 채널입니다.
const AndroidNotificationChannel silentChannel = AndroidNotificationChannel(
  'silent_background_channel',
  '백그라운드 서비스 채널',
  description: '상단 뱃지 노출 없이 조용히 백그라운드 위치를 수집합니다.',
  importance: Importance.min, // 중요도 Min 설정으로 소리/아이콘/팝업이 뜨지 않음
  showBadge: false,
);

// [VS Code 터미널 출력 전용 디버그 로그 함수]
void logToConsole(String tag, String message) {
  final now = DateTime.now();
  final timeStr =
      "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
  debugPrint("[$timeStr] [$tag] $message");
}

// [앱 완전히 종료 시 구글 FCM 푸시 수신 백그라운드 핸들러]
// 이 핸들러는 앱 화면이 완전히 꺼져 있을 때도 백엔드가 FCM을 쏘면 구글 시스템이 활성화하여 동작합니다.
@pragma('vm:entry-point') // 백그라운드 Isolate 분리 진입을 위해 다트 컴파일러에 명시 필수
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드 실행을 위해 파이어베이스 엔진 리로드 초기화
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("[FCM Background] 수신 메시지 ID: ${message.messageId}");
  debugPrint("[FCM Background] Data: ${message.data}");

  // 백엔드가 전달한 푸시 데이터에 가맹점 ID(store_id)가 들어있는지 검증
  if (message.data.containsKey('store_id')) {
    debugPrint(
        "[FCM Background] 🌺 동백전 방문 매장 감지 (store_id): ${message.data['store_id']}");
  }
}

// [로컬 푸시 알림 서비스 초기화 및 안드로이드 OS에 알림 채널 등록]
Future<void> initLocalNotifications() async {
  // 알림 노출 시 상단바 아이콘 지정 (mipmap 기본 런처 아이콘 지정)
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  // 로컬 노티피케이션 초기화 구동
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      // 상단 푸시 알림 팝업을 클릭했을 때 앱이 켜지며 콜백으로 전달되는 페이로드 처리
      if (details.payload != null) {
        logToConsole("LOCAL_NOTIF", "Clicked Payload: ${details.payload}");
      }
    },
  );

  // 안드로이드 OS 시스템에 위의 1.일반 알림 채널과 2.무음 수집 채널을 생성/등록
  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(notificationChannel);
  await androidPlugin?.createNotificationChannel(silentChannel);
}
