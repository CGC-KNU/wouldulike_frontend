import 'package:flutter/material.dart';

class AffiliateCoupon {
  AffiliateCoupon({
    required this.id,
    required this.name,
    required this.expiresAt,
    required this.status,
    this.description,
  });

  final String id;
  final String name;
  final DateTime expiresAt;
  String status; // 'available' or 'used'
  final String? description;

  bool get isUsed => status == 'used';
}

class AffiliateStampHistory {
  AffiliateStampHistory({
    required this.id,
    required this.accruedAt,
    required this.note,
  });

  final String id;
  final DateTime accruedAt;
  final String note;
}

class AffiliateRestaurant {
  AffiliateRestaurant({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryLabel,
    required this.address,
    required this.distanceKm,
    required this.heroImage,
    required this.galleryImages,
    required this.description,
    required this.phoneNumber,
    required this.businessHours,
    required this.stampGoal,
    required this.stampCount,
    required List<AffiliateCoupon> coupons,
    required List<AffiliateStampHistory> stampHistory,
  })  : coupons = List<AffiliateCoupon>.of(coupons),
        stampHistory = List<AffiliateStampHistory>.of(stampHistory),
        recentUsage = stampHistory.isNotEmpty ? stampHistory.first.accruedAt : null;

  final String id;
  final String name;
  final String categoryId;
  final String categoryLabel;
  final String address;
  final double distanceKm;
  final String heroImage;
  final List<String> galleryImages;
  final String description;
  final String phoneNumber;
  final String businessHours;
  final int stampGoal;
  final List<AffiliateCoupon> coupons;
  final List<AffiliateStampHistory> stampHistory;
  int stampCount;
  DateTime? recentUsage;

  int get availableCouponCount => coupons.where((coupon) => !coupon.isUsed).length;
  int get totalCouponCount => coupons.length;

  void addStamp() {
    if (stampCount >= stampGoal) return;

    stampCount += 1;
    final entry = AffiliateStampHistory(
      id: 'stamp-${stampHistory.length + 1}',
      accruedAt: DateTime.now(),
      note: '관리자 적립',
    );
    stampHistory.insert(0, entry);
    recentUsage = entry.accruedAt;

    if (stampCount == 5 || stampCount == stampGoal) {
      coupons.insert(
        0,
        AffiliateCoupon(
          id: 'coupon-$id-${coupons.length + 1}',
          name: stampCount == stampGoal ? '무료 메뉴 쿠폰' : '추가 적립 쿠폰',
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          status: 'available',
          description: '스탬프 적립 리워드로 자동 발급',
        ),
      );
    }
  }

  void useCoupon(String couponId) {
    final target = coupons.firstWhere(
      (coupon) => coupon.id == couponId,
      orElse: () => throw ArgumentError('Coupon not found'),
    );
    target.status = 'used';
    recentUsage = DateTime.now();
  }
}

class _AffiliateCategory {
  const _AffiliateCategory({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final String icon;
}

class AffiliateBenefitsScreen extends StatefulWidget {
  const AffiliateBenefitsScreen({super.key});

  @override
  State<AffiliateBenefitsScreen> createState() => _AffiliateBenefitsScreenState();
}

class _AffiliateBenefitsScreenState extends State<AffiliateBenefitsScreen> {
  static const _adminPin = '0000';
  late final List<_AffiliateCategory> _categories;
  late final List<AffiliateRestaurant> _catalog;

  String _selectedCategoryId = 'all';
  List<AffiliateRestaurant> _visibleRestaurants = [];

  @override
  void initState() {
    super.initState();
    _categories = _buildCategories();
    _catalog = _buildMockRestaurants();
    _applyFilter();
  }

  List<_AffiliateCategory> _buildCategories() => const [
        _AffiliateCategory(id: 'all', label: '전체', icon: '🍽️'),
        _AffiliateCategory(id: 'korean', label: '한식', icon: '🍚'),
        _AffiliateCategory(id: 'japanese', label: '일식', icon: '🍜'),
        _AffiliateCategory(id: 'western', label: '양식', icon: '🍝'),
        _AffiliateCategory(id: 'cafe', label: '카페', icon: '☕'),
        _AffiliateCategory(id: 'dessert', label: '디저트', icon: '🧁'),
      ];

  List<AffiliateRestaurant> _buildMockRestaurants() {
    List<AffiliateStampHistory> buildHistory(int count, int step) {
      return List.generate(count, (index) {
        return AffiliateStampHistory(
          id: 'history-${index + 1}',
          accruedAt: DateTime.now().subtract(Duration(days: index * step + 1)),
          note: index.isEven ? '방문 적립' : '이벤트 적립',
        );
      });
    }

    List<AffiliateCoupon> buildCoupons(String prefix) => [
          AffiliateCoupon(
            id: '$prefix-1',
            name: '사이드 메뉴 무료',
            expiresAt: DateTime.now().add(const Duration(days: 15)),
            status: 'available',
            description: '2만원 이상 주문 시 사용 가능',
          ),
          AffiliateCoupon(
            id: '$prefix-2',
            name: '전 메뉴 10% 할인',
            expiresAt: DateTime.now().add(const Duration(days: 30)),
            status: 'available',
            description: '첫 방문 고객 전용',
          ),
        ];

    return [
      AffiliateRestaurant(
        id: 'rest-001',
        name: '나이스샤워 경북대점',
        categoryId: 'japanese',
        categoryLabel: '일식 · 텐동 전문점',
        address: '대구 북구 대학로13길 20 1층',
        distanceKm: 2.3,
        heroImage: 'https://images.unsplash.com/photo-1604908177698-af4182d9fd1e',
        galleryImages: [
          'https://images.unsplash.com/photo-1604908177488-1991701b9efa',
          'https://images.unsplash.com/photo-1574966745260-83ac948ec7ed',
          'https://images.unsplash.com/photo-1504674900247-0877df9cc836',
        ],
        description: '바삭한 튀김과 고소한 소스로 유명한 텐동 전문점입니다. 제휴 고객에게 다양한 스탬프 혜택을 제공합니다.',
        phoneNumber: '0507-1495-5701',
        businessHours: '매일 10:00 ~ 22:00',
        stampGoal: 10,
        stampCount: 7,
        coupons: buildCoupons('rest-001'),
        stampHistory: buildHistory(7, 1),
      ),
      AffiliateRestaurant(
        id: 'rest-002',
        name: '카페 달콤',
        categoryId: 'cafe',
        categoryLabel: '카페 · 디저트',
        address: '서울 마포구 합정로 45',
        distanceKm: 1.3,
        heroImage: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836',
        galleryImages: [
          'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4',
          'https://images.unsplash.com/photo-1504674900247-0877df9cc836',
        ],
        description: '싱글 오리진 커피와 수제 디저트를 즐길 수 있는 합정 카페입니다.',
        phoneNumber: '02-1234-5678',
        businessHours: '매일 09:00 ~ 21:00',
        stampGoal: 10,
        stampCount: 3,
        coupons: buildCoupons('rest-002'),
        stampHistory: buildHistory(3, 2),
      ),
      AffiliateRestaurant(
        id: 'rest-003',
        name: '한강 뷰 한식당',
        categoryId: 'korean',
        categoryLabel: '모던 한식',
        address: '서울 영등포구 여의서로 130',
        distanceKm: 4.8,
        heroImage: 'https://images.unsplash.com/photo-1482049016688-2d3e1b311543',
        galleryImages: [
          'https://images.unsplash.com/photo-1466978913421-dad2ebd01d17',
          'https://images.unsplash.com/photo-1504674900247-0877df9cc836',
        ],
        description: '한강 야경과 함께 정갈한 한식 코스를 즐길 수 있는 제휴 레스토랑입니다.',
        phoneNumber: '010-9876-5432',
        businessHours: '매일 17:00 ~ 24:00',
        stampGoal: 10,
        stampCount: 9,
        coupons: buildCoupons('rest-003'),
        stampHistory: buildHistory(9, 1),
      ),
    ];
  }

  void _applyFilter() {
    final filtered = _selectedCategoryId == 'all'
        ? _catalog
        : _catalog.where((restaurant) => restaurant.categoryId == _selectedCategoryId).toList();

    setState(() {
      _visibleRestaurants = filtered;
    });
  }

  void _selectCategory(String categoryId) {
    if (_selectedCategoryId == categoryId) return;
    setState(() => _selectedCategoryId = categoryId);
    _applyFilter();
  }

  void _openRestaurantDetail(AffiliateRestaurant restaurant) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AffiliateRestaurantDetailPage(
          restaurant: restaurant,
          adminPin: _adminPin,
          onChanged: () => setState(() {}),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: _categories.map((category) {
          final selected = category.id == _selectedCategoryId;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ChoiceChip(
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(category.icon, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 6),
                  Text(category.label),
                ],
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              selected: selected,
              onSelected: (_) => _selectCategory(category.id),
              selectedColor: const Color(0xFFEEF2FF),
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: selected ? const Color(0xFF312E81) : const Color(0xFF6B7280),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildRestaurantCard(AffiliateRestaurant restaurant) {
    final recentUsage = restaurant.recentUsage != null
        ? _formatDate(restaurant.recentUsage!)
        : '최근 사용 없음';

    return InkWell(
      onTap: () => _openRestaurantDetail(restaurant),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 110,
                height: 110,
                child: Image.network(restaurant.heroImage, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    restaurant.address,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(restaurant.categoryLabel, style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280))),
                      const SizedBox(width: 8),
                      const Icon(Icons.place_outlined, size: 14, color: Color(0xFFDC2626)),
                      Text(' ${restaurant.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 12.5, color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildStatChip(
                        icon: Icons.stars_rounded,
                        label: '스탬프 ${restaurant.stampCount}/${restaurant.stampGoal}',
                        background: const Color(0xFFE0E7FF),
                        foreground: const Color(0xFF312E81),
                      ),
                      _buildStatChip(
                        icon: Icons.card_giftcard,
                        label: '쿠폰 ${restaurant.availableCouponCount}/${restaurant.totalCouponCount}',
                        background: const Color(0xFFFFF7E6),
                        foreground: const Color(0xFFB45309),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('최근 사용: $recentUsage', style: const TextStyle(fontSize: 11.5, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101828),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('제휴 식당'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildCategoryFilter(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView.separated(
                  itemCount: _visibleRestaurants.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  padding: const EdgeInsets.only(bottom: 32),
                  itemBuilder: (context, index) {
                    return _buildRestaurantCard(_visibleRestaurants[index]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AffiliateRestaurantDetailPage extends StatefulWidget {
  const AffiliateRestaurantDetailPage({
    super.key,
    required this.restaurant,
    required this.adminPin,
    required this.onChanged,
  });

  final AffiliateRestaurant restaurant;
  final String adminPin;
  final VoidCallback onChanged;

  @override
  State<AffiliateRestaurantDetailPage> createState() => _AffiliateRestaurantDetailPageState();
}

class _AffiliateRestaurantDetailPageState extends State<AffiliateRestaurantDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isStamping = false;
  bool _isUsingCoupon = false;

  AffiliateRestaurant get restaurant => widget.restaurant;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<String?> _promptPin({required String title}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('관리자 PIN 4자리를 입력해주세요.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '0000',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.isEmpty) {
                      setState(() {
                        errorText = 'PIN을 입력해주세요.';
                      });
                      return;
                    }
                    Navigator.of(context).pop(value);
                  },
                  child: const Text('확인'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF312E81),
      ),
    );
  }

  Future<void> _handleStampCollect() async {
    final pin = await _promptPin(title: '스탬프 적립');
    if (pin == null) return;
    if (pin != widget.adminPin) {
      _showSnack('관리자 PIN이 올바르지 않습니다.', isError: true);
      return;
    }

    setState(() => _isStamping = true);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    setState(() {
      restaurant.addStamp();
      _isStamping = false;
    });
    widget.onChanged();
    _showSnack('스탬프가 적립되었습니다.');
  }

  Future<void> _handleCouponUse(String couponId) async {
    final pin = await _promptPin(title: '쿠폰 사용');
    if (pin == null) return;
    if (pin != widget.adminPin) {
      _showSnack('관리자 PIN이 올바르지 않습니다.', isError: true);
      return;
    }

    setState(() => _isUsingCoupon = true);
    await Future<void>.delayed(const Duration(milliseconds: 350));

    try {
      restaurant.useCoupon(couponId);
      setState(() => _isUsingCoupon = false);
      widget.onChanged();
      _showSnack('쿠폰 사용이 완료되었습니다.');
    } on ArgumentError catch (_) {
      setState(() => _isUsingCoupon = false);
      _showSnack('쿠폰 정보를 찾을 수 없습니다.', isError: true);
    }
  }

  Widget _buildHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(restaurant.heroImage, fit: BoxFit.cover),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Row(
                children: [
                  _circleIconButton(Icons.share),
                  const SizedBox(width: 8),
                  _circleIconButton(Icons.favorite_border),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                restaurant.name,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
              ),
              const SizedBox(height: 8),
              Text(restaurant.categoryLabel, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
              const SizedBox(height: 4),
              Text(
                '${restaurant.distanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleIconButton(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: const Color(0xFF4B5563)),
    );
  }

  Widget _buildStampBoard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111C44),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.card_giftcard, color: Color(0xFFFFD600)),
              SizedBox(width: 8),
              Text(
                '스탬프 혜택',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(restaurant.stampGoal, (index) {
              final filled = index < restaurant.stampCount;
              return Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: filled ? Colors.white : const Color(0xFF1E2959),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: filled
                    ? const Icon(Icons.restaurant, color: Color(0xFF1E2959))
                    : Text('${index + 1}', style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
              );
            }),
          ),
          const SizedBox(height: 16),
          const Text('현재 진행도', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: restaurant.stampCount / restaurant.stampGoal,
              minHeight: 8,
              backgroundColor: const Color(0xFF1E2959),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD600)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '리워드 획득까지 ${restaurant.stampGoal - restaurant.stampCount}개 남았어요!',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isStamping ? null : _handleStampCollect,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E2959),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_isStamping ? '적립 중...' : '스탬프 적립하기'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCouponList() {
    if (restaurant.coupons.isEmpty) {
      return const Text('보유 쿠폰이 없습니다.', style: TextStyle(color: Color(0xFF6B7280)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('보유 쿠폰', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Column(
          children: restaurant.coupons.map((coupon) {
            final used = coupon.isUsed;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: used ? const Color(0xFF1F2937) : const Color(0xFF1E2959),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          coupon.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        if (coupon.description != null) ...[
                          const SizedBox(height: 4),
                          Text(coupon.description!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          '만료일 ${_formatDate(coupon.expiresAt)}',
                          style: const TextStyle(color: Color(0xFFFFD600), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: used || _isUsingCoupon ? null : () => _handleCouponUse(coupon.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: used ? Colors.grey.shade500 : Colors.white,
                      foregroundColor: used ? Colors.white : const Color(0xFF1E2959),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    child: Text(used ? '사용완료' : '사용하기'),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildGallery() {
    if (restaurant.galleryImages.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: restaurant.galleryImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.network(restaurant.galleryImages[index], fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoTable() {
    Text infoLabel(String text) => Text(text, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13));
    Text infoValue(String text) => Text(text, style: const TextStyle(color: Color(0xFF1F2937), fontSize: 14, fontWeight: FontWeight.w600));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('기본 정보', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  infoLabel('주소'),
                  const SizedBox(height: 4),
                  infoValue(restaurant.address),
                  const SizedBox(height: 12),
                  infoLabel('전화번호'),
                  const SizedBox(height: 4),
                  infoValue(restaurant.phoneNumber),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  infoLabel('영업 시간'),
                  const SizedBox(height: 4),
                  infoValue(restaurant.businessHours),
                  const SizedBox(height: 12),
                  infoLabel('카테고리'),
                  const SizedBox(height: 4),
                  infoValue(restaurant.categoryLabel),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
        title: Text(restaurant.name),
      ),
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, _) {
            return [
              SliverToBoxAdapter(child: _buildHero()),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF312E81),
                    unselectedLabelColor: const Color(0xFF9CA3AF),
                    indicatorColor: const Color(0xFF312E81),
                    tabs: const [
                      Tab(text: '혜택'),
                      Tab(text: '매장정보'),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStampBoard(),
                    const SizedBox(height: 24),
                    _buildCouponList(),
                    const SizedBox(height: 24),
                    const Text('최근 적립 내역', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    ...restaurant.stampHistory.take(5).map((entry) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.stars_rounded, color: Color(0xFF6366F1)),
                        title: Text(entry.note, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(_formatDate(entry.accruedAt)),
                      );
                    }),
                  ],
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGallery(),
                    const SizedBox(height: 20),
                    _buildInfoTable(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;

  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}
