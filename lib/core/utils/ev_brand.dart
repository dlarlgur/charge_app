/// 브랜드 충전소 판정 — 서버 services/evBrand.js 와 규칙 동일 유지 필수 (쌍둥이 모듈).
/// BMW 차징스테이션 등 차량 브랜드 충전 네트워크는 원천(환경부)에 브랜드 코드가
/// 없어 충전소명 기반 파생 판정한다 (E-pit 만 busiId='HD').
/// 설계: charge_server/docs/brand_charger_filter_design.md (2026-08-05 형 승인, 5개)
library;

class EvBrandDef {
  final String code;
  final String label;
  final bool Function(String nm, String? busiId) match;
  const EvBrandDef(this.code, this.label, this.match);
}

final RegExp _reBmw = RegExp(r'^bmw');
final RegExp _rePorsche = RegExp('포르쉐|포르셰');
final RegExp _reAudi = RegExp('^아우디');
// '벤츠' 단독 매칭 금지 — "벤츠모텔"/"벤츠공업사" 노이즈 (설계서 엣지 케이스)
final RegExp _reBenz = RegExp('메르세데스|벤츠 ?hpc');

final List<EvBrandDef> evBrands = [
  EvBrandDef('BMW', 'BMW 차징스테이션', (nm, b) => _reBmw.hasMatch(nm)),
  EvBrandDef('EPIT', '현대 E-pit', (nm, b) => b == 'HD'),
  EvBrandDef('PORSCHE', '포르쉐', (nm, b) => _rePorsche.hasMatch(nm)),
  EvBrandDef('AUDI', '아우디', (nm, b) => _reAudi.hasMatch(nm)),
  EvBrandDef('BENZ', '벤츠 HPC', (nm, b) => _reBenz.hasMatch(nm)),
];

/// 충전소의 브랜드 코드. 브랜드가 아니면 null.
/// busiId 는 없어도 됨 — 그 경우 E-pit 판정만 스킵된다 (검토 1번).
String? evBrandOf(String? stationNm, String? busiId) {
  final nm = (stationNm ?? '').trim().toLowerCase();
  for (final b in evBrands) {
    if (b.match(nm, busiId)) return b.code;
  }
  return null;
}

/// 브랜드 코드 → 표시 라벨. 미지 코드는 그대로.
String evBrandLabel(String code) {
  for (final b in evBrands) {
    if (b.code == code) return b.label;
  }
  return code;
}
