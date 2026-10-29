# GiriStairの開発ルール

GiriStairのiPhone版は **Swift / SwiftUI**、Android版は既存のFlutter実装です。ユーザーはiPhoneとブラウザで確認するため、開発ツールのインストールを前提にしません。

- 作業前にREADME.md、docs/SPEC.md、docs/DESIGN.md、docs/SETUP.mdを確認します。
- iPhoneの本体は `native/GiriStair/`。`lib/`・`ios/Runner/*.swift` はAndroid用Flutter実装と旧iPhone実装です。iPhoneの変更をFlutter側だけへ入れないでください。
- **LiveStairの実コードがデザインと操作の基準**です。LiveStair本体は参照専用で一切変更しません。移植元はdocs/NATIVE_MIGRATION.mdに固定します。参照不能なら推測で作らず報告します。
- 新しい画面も、移植したCommonUI.swiftの実際のForm/List/Picker・AppCardSectionTitle・appSectionCardStyle・appIndexListStyleを使います。字体・角丸・行高を個別の近似値へ置き換えません。
- ページタイトルは34 boldの標準design、セクション見出しは18 bold Roundedです。すべてをRoundedや同じweightにしません。日本語はiOSのシステムフォントへ任せます。
- TabView・NavigationStackの標準タブ／戻る＜、SF Symbols、Picker.menuを使います。独自の偽タブ／戻るボタンは作りません。時刻は5分刻み、既存の未定値や1分単位の時刻を開くだけで書き換えません。
- タブは登録・一覧・戦績・思考・設定。一覧の参加予定→参加済の順、生／ネットの同格、サイト周期／ステージ／お題回／自己結果／全体入賞者の区別を維持します。
- Bundle ID `com.livestair.giristair`、Documents/giristair.json、schemaVersion 1と既存JSONのキー・enum値・画像・メモ・IDを維持します。読込失敗を空データとして上書きしません。保存成功はdurable write後だけ通知します。
- 初回native保存前に旧ファイル原本をgiristair.flutter-v1.jsonへ保存します。期間終了・会の削除で思考メモを消しません。
- 提供ブランド原本はassets/brand/source。アイコン・起動画面は既存Assets.xcassets、横ロゴはnative生成時に原本をコピーします。描き直し・再配色はしません。
- `.ci/native_project.py` + XcodeGenでnativeプロジェクトを生成します。CodemagicのiPhoneワークフローはSwift版をビルドします。署名キー・証明書はリポジトリへ入れません。
- 確認の基本は保存互換性テストとiOSビルドです。**自動撮影を毎回の必須工程にせず、細かな表示・操作はユーザーの端末確認を優先**します。
- 実行できないSwift／実機／署名／TestFlight確認は未実施と明記します。別ブランチとPRで渡し、勝手にmainへマージしません。
