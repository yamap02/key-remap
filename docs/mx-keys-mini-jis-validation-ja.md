# MX Keys Mini の JIS 変換キー対応

2026-10-26。実装コミット `c4d8d18`、候補アプリ build 8。

## 原因と変更

「カタカナ／ひらがな／ローマ字」に対応する `international2`（Keyboard page 0x07 / usage 0x88）が Swift の設定用カタログと Core の設定コンパイラに存在せず、変換元として指定できなかった。Mac の「かな」`japanese_kana`（0x90）とは別の HID キーである。接続先やキーボードの OS モードによって実際に送られるコードは異なるため、実機でのコード確認は別途必要。

- `international2`～`international5` を両カタログに追加。「日本語・国際キー」から刻印に沿った名前で選べる。
- `international1` は「ろ」、`international3` は「￥」、`international4` は「変換」、`international5` は「無変換」と表示する。
- キー録音に JIS の「￥」（mac key code 93）、「ろ」（94）を追加。OS が通知しない変換キーには録音ダイアログからメニュー選択を案内する。Windows JIS の全変換キーを NSEvent で録音できるという意味ではない。
- Mac の「かな」「英数」の割り当てと既存設定は保持する。未知の物理入力を別のキーに自動置換しない。

HID usage の参照元: [USB-IF HID Usage Tables](https://www.usb.org/sites/default/files/hut1_21_0.pdf)。

## 検証

- `swift test`: 28件成功。追加した JIS キーを使った設定の保存・再読み込みも共通 C++ コンパイラを通して検証。
- `scripts/test-core.sh`: 49,657アサーション成功。各 JIS キーの変換元・変換先の押下／解放、Mac のかなとの区別、仮想 HID レポートでの保持／解放を検証。既存の出力・キュー・サービス停止試験も成功。
- `scripts/build-pkg.sh ReKey-0.1.0-mx-keys-mini-jis.pkg`: 成功。候補アプリの厳密な署名検証成功。
- パッケージを展開し、候補アプリの全18ファイルと SHA-256 が一致。`build/mx-jis-package-verification.json` に比較結果を保存。
- 旧インストールを `build/Backups/ReKey-before-mx-jis.app` に退避。
- 配布物は従来どおり未公証・インストーラ署名なしの開発用pkg。

## 実機への反映

`/Applications/ReKey.app` は build 8 に更新済み。厳密な署名検証に成功し、候補アプリの全18ファイルと SHA-256 が一致した（`build/mx-jis-install-verification.json`）。UI を新しいプロセスで起動した。

更新後の Core / Agent は launchd の登録に親 bundle version 8 が反映されたが、起動時に EX_CONFIG（78）となった。バックグラウンド項目のオフ→オンで署名登録を更新する操作を開始し、システム設定の Touch ID 認証待ち。入力監視の実効状態、サービス再起動、物理キーの入力コードと変換結果はまだ未確認。

MX Keys Mini の該当キーを Return にしたい場合は、更新後に対象デバイスの変更前を「カタカナ／ひらがな／ローマ字（JIS）」、変更後を Return にする。現在の「かな」→ Return 設定を別キーへ黙って書き換えることはしない。
