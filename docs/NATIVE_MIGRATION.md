# iPhone版のSwiftUI移行（0.4.0）

Flutterの画面を調整してもLiveStairとの差が残ったため、ユーザーの指示によりiPhone版をSwift／SwiftUIへ切り替えます。Android版のFlutterコードは残します。

## 移植元

LiveStair `074206d2d92cefdf6e1a076900ed7af807ae1eb8`（2026-10-29の参照時点のmain）を読み取りました。LiveStair本体は一切変更しません。

- CommonUI.swift：テーマ、字体、AppCardSectionTitle、AppIndexHeaderCard、row背景、card、Form/Listの設定、検索、メニュー、保存時フィードバック。
- ContentView.swift：TabView、メイン見出し、一覧の検索・セグメント・条件行、カレンダーの年月操作。
- EventBasicEditor.swift：FormとPicker、入力ラベル、日時入力。
- LiveDetailView.swift・LiveListEventCard.swift：一覧カードと詳細行。
- JapaneseHolidays.swift：祝日規則を移植。
- TicketScheduleViews.swift・TicketScheduleGroups.swift：日程依存の参照。
- SettingsView.swift・VenueDetailView.swift・ArtistDetailView.swift・ScreenshotView.swift・LiveListShareView.swift：設定・各一覧／詳細・共有の参照。

音楽専用モデル等への依存を取り除き、GiriStairの生／ネット・通常／大会・日程・結果・思考へ接続します。iPhoneではFlutterの描画エンジンやUIKit bridgeを使いません。

## アプリとデータ

- native/GiriStairがiPhone本体。生成プロジェクトnative/GiriStair.xcodeprojはgit管理せず、.ci/native_project.pyとXcodeGenから生成。
- Bundle IDは既存のcom.livestair.giristair。同じアプリとして更新し、同じDocuments/giristair.jsonを読みます。
- schemaVersionは1。Flutterのキー、enum raw値、文字列ID、ISO日時、日付だけのeventDate、base64画像を保持します。
- 最初のnative書込前に読み込んだ原本をgiristair.flutter-v1.jsonへ退避。既存.bakと原子的writeを維持。読み込み失敗中は通常の保存を禁止します。
- JSONのバックアップと明示的な復元も継続。会・日程の削除で思考本文を失いません。
- 標準のSwiftUIの実装に合わせ、最低iOSはLiveStairと同じ18.1へ変更。旧Flutter版は15.5以降でした。
- native確認用バージョンは0.4.0。Codemagicの連番を引き続きbuild numberに使います。

## 確認方法

1. Pythonのnative生成テスト。
2. 実際のSwiftモデル・ストア・日程をコンパイルするnative/Tests/DomainRegression.swift。旧JSON・日時・原本退避・不正データ・書込失敗・周期重複・名前変更・結果区分を検証。
3. GitHub ActionsでSwiftUIアプリをiOS SDKでコンパイル。
4. Codemagicの「3. iPhone確認用（TestFlightへアップロード）」で端末へ渡す。細かな表示と操作は端末で確認。

毎回のスクリーンショット撮影は必須工程にしません。以前のFlutter撮影ワークフローは手動起動に限定します。SwiftUI版の見た目の完全一致やTestFlight実機確認を、自動コンパイル成功だけでは断定しません。

日時カレンダーの内容はLiveStair由来ですが、任意日時の共通行ではポップオーバーに載せています（元の登録画面は下部overlay）。その他のGiri固有機能の項目や順序は保持します。
