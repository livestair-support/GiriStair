# Claude Code・Codex 共通ルール

AGENTS.md、docs/DESIGN.md、docs/NATIVE_MIGRATION.mdを読んでから作業してください。

- iPhoneはnative/GiriStairのSwiftUI版。Androidは既存Flutter版です。
- LiveStairの実際のSwiftUI共通部品を移植して使います。LiveStair風の独自再実装へ戻しません。参照元はLiveStair `074206d2d92cefdf6e1a076900ed7af807ae1eb8`。
- LiveStairとの照合はアプリ全体に適用します。一覧だけに限定せず、5タブ・登録／詳細／編集・各一覧／プロフィール・集計／共有・カレンダー・シートに、対応するLiveStairの実装を使ってください。今後の追加画面も同じです。
- 共通部品を使っただけで一致としません。画面側の余白・字間／行間・値の固定幅・時刻とアイコンの位置・日付書式・空表示も比較します。共通変更は各タブへの影響を確認します。
- UI日時はDatePresentation.swiftの文脈別書式で統一し、JSON日時や集計の期間計算を変えません。

- native/GiriStair/CommonUI.swiftのソース由来の寸法・字体・色・Form/Listのrow背景と区切り線を継承します。ページ34bold標準design／セクション18boldRoundedを区別します。
- ネイティブTabView、NavigationStack、Picker、5分刻みUIDatePickerを使います。標準の戻る＜とジェスチャーを個別のアイコンへ置き換えません。未保存の編集は破棄確認か保護されたシートで扱います。
- 既存の機能とDocuments/giristair.jsonのschema1を保持します。原本保護・読込失敗ガード・原子的保存を維持します。
- 原本のアイコン・ロゴ・起動画面を継承します。
- 毎回の自動撮影は不要です。解析／データ互換性／ビルドを確認し、細かな見た目・操作は端末で確認します。
- LiveStairは変更せず、GiriStairも別ブランチ・PRまで。mainへ自動マージしません。
