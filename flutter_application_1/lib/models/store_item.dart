import 'package:latlong2/latlong.dart';

// 동백전 가맹점 샘플 데이터 모델
class StoreItem {
  final String id;
  final String name;
  final LatLng location;
  final String category;
  final String benefit;

  const StoreItem({
    required this.id,
    required this.name,
    required this.location,
    required this.category,
    required this.benefit,
  });
}

final List<StoreItem> kSampleStores = [
  const StoreItem(
    id: "store_999",
    name: "동백 베이커리 서면점",
    location: LatLng(35.179858, 129.076042),
    category: "베이커리/카페",
    benefit: "동백전 결제 시 10% 캐시백 & 스탬프 1개 적립",
  ),
  const StoreItem(
    id: "store_101",
    name: "부산시청 동백식당",
    location: LatLng(35.179058, 129.074942),
    category: "한식전문점",
    benefit: "동백전 캐시백 5% + 즉시할인 쿠폰 제공",
  ),
  const StoreItem(
    id: "store_102",
    name: "광안리 스탬프 카페",
    location: LatLng(35.180558, 129.074142),
    category: "디저트/음료",
    benefit: "체류 완료 시 아메리카노 1+1 쿠폰 지급",
  ),
];
