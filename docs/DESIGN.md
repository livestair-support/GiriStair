# LiveStairに合わせるUI仕様

基準はLiveStairのSwiftUI実装です。従来のGiriStairの値を正解とは扱いません。参照は [LiveStair 8431bb5](https://github.com/livestair-support/LiveStair/tree/8431bb50778d7b5f22f73226d3306f9e2f9f0d5e)。LiveStairは変更しません。調査結果と確認範囲は [照合記録](UI_PARITY_AUDIT.md) に残します。

## 文字

`StairTypography.role` で役割を分けます。iPhoneの `appFontSize` 倍率は1.0です。

| 要素 | SwiftUIの指定 | GiriStair |
| --- | --- | --- |
| ページタイトル | 34 bold、標準design | pageTitle |
| セクションタイトル | 18 bold、Rounded | sectionTitle |
| 左ラベル | subheadline.medium（15） | formLabel |
| 入力・placeholder・Picker値 | body（17 regular） | input / value |
| 設定済み日付 | body.semibold（17） | dateValue |
| 保存 | headline.bold（17） | saveButton |
| 補助文字 | footnote（13）/caption（12） | footnote / caption |

本文を一律w500にしません。固定行高1.25も廃止し、自然なメトリクスを使います。ロケールはja_JPです。iOS起動時にUIFont/CoreTextから取得した本文・日本語fallback・Roundedの**family名**を使い、役割ごとのweightを指定します。ページタイトルなどDisplayはFlutterが登録する `CupertinoSystemDisplay` を維持します。端末情報がない場合はFlutterの標準 `CupertinoSystemText` / `CupertinoSystemDisplay` と日本語familyへ退避します。

SkiaのCoreText照合は `kCTFontFamilyNameAttribute` を必須条件にするため、PostScriptのface名をfamily欄へ渡しません（[固定SDKに対応する実装](https://github.com/google/skia/blob/e9ed4fc9f1544c58d8a9347c1fc9471d8dd7c465/src/ports/SkFontMgr_mac_ct.cpp#L337)）。Latin用system familyを先に置き、日本語fallbackが英数字の第一候補になるのを防ぎます。フォントファイルの同梱や私的なフォント名の推測はしません。AndroidへApple専用フォント名を強制しません。

## Form・カード

登録はEventBasicEditorのFormを基準に、最小行高48、行内余白は上下8・左右16、セクション間隔14、先頭余白8です。拡大文字では高さを伸ばします。参加者だけは多数入力用の既存44行を維持します。

セクション見出しは28のbadge・glyph14 semibold・文字18 bold Rounded。登録badgeの背景はアクセント色の0.12、汎用は0.14です。メイン見出しは38のbadge・glyph19 boldと34 boldの文字、余白は左右18・上8・下14、保存は44高です。

用途色は `StairColors` にまとめます。カードは淡いtint、continuousの角丸、細い枠、左3のアクセントです。Form行の区切り線は左右16、見出し直下は全幅です。追加依頼に従い線は0.75pt、黒0.20／白0.22へ強めます。OSが描くFormの正確な曲率はRoundedSuperellipseで近似します。時刻は70×32・モノスペース数字、未定操作との境界に短い縦線を置きます。

キーボードで画面をリサイズし、入力を保持します。下部タブを隠したときは末尾余白を縮めます。編集画面は44高のナビゲーションと別の大きな見出しを使います。

## iPhoneの標準部品

- タブは実際のUITabBarControllerです。独自カプセルや選択pillをFlutterで描きません。SF Symbols・文字・背景・選択形状・アニメーション・safe areaはOSが決定します。iOS 26の外観はiOS 26 SDK以降でリンクしたビルドで確認します。
- Pickerは右側に実際のUIButton/UIMenuを置き、ラベル・ⓘとは別のタップ領域にします。チェック・位置・開閉・キャンセルをOSへ任せます。外側で閉じても値を変えません。参加状況だけselection feedbackを付けます。
- 時刻はcompact UIDatePickerです。すべての時刻選択は5分刻みです。既存の1分単位の日時はキャンセル時に丸めて保存しません。未定を押しただけで架空の時刻を保存しません。投稿・投票日時はnative wheelと確定・キャンセルを使います。
- サブページはStairNavigationBar/StairBackButtonを使います。iPhoneの戻る＜はUINavigationBarの標準back itemで描画し、Flutter側のルート・未保存確認・戻るジェスチャーを維持します。
- 会場のマップはMapKitの検索・選択・190pt/角丸16のプレビューです。検索は押したときだけ行い、位置情報許可は要求しません。Android等は地図URLと外部マップを使えます。
- 日付はLiveStair独自カレンダーをFlutterで合わせ、日を押して確定します。月・年移動、未定への解除、外側タップのキャンセルを用意します。
- badgeのアイコンは端末のSF Symbolsを実際に描画して使い、非iOS・未対応アイコンはFlutterへfallbackします。
- 5タブ、IndexedStackの状態保持、各画面の機能を維持します。Androidと広い画面はCupertinoTabBarへfallbackします。

一覧はLiveStairの一覧／月間カレンダー切替・年月移動を基準にします。期間線にサイト名と投稿／投票を明記し、生・ネットに表示上の優劣を付けません。土曜は青、日曜・祝日は赤です。祝日はJapaneseHolidays.swiftと同じ規則で計算します。

0.3のデータ・集計・周期管理仕様はSPEC.md、要件はWORKFLOW_REVISION.mdを参照します。保存互換性を保ち、近似箇所と検証範囲は照合記録・PRに明記します。

ブランド素材はユーザー提供のアイコン・横長ロゴ・起動画面を使用します。原本、OS用サイズ、読込画面と共有画像への適用は [BRAND_ASSETS.md](BRAND_ASSETS.md) に定義します。起動背景のクリーム色はブランド画像用で、既存の画面アクセント色を一律に変更しません。
