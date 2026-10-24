# ansible-template

Ansibleで環境設定を行う汎用テンプレートプロジェクトです。

* 詳しい仕様(各ファイルの役割、実行フロー、ディレクトリ構成)は [SPEC.md](SPEC.md) を参照してください。

## 前提

[mise](https://mise.jdx.dev/) を使ってツールとPython仮想環境を用意します。

```bash
mise install          # Python を取得する
mise run install      # .venv に Ansible / lint ツール / passlib と Ansible Collection をインストールする
```

`passlib` は `bootstrap.yml` がパスワードのハッシュ化に使う `password_hash` フィルタのために必要です
(`requirements.txt` に含まれています)。
以降のコマンドは `mise` の環境(`.venv`)上で実行します。`mise` を使わない場合は `requirements.txt` を自分で
インストールし、`./scripts/install-collections.sh` を実行してください。

## 初期設定・セットアップ手順

1. `mise run install` で Python 依存と Ansible Collection をインストールする
2. `inventory/hosts.yml` を対象ホストに合わせて編集する
3. `group_vars/all.yml` の `provisioning_group` / `provisioning_user` を対象環境に合わせて編集する (作成するAnsibleユーザー、SSH公開鍵など)。
   `provisioning_user.password` には**平文の**パスワードをそのまま設定する(ハッシュ化は
   `bootstrap.yml` が実行時に `password_hash` フィルタで行う。sudoはNOPASSWDにせず、パスワード認証を必須にしている)。
   このファイルはファイル全体をVault暗号化してはいないため、設定したら
   `./scripts/encrypt-string.sh password` で **この値だけ** を暗号化し、出力
   (`password: !vault |` ブロック)で該当行を置き換える
4. `inventory/bootstrap.yml` の初期ログイン情報 (bootstrap用) を必要に応じて編集し、`./scripts/encrypt.sh inventory/bootstrap.yml` でVault暗号化する
5. `inventory/provisioning.yml` の `ansible_user` / `ansible_private_key_file` を設定する
   (`ansible_become_password` は `group_vars/all.yml` の `provisioning_user.password` を参照する形になっているため編集不要。
   このファイル自体はもう秘密を含まないためVault暗号化も不要)
6. `./ssh/{{ ansible_user }}` にプロビジョニング用の秘密鍵を配置する (または `bootstrap.yml` 実行時に自動配置)
7. カレントディレクトリに `.vault_password` を配置する (または `exec.sh` 実行時に入力)
8. 必要な独自roleを `roles/` 配下に追加し、`provisioning.yml` の `roles:` セクション(既定はコメントアウト)を有効化する

## CI のローカル実行

検査(yamllint / syntax-check / ansible-lint)をローカルで実行できます。GitHub Actions は使用しません。

```bash
mise run ci           # 全検査を実行
mise run yamllint     # 個別に実行する場合(syntax-check / ansible-lint も同様)
```

## 実行例

```bash
./exec.sh                 # all グループに対して実行
./exec.sh webservers      # webservers グループに限定して実行
BOOTSTRAP_ASK_BECOME_PASS=1 ./exec.sh   # bootstrap時にbecomeパスワードを都度入力する
```

## パスワードの変更/確認

`group_vars/all.yml` はファイル全体をVault暗号化しておらず、`password` の値だけを個別にインライン暗号化
しているため、`ansible-vault view`/`decrypt`(=`scripts/decrypt.sh`)はこのファイルには使えない。

```bash
# 変更(値を新しくして再暗号化。出力(`password: !vault |` ブロック)で
# group_vars/all.yml の該当行を置き換える)
./scripts/encrypt-string.sh password       # プロンプトで新しい平文パスワードを入力

# 確認(復号して表示)
./scripts/decrypt-string.sh provisioning_user.password
```
