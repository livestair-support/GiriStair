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

機能の変更時はAGENTS.md「0.5以降の機能ルール」とdocs/FEATURE_REVISION_05.mdを参照してください。4種別を独立して扱い、参加状況は日時から導出し、通過後の次段階はユーザー保存前に作成しません。LiveStairのサジェスト、詳細と思考の遷移、保存互換性を新しいページでも維持します。

通常サイトの周期・リーグ・シーズンとお題/回答の分類はdocs/SITE_CYCLES.mdを参照します。投稿中／投票中が明確なカード、一覧と戦績の同じ形式タブ、準備中サポートの非リンク表示を維持してください。

一覧の形式切替は実UIテストを含めて確認します。シーズンの不明な開始日や終了日を逆算せず、共有は設定とプレビューを分け、0.7のAGENTS.mdを継承します。

一覧の時刻更新はページ側のTimelineViewにまとめ、サイトカードへ現在時刻を渡します。Listセル内へ別のTimelineViewを重ねません。
