# GiriStair

自分の大喜利への参加予定、締切、結果、回答やお題のメモを残すアプリです。iPhone版はLiveStairを基準とするSwift／SwiftUIです。Android版は既存Flutter実装を維持します。

## 画面

| タブ | 内容 |
| --- | --- |
| 登録 | 生大喜利／ネット大喜利、大会／通常を選んで予定・記録を入力 |
| 一覧 | 登録した会の検索、詳細、編集 |
| 戦績 | 自分の大会の結果を振り返る |
| 思考 | ネット大喜利の日程に紐づくお題と回答案、自作のお題と使用状態、自由メモ |
| 設定 | 共有・集計・プレイヤー・テーマ・通知・バックアップ・サポート |

データは端末内に保存します。ログイン、クラウド同期、ストアへの自動公開はありません。設定から通知・JSONバックアップ・共有画像の作成ができます。参加者は登録画面の「文字貼り付け」「OCR読み取り」から追加できます（日本語の文字認識は端末内）。SwiftUI版はLiveStairと同じiOS 18.1以降に対応します。画面と保存データの仕様は [docs/SPEC.md](docs/SPEC.md) を参照してください。

## AI・GitHub・Codemagicで進める

ユーザーはiPhoneやPCでAIに変更を依頼し、GitHubで変更を取り込み、Codemagicでビルドし、TestFlightで確認します。PCにFlutterやXcodeを入れる必要はありません。

初回のアカウント設定と、毎回押すボタンは **[docs/SETUP.md](docs/SETUP.md)** にまとめています。AppleやCodemagicの登録は、このリポジトリのファイルが存在するだけでは完了しません。

## 開発・確認

iPhoneは `.ci/native_project.py` とXcodeGenでSwiftUIプロジェクトを生成します。通常はGitHub ActionsとCodemagicで確認し、PCへのインストールは不要です。データ移行は[docs/NATIVE_MIGRATION.md](docs/NATIVE_MIGRATION.md)を参照してください。

```sh
python3 .ci/native_project.py
xcodegen generate --spec native/project.json
xcodebuild -project native/GiriStair.xcodeproj -scheme GiriStair -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Android用のFlutter 3.44.0とlib/test、旧iPhoneプロジェクトは残しています。Androidの変更は従来どおりFlutterの解析・テスト・APKビルドを行います。

| Codemagicワークフロー | 内容 |
| --- | --- |
| 1. 確認（Swiftテスト・iOSビルド） | 署名なしで保存互換性のSwiftテストとSwiftUIアプリのコンパイルを確認。アップロードなし |
| 2. Android確認（デバッグAPK） | Android用のデバッグAPKを作成。Google Playへの公開なし |
| 3. iPhone確認用（TestFlightへアップロード） | 登録済みの署名設定を使い、確認用IPAをApp Store Connectに送信 |

ワークフローは手動で実行します。iPhone確認用ワークフローもApp Store審査には提出しません。TestFlightの内部テストへのテスター追加はApp Store Connectで行います。
