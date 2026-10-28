/// Normalizes search and duplicate matching without changing the displayed name.
String playerSearchKey(String text) {
  const halfwidth = 'ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ';
  const fullwidth = 'ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン';
  const unvoiced = 'ウカキクケコサシスセソタチツテトハヒフヘホ';
  const voiced = 'ヴガギグゲゴザジズゼゾダヂヅデドバビブベボ';
  const semiUnvoiced = 'ハヒフヘホ';
  const semiVoiced = 'パピプペポ';
  final runes = <int>[];
  for (var rune in text.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) rune -= 0xFEE0;
    if (rune == 0x3000) rune = 0x20;
    final halfIndex = halfwidth.indexOf(String.fromCharCode(rune));
    if (halfIndex >= 0) rune = fullwidth.codeUnitAt(halfIndex);
    final dakuten = rune == 0xFF9E || rune == 0x3099 || rune == 0x309B;
    final handakuten = rune == 0xFF9F || rune == 0x309A || rune == 0x309C;
    if ((dakuten || handakuten) && runes.isNotEmpty) {
      var previous = runes.last;
      if (previous >= 0x3041 && previous <= 0x3096) previous += 0x60;
      final from = dakuten ? unvoiced : semiUnvoiced;
      final to = dakuten ? voiced : semiVoiced;
      final index = from.indexOf(String.fromCharCode(previous));
      if (index >= 0) {
        runes[runes.length - 1] = to.codeUnitAt(index);
        continue;
      }
    }
    runes.add(rune);
  }
  final normalized = String.fromCharCodes(
    runes.map((rune) => rune >= 0x30A1 && rune <= 0x30F6 ? rune - 0x60 : rune),
  );
  return normalized.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Parses copied participant lists or OCR output. Names containing spaces remain
/// intact; source headings and URLs are omitted. The caller previews candidates
/// before applying them because OCR can include text other than player names.
List<String> parseParticipantNames(String source) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in source.split(RegExp(r'[\r\n,，、\t]+'))) {
    var name = raw.trim();
    name = name.replaceFirst(
      RegExp(r'^\s*(?:[-・●○■□▪︎•]\s*|[0-9０-９]+[.．)）:：]\s*)'),
      '',
    );
    name = name.replaceFirst(RegExp(r'^@(?=\S)'), '').trim();
    if (name.isEmpty ||
        RegExp(r'^(?:https?://|www\.)', caseSensitive: false).hasMatch(name) ||
        RegExp(
          r'^(?:参加者(?:一覧)?|参加予定(?:者)?|参加(?:する)?人|参加者名|名前|参加者リスト|キャンセル待ち)(?:\s*[（(]?[0-9０-９]+\s*人?[)）]?)?\s*[:：]?$',
        ).hasMatch(name)) {
      continue;
    }
    final key = playerSearchKey(name);
    if (seen.add(key)) result.add(name);
  }
  return result;
}
