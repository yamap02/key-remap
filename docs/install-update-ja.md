# ReKey のインストールと更新

**この手順は公開準備中です。** ReKey の公開先、署名・公証、更新の実機検証はまだ確定していません。公開版が利用できると確認するまで、この文書を配布開始の案内として使用しないでください。現在の対象は macOS 27 と Apple Silicon です。

## 初めてインストールする

1. 利用中の Mac に別の入力手段があることを確認し、Karabiner-Elements の入力サービスなど、キーボードを占有する他のリマップアプリを停止します。
2. ReKey が対応する公式 Karabiner VirtualHID ドライバをインストールします。現在の開発版は [公式の 8.6.0 パッケージ](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/blob/ac836ed8a974cd5182495251855cabdb762f50cb/dist/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg) に対応しています。公開時には配布ページの対応バージョンを再確認してください。GitHub のファイル画面からダウンロードし、macOS のインストーラで開きます。
3. ターミナルで次のコマンドを実行します。macOS にシステム機能拡張の許可を求められたら、システム設定で許可し、必要に応じて再起動します。公式の[ドライバ導入手順](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice#usage)も参照してください。

   ```sh
   /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
   ```

4. 公開先が決まったら、ReKey の GitHub Releases から初回導入用の署名・公証済み pkg を入手し、開いて画面に従います。管理者認証は macOS の画面で行います。**現時点では公開先も公開用 pkg もありません。**
5. アプリケーションフォルダから ReKey を開き、「権限」画面の「入力サービスを登録」を押します。システム設定のバックグラウンド項目で ReKey のサービスと共有 Virtual HID デーモンを許可します。ReKey が共有デーモンを登録するため、公式の開発者向け手順にあるデーモンのターミナル常駐起動は不要です。
6. 「権限」画面で入力監視を確認し、必要なら Finder に表示される `rekey-core` をシステム設定の入力監視に追加・許可して「入力サービスを再起動」を押します。EventViewer を使う場合は ReKey Agent のアクセシビリティも許可します。macOS が追加の承認や再起動を求める場合は指示に従ってください。
7. ReKey の画面でドライバと入力サービスの状態を確認し、簡単なキー変換を設定して、テキスト欄で押下と解放を確認します。入力できなくなった場合は別の入力手段で ReKey のサービスを停止します。

公式ドライバ本体のライセンスは [Unlicense](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/blob/ac836ed8a974cd5182495251855cabdb762f50cb/LICENSE.md) です。ReKey に含まれる Sparkle とその他の依存物のライセンスは、app の `Contents/Resources/Licenses/` にあります。公開前の依存・ライセンス確認は未完了です。

## 更新する

ReKey の「その他」画面で「今すぐ更新を確認」を押します。「更新を自動的に確認」を有効にすると定期的に更新を確認します。自動ダウンロードと自動インストールは行いません。更新を選択した後は入力サービスを停止し、インストール時に macOS の管理者認証を求められる場合があります。

更新後は設定とサービスの状態を確認してください。更新の取消しや失敗後に入力サービスが停止したままの場合は、ReKey の表示を確認し、必要に応じて「権限」画面の「入力サービスを再起動」やシステム設定のバックグラウンド項目を確認します。更新が保留中のときはメニューバーの「更新を確認…」から再開または取消しを選びます。これらの更新・復旧操作は公開用の実機検証がまだ必要です。

更新できない場合、署名や配信元を確認できないファイルを使わず、配布元が用意した既知の旧版と復旧案内を確認してください。設定は `~/Library/Application Support/ReKey/` にあります。削除や再インストールの前にバックアップしてください。ReKey のアンインストールでは、他のアプリと共有する Karabiner VirtualHID ドライバを自動削除しません。
