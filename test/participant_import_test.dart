import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/participant_import.dart';

void main() {
  test('コピー/OCRの番号と見出しを除き重複をまとめる', () {
    expect(
      parseParticipantNames(
        '参加者一覧（７０人）\n1. 田中\n2） 佐藤\n・山田、田中\nhttps://twipla.jp/events/123\n大喜利 A',
      ),
      ['田中', '佐藤', '山田', '大喜利 A'],
    );
  });

  test('名前のスペースと記号を保持し70人以上取り込める', () {
    final names = List.generate(75, (i) => 'Player $i');
    expect(parseParticipantNames(names.join('\n')), names);
    expect(parseParticipantNames('A-B / C\nC++'), ['A-B / C', 'C++']);
  });

  test('検索はかな・英字の大小・全半角を吸収する', () {
    expect(playerSearchKey('タナカ Ａ'), playerSearchKey('たなか a'));
    expect(
      playerSearchKey('ｶﾞｷﾞｸﾞｹﾞｺﾞ ﾊﾟﾋﾟﾌﾟﾍﾟﾎﾟ'),
      playerSearchKey('がぎぐげご ぱぴぷぺぽ'),
    );
    expect(playerSearchKey('か\u3099'), playerSearchKey('ガ'));
    expect(parseParticipantNames('PLAYER\nＰｌａｙｅｒ'), ['PLAYER']);
  });
}
