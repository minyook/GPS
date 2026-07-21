# 위치 기반 체류 판정 및 FCM 푸시 알림 백엔드 시스템

FastAPI와 Firebase Admin SDK(Firestore, FCM)를 활용하여 5분 주기 클라이언트 GPS 좌표를 수신하고, DB 비용을 최적화하며 10분 이상 매장에 체류한 고객에게 결제 유도 푸시 알림을 발송하는 백엔드 서버입니다.

---

## 📁 프로젝트 폴더 구조

```text
GPS_TEST/
├── app/
│   ├── core/
│   │   ├── config.py             # Pydantic Settings 기반 환경변수 관리
│   │   └── firebase.py           # Firebase Admin SDK & Firestore 초기화
│   ├── models/
│   │   └── schemas.py            # Pydantic API DTO 스키마
│   ├── routers/
│   │   ├── user.py               # POST /api/user/fcm-token
│   │   └── location.py           # POST /api/location
│   ├── services/
│   │   ├── user_service.py       # FCM 토큰 등록/갱신 비즈니스 로직
│   │   ├── location_service.py   # 위치 수신, Haversine 거리계산, 체류판정 로직
│   │   └── fcm_service.py        # FCM 푸시알림 발송 및 notification_history 관리
│   ├── utils/
│   │   └── haversine.py          # Haversine 구면거리 계산 유틸리티
│   └── main.py                   # FastAPI 엔트리포인트 어플리케이션
├── scripts/
│   └── seed_stores.py            # 테스트용 샘플 매장 등록 스크립트
├── serviceAccountKey.json.example# 파이어베이스 서비스 계정 키 예시
├── requirements.txt              # 파이썬 의존성 패키지
└── README.md                     # 시스템 가이드 문서
```

---

## 🗄️ Firestore 컬렉션 구조 (스키마)

1. **`users`**
   - Document ID: `{user_id}`
   - Data: `{ fcm_token: String, updated_at: Timestamp }`

2. **`stores`**
   - Document ID: `{store_id}`
   - Data: `{ name: String, location: GeoPoint, radius: int, has_stamp_event: bool }`

3. **`stay_status`**
   - Document ID: `{user_id}`
   - Data: `{ store_id: String, arrival_time: Timestamp, consecutive_count: int, status: String("candidate" | "confirmed" | "left") }`

4. **`notification_history`**
   - Document ID: `{auto_id}`
   - Data: `{ user_id: String, store_id: String, sent_date: String("YYYY-MM-DD"), timestamp: Timestamp }`

---

## 🚀 빠른 시작 가이드

### 1. 의존성 설치
```bash
pip install -r requirements.txt
```

### 2. Firebase 서비스 계정 키 설정
Firebase Console -> 서비스 계정 -> **새 개인 키 생성**을 다운로드하여 프로젝트 루트에 `serviceAccountKey.json`으로 저장합니다.

### 3. 서버 실행
```bash
uvicorn app.main:app --reload --port 8000
```
- Swagger API Docs: `http://localhost:8000/docs`

---

## 📡 API 엔드포인트 사양

### 1. FCM 토큰 등록 API
- **Endpoint**: `POST /api/user/fcm-token`
- **Request Body**:
```json
{
  "user_id": "user_12345",
  "fcm_token": "fcm_token_sample_abc123"
}
```
- **Response**:
```json
{
  "success": true,
  "message": "FCM token registered successfully.",
  "data": {
    "user_id": "user_12345"
  }
}
```

### 2. 위치 정보 수신 및 체류 판정 API
- **Endpoint**: `POST /api/location`
- **Request Body**:
```json
{
  "user_id": "user_12345",
  "latitude": 37.4979,
  "longitude": 127.0276,
  "accuracy": 15.0
}
```
- **Response (Early Return - accuracy > 50인 경우)**:
```json
{
  "success": true,
  "message": "Location processed successfully.",
  "data": {
    "status": "ignored",
    "reason": "low_accuracy",
    "accuracy": 65.0
  }
}
```
- **Response (체류 진행/확정 시)**:
```json
{
  "success": true,
  "message": "Location processed successfully.",
  "data": {
    "status": "confirmed",
    "consecutive_count": 2,
    "stay_minutes": 10.2,
    "matched_store": {
      "store_id": "store_gangnam_01",
      "name": "강남역 메가커피점",
      "radius": 50,
      "has_stamp_event": true,
      "distance": 12.5
    },
    "is_newly_confirmed": true
  }
}
```

---

## 🧠 핵심 알고리즘 및 락(Lock) 처리

1. **DB 비용 방어 (Early Return)**:
   - 수신된 GPS 정확도(`accuracy > 50`)가 낮을 경우 즉시 조기 반환하여 Firestore 쿼리를 실행하지 않음.
2. **Haversine 직접 구현**:
   - 파이썬 `math` 라이브러리로 위도/경도 기반 직선거리(m)를 직접 산출.
3. **체류 판정 알고리즘**:
   - 매장 반경(radius) 안 최초 수신: `candidate`, `consecutive_count=1`
   - 5분 후 연속 진입(consecutive_count >= 2) 또는 10분 경과시: `confirmed`로 업데이트
   - 매장 반경 이탈 시: `stay_status`를 `status="left"`로 초기화
4. **마케팅 락 (Daily Push Lock)**:
   - `has_stamp_event == True` 매장인지 검증
   - `notification_history` 컬렉션에서 `(user_id, store_id, 오늘날짜 "YYYY-MM-DD")` 조합을 조회하여 당일 푸시가 이미 전송된 고객에게는 알림 발송 생략.
