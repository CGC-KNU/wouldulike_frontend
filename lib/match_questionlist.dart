// questions.dart

class Question {
  final String questionText;
  final List<Answer> answers;

  Question({
    required this.questionText,
    required this.answers,
  });
}

class Answer {
  final String text;
  final String subtitle;  // 부연 설명을 위한 필드 추가
  final int score;

  Answer({
    required this.text,
    required this.subtitle,
    required this.score,
  });
}

class QuestionData {
  static List<Question> questions = [
    Question(
      questionText: '오늘의 기분은 어떤가요?',
      answers: [
        Answer(
            text: '정적',
            subtitle: '날씬한 것 같은 기분이에요!',
            score: 1
        ),
        Answer(
            text: '무난무난해요',
            subtitle: '평범하고 안정적이에요',
            score: 2
        ),
        Answer(
            text: '좀 짜증나요',
            subtitle: '조용히 쉬고 싶네요.',
            score: 3
        ),
      ],
    ),
    Question(
      questionText: '어떤 분위기를 원하시나요?',
      answers: [
        Answer(
            text: '활기찬 분위기',
            subtitle: '신나고 즐거운 시간을 보내고 싶어요',
            score: 1
        ),
        Answer(
            text: '차분한 분위기',
            subtitle: '조용하고 평화로운 시간을 보내고 싶어요',
            score: 2
        ),
        Answer(
            text: '아늑한 분위기',
            subtitle: '편안하고 따뜻한 시간을 보내고 싶어요',
            score: 3
        ),
      ],
    ),
    Question(
      questionText: '오늘 식사 예산은 어느정도인가요?',
      answers: [
        Answer(
            text: '가성비 최고',
            subtitle: '1만원 이하로 맛있게 먹고싶어요',
            score: 1
        ),
        Answer(
            text: '적당한 가격',
            subtitle: '1-2만원 정도 생각하고 있어요',
            score: 2
        ),
        Answer(
            text: '가격은 중요하지 않아요',
            subtitle: '맛있다면 얼마든지!',
            score: 3
        ),
      ],
    ),
    Question(
      questionText: '어떤 종류의 음식을 선호하시나요?',
      answers: [
        Answer(
            text: '한식',
            subtitle: '든든하고 건강한 한식이 좋아요',
            score: 1
        ),
        Answer(
            text: '양식',
            subtitle: '피자나 파스타가 끌려요',
            score: 2
        ),
        Answer(
            text: '아시안',
            subtitle: '이국적인 맛을 즐기고 싶어요',
            score: 3
        ),
      ],
    ),
    Question(
      questionText: '매운 음식은 어느정도 드실 수 있나요?',
      answers: [
        Answer(
            text: '매운거 좋아해요',
            subtitle: '불닭볶음면도 잘 먹어요',
            score: 1
        ),
        Answer(
            text: '적당히 매운맛',
            subtitle: '신라면 정도는 괜찮아요',
            score: 2
        ),
        Answer(
            text: '매운건 어려워요',
            subtitle: '순한맛이 좋아요',
            score: 3
        ),
      ],
    ),
    Question(
      questionText: '식사 소요시간은 어느정도 예상하시나요?',
      answers: [
        Answer(
            text: '빠르게',
            subtitle: '30분 이내로 먹고싶어요',
            score: 1
        ),
        Answer(
            text: '여유있게',
            subtitle: '1시간 정도 생각하고 있어요',
            score: 2
        ),
        Answer(
            text: '천천히',
            subtitle: '시간에 구애받지 않고 즐기고 싶어요',
            score: 3
        ),
      ],
    ),
    Question(
      questionText: '어떤 자리 배치를 선호하시나요?',
      answers: [
        Answer(
            text: '테이블 좌석',
            subtitle: '편하게 앉아서 먹고싶어요',
            score: 1
        ),
        Answer(
            text: '룸 좌석',
            subtitle: '프라이빗한 공간이 좋아요',
            score: 2
        ),
        Answer(
            text: '바 좌석',
            subtitle: '분위기있게 즐기고 싶어요',
            score: 3
        ),
      ],
    ),
    Question(
      questionText: '식사 후 어떤 계획이 있으신가요?',
      answers: [
        Answer(
            text: '디저트 타임',
            subtitle: '카페에서 달달한 것도 먹고싶어요',
            score: 1
        ),
        Answer(
            text: '산책하기',
            subtitle: '근처 공원을 걸어볼까 해요',
            score: 2
        ),
        Answer(
            text: '바로 귀가',
            subtitle: '식사만 하고 들어갈 예정이에요',
            score: 3
        ),
      ],
    ),
  ];
}