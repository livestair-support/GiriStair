# GiriStairのアイコン・ロゴ・起動画面

横長ロゴ・起動画面は2026年10月29日の提供原本を採用しています。アプリアイコンは2026年10月30日に追加された、縮小時にも読みやすい1254×1254の画像へ差し替えました。描き直し・生成・色の変更・文字の置換はしていません。

| 原本 | 保存先 | 使用箇所 |
| --- | --- | --- |
| 四角いアイコン（1254×1254） | `assets/brand/source/app_icon.jpg` | iPhone・iPad・App Store・Androidのアプリアイコン |
| 横長ロゴ（1280×282、白背景） | `assets/brand/source/wordmark.jpg` | `BrandWordmark`、共有画像のヘッダー |
| 起動画面（590×1280） | `assets/brand/source/launch_screen.jpg` | iOS LaunchScreen・Flutter読込中・Android起動ロゴ |

原本JPEGはバイト列をそのまま保存し、`manifest.json`でハッシュを検査します。背景色は原本のクリーム色 `#F5F1E8` です。横長ロゴの白背景は透明化していません。UIの既存アクセント色は変更していません。

## OS用の派生画像

- iOSはAppIconの全指定サイズをRGB・アルファなしのPNGで用意しています。角丸はOSに任せます。
- iOS起動画面は1x・2x・3xを用意し、Storyboardの`scaleAspectFit`で縦横比を保ちます。Flutterの読込中も起動画面原本を`BoxFit.contain`で表示します。
- Androidは5密度の通常・丸型アイコンとAPI 26以降のAdaptive Iconを用意しています。OSのマスクで下部の文字が欠けないよう、絵全体に安全余白を加えています。
- Androidの起動Drawableは3枚目の文字を含む範囲だけを、周囲の空白を除いて取り出しています。文字・色・形はそのままです。Android 12以降はOS指定のスプラッシュ領域に合わせた縮小表示になるため、最初のネイティブ画面のサイズはOSに従います。その後のFlutter読込画面には3枚目全体を表示します。

## 再生成とCI

派生画像を作り直す場合のみPillowを利用します。

```sh
python3 .ci/brand_assets.py --regenerate
python3 .ci/brand_assets.py
```

通常のビルドにはPillowは不要です。生成済みのNative画像・XML・Storyboardを`assets/brand/native-assets.zip`に保存し、`.ci/prepare_project.py`が標準ライブラリで各Nativeディレクトリへ復元します。生成済みファイルもリポジトリへ含めているため、通常の`flutter run`でも採用したアイコンを使用します。

原本、生成用スクリプト、zip、manifest、iOS・Android側の派生ファイルは一緒に更新してください。CIでは画像寸法・App Store用アルファなし・原本ハッシュと、Native素材を消した後の復元を検査します。実機のホーム画面や起動アニメーションは別途確認が必要です。
