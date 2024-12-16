import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:url_launcher/url_launcher.dart';
class UrlLauncherUtil {
  static Future<void> launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);

    try {
      if (await canLaunchUrl(url)) {
        final bool launched = await launchUrl(
          url,
          mode: LaunchMode.platformDefault,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );

        if (!launched) {
          final bool externalLaunched = await launchUrl(
            url,
            mode: LaunchMode.externalApplication,
          );

          if (!externalLaunched) {
            throw 'Could not launch $urlString';
          }
        }
      } else {
        throw 'Could not launch $urlString';
      }
    } catch (e) {
      try {
        final bool inAppLaunched = await launchUrl(
          url,
          mode: LaunchMode.inAppWebView,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );

        if (!inAppLaunched) {
          throw 'Could not launch $urlString';
        }
      } catch (e) {
        print('Error launching URL: $e');
        rethrow;
      }
    }
  }
}
class HomeContent extends StatefulWidget {
  @override
  _HomeContentState createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  final PageController _pageController = PageController();

  // URL 열기 함수
  // HomeContent 클래스 내부에서
  Future<void> _launchURL(String url) async {
    try {
      await UrlLauncherUtil.launchURL(url);
    } catch (e) {
      // 에러 발생시 사용자에게 알림
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('URL을 열 수 없습니다: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 공통 스타일
    final double padding = screenWidth * 0.04; // 화면 크기에 따라 여백 조정
    final double cardWidth = screenWidth * 0.35; // 카드 너비 비율
    final double pageViewHeight = screenWidth * 0.5;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        //centerTitle: true,
        title: Image.asset(
          'assets/images/wouldulike.png', // 로고 이미지 경로
          height: 20, // 원하는 높이로 설정
        ),
      ),

      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "오늘의 트렌드 뉴스" 섹션
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '오늘의 트렌드 뉴스',
                    style: TextStyle(
                      fontSize: screenWidth * 0.05,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  //Text(
                    //'전체 보기',
                    //style: TextStyle(
                      //color: Colors.blue,
                      //fontWeight: FontWeight.bold,
                      //fontSize: screenWidth * 0.035,
                   // ),
                  //),
                ],
              ),
              SizedBox(height: padding * 0.5),
              // PageView 섹션
              Container(
                height: pageViewHeight,
                child: PageView(
                  controller: _pageController,
                  children: [
                    _buildPage(
                      'assets/images/food1.png',
                      '면역력 강화를 위한 10가지 한식 슈퍼푸드',
                      '우리 몸에 좋은 전통 식재료 알아보기',
                      'https://www.naver.com/',
                    ),
                    _buildPage(
                      'assets/images/food_image2.png',
                      '피부 건강을 위한 필수 영양소',
                      '피부를 지키는 다양한 영양소들',
                      'https://www.naver.com/',
                    ),
                    _buildPage(
                      'assets/images/food_image3.png',
                      '건강을 위한 슈퍼푸드 소개',
                      '하루 한 번 건강을 챙기자',
                      'https://www.naver.com/',
                    ),
                    _buildPage(
                      'assets/images/food_image4.png',
                      '베스킨라빈스 아이스크림',
                      '하루 한 번 밥먹기',
                      'https://www.naver.com/',
                    ),
                  ],
                ),
              ),
              SizedBox(height: padding * 0.6),
              Center(
                child: SmoothPageIndicator(
                  controller: _pageController,
                  count: 4,
                  effect: WormEffect(
                    dotWidth: screenWidth * 0.02,
                    dotHeight: screenWidth * 0.02,
                    spacing: screenWidth * 0.02,
                  ),
                ),
              ),
              SizedBox(height: padding * 0.8),
              // "이번 주 핫한 메뉴" 섹션
              Text(
                '이번 주 가장 핫한 메뉴들을 만나보세요!',
                style: TextStyle(
                  fontSize: screenWidth * 0.045,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: padding * 0.7),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildMenuCard(
                      'assets/images/food_image4.png',
                      '스테이크 샐러드',
                      '신선한 조합이 당신을\n자극합니다',
                      cardWidth,
                    ),
                    _buildMenuCard(
                      'assets/images/food_image5.png',
                      '매콤 치킨버거',
                      '매콤한 치킨버거로\n입맛을 사로잡다',
                      cardWidth,
                    ),
                    _buildMenuCard(
                      'assets/images/food_image6.png',
                      '시그니처 스테이크',
                      '육즙 가득한\n스테이크의 향연',
                      cardWidth,
                    ),
                    _buildMenuCard(
                      'assets/images/food_image7.png',
                      '새로운 국수',
                      '국수로\n밥먹기',
                      cardWidth,
                    ),
                  ],
                ),
              ),
              SizedBox(height: padding * 0.8),
              // "이번 주 핫한 메뉴" 섹션
              Text(
              '당신의 입맛에 맞는 최적의 장소를 추천합니다!',
                style: TextStyle(
                  fontSize: screenWidth * 0.045,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: padding * 0.4),
              Container(
                height: screenHeight * 0.6, // 높이 조정
                child: ListView.builder(
                  itemCount: 5, // 4-5개 정도의 음식점 카드
                  itemBuilder: (context, index) {
                    return _buildRestaurantCard(
                      'assets/images/food_image${index + 1}.png',
                      '음식점${index + 1}',
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(String imagePath, String title, String subtitle, String url) {
    return GestureDetector(
      onTap: () => _launchURL(url), // 클릭 시 URL 열기
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: Stack(
          children: [
            Image.asset(
              imagePath,
              fit: BoxFit.cover,
              width: double.infinity,
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black.withOpacity(0.3),
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(String imagePath, String title, String description, double width) {
    return Container(
      width: width,
      margin: EdgeInsets.only(right: width * 0.05),
      decoration: BoxDecoration(
        color: Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            child: Image.asset(
              imagePath,
              height: width * 0.8,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(width * 0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: width * 0.09,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: width * 0.08,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 8),
                /*
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {},
                    child: Text(
                      '자세히 보기',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: width * 0.08,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Color(0xFF000080),
                      padding: EdgeInsets.symmetric(vertical: width * 0.0003),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),*/
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildRestaurantCard(String imagePath, String restaurantName) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isLiked = false; // 각 카드에 찜 상태를 위한 변수

        return Container(
          margin: EdgeInsets.only(bottom: 16.0),
          padding: EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.0),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 이미지
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Image.asset(
                      imagePath,
                      height: 100,
                      width: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(width: 16.0), // 이미지와 텍스트 간 간격

                  // 식당 이름 텍스트
                  Text(
                    restaurantName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // 찜 아이콘 버튼 (오른쪽 상단)
              Positioned(
                top: 0,
                right: 0,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return IconButton(
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.red : Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          isLiked = !isLiked; // 상태 변경
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}
