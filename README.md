# GiriStair

自分の大喜利への参加予定、締切、結果、回答やお題のメモを残すアプリです。FlutterでiPhone向けに先行開発し、Androidにも展開できる構成にしています。

## 画面

| タブ | 内容 |
| --- | --- |
| 登録 | 生大喜利／ネット大喜利、大会／通常会を選んで予定・記録を入力 |
| 一覧 | 登録した会の検索、詳細、編集 |
| 戦績 | 自分の大会の結果を振り返る |
| 思考 | 投稿期間中のネット大喜利に向けた回答メモ、主催会のお題作り、自由メモ |
| 設定 | 集計などの補助機能とアプリ情報 |

データは端末内に保存します。初期版はログイン、クラウド同期、締切通知、ストアへの自動公開を含みません。画面と保存データの仕様は [docs/SPEC.md](docs/SPEC.md) を参照してください。

## AI・GitHub・Codemagicで進める

ユーザーはiPhoneやPCでAIに変更を依頼し、GitHubで変更を取り込み、Codemagicでビルドし、TestFlightで確認します。PCにFlutterやXcodeを入れる必要はありません。

初回のアカウント設定と、毎回押すボタンは **[docs/SETUP.md](docs/SETUP.md)** にまとめています。AppleやCodemagicの登録は、このリポジトリのファイルが存在するだけでは完了しません。

## 開発・確認

Flutterは `codemagic.yaml` の `3.44.0` に固定しています。SDKを使える環境では次を実行します。

```sh
python3 .ci/prepare_project.py
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
```

`.ci/prepare_project.py` は `ios/`・`android/` がない場合だけ、一時フォルダに作ったFlutterの標準プロジェクトからnative部分をコピーします。`lib/`・`test/`・`pubspec.yaml` は上書きしません。既にnative部分がある場合はそのプロジェクトを使い、アプリの表示名とIDを確認します。

| Codemagicワークフロー | 内容 |
| --- | --- |
| 1. 確認（解析・テスト・iOSビルド） | 署名なしで解析、テスト、iOSコンパイルを確認。アップロードなし |
| 2. Android確認（デバッグAPK） | Android用のデバッグAPKを作成。Google Playへの公開なし |
| 3. iPhone確認用（TestFlightへアップロード） | 登録済みの署名設定を使い、確認用IPAをApp Store Connectに送信 |

ワークフローは手動で実行します。iPhone確認用ワークフローもApp Store審査には提出しません。TestFlightの内部テストへのテスター追加はApp Store Connectで行います。
