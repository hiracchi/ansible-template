# ansible-template

Ansibleで環境設定を行う汎用テンプレートプロジェクトです。

* 詳しい仕様(各ファイルの役割、実行フロー、ディレクトリ構成)は [SPEC.md](SPEC.md) を参照してください。

## 新規プロジェクトの作成

このテンプレートから新しいプロジェクトを作るには、次のコマンドを実行します。
プロジェクト名のディレクトリが作成され、テンプレートが clone されたうえで、新規の git リポジトリとして初期化されます。

```bash
curl -fsSL https://raw.githubusercontent.com/hiracchi/ansible-template/main/scripts/new-project.sh | bash -s -- <プロジェクト名>
```

作成先の親ディレクトリを指定する場合は、末尾に続けて指定します。

```bash
curl -fsSL https://raw.githubusercontent.com/hiracchi/ansible-template/main/scripts/new-project.sh | bash -s -- <プロジェクト名> <作成先の親ディレクトリ>
```

スクリプトの中身を確認してから実行したい場合は、ファイルに保存してから実行してください。

```bash
curl -fsSLO https://raw.githubusercontent.com/hiracchi/ansible-template/main/scripts/new-project.sh
bash new-project.sh <プロジェクト名>
```

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
   `./scripts/encrypt-string.sh -e provisioning_user.password` で **この値だけ** を暗号化する
   (`group_vars/all.yml` の該当行が `!vault` ブロックに直接置き換わる。他の行・コメントは残る)
4. `inventory/bootstrap.yml` の初期ログイン情報 (bootstrap用) を必要に応じて編集し、Vault暗号化する。
   平文の初期パスワードをコミットしないこと。暗号化の方法は次のどちらか
   * ファイル全体: `./scripts/encrypt-file.sh inventory/bootstrap.yml`(閲覧は `./scripts/view.sh inventory/bootstrap.yml`)
   * 値ごと: `./scripts/encrypt-string.sh -e ansible_password inventory/bootstrap.yml` と
     `./scripts/encrypt-string.sh -e ansible_become_password inventory/bootstrap.yml`
     (`ansible_user` は平文のまま。`bootstrap.sh` の `-e @inventory/bootstrap.yml` で復号できる。
     この場合 `view.sh` / `ansible-vault view` は使えない)
5. `inventory/provisioning.yml` の `ansible_user` / `ansible_private_key_file` を設定する
   (`ansible_become_password` は `group_vars/all.yml` の `provisioning_user.password` を参照する形になっているため編集不要。
   このファイル自体はもう秘密を含まないためVault暗号化も不要)
6. `./ssh/{{ ansible_user }}` にプロビジョニング用の秘密鍵を配置する (または `bootstrap.yml` 実行時に自動配置)
7. カレントディレクトリに `.vault_password` を配置する (または `provision.sh` / `bootstrap.sh` 実行時に入力)
8. `disable_initial_user_name` (`roles/disable_initial_user/defaults/main.yml`、既定 `ubuntu`) を `inventory/bootstrap.yml` の `ansible_user` に合わせる
9. 必要な独自roleを `roles/` 配下に追加し、`provisioning.yml` の `roles:` セクションに列挙して有効化する

## CI のローカル実行

検査(yamllint / syntax-check / ansible-lint)をローカルで実行できます。GitHub Actions は使用しません。

```bash
mise run ci           # 全検査を実行
mise run yamllint     # 個別に実行する場合(syntax-check / ansible-lint も同様)
```

## 実行例

```bash
# 新規ホストの初期化(初期ユーザーで接続し、provisioning ユーザーを作る。初期化済みホストは拒否される)
./bootstrap.sh web-01
BOOTSTRAP_ASK_BECOME_PASS=1 ./bootstrap.sh web-01   # becomeパスワードを都度入力する

# 初期化済みホストへの適用(接続できないホストがあれば中止する)
./provision.sh                 # all グループに対して実行
./provision.sh webservers      # webservers グループに限定して実行
```

## 運用スクリプト(読み取り中心)

```bash
# ホストの健康状態の検査(読み取り専用)。ノード名か all(既定は all グループ)を指定する
./scripts/node-health.sh web-01
./scripts/node-health.sh -g webservers all      # all の対象を webservers グループにする

# ノードの電源オフ(確認あり)。-n で対象の一覧だけ表示、-d 分 で遅延、-y で確認を省略
./scripts/shutdown-nodes.sh -n web-01
./scripts/shutdown-nodes.sh -d 10 -g webservers all

# 機器スペックの一覧(Markdown)を docs/hosts/machine-specs.md に出力する
./scripts/collect-machine-specs.sh
./scripts/collect-machine-specs.sh -o - -x db-01   # 標準出力へ。db-01 は除外する
```

プロジェクトに合わせて、各スクリプトの先頭にある設定(`DEFAULT_ALL_GROUP`、`DEFAULT_CRASH_CHECKS`、
`DOC_TITLE`、`DEFAULT_EXCLUDE_HOSTS`)を変えてください。詳細は SPEC.md を参照。

## パスワードの変更/確認

`group_vars/all.yml` はファイル全体をVault暗号化しておらず、`password` などの値だけを個別にインライン暗号化
しているため、`ansible-vault view`/`decrypt`(=`scripts/view.sh` / `scripts/decrypt-file.sh`)はこのファイルには使えない。
`view.sh` と `decrypt-file.sh` は、ファイル全体を暗号化したファイル用。

```bash
# 変更(隠し入力で受け取り、group_vars/all.yml の該当キーを !vault ブロックに自動で置き換える)
./scripts/encrypt-string.sh provisioning_user.password

# ファイルにある現在の値を、入力なしでそのまま暗号化する(平文を入れた後の暗号化に使う)
./scripts/encrypt-string.sh -e provisioning_user.password

# 別のYAMLファイルの値を暗号化する(第2引数でファイルを指定)
./scripts/encrypt-string.sh -e ansible_password inventory/bootstrap.yml

# リストの要素は user 名などで指定する(入力値は SHA-512 ハッシュに変換してから暗号化される)
./scripts/encrypt-string.sh my_users.<名前>.password

# ハッシュだけを作りたい場合(依存は openssl のみ)
./scripts/hash-password.sh

# 確認(復号して表示。第2引数で対象ファイルを指定可、省略時は group_vars/all.yml)
./scripts/decrypt-string.sh provisioning_user.password

# inventory/bootstrap.yml を値ごとに暗号化した場合の確認
./scripts/decrypt-string.sh ansible_password inventory/bootstrap.yml
```
