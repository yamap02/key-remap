# GitHub Releases と Sparkle の配布操作

配布先は [yamap02/key-remap の Releases](https://github.com/yamap02/key-remap/releases)。
ソースは公開済み。更新フィードは次の固定 URL を使用する。

```text
https://github.com/yamap02/key-remap/releases/latest/download/appcast.xml
```

`scripts/github-release.py` はローカル Mac のキーチェーンを使い、署名・公証済みの初回導入 pkg、Sparkle 更新 zip、署名済み appcast を作成する。GitHub Actions へ秘密鍵を渡す必要はない。`prepare` は下書きまで、`publish` は一般公開と latest の切替まで実行する。更新方法は [Sparkle 公式手順](https://sparkle-project.org/documentation/publishing/) に従い、通常の app 更新を使う。pkg は初回導入用で、Sparkle から実行しない。

## Apple Developer Program 未加入での開発版配布

2026-11-14、配布者の判断により、未公証の開発版を公開する方式を追加した。
app は ad-hoc 署名、初回導入 pkg は未署名。Apple による発行者確認・公証はない。
Sparkle の feed と zip の EdDSA 署名・改ざん検査は有効にする。
初回導入は macOS の「システム設定 → プライバシーとセキュリティ → このまま開く」で利用者が許可する。
OS 全体のセキュリティ設定を無効にする手順は使用しない。

配布用 Sparkle 鍵はこの Mac のキーチェーン account `yamap02.key-remap.sparkle` に作成済み。
公開鍵は `Resources/sparkle-public-key.txt` に固定し、キーチェーンの鍵と一致しなければ配布を中止する。
秘密鍵は GitHub、Git、成果物へ含めない。

未公証版では、後述の Developer ID と公証資格情報の設定を省き、各コマンドへ明示的にフラグを付ける。

```sh
python3 scripts/github-release.py prepare 0.1.0 1 --unnotarized-development
python3 scripts/github-release.py publish 0.1.0 1 --unnotarized-development
python3 scripts/github-release.py verify 0.1.0 1 --unnotarized-development
```

タグ・クリーンな作業ツリー・前回 feed・build・署名・pkg と zip の内容一致・公開後の照合は通常と同じ。
このモードでは Apple の署名、公証、staple と Gatekeeper の許可判定を実行しない。
公開時には未公証であることと SHA-256 を Release の説明へ記載する。
通常モードの署名・公証要件は維持し、未公証への自動フォールバックは行わない。

初回導入・root 所有 app の実更新・入力監視の再承認・物理キー解放は利用環境での確認が必要。
ad-hoc 署名は更新でコードの識別情報が変わり、入力監視やバックグラウンド項目の再承認が必要になる場合がある。
検証記録のない実機の動作を保証するものではない。

## Developer ID による署名・公証版の初回設定

macOS 27 / Apple Silicon、対応する Xcode / Swift、Python 3.11 以上、認証済みの `gh` CLI を使用する。
Apple Developer Program の Developer ID Application と Developer ID Installer の証明書を、秘密鍵とともにログインキーチェーンへ登録する。
第三者のドライバ署名や provisioning profile は使用しない。

```sh
swift package resolve
security find-identity -v -p codesigning

# Sparkle 2.9.6 の専用鍵をキーチェーンに作成する（既存なら再利用）。
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account yamap02.key-remap.sparkle

# 対話入力で Apple の公証資格情報を登録する。
xcrun notarytool store-credentials rekey-notary
```

Sparkle の秘密鍵はリポジトリや Release に保存せず、キーチェーンと管理されたバックアップに保管する。鍵は次回以降も同じものを使う。公開鍵は毎回キーチェーンから読み取り、app に埋め込む。

配布コマンドに渡す環境変数（実際の値に置き換える）：

```sh
export REKEY_TEAM_ID='自分の10文字のTeam ID'
export REKEY_SIGNING_IDENTITY='Developer ID Application: 自分の名前 (TEAMID)'
export REKEY_INSTALLER_IDENTITY='Developer ID Installer: 自分の名前 (TEAMID)'
export REKEY_NOTARY_PROFILE='rekey-notary'
```

製品 ID は `io.github.yamap02.ReKey`、Sparkle キーチェーン account は `yamap02.key-remap.sparkle` に固定する。
開発版の `jp.example.rekey` からの変更に伴い、開発版を停止・解除してから製品版を導入し、バックグラウンド項目・入力監視・必要な場合のアクセシビリティを再承認する。開発版からの自動移行は対象にしない。初回製品版の配布後は ID と鍵を維持する。

## 共通のタグ準備とリリース操作

以下の `0.1.0` と build `1` は操作例。表示版・タグは再利用せず、build は配布済みの全 build より大きな整数を指定する。
事前に通常のテストと [実機検証](sparkle-physical-validation-ja.md) を済ませる。

```sh
swift test
scripts/test-core.sh
python3 -m unittest discover -s Tests/Distribution -p 'test_*.py'

# 変更をコミットし、配布するコミットへタグを付ける。
git tag -a v0.1.0 -m 'ReKey 0.1.0: initial signed distribution'
git push origin HEAD
git push origin v0.1.0

python3 scripts/github-release.py prepare 0.1.0 1
```

`prepare` は次を実行する。

1. 公開リポジトリ、作業ツリー、ローカルと公開先のタグ、Release の重複と競合する下書きを確認する。
2. 2 回目以降は公開中の feed を HTTPS で取得・署名検証し、build が全履歴より新しいことを確認する。取得や署名検証の失敗時は中止する。
3. 製品 ID と feed・公開鍵を埋め込み、Developer ID 署名した app をビルド、公証、staple、Gatekeeper 検査する。
4. その app から zip と署名済み appcast を生成し、旧版の URL・署名と履歴の保持を検査する。
5. 同一 app を使って初回導入 pkg を署名・公証し、zip の展開結果も検査する。
6. 3 ファイルを Release 下書きへアップロードし、再取得したファイルの SHA-256 と Sparkle 署名を照合する。

ローカルの成果物と再開用情報は `build/releases/v0.1.0/` に残る。前回 feed と `release.json` を公開完了まで保持する。
途中失敗時は下書きと出力を点検する。コマンドは既存ディレクトリ・Release・pkg を上書きしない。
下書き作成後の検証だけ失敗した場合は、原因を修正して `publish` で再検証できる。ビルドからやり直す場合は、失敗したローカル成果物を別場所へ移し、同じタグの下書きがあれば削除してから再実行する。公開済み Release を削除して再利用しない。

GitHub の下書きに、今回の変更点・既知の問題・実機検証結果を追記して内容を確認する。
公開する際は、タグをチェックアウトしたクリーンな作業ツリーで次を実行する。

```sh
python3 scripts/github-release.py publish 0.1.0 1
```

`publish` はタグ、前回 feed、下書きの実ファイルを再確認してから公開し、latest に指定する。
公開後は認証なし HTTPS で pkg・zip・appcast と固定 feed URL を取得し、ローカルの検証済み成果物と照合する。
前回 feed が準備後に変わっていたら公開を中止する。

公開後の検証失敗は Release を自動で非公開へ戻さない。GitHub 側の反映やキャッシュの遅延を確認して、次で再検証する。

```sh
python3 scripts/github-release.py verify 0.1.0 1
```

`verify` は現時点の latest と一致するかも確認するため、過去版を指定すると latest の比較は失敗する。
配布終了や問題発生時の対応は [公開・配布の運用](public-distribution-readiness-ja.md) を参照する。
この自動化は署名・公証・配信の手順を扱い、実機での入力解放やサービス再接続の確認を代替しない。
