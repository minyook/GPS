# 🌺 동백전 위치 체류 수집 및 FCM 알림 통신 가이드 (README)

이 문서는 플러터(Flutter) 클라이언트와 FastAPI 백엔드 간에 화면(UI) 없이 **"실시간 위치 수집 ➡️ 백엔드 전송 ➡️ 체류 판정 ➡️ FCM 푸시 알림 발송"**만 핵심 모듈로 떼어내서 개발할 때 참고하는 개발 가이드라인입니다.

---

## 📡 1. 플러터 앱 (Flutter App) - 통신 & 알림 핵심 모듈

화면 없이 백그라운드 수집과 알림 수신만 처리할 때 사용하는 핵심 파일 및 함수 구조입니다.

### ① 알림 초기화 및 수신 핸들러
- **위치**: `lib/services/fcm_service.dart`
- **핵심 함수**:
  - `initLocalNotifications()`: 폰 상단 헤드업 알림을 띄우기 위한 채널 설정 및 초기화
  - `firebaseMessagingBackgroundHandler()`: 앱이 꺼져 있거나 백그라운드일 때 수신된 FCM 푸시 알림 처리

### ② 백그라운드 위치 측정 및 서버 전송 (30초 주기)
- **위치**: `lib/services/background_service.dart`
- **핵심 함수**:
  - `performLocationCheck()`: 30초마다 실제 GPS를 측정하여 백엔드 `POST /api/location`으로 HTTP POST 요청 발송
  - `initializeBackgroundService()`: 안드로이드 포어그라운드 서비스 및 무음 채널(`silent_background_channel`) 설정

### ③ 디바이스 FCM 토큰 백엔드 등록
- **위치**: `lib/screens/main_screen.dart`
- **핵심 함수**:
  - `_registerFcmTokenToServer(String token)`: 스마트폰의 고유 FCM 푸시 토큰 주소를 백엔드 `POST /api/user/fcm-token`으로 등록하는 통신 함수

---

## 🖥️ 2. FastAPI 백엔드 (FastAPI) - 수신 & 푸시 전송 핵심 모듈

수신된 데이터 기반으로 체류를 판단하여 구글 파이어베이스 서버로 알림을 쏘는 핵심 파일 및 함수 구조입니다.

### ① FCM 토큰 관리 서비스
- **위치**: `app/services/user_service.py`
- **핵심 함수**:
  - `register_fcm_token()`: 클라이언트로부터 전달받은 FCM 토큰을 메모리 캐시(`G_FCM_TOKENS`) 및 DB에 등록

### ② 위치 정보 수신 및 체류 판단
- **위치**: `app/services/location_service.py`
- **핵심 함수**:
  - `process_location_update()`: 30초마다 전송된 GPS 좌표를 수신하여 가맹점 반경(50m) 내 체류 여부를 연산하고 FCM 발송 트리거 호출

### ③ FCM 푸시 알림 실제 발송 (Firebase Admin SDK)
- **위치**: `app/services/fcm_service.py`
- **핵심 함수**:
  - `process_and_send_stay_notification()`: `firebase_admin.messaging.send(message)`를 직접 사용하여 사용자의 폰 상단으로 진짜 동백전 팝업 푸시 알림을 즉시 발송

---

## 🔗 3. 클라이언트 ↔ 서버 API 데이터 통신 규격

### 1) FCM 토큰 등록 API (POST)
- **Endpoint**: `POST /api/user/fcm-token`
- **Request Header**:
  ```json
  {
    "Content-Type": "application/json",
    "ngrok-skip-browser-warning": "69420"
  }
  ```
- **Request Body**:
  ```json
  {
    "user_id": "test_user_flutter",
    "fcm_token": "fcm_token_string_here..."
  }
  ```

### 2) 위치 정보 전송 API (POST)
- **Endpoint**: `POST /api/location`
- **Request Header**:
  ```json
  {
    "Content-Type": "application/json",
    "ngrok-skip-browser-warning": "69420"
  }
  ```
- **Request Body**:
  ```json
  {
    "user_id": "test_user_flutter",
    "latitude": 35.179558,
    "longitude": 129.075642,
    "accuracy": 15.0
  }
  ```

### 3) 백엔드 FCM 발송 메시지 규격 (Payload)
- **FCM Message Object**:
  ```json
  {
    "notification": {
      "title": "💳 [가맹점명] (동백전 가맹점)",
      "body": "[가맹점명]은(는) 동백전 가맹점입니다! 동백전으로 결제하고 스탬프도 적립하세요 🎁"
    },
    "data": {
      "store_id": "store_999",
      "type": "STAMP_EVENT_ALERT",
      "click_action": "FLUTTER_NOTIFICATION_CLICK"
    }
  }
  ```
