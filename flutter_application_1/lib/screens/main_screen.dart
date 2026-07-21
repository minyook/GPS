import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/store_item.dart';
import '../services/fcm_service.dart';
import '../services/background_service.dart';

const LatLng kDefaultCenter = LatLng(35.179558, 129.075642); // 부산 시청 기본 위치

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _urlController =
      TextEditingController(text: kDefaultBaseUrl);

  String? _fcmToken;
  String _lastClickedStoreId = "없음";
  bool _isServiceRunning = false;

  LatLng _currentLocation = kDefaultCenter;
  double _currentAccuracy = 15.0;
  bool _hasLocationData = false;

  List<StoreItem> _activeStores = List.from(kSampleStores);
  StoreItem? _nearestStore;
  double _nearestDistance = 99999.0;

  StreamSubscription? _logSubscription;
  StreamSubscription? _posSubscription;

  void _updateNearbyStores(double lat, double lng) {
    final List<StoreItem> nearbyList = [
      StoreItem(
        id: "store_999",
        name: "동백 베이커리 (내 주변 매장)",
        location: LatLng(lat + 0.00020, lng + 0.00020), // 약 25m 거리
        category: "베이커리/카페",
        benefit: "동백전 결제 시 10% 캐시백 & 스탬프 1개 적립",
      ),
      StoreItem(
        id: "store_101",
        name: "부산시청 동백식당",
        location: LatLng(lat - 0.00035, lng + 0.00025), // 약 45m 거리
        category: "한식전문점",
        benefit: "동백전 캐시백 5% + 즉시할인 쿠폰 제공",
      ),
      StoreItem(
        id: "store_102",
        name: "동백 스탬프 카페",
        location: LatLng(lat + 0.00045, lng - 0.00035), // 약 60m 거리
        category: "디저트/음료",
        benefit: "체류 완료 시 아메리카노 1+1 쿠폰 지급",
      ),
    ];

    StoreItem? minStore;
    double minDistance = 99999.0;

    for (var store in nearbyList) {
      double dist = Geolocator.distanceBetween(
        lat,
        lng,
        store.location.latitude,
        store.location.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        minStore = store;
      }
    }

    if (mounted) {
      setState(() {
        _activeStores = nearbyList;
        _nearestStore = minStore;
        _nearestDistance = minDistance;
      });
    }

    logToConsole(
        "GEO_SEARCH", "가장 가까운 동백전 가맹점: ${minStore?.name} (${minDistance.toStringAsFixed(1)}m)");
  }

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _setupFcm();
    _listenToBackgroundService();
    _checkServiceStatus();
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _posSubscription?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    PermissionStatus notifStatus = await Permission.notification.request();
    PermissionStatus locStatus = await Permission.location.request();
    await Permission.ignoreBatteryOptimizations.request();

    logToConsole("PERM", "Notification: $notifStatus, Location: $locStatus");

    if (locStatus.isGranted) {
      PermissionStatus alwaysStatus = await Permission.locationAlways.request();
      logToConsole("PERM", "LocationAlways: $alwaysStatus");
    }
  }

  Future<void> _setupFcm() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      String? token = await messaging.getToken();
      if (mounted) {
        setState(() {
          _fcmToken = token;
        });
      }

      if (token != null) {
        logToConsole("FCM", "Token acquired: $token");
        await _registerFcmTokenToServer(token);
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        if (mounted) {
          setState(() {
            _fcmToken = newToken;
          });
        }
        logToConsole("FCM", "Token refreshed: $newToken");
        await _registerFcmTokenToServer(newToken);
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        logToConsole(
            "FCM_RECV", "Title: ${message.notification?.title}, Data: ${message.data}");

        if (message.data.containsKey('store_id')) {
          final storeId = message.data['store_id'].toString();
          if (mounted) {
            setState(() {
              _lastClickedStoreId = storeId;
            });
            _showDongbaekDialog(storeId, message.notification?.body);
          }
        }

        RemoteNotification? notification = message.notification;
        AndroidNotification? android = message.notification?.android;
        if (notification != null && android != null) {
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

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        logToConsole("FCM_CLICK", "Opened App Data: ${message.data}");
        _handleNotificationClick(message.data);
      });

      RemoteMessage? initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        logToConsole("FCM_INIT", "Terminated App Data: ${initialMessage.data}");
        _handleNotificationClick(initialMessage.data);
      }
    } catch (e) {
      logToConsole("FCM_ERR", "Setup FCM failed: $e");
    }
  }

  Future<void> _registerFcmTokenToServer(String token) async {
    final serverUrl = _urlController.text.trim();
    final url = Uri.parse('$serverUrl/api/user/fcm-token');
    final payload = {"user_id": kUserId, "fcm_token": token};

    logToConsole("API_FCM", "POST $url Payload: ${jsonEncode(payload)}");

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': '69420',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      logToConsole(
          "API_FCM_RESP", "Status: ${response.statusCode}, Body: ${response.body}");
    } catch (e) {
      logToConsole("API_FCM_ERROR", "$e");
    }
  }

  void _handleNotificationClick(Map<String, dynamic> data) {
    if (data.containsKey('store_id')) {
      final storeId = data['store_id'].toString();
      if (mounted) {
        setState(() {
          _lastClickedStoreId = storeId;
        });
        _showDongbaekDialog(storeId, "매장에 일정 시간 체류하셨습니다! 동백전 결제 혜택을 확인해 보세요.");
      }
    }
  }

  void _showDongbaekDialog(String storeId, String? message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Text("🌺 ", style: TextStyle(fontSize: 22)),
            Text("동백전 체류 결제 안내",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message ??
                  "현재 매장에 장시간 체류 중입니다! 동백전으로 결제하고 캐시백 혜택을 받아보세요.",
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.pink[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.pink.shade200),
              ),
              child: Text(
                "📍 체류 매장 ID: $storeId",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.pink),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("닫기"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE91E63),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("동백전 결제 창으로 이동합니다.")),
              );
            },
            child: const Text("동백전으로 결제하기"),
          ),
        ],
      ),
    );
  }

  void _showStoreBottomSheet(StoreItem store) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, color: Color(0xFFE91E63), size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    store.name,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.pink[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    store.category,
                    style: const TextStyle(
                        color: Color(0xFFE91E63),
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text("📍 매장 ID: ${store.id}",
                style: const TextStyle(
                    color: Colors.grey, fontSize: 12, fontFamily: 'monospace')),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  const Text("🎁 ", style: TextStyle(fontSize: 16)),
                  Expanded(
                    child: Text(
                      store.benefit,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE91E63),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showDongbaekDialog(
                      store.id, "${store.name} 체류 중입니다! 동백전으로 결제하고 혜택을 받아보세요.");
                },
                child: const Text("동백전 체류 결제 테스트 시뮬레이션"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _listenToBackgroundService() {
    final service = FlutterBackgroundService();

    _logSubscription = service.on('log').listen((event) {
      if (event != null && event['message'] != null) {
        logToConsole("BG_SERVICE", event['message'].toString());
      }
    });

    _posSubscription = service.on('updatePosition').listen((event) {
      if (event != null &&
          event['latitude'] != null &&
          event['longitude'] != null) {
        final double lat = event['latitude'];
        final double lng = event['longitude'];
        final double acc = (event['accuracy'] ?? 15.0).toDouble();

        if (mounted) {
          setState(() {
            _currentLocation = LatLng(lat, lng);
            _currentAccuracy = acc;
            _hasLocationData = true;
          });
          _updateNearbyStores(lat, lng);
          _mapController.move(_currentLocation, 16.0);
        }
      }
    });
  }

  Future<void> _checkServiceStatus() async {
    final service = FlutterBackgroundService();
    bool running = await service.isRunning();
    if (mounted) {
      setState(() {
        _isServiceRunning = running;
      });
    }
  }

  Future<void> _toggleService() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();

    if (isRunning) {
      service.invoke("stopService");
      if (mounted) {
        setState(() {
          _isServiceRunning = false;
        });
      }
      logToConsole("SERVICE", "Background Service Stopped");
    } else {
      final serverUrl = _urlController.text.trim();
      service.invoke("setServerUrl", {"url": serverUrl});
      await service.startService();
      if (mounted) {
        setState(() {
          _isServiceRunning = true;
        });
      }
      logToConsole("SERVICE", "Background Service Started");
    }
  }

  Future<void> _sendManualLocation() async {
    try {
      logToConsole("MANUAL", "1회 위치 측정 시작...");

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 25),
          ),
        );
      } catch (e) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        logToConsole("MANUAL_ERR", "Location Null Timeout");
        return;
      }

      final LatLng newPos = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentLocation = newPos;
          _currentAccuracy = position!.accuracy;
          _hasLocationData = true;
        });
        _updateNearbyStores(position.latitude, position.longitude);
        _mapController.move(newPos, 16.0);
      }

      logToConsole("MANUAL",
          "Location: (${position.latitude}, ${position.longitude}) acc: ${position.accuracy}m");

      if (position.accuracy > 200.0) {
        logToConsole("MANUAL", "Filtered: accuracy > 200m");
        return;
      }

      final serverUrl = _urlController.text.trim();
      final url = Uri.parse('$serverUrl/api/location');
      final payload = {
        "user_id": kUserId,
        "latitude": position.latitude,
        "longitude": position.longitude,
        "accuracy": double.parse(position.accuracy.toStringAsFixed(1)),
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': '69420',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      logToConsole(
          "MANUAL_RESP", "Status: ${response.statusCode}, Body: ${response.body}");
    } catch (e) {
      logToConsole("MANUAL_ERR", "Failed to send manual location: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text("🌺 ", style: TextStyle(fontSize: 20)),
            Text("동백전 가맹점 체류 지도",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          // 1. 체류 감지 상태 표시 카드
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: _isServiceRunning ? Colors.pink[50] : Colors.grey[100],
            child: Row(
              children: [
                Icon(
                  _isServiceRunning ? Icons.radar : Icons.radar_outlined,
                  color:
                      _isServiceRunning ? const Color(0xFFE91E63) : Colors.grey,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isServiceRunning
                            ? "📍 매장 체류 감지 작동 중 (30초 테스트)"
                            : "⏸️ 체류 감지 중지됨",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _isServiceRunning
                              ? const Color(0xFFE91E63)
                              : Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                      if (_nearestStore != null)
                        Text(
                          "🎯 근처 가맹점: ${_nearestStore!.name} (${_nearestDistance.toStringAsFixed(0)}m 거리에 위치)",
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE91E63)),
                        )
                      else
                        Text(
                          _hasLocationData
                              ? "위도: ${_currentLocation.latitude.toStringAsFixed(4)}, 경도: ${_currentLocation.longitude.toStringAsFixed(4)} (오차: ${_currentAccuracy.toStringAsFixed(0)}m)"
                              : "위치 수집 대기 중... ([1회 측정] 클릭)",
                          style:
                              const TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                    ],
                  ),
                ),
                Switch(
                  value: _isServiceRunning,
                  activeTrackColor: const Color(0xFFE91E63),
                  onChanged: (val) => _toggleService(),
                ),
              ],
            ),
          ),

          // 2. 메인 지도 UI 영역 (FlutterMap)
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLocation,
                    initialZoom: 15.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.flutter_application_1',
                    ),
                    // 1. 동백전 가맹점 마커 레이어 (실시간 주변 가맹점 자동 동적 매핑)
                    MarkerLayer(
                      markers: _activeStores.map((store) {
                        return Marker(
                          point: store.location,
                          width: 110,
                          height: 60,
                          child: GestureDetector(
                            onTap: () => _showStoreBottomSheet(store),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black26, blurRadius: 4)
                                    ],
                                    border: Border.all(
                                        color: const Color(0xFFE91E63),
                                        width: 1.5),
                                  ),
                                  child: Text(
                                    store.name,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.storefront_rounded,
                                    color: Color(0xFFE91E63), size: 28),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_hasLocationData) ...[
                      // 50m 오차 반경 동심원 시각화
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _currentLocation,
                            radius: 50, // 50m 반경 시각 표시
                            useRadiusInMeter: true,
                            color:
                                const Color(0xFFE91E63).withValues(alpha: 0.15),
                            borderColor: const Color(0xFFE91E63),
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                      // 현재 위치 Pin 마커
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentLocation,
                            width: 50,
                            height: 50,
                            child: const Column(
                              children: [
                                Icon(Icons.location_on,
                                    color: Color(0xFFE91E63), size: 38),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),

                // 수동 위치 측정 Floating 버튼
                Positioned(
                  right: 16,
                  bottom: 80,
                  child: FloatingActionButton.extended(
                    onPressed: _sendManualLocation,
                    backgroundColor: const Color(0xFFE91E63),
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.my_location),
                    label: const Text("1회 측정 & 전송",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),

          // 3. 하단 서버 URL 연결 정보 바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[200],
            child: Row(
              children: [
                const Icon(Icons.link, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "서버 URL: ${_urlController.text}",
                    style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _fcmToken != null ? Colors.green[100] : Colors.amber[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _fcmToken != null ? "FCM 연결됨 ($_lastClickedStoreId)" : "FCM 대기 중",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _fcmToken != null
                          ? Colors.green[800]
                          : Colors.amber[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
