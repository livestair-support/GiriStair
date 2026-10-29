# LiveStairを基準にするUI仕様

iPhone版0.4以降はSwift／SwiftUIです。基準はLiveStair `074206d2d92cefdf6e1a076900ed7af807ae1eb8` の実コード。移植元・データ互換性は[NATIVE_MIGRATION.md](NATIVE_MIGRATION.md)を参照します。

## 共通部品

native/GiriStair/CommonUI.swiftへ、LiveStairのテーマ、AppCardSectionTitle、AppIndexHeaderCard、appSectionCardStyle、appTintedCard、appIndexListStyle、appEditorFormStyle、AppSearchField、AppMenuとカレンダーの内容を移植しています。新しい画面も実際のForm／Listの中でこれらを使います。Flutter向けの近似値はiPhoneの正解として扱いません。

ページ見出しは34 boldの標準design。セクションは18 bold Rounded、28pt badgeと14semibold symbolです。ラベルはsubheadline.medium、入力・選択値はbody、設定済み日付はsemiboldです。日本語フォントはSwiftUIのシステム指定を使い、family名の推測や独自フォント照合を行いません。

カードの色・背景・左アクセント・枠線、Formの余白、区切り線は移植した部品へ集約します。List／Formの標準曲率やタップ・スクロール・キーボード動作はSwiftUIへ任せます。本文を一律に太くしたり小さくしません。

## 操作

5タブはSwiftUI TabView。各タブはNavigationStackで状態を持ち、サブページの戻る＜とスワイプはOS標準です。選択はPicker.menu、参加予定→参加済は標準segmented Picker、時刻は5分刻みのUIDatePickerです。未定や既存時刻を開くだけで保存しません。

一覧はLiveStairの検索→セグメント→条件行とカードを基準にし、件数・折りたたみ・ソートを持ちます。生とネットを同格に扱い、カレンダーの期間線にはサイト名と投稿／投票を表示します。土日・祝日色はLiveStairのJapaneseHolidays由来です。

## ブランドと確認

ユーザー提供の原本はassets/brand/source。アイコンと起動画面の既存アセットをSwiftUIターゲットでも共有し、横ロゴは原本を変更せずリソースへコピーします。

自動撮影を毎回の確認条件にしません。データテストとビルドを通し、詳細な表示・戻る操作・キーボード・メニューは端末でLiveStairと比較します。Giri固有の機能・入力データを削って外観だけを合わせません。
