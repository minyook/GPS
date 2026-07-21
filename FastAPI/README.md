# 💳 동백전 리뉴얼 시스템 통합 위치기반 체류 판정 백엔드 (FastAPI)

> **문서 버전:** v1.2 (동백전 리뉴얼 시스템 통합 데이터 명세서 v1.2 완벽 반영)  
> **아키텍처:** Firebase SQL Connect (PostgreSQL) + Redis (In-Memory) + Cloud Firestore (NoSQL) + FastAPI

FastAPI와 Cloud SQL PostgreSQL(SQL Connect), Redis, Firebase Admin SDK(Firestore, FCM)를 결합하여 **5분 주기 위치 핑 수신**, **스마트 DB 비용 방어**, **가맹점 10분 이상 체류 고객 대상 동백전 결제 유도 및 스탬프 적립 알림 발송**을 수행하는 핵심 백엔드 서비스입니다.

---

## 🏛️ 통합 데이터 아키텍처 구성

| 구성 요소 | 기반 기술 | 주요 역할 및 담당 데이터 영역 |
| :--- | :--- | :--- |
| **SQL Connect** | Cloud SQL (PostgreSQL) | `user`, `store` (가맹점 좌표 마스터), `location_alert_history`, `waiting_history` 등 무결성 데이터 원장 |
| **In-Memory** | Redis | `user:geolocations` (GEO 위치 핑), `user:geofence:{userId}:{storeId}` (TTL 5분 반경 체류 판정) |
| **Firestore** | Cloud Firestore (NoSQL) | `/fcm_devices/{user_id}` (디바이스 토큰 동기화), `stay_status` 라이브 세션 |
| **FastAPI** | Python 3.11+ | Haversine 구면거리 계산, 10분 체류 감지 알고리즘, 하루 2회 알림 제한 마케팅 락 |

---

## 📂 프로젝트 폴더 구조

```text
FastAPI/
├── app/
│   ├── core/
│   │   ├── config.py                 # Pydantic Settings (체류 10분, 1일 2회 푸시 락 설정)
│   │   ├── firebase.py               # Firebase Admin SDK & Firestore 초기화
│   │   ├── redis.py                  # Redis In-Memory GEO 및 Geofence TTL 연동
│   │   └── sql_connect.py            # Firebase SQL Connect (PostgreSQL) Connector 모듈
│   ├── models/
│   │   └── schemas.py                # Pydantic DTO (LocationUpdateRequest, FCMTokenRegisterRequest)
│   ├── routers/
│   │   ├── user.py                   # POST /api/user/fcm-token
│   │   └── location.py               # POST /api/location
│   ├── services/
│   │   ├── user_service.py           # SQL Connect user & /fcm_devices 동기화
│   │   ├── location_service.py       # SQL Connect store 기반 Haversine 체류 감지
│   │   └── fcm_service.py            # FCM 푸시 발송 및 location_alert_history 기록
│   ├── utils/
│   │   ├── haversine.py              # Haversine 위치 거리(m) 산출 알고리즘
│   │   └── uuid_helper.py            # UUID 규격 안전 변환 유틸리티
│   └── main.py                       # FastAPI 웹 서버 엔트리포인트
├── scripts/
│   ├── seed/                         # DB 테이블 생성 및 가맹점 마이그레이션 시드 툴
│   │   ├── create_location_alert_table.py
│   │   ├── seed_sql_connect_stores.py
│   │   ├── import_busanjingu_stores.py
│   │   └── seed_stores.py
│   ├── inspect/                      # DB 스키마 검증 및 CSV 좌표 분석 유틸리티
│   │   ├── inspect_sql_tables.py
│   │   ├── inspect_waiting_history.py
│   │   ├── inspect_store_coords.py
│   │   ├── inspect_csv.py
│   │   └── get_test_store.py
│   └── tests/                        # 전체 백엔드 체류 파이프라인 검증 툴
│       ├── test_full_sql_pipeline.py
│       ├── test_sql_connect_location.py
│       ├── test_location_match.py
│       ├── test_user_location.py
│       ├── test_direct_sql.py
│       └── reset_location_test.py
├── 부산광역시_지역화폐(동백전) 가맹점 현황_20260424.csv  # 부산진구 가맹점 마스터 데이터
├── serviceAccountKey.json.example    # 파이어베이스 계정 키 예시 파일
├── requirements.txt                  # 의존성 패키지 리스트
└── README.md                         # FastAPI 안내 문서
```

---

## 🗄️ PostgreSQL (SQL Connect) 스키마 정의

1. **`user`**
   - `id` (UUID, PK), `name` (TEXT), `phone` (TEXT), `email` (TEXT), `role` (TEXT), `status` (TEXT), `created_at`, `last_login_at`

2. **`store`**
   - `id` (UUID, PK), `owner_user_id` (UUID, FK), `name` (TEXT), `category` (TEXT), `latitude` (DOUBLE), `longitude` (DOUBLE), `address` (TEXT), `phone` (TEXT), `is_dongbaek_merchant` (BOOLEAN), `status` (TEXT), `created_at`

3. **`location_alert_history`**
   - `id` (UUID, PK), `user_id` (TEXT), `store_id` (TEXT), `store_name` (TEXT), `status` (TEXT), `alert_sent` (BOOLEAN), `sent_date` (TEXT), `created_at`, `updated_at`

---

## 🚀 실행 가이드

### 1. 의존성 패키지 설치
```bash
pip install -r requirements.txt
```

### 2. 인증 키 파일 배치
Firebase Console에서 다운로드한 `serviceAccountKey.json` 파일을 `FastAPI/` 루트 경로에 위치시킵니다.

### 3. PostgreSQL 시드 데이터 이관 (부산진구 100개 가맹점)
```bash
python scripts/seed/seed_sql_connect_stores.py
```

### 4. FastAPI 백엔드 서버 구동
```bash
uvicorn app.main:app --reload --port 8000
```
- Swagger API 문서: `http://localhost:8000/docs`

---

## 📡 주요 API 명세

### 1. 위치 정보 수신 및 체류 판정 API
- **Endpoint**: `POST /api/location`
- **Request Body**:
```json
{
  "user_id": "test_dongbaek_user_001",
  "latitude": 35.1501,
  "longitude": 129.0559,
  "accuracy": 10.0
}
```
- **Response**:
```json
{
  "status": "confirmed",
  "consecutive_count": 2,
  "stay_minutes": 10.0,
  "matched_store": {
    "store_id": "448216bb-82cd-416f-85bf-21539f9b4782",
    "name": "행복약국",
    "radius": 50.0,
    "has_stamp_event": true,
    "isDongbaekMerchant": true,
    "distance": 0.0
  },
  "is_newly_confirmed": true
}
```

---

## 🧠 체류 알고리즘 & 마케팅 락 (Marketing Lock)

1. **DB 비용 방어 (Early Return)**:
   - `accuracy > 50m`인 저품질 GPS 수신 시 즉시 무시하여 DB 연산을 차단.
2. **PostgreSQL 1순위 매장 탐색**:
   - SQL Connect `store` 테이블의 위/경도 좌표와 Haversine 거리를 상호 계산하여 50m 반경 이내 가맹점 매칭.
3. **체류 판정 규칙**:
   - 10분 체류 (5분 간격 2회 연속 수신) 달성 시 `confirmed`로 체류 확정.
4. **하루 2회 푸시 제한 (Daily Push Lock)**:
   - `location_alert_history` 테이블에서 당일(`sent_date`) 동일 가맹점 발송 횟수를 쿼리하여 **하루 최대 2회**를 초과하지 않도록 자동 락 처리.
