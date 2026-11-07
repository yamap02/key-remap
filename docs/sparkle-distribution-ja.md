# Sparkle 配布の準備と出荷ゲート（2026-11-07）

**一般公開不可。** Sparkle の組込みは開発段階であり、製品 ID、実証明書、公証、更新の実機安全性、ドライバの出荷要件は未完了。この文書は未確認のコマンドを完成済みのリリース手順として扱わない。

## 更新方式の判断

通常の app 更新を優先して検証する。現在の pkg は `/Applications/ReKey.app` を root:wheel、他ユーザーから書き込み不可にし、Core はその app と Agent の指定要件を XPC に適用する。Sparkle 2.9.6 の通常インストーラは旧 app の所有者・グループを新 app に合わせようとするが、失敗を致命的エラーにしない。したがってコードの存在だけでは root 所有が維持される保証にならない。更新後に全階層の所有権とモード、Core の新しい署名要件および接続、Agent・Core の旧プロセス停止を確認する必要がある。

成立しない場合のみ flat pkg を検討する。pkg 更新には管理者認証が毎回必要で、サイレントインストール、差分更新、通常の `generate_appcast` の利用に制限がある。pkg の preinstall は launchd の停止失敗、Core/VHID の残存やプロセス検査失敗を検出するとインストールを中止する。停止後にインストールが中断すると自動再登録は未対応で、postinstall は権限を設定するだけ。実機の停止・失敗時の復旧や Agent の再登録は未検証。現状の pkg を Sparkle 更新として配布しない。[Sparkle package updates](https://sparkle-project.org/documentation/package-updates/) / [publishing](https://sparkle-project.org/documentation/publishing/)

## 現在の実装と検証

- `check_for_updates` は設定 JSON の自動確認設定として使う。設定画面から手動確認できる。自動ダウンロード・自動インストールは無効。feed URL または EdDSA 公開鍵のない開発ビルドでは更新を開始しない。
- Sparkle 2.9.6 を固定。`REKEY_FEED_URL` と `REKEY_ED_PUBLIC_KEY` を両方指定して HTTPS feed と公開鍵を埋め込む。feed 署名と更新の展開前検証を必須とする。公開鍵は秘密鍵ではない。
- `REKEY_VERSION` は app と Agent の表示版、`REKEY_BUILD_NUMBER` は app と Agent の build 番号および pkg receipt の版。明示しない開発ビルドではそれぞれ `0.1.0` と Git コミット数を使用。公開時には両方を明示し、build 番号はリリースごとに単調増加させる。`scripts/check-appcast-version.py` は署名検証済み feed の全履歴より新しい整数 build を要求する。試験 pkg の展開結果では ID と build 2001 が app と一致した。
- `swift test`、`scripts/test-core.sh`、開発用 app のビルドと `codesign --verify --deep --strict` が通過。使い捨ての試験鍵で通常 app の zip と署名済み appcast を生成し、署名検証と feed・zip 改ざんの拒否を確認した。試験鍵は一時ディレクトリに作り実行後に削除した。実際の配布鍵による検証ではない。
- Core は起動時の app・Agent・Core 実行ファイルの実体・属性と親ディレクトリの所有権・書込み権限を100ms間隔で照合し、置換・削除・変更を検知すると入力を解放してプロセスを再起動するまで再取得しない。Core 起動時に app と Agent の両方の署名・所有権が検証できなければ起動を拒否する。オフラインテストで置換・削除・変更・書込み権限と復帰抑止を検証した。Sparkle の更新発見画面で利用者がインストールを選んだ時点で、UI は設定を保存し、有効な Core と Agent の停止完了まで Sparkle に選択を返さない。これにより通常経路では、終了時に自動適用されうる更新の準備より前に停止する。再起動延期コールバックでも停止状態を再検査する。停止前の復旧記録、停止失敗時の更新キャンセル、準備中の更新中断、古い build の保留状態と停止再検査を模擬テストした。同じ旧 build で再起動した保留更新はサービスを停止したままにし、メニューの「更新を確認」から再開またはキャンセルできる。途中終了後は停止状態を再検査する。Sparkle の既存保留更新からの移行、コールバックを経由しない終了経路と macOS の実動作は未検証。UI は記録済みの build 番号が変わった時に、有効だった Core と Agent の再登録を試みる。途中失敗時の次回起動での再試行、無効・承認待ちサービスを有効化しないこと、設定ファイル保持をモックと一時設定ファイルで検証した。旧版で build 番号を記録していない初回移行や、pkg で停止済みと判定されるサービス、bundle ID 変更は対象外であり、実機検証が必要。
- 実際の Sparkle 2.9.6 を一時的な試験 app に組み込み、署名済みローカル feed について更新あり・なし、feed 改ざん拒否、通信失敗、同じ長さの改ざん済み更新ファイルの取得後・展開前の EdDSA 署名拒否を確認した（`Tests/Distribution/test-sparkle-probe.py`）。試験は loopback HTTP と使い捨て鍵で、取得する試験ファイルはインストールできないデータに限定し、実行やインストールはしない。本番 HTTPS・配布鍵・ReKey の更新 UI は未検証。通常 app の root 所有維持、更新中断と物理キー解放、実機での設定保持とサービス再接続も未検証。署名済み製品版・公証・GitHub への公開も未実施。

## 出荷前に必要なもの

1. 配布者の Apple Developer Program、実際の Team ID と一意な製品 bundle ID、Developer ID Application 証明書、pkg が必要なら Developer ID Installer 証明書を用意する。`REKEY_PRODUCT_ID` は app、Agent、Core の XPC 判定、pkg ID に反映される。`REKEY_TEAM_ID` を指定すると ad-hoc 署名を拒否し、App・Agent・Core の署名 Team ID を照合する。未指定時は開発用 `jp.example.rekey` と ad-hoc 署名を使う。launchd / Mach service 名には開発用の `jp.example.rekey` が残り、製品 ID 変更時の既存登録・TCC 承認の移行と同時インストールは未検証。実在の証明書を使った照合も未検証。
2. `xcrun notarytool store-credentials` 等で公証資格情報をキーチェーンに保管し、パスワード、API 秘密鍵、署名鍵をリポジトリ、コマンド履歴、CI ログへ書かない。専用の Sparkle EdDSA 鍵を `generate_keys --account <組織専用名>` でキーチェーンに生成し、公開鍵のみビルド設定に渡す。秘密鍵は管理された安全な場所にバックアップし、紛失・ローテーション方針を決める。
3. GitHub の公開リポジトリと Releases を決め、HTTPS の安定した feed URL と、各バージョンに固定された HTTPS 更新ファイル URL を設計する。`latest/download` を feed に使う場合は Release 公開時の切替・キャッシュと、過去アイテムが元のバージョンの asset を指すことを検証する。認証が必要な private Release の URL を公開 feed とみなさない。
4. 実際の識別子・署名で App、Agent、Core と Sparkle の各ヘルパーを Developer ID 署名し、Apple に公証・staple する。`codesign`、`spctl`、`stapler` と配布アーカイブ展開後の署名を確認する。公開前の署名・公証自動化と本番向け失敗時停止処理は未実装。
5. クリーンな試験 Mac で旧版→新版を検証し、更新の有無、不正な署名、通信断、署名付き feed の改ざん、管理者認証の拒否、インストール中断、再起動、設定保持、Core/Agent の再接続と物理キーボード解放を確認する。`disable_on_quit=false` でも実機のすべての更新・終了・中断経路で入力が解放されることを検証する。更新選択を経由せずすでに保留されていた更新や異常終了の経路では通常終了通知は非同期であり、設定により Core は入力を保持しうる。検証前に公開しない。

## 初回導入とドライバ

現状 ReKey は公式の [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) に依存する。公式配布元から互換性のある署名・公証済み単独ドライバ pkg を入手し、管理者としてインストールする。インストール後、公式 Manager の `activate` を実行してから macOS が求めるシステム機能拡張をシステム設定で許可し、必要なら再起動する。ReKey の権限画面の「入力サービスを登録」で共有 Virtual HID デーモンも登録し、バックグラウンド項目と `rekey-core` の入力監視を許可する。EventViewer を使う場合は Agent のアクセシビリティも必要。公式ドライバの本体は Unlicense。ReKey が組み込む Sparkle のライセンス（同梱コンポーネントの告知を含む）と VirtualHID 本体のライセンスは app の `Contents/Resources/Licenses/` に収録する。Core がコンパイルするヘッダーを依存解析し、Asio・pqrs・Microsoft GSL・nlohmann/json・nod・type_safe のライセンスと著作権表示も同じ場所に収録する。各ヘッダーの正確な取得元リビジョンは vendored tree に揃っていないため、更新時と公開前に依存・通知を再監査する。

公式 Manager はインストールされた公式 pkg のものを利用する：

```sh
/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
```

公式の案内と異なり、ReKey は権限画面から共有デーモンを SMAppService に登録するため、ターミナルで `sudo` 起動したデーモンを常時動かす手順は不要。固定された依存の package 8.6.0、driver 1.8.0、client protocol 7 に互換のある公式ドライバを使い、配布元と署名・公証を確認する。異なる protocol のデーモンとは通信できない。

既存要件は独自 dext / IOUserClient と性能・復帰時間などを出荷ゲートとしている（[requirements.md](requirements.md)）。公式ドライバの利用だけでこのゲートが免除されるとは判断できず、独自ドライバ要否の決定、entitlement、承認、ライセンスの最終確認が未解決。

## 障害時の暫定復旧

安全な別入力手段を確保し、ReKey の設定画面から入力サービスを停止する。アプリが操作できない場合は macOS のバックグラウンド項目で ReKey のサービスを無効化し、必要なら再起動する。設定は `~/Library/Application Support/ReKey/` にあり、削除や上書き前にバックアップする。サービス登録の承認、入力監視、ドライバ拡張を再確認し、署名と公証を確認した既知の旧版から復旧する。更新取消し後の自動復旧処理は実装したが実機未検証。保留状態で同じ版が起動した場合は入力サービスを停止したまま、メニューから「更新を確認」で再開・キャンセルする。

## 署名済み通常 app のリリース準備手順（出荷ゲート通過後）

以下は通常 app 更新の検証が完了した後に配布担当者が使う手順。事前に署名鍵と公証資格情報をキーチェーンへ登録し、Sparkle 2.9.6 の公式配布物の `bin` を `SPARKLE_BIN` に指定する。実際の値は配布担当者が設定する。`REKEY_PRODUCT_ID` や署名チームの変更は TCC・サービス登録への影響があるため、既存利用者向けには移行を検証する。

1. 前回の appcast を HTTPS で取得し、**変更する前に**同じ配布用鍵で検証する。初回のみ、過去リリースがないことを別途確認して feed 比較を省略する。新しい build は前回値より大きく、表示版やタグも配布履歴と重複しないものにする。

   ```sh
   curl --fail --location "$REKEY_FEED_URL" -o build/previous-appcast.xml
   "$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify build/previous-appcast.xml
   python3 scripts/check-appcast-version.py build/previous-appcast.xml "$REKEY_BUILD_NUMBER"
   ```

2. `REKEY_PRODUCT_ID`、`REKEY_TEAM_ID`、`REKEY_SIGNING_IDENTITY`、`REKEY_VERSION`、`REKEY_BUILD_NUMBER`、`REKEY_FEED_URL`、`REKEY_ED_PUBLIC_KEY` を設定して `scripts/build-app.sh` を実行する。配布用 Team ID と署名が一致しなければビルドは失敗する。`codesign --verify --deep --strict --verbose=2 build/ReKey.app` で署名を確認する。
3. `ditto -c -k --sequesterRsrc --keepParent build/ReKey.app build/notary.zip` を作成し、`xcrun notarytool submit build/notary.zip --keychain-profile "$REKEY_NOTARY_PROFILE" --wait` が Accepted になったことを確認する。`xcrun stapler staple build/ReKey.app`、`xcrun stapler validate build/ReKey.app`、`spctl --assess --type execute --verbose=4 build/ReKey.app` を実行し、staple 後の app から配布 zip を作り直す。拒否された場合は公開せず、notarytool のログを Apple から取得して修正する。
4. 空の作業ディレクトリを用意し、直前に検証した旧 feed を `appcast.xml` としてコピーする。そこへ `ditto -c -k --sequesterRsrc --keepParent build/ReKey.app <作業ディレクトリ>/ReKey-<表示版>.zip` で新しい zip を置く。初回は旧 feed を置かない。`generate_appcast --account "$SPARKLE_ACCOUNT" --maximum-versions 0 --maximum-deltas 0 --download-url-prefix "https://github.com/<owner>/<repo>/releases/download/<tag>/" <作業ディレクトリ>` で作成する。owner・repo・tag は実際の GitHub Releases の値に置き換え、過去 item の URL が各旧 release を指したままか確認する。生成後 `sign_update --account "$SPARKLE_ACCOUNT" --verify <作業ディレクトリ>/appcast.xml` で署名を検証し、新旧各項目の build 番号、HTTPS URL、公開鍵、enclosure 署名を点検する。公開鍵と秘密鍵が対応することも署名検証および旧版による実機更新で確認する。
5. `gh release create <tag> --draft --verify-tag` で下書きを作り、署名・公証済み初回導入 pkg、更新 zip、署名済み appcast をアップロードする。下書きと試験環境で asset、内容と順序を確認してから公開する。安定 feed を GitHub の `releases/latest/download/appcast.xml` に置く場合、各正式 release にその名前の feed を含めて `gh release edit <tag> --draft=false --latest` で切り替える。公開後は feed と新旧 asset を HTTPS で実際に取得し、署名と内容を再検証する。初回導入 pkg は `REKEY_INSTALLER_IDENTITY` と `REKEY_NOTARY_PROFILE` を設定した `scripts/build-pkg.sh` で生成し、Installer 署名・公証を別途確認する。

この手順自体も実在する署名・公証・配信先での通し検証は未実施。現在の pkg 停止処理の実機挙動と Sparkle 更新時の入力解放が未検証のため、手順があることを公開承認とみなさない。
