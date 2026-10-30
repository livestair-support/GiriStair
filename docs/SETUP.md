# iPhoneでGiriStairを確認する手順

iPhone版は0.4.0からSwiftUIです。CodemagicのiPhoneワークフローはFlutterを使用せずnative/GiriStairをビルドします。PRの確認中はその作業ブランチ、マージ後はmainを選びます。

## 現在の前提

- GitHubのリポジトリは `livestair-support/GiriStair`。
- 初期設定のBundle IDは **`com.livestair.giristair`**。Apple側に登録した値が違う場合は、AIにその値を伝え、`.ci/app_config.json` と `codemagic.yaml` を合わせてからビルドします。
- LiveStairの手順書には、同じ開発者のCodemagicにApple連携 **`LiveStair ASC`** と配布用証明書を設定済みと記載されています。このリポジトリからサービス画面の実際の設定・期限・権限は確認できません。
- ユーザーはブラウザ操作とiPhoneでの確認を担当します。コード、Flutter SDKのセットアップ、設定ファイルの編集はAIに依頼できます。

## 1. GitHubで初期コードを取り込む

1. AIから渡されたGiriStairのプルリクエストを開きます。
2. 内容を確認して「Merge pull request」→「Confirm merge」を押します。
3. GiriStairの`main`に`pubspec.yaml`・`lib/`・`codemagic.yaml`が表示されれば完了です。

## 2. CodemagicにGiriStairを追加する

1. LiveStairを使っているものと同じCodemagicアカウントにログインします。
2. 「Applications」→「Add application」→「GitHub」を選びます。
3. `livestair-support/GiriStair`を選び、codemagic.yamlを使うプロジェクトとして追加します。
4. 設定方法は`codemagic.yaml`を使います。Flutter workflow editor用に別の設定を作る必要はありません。

GiriStairが候補に出ない場合は「Integrations」→GitHub連携の「Manage integration／Configure」を開き、アクセス対象リポジトリにGiriStairを追加します。

## 3. まず署名なしの確認ビルドを行う

1. 「Applications」→「GiriStair」→「Start new build」。
2. ブランチは`main`。
3. ワークフローは **「1. 確認（Swiftテスト・iOSビルド）」**。
4. 「Start new build」を押します。

このワークフローはSwiftの保存互換性テストと、署名しないSwiftUI iOSビルドを行います。成功しても、まだiPhoneにはインストールできません。失敗した場合は、赤くなった工程名とエラー付近のログをAIに送ってください。

## 4. Apple側のGiriStair登録を確認する

既に済ませた場合は同じものを使います。

1. Apple Developerの「Certificates, Identifiers & Profiles」→「Identifiers」でGiriStairのApp IDを確認します。
2. Bundle IDを`com.livestair.giristair`と照合します。
3. App Store Connectの「Apps／マイApp」にGiriStairがあることを確認します。
4. 新規作成する場合は「＋」→「New App／新規App」、iOS・日本語・GiriStair用Bundle IDを選択し、SKUに`giristair-ios`を入力します。

名前が使えない場合はApp Storeの表示名を調整できます。Bundle IDはコードと署名に関わるため、入力値をAIに正確に伝えてください。

## 5. 既存のApple連携とGiriStair用プロファイルを使う

1. Codemagicの設定で「Integrations」→「Developer Portal」を開き、`LiveStair ASC`があることを確認します。
2. 同じAppleチームでアプリにアクセスできる連携なら、そのまま使えます。別の連携名を使う場合は、AIが`codemagic.yaml`の名前を合わせます。
3. Apple Developerの「Profiles」→「＋」で、Distributionの「App Store Connect」を選びます。
4. GiriStairのApp IDと、Codemagicに登録済みで有効なApple Distribution証明書を選択します。
5. 名前を`GiriStair Codemagic AppStore`として生成します。
6. Codemagicの「codemagic.yaml settings」→「Code signing identities」→「iOS provisioning profiles」で「Fetch profiles」を押し、GiriStairのプロファイルを取り込みます。
7. プロファイルに対応する証明書が利用可能と表示されることを確認します。

新しい証明書を毎回発行する必要はありません。APIキー（`.p8`）、証明書、署名ファイルはCodemagicの設定画面で扱い、GitHubやチャットには貼らないでください。

## 6. TestFlightへアップロードする

1. Codemagicで「GiriStair」→「Start new build」。
2. ブランチは`main`。
3. ワークフローは **「3. iPhone確認用（TestFlightへアップロード）」**。
4. 「Start new build」を押します。

この工程では、Swiftの保存互換性テスト、署名済みIPAの作成、App Store Connectへのアップロードを行います。ビルド番号はCodemagicの`PROJECT_BUILD_NUMBER`を使用します。別のCodemagicアプリや別経路からアップロードするようになった場合は、過去の番号より大きい番号になるようAIに調整を依頼してください。

この設定はApp Storeへの審査提出も、外部テスト用のベータ審査への自動提出も行いません。Apple側で処理が終わったビルドを、App Store Connectの内部テストで利用します。

## 7. iPhoneに入れて確認する

1. App Store ConnectのGiriStair→「TestFlight」を開きます。
2. コンプライアンスについて追加の質問が表示された場合は、実際のアプリの内容に合わせて回答します。
3. 「内部テスト」でグループを作成し、自分のApp Store Connectユーザーを追加します。
4. 処理済みビルドをそのグループに追加します。以後の自動配信はグループの設定で選べます。
5. iPhoneのTestFlightを開き、GiriStairをインストールします。

最初に確認する操作は、5タブの表示、生／ネットの登録切替、1件の保存・再起動、投稿期間中の会の思考タブ表示、メモの保存です。投稿期間が終わったメモも残ること、会を削除してもメモ本文が消えないことを確認してください。

## ふだんの変更

AIに変更を依頼 → PRを確認・マージ → Codemagicの確認ビルド → TestFlight用ビルド → iPhoneで確認、の順に進めます。GitHubを変更しただけではインストール済みアプリは更新されません。

Androidの確認は **「2. Android確認（デバッグAPK）」** を使います。Google Playのアカウントや公開用署名の設定はAndroid版を公開する段階で追加します。デバッグAPKが作れたこととAndroid実機での動作確認は別です。

## 参考

- [AppleのApp ID登録](https://developer.apple.com/help/account/identifiers/register-an-app-id/)
- [App Store Connectの新規App登録](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Codemagicのアプリ追加](https://docs.codemagic.io/getting-started/adding-apps/)
- [CodemagicのFlutter設定](https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/)
- [App Store Connectへの配布](https://docs.codemagic.io/yaml-publishing/app-store-connect/)
