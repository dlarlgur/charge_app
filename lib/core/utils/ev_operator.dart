/// 충전 사업자명 정규화 — 서버 services/evOperatorFilter.js 의 Dart 포팅.
/// 원천(환경부) busi_nm 은 같은 사업자가 여러 이름으로 쪼개져 있어
/// ((주)/주식회사/㈜/공백/이름중복) 대표명으로 정규화한다.
/// AI 추천 필터(서버)와 지도·홈 필터(클라)가 반드시 같은 기준을 쓰도록 공용.
///
/// canonicalEvOperator(): 대표 12곳이면 대표명, 아니면 정리·병합된 원본명(롱테일).
library;

class _Rep {
  final String name;
  final RegExp re;
  const _Rep(this.name, this.re);
}

// 대표 사업자 — matcher 는 정규화된 이름(공백/(주)/주식회사 제거) 기준. 순서대로 첫 매칭.
final List<_Rep> _representatives = [
  _Rep('환경부', RegExp('환경부')),
  _Rep('한국전력', RegExp('한국전력|한전')),
  _Rep('채비', RegExp('채비')),
  _Rep('SK일렉링크', RegExp('일렉링크')),
  _Rep('SK시그넷', RegExp('시그넷')),
  _Rep('워터', RegExp('워터|브라이트에너지')),
  _Rep('에버온', RegExp('에버온')),
  _Rep('GS차지비', RegExp('차지비')),
  _Rep('파워큐브', RegExp('파워큐브')),
  _Rep('LG U+볼트업', RegExp('볼트업|엘지유플러스|LG유플러스', caseSensitive: false)),
  _Rep('플러그링크', RegExp('플러그링크')),
  _Rep('이지차저', RegExp('이지차저')),
];

// busiId 하드코딩 매핑 (이름이 브랜드와 다른 케이스)
const Map<String, String> _busiIdToRep = {'BE': '워터'};

final RegExp _legalRe = RegExp(r'㈜|\(주\)|주식회사|\(유\)|\(사\)|\(재\)');
final RegExp _spaceRe = RegExp(r'\s+');

/// 사업자명 정리 — 법인 접두/접미·공백 제거 + 이름 중복 접힘("스타코프스타코프"→"스타코프").
String cleanEvOperatorName(String? nm) {
  var s = (nm ?? '').replaceAll(_legalRe, '').replaceAll(_spaceRe, '');
  if (s.length >= 4 &&
      s.length % 2 == 0 &&
      s.substring(0, s.length ~/ 2) == s.substring(s.length ~/ 2)) {
    s = s.substring(0, s.length ~/ 2);
  }
  return s;
}

/// 스테이션의 대표 사업자명. 대표 12곳이면 대표명, 아니면 정리·병합된 이름(롱테일).
String canonicalEvOperator(String? busiNm, [String? busiId]) {
  if (busiId != null && _busiIdToRep.containsKey(busiId)) {
    return _busiIdToRep[busiId]!;
  }
  final s = cleanEvOperatorName(busiNm);
  if (s.isEmpty) return '';
  for (final r in _representatives) {
    if (r.re.hasMatch(s)) return r.name;
  }
  return s;
}
