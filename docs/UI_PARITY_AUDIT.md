# LiveStairとの照合記録

参照コミット: `8431bb50778d7b5f22f73226d3306f9e2f9f0d5e`。CommonUI.swift、EventBasicEditor.swift、ContentView.swiftをGitHubから読み取り、参照用コピーで照合しました。LiveStairのファイルは変更していません。会話中のスクリーンショットも参考にしています。

## 修正前に確認した差

| 対象 | LiveStairの実装 | GiriStairの差と対応 |
| --- | --- | --- |
| 字体 | AppCardSectionTitleは18 bold Rounded、MainTabTitleLabelは34 bold。入力・Pickerにfont上書きなし | 一律w500を廃止し、regular/medium/semibold/boldを役割で分離。Roundedは端末descriptorを使用 |
| 日本語 | SwiftUIシステムフォントcascade | UIFont/CoreTextで実際の日本語familyを取得し、役割別weightで指定。PostScript名をfamilyとして渡す誤りを修正。Flutter側の実描画も確認が必要 |
| 行高 | editorRowInsets上下8・左右16、defaultMinListRowHeight48、section gap14、top margin8 | 独自vertical5/min38、cardmargin7とscrolltop4から参照値へ |
| 見出し・保存 | MainTabTitleHeader左右18・上8・下14、保存17 bold/44高 | 保存tap boxにより見出しが高かった。44へ揃え、登録と編集のナビゲーションを区別 |
| Formの境界 | listRowInsetsを使うseparator | 全行全幅だった線を左右16へ。continuous cornerを近似 |
| タブ | ContentView.mainTabViewは標準TabView/tabItem。独自pillなし | 独自blur・pill・余白・hapticを廃止し、iPhoneではUITabBarControllerへ |
| メニュー | 右側の固定サイズPicker(.menu)。attendanceだけsensoryFeedback | 行全体のshowGeneralDialogから、右側のnative UIButton/UIMenuへ |
| 日付・時刻 | 独自カレンダーは日を押して確定。compact DatePicker70×32 | 日付のDone手順を廃止、compact時刻へ。月・年移動も合わせる |
| 非iOS | 対象外 | Appleフォント強制を除去。native UIはiOSの起動確認後だけ有効化 |

主な根拠はCommonUIのAppCardSectionTitle/AppSectionCardModifier/MainTabTitleLabel/MainTabTitleHeaderと、EventBasicEditorのeditorRowInsets/editorCardSectionHeader/editorFieldLabel/basicSection/categoryPicker/attendancePicker/dateRow/EventEditorTimePickerButton/EventDateCalendarPickerViewです。

字体の解決経路も固定Flutter SDKのengineと、DEPSで固定された[SkiaのCoreText manager](https://github.com/google/skia/blob/e9ed4fc9f1544c58d8a9347c1fc9471d8dd7c465/src/ports/SkFontMgr_mac_ct.cpp#L337)で確認しました。SkParagraphの[family照合](https://github.com/google/skia/blob/e9ed4fc9f1544c58d8a9347c1fc9471d8dd7c465/modules/skparagraph/src/FontCollection.cpp#L185)はfamily名を要求します。本文・Rounded・日本語に端末のfamily名を使い、weightは別に渡します。本文のLatin system familyを日本語より先に置き、Displayはengine登録済みのproxyを維持します。family情報がない場合、PostScript名で代用せず既存の標準fallbackに戻します。テストは描画へ届くstyleも検査しますが、実際のグリフ一致を証明するものではありません。

## 合わせられるものと残る差

寸法、余白、色、文字の役割、行順、選択値更新、キーボード対応はFlutter側で合わせられます。タブ、Pickerメニュー、compact時刻のOS依存部分は実際のUIKitを使います。Roundedや日本語faceを端末から取得しても、Flutterの文字組み・fallbackがSwiftUIと完全に同じとはコード上だけで証明できません。

Form自体はSwiftUI Formではありません。曲率、OS更新によるリスト余白、カーソル・選択ハンドル、画面遷移の細かい物理特性、FlutterのCupertino確認ダイアログには差が残る可能性があります。LiveStairの未定時刻は最初のタップで18時・19時を設定しますが、GiriStairの開始・終了に無関係な時刻を保存しないよう、未定を保持して選択させます。投稿・投票日時はGiriStairの確定シートを維持します。時刻の刻みはLiveStairが5分、GiriStairは既存の1分単位の入力を維持します。カレンダーの日本の祝日色は移植せず、週末色を合わせます。

## 検証方法

Flutter 3.44.0で整形・静的解析・機能テストと、行高・余白・keyboard・字体役割・native channelの回帰検査を行います。Android向けフォントとnative UIの無効化も検査します。iOS preview workflowはXcode/iOS 26以降の実シミュレーターでGiriStairをビルドし、登録PNGと機種・OS・SDKのmetadataを保存します。これはLiveStair本体の画像ではありません。

両アプリを同じiPhone・iOS・文字サイズ「標準」・ライト表示で開き、次を比較してください。

1. 登録タイトル、基本情報、形式ラベル、通常会の値、placeholder、保存の字形とベースライン。
2. 形式・参加状況の右側を押し、チェック、表示位置、外側タップ、選択更新、触覚の違い。
3. 日付の月・年移動と日を押して閉じる動作。時刻を選ばなければ未定のままであること。
4. タブの選択pill・SF Symbols・文字・下端距離、キーボードとタブ再表示、入力保持。
5. 一覧・戦績・思考・設定・詳細・編集の見出しとカード、拡大文字・ダーク・横向きの崩れ。

検査結果はPRに記載します。シミュレーター画像と、実機で2アプリを同条件にした比較は区別します。署名付きビルド・TestFlight配信・実機確認を実施済みとは扱いません。
