class SchoolOption {
  const SchoolOption({
    required this.code,
    required this.name,
  });

  final String code;
  final String name;
}

class CollegeOption {
  const CollegeOption({
    required this.code,
    required this.name,
  });

  final String code;
  final String name;
}

class DepartmentOption {
  const DepartmentOption({
    required this.code,
    required this.collegeCode,
    required this.name,
  });

  final String code;
  final String collegeCode;
  final String name;
}

const List<SchoolOption> knuSchools = <SchoolOption>[
  SchoolOption(code: 'KNU', name: '경북대학교'),
];

const List<CollegeOption> knuColleges = <CollegeOption>[
  CollegeOption(code: 'HUM', name: '인문대학'),
  CollegeOption(code: 'SOC', name: '사회과학대학'),
  CollegeOption(code: 'NAT', name: '자연과학대학'),
  CollegeOption(code: 'BUS', name: '경상대학'),
  CollegeOption(code: 'ENG', name: '공과대학'),
  CollegeOption(code: 'ITC', name: 'IT대학'),
  CollegeOption(code: 'AGR', name: '농업생명과학대학'),
  CollegeOption(code: 'ART', name: '예술대학'),
  CollegeOption(code: 'EDU', name: '사범대학'),
  CollegeOption(code: 'MED', name: '의과대학'),
  CollegeOption(code: 'DEN', name: '치과대학'),
  CollegeOption(code: 'VET', name: '수의과대학'),
  CollegeOption(code: 'HSC', name: '생활과학대학'),
  CollegeOption(code: 'NUR', name: '간호대학'),
  CollegeOption(code: 'PHA', name: '약학대학'),
  CollegeOption(code: 'ADV', name: '첨단기술융합대학'),
  CollegeOption(code: 'ECO', name: '생태환경대학'),
  CollegeOption(code: 'SCI', name: '과학기술대학'),
  CollegeOption(code: 'PAD', name: '행정학부'),
  CollegeOption(code: 'AUT', name: '자율전공학부'),
  CollegeOption(code: 'EAA', name: '공과대학/농업생명과학대학'),
  CollegeOption(code: 'FUT', name: '자율미래인재학부'),
];

List<DepartmentOption> _buildDepartments(
  String collegeCode,
  List<String> names,
) {
  return List<DepartmentOption>.generate(names.length, (int index) {
    final number = (index + 1).toString().padLeft(3, '0');
    return DepartmentOption(
      code: '${collegeCode}_$number',
      collegeCode: collegeCode,
      name: names[index],
    );
  });
}

final List<DepartmentOption> knuDepartments = <DepartmentOption>[
  ..._buildDepartments('HUM', <String>[
    '국어국문학과',
    '사학과',
    '불어불문학과',
    '중어중문학과',
    '일어일문학과',
    '노어노문학과',
    '영어영문학과',
    '철학과',
    '독어독문학과',
    '고고인류학과',
    '한문학과',
    '인문대학 자율학부',
  ]),
  ..._buildDepartments('SOC', <String>[
    '정치외교학과',
    '지리학과',
    '심리학과',
    '미디어커뮤니케이션학과',
    '사회학과',
    '문헌정보학과',
    '사회복지학부',
    '사회과학대학 자율학부',
  ]),
  ..._buildDepartments('NAT', <String>[
    '수학과',
    '물리학과',
    '화학과',
    '생물학과',
    '생명공학부',
    '통계학과',
    '지구시스템과학부',
    '지질학전공',
    '천문대기과학전공',
    '해양학전공',
    '자연과학대학 자율학부',
  ]),
  ..._buildDepartments('BUS', <String>[
    '경제통상학부',
    '경영학부',
    '경상대학 자율학부',
  ]),
  ..._buildDepartments('ENG', <String>[
    '금속재료공학과',
    '신소재공학과',
    '기계공학부',
    '기계공학전공',
    '기계설계학전공',
    '로봇/자동화전공',
    '건축학부',
    '건축학전공',
    '건축공학전공',
    '응용화학과',
    '토목공학과',
    '화학공학과',
    '고분자공학과',
    '섬유시스템공학과',
    '환경공학과',
    '에너지공학부',
    '신재생에너지전공',
    '에너지변환전공',
    '공과대학 자율학부',
  ]),
  ..._buildDepartments('ITC', <String>[
    '전자공학부',
    '회로및임베디드시스템공학전공',
    '반도체및디스플레이공학전공',
    '멀티미디어및의공학전공',
    '전자파및광전자공학전공',
    '인공지능및신호처리전공',
    '정보통신공학전공',
    '지능시스템및제어공학전공',
    '전자공학부 인공지능전공',
    '전자공학부 모바일공학전공',
    '컴퓨터학부',
    '플랫폼소프트웨어전공',
    '데이터과학전공',
    '인공지능컴퓨팅전공',
    '글로벌소프트웨어융합전공',
    '전기공학과',
    'IT대학 자율학부',
    'IT 첨단자율학부',
  ]),
  ..._buildDepartments('AGR', <String>[
    '응용생명과학부',
    '식물생명과학전공',
    '환경생명화학전공',
    '식물의학과',
    '식품공학부',
    '식품생물공학전공',
    '식품소재공학전공',
    '식품응용공학전공',
    '산림과학·조경학부',
    '임학전공',
    '임산공학전공',
    '조경학전공',
    '원예과학과',
    '바이오섬유소재학과',
    '농업토목공학과',
    '스마트생물산업기계공학과',
    '농산업학과',
    '식품자원경제학과',
    '농업생명과학대학 자율학부',
  ]),
  ..._buildDepartments('ART', <String>[
    '음악학과',
    '국악학과',
    '미술학과',
    '디자인학과',
  ]),
  ..._buildDepartments('EDU', <String>[
    '교육학과',
    '영어교육과',
    '역사교육과',
    '일반사회교육과',
    '수학교육과',
    '화학교육과',
    '지구과학교육과',
    '체육교육과',
    '국어교육과',
    '유럽어교육학부',
    '독어교육전공',
    '불어교육전공',
    '지리교육과',
    '윤리교육과',
    '물리교육과',
    '생물교육과',
    '가정교육과',
    '정보·컴퓨터교육과',
  ]),
  ..._buildDepartments('MED', <String>[
    '의학과',
    '의예과',
  ]),
  ..._buildDepartments('DEN', <String>[
    '치의학과',
    '치의예과',
  ]),
  ..._buildDepartments('VET', <String>[
    '수의학과',
    '수의예과',
  ]),
  ..._buildDepartments('HSC', <String>[
    '아동학부',
    '아동가족학전공',
    '아동학전공',
    '의류학과',
    '식품영양학과',
  ]),
  ..._buildDepartments('NUR', <String>[
    '간호학과',
  ]),
  ..._buildDepartments('PHA', <String>[
    '약학과',
  ]),
  ..._buildDepartments('ADV', <String>[
    '융합학부',
    '수소및신재생에너지전공',
    '혁신신약학과',
    '로봇공학과',
    '스마트모빌리티공학과',
    '우주공학부',
    '의생명융합공학과',
    '첨단기술융합대학 자율학부 1',
    '첨단기술융합대학 자율학부 2',
  ]),
  ..._buildDepartments('ECO', <String>[
    '식물자원학과',
    '곤충생명과학과',
    '체육학부',
    '체육학전공',
    '건강운동관리전공',
    '산림생태보호학과',
    '관광학과',
    '축산학과',
    '동물생명공학과',
    '말/특수동물학과',
  ]),
  ..._buildDepartments('SCI', <String>[
    '건설방재공학과',
    '정밀기계공학과',
    '소프트웨어학과',
    '에너지화학공학과',
    '섬유패션디자인학부',
    '섬유공학전공',
    '패션디자인전공',
    '환경안전공학과',
    '자동차공학부',
    '친환경자동차전공',
    '지능형자동차전공',
    '나노신소재공학과',
    '식품외식산업학과',
    '위치정보시스템학과',
    '스마트플랜트공학과',
    '치위생학과',
  ]),
  ..._buildDepartments('PAD', <String>[
    '행정학부',
  ]),
  ..._buildDepartments('AUT', <String>[
    '자율전공학부',
  ]),
  ..._buildDepartments('EAA', <String>[
    '공학 첨단자율학부',
  ]),
  ..._buildDepartments('FUT', <String>[
    '자율미래인재학부',
  ]),
];
