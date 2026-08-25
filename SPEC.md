# SPEC

このリポジトリの現在の仕様まとめです。使い方(セットアップ手順・実行コマンド)は [README.md](README.md) を参照してください。

> **注記**: 過去のREADMEは `site.yml` / `inventories/production/` / `roles/bootstrap` などを前提とした、より作り込まれた構成を説明していましたが、
> commit `992c08e`(「update」)でその構成は撤去され、現在は `inventory/` + `bootstrap.yml` + `provisioning.yml` を直接書く簡易構成に戻っています。
> 旧構成は `git show 992c08e^:site.yml` などで参照できます。
> また、旧構成前提で動かなくなっていた `scripts/run-playbook.sh` は削除済みです。実行入口は [exec.sh](exec.sh) に一本化しています。

## 実行は exec.sh に一本化

* [exec.sh](exec.sh) が唯一の実行入口
    * `inventory/hosts.yml` / `inventory/bootstrap.yml` / `inventory/provisioning.yml` を使う

## exec.sh の実行フロー

1. `check_connect()`: `inventory/provisioning.yml` の変数(`ansible_user: pdfansible` など)を `--extra-vars` で渡し、`ansible -a uptime` で対象グループに接続できるか確認する
2. 接続できれば `do_provisioning()` に進み、`provisioning.yml` を実行する
3. 接続できなければ `initialize()` で `inventory/bootstrap.yml` の変数(`ansible_user: pdf00` など)を使い `bootstrap.yml` を実行する
4. bootstrap後に再度 `check_connect()` を行い、成功すれば `do_provisioning()` を実行する。失敗したらエラー終了する
5. 実行末尾に `reboot_system()` が定義されているが呼び出しはコメントアウトされている(未使用)

引数: 第1引数がグループ/ホスト名として `GROUP` に入り、`ansible-playbook -l ${GROUP}` に渡される(省略時は `all`)。

Vaultパスワードは `./.vault_password` があれば `--vault-password-file` を使い、無ければ `--ask-vault-pass`。
`BOOTSTRAP_ASK_BECOME_PASS=1` を環境変数で指定すると bootstrap 実行時に `--ask-become-pass` を追加する。

## bootstrap.yml (現状)

* play名 `Setup Ansible User`、`hosts: all`、`become: false`(各タスクで個別に `become: true`)
* `provisioning_group.{group,gid}` でグループ作成
* `provisioning_user.{user,uid,group,groups,password}` でユーザー作成
* `provisioning_user.public_key` を `authorized_key` に登録
* `community.general.sudoers` で `provisioning_user.user` にNOPASSWDのsudoersを設定(name: `provisioning-user`)
* `provisioning_user.private_key` が定義されていれば、localhost側 `./ssh/{{ provisioning_user.user }}` が未作成の場合のみ書き出す(次回ログオン用)

**注意**: `provisioning_group` / `provisioning_user` という変数は、`inventory/bootstrap.yml` にも `group_vars/*.yml` にもロールのdefaultsにも定義されていない。
`roles/` は `.gitkeep` のみで中身が無い。つまり **現状のままではこれらの変数が未定義で実行時エラーになる**(どこかで `-e` や host_vars 等を使って渡す前提と思われるが、その仕組みは未実装)。

## provisioning.yml (現状)

* Play1 `Update apt source`: `/etc/apt/sources.list` の `http://` または `mirror://` 始まりの行を `mirror://mirrors.ubuntu.com/mirrors.txt` に置換
* Play2 `Setup all hosts`:
    * `pre_tasks` で `apt update`(`cache_valid_time: 600`)+ `autoremove` + `upgrade: safe`
    * `roles: [timezone, hostname, hosts, ubuntu-base]` を適用
    * 追加パッケージとして `locales-all` をインストール

**注意**: `roles/` 配下は空(`.gitkeep` のみ)のため、上記4つのroleは**実体が存在せず実行時に失敗する**。

## inventory 配下

* [inventory/hosts.yml](inventory/hosts.yml)
    * グループ: `frontend`(`jarvis-prxvm-docker-01`, host指定あり)、`cluster_clients`(`jarvis-prxvm-gw-01`)、`ubuntu2604_sudows`(`jarvis-control-01`)
    * `vars` で `ansible_connection: ssh`, `ansible_port: 22`
* [inventory/bootstrap.yml](inventory/bootstrap.yml)
    * bootstrap用の初期ログイン変数: `ansible_user: pdf00`, `ansible_password`, `ansible_become_password`(共に `initial0`)
    * 平文パスワードが直接書かれている。運用時はvault化が必要(現状は雛形のまま)
* [inventory/provisioning.yml](inventory/provisioning.yml)
    * provisioning用ユーザー: `ansible_user: pdfansible`, `ansible_private_key_file: ./ssh/pdfansible`

## group_vars

* [group_vars/all.yml](group_vars/all.yml): 空ファイル
* [group_vars/ubuntu2604_sudows.yml](group_vars/ubuntu2604_sudows.yml): `ansible_become: true` / `ansible_become_method: sudo` / `ansible_become_exe: /usr/bin/sudo.ws`(標準の `/usr/bin/sudo` ではなく `sudo.ws` という別コマンドを指定している。対象環境固有のラッパーと思われる)

## ansible.cfg

* `host_key_checking = False`
* `log_path = ./ansible.log`
* `allow_world_readable_tmpfiles = True`
* `[ssh_connection] pipelining = True`
* `[privilege_escalation] become_flags = -H -S`

## ssh_config

リポジトリ直下の [ssh_config](ssh_config) はSSHクライアント向けの設定(`ForwardAgent`, `StrictHostKeyChecking no`, `UserKnownHostsFile /dev/null` など)。
`ansible.cfg` の `[ssh_connection]` からは参照されておらず、`exec.sh` からも使われていない。手動で `ssh -F ssh_config` するか、`~/.ssh/config` に読み込ませる運用を想定していると思われるが、結線は未実装。

## collections

[collections/requirements.yml](collections/requirements.yml): `ansible.posix`, `community.general`
`scripts/install-collections.sh` で `ansible-galaxy collection install -r collections/requirements.yml` を実行する。

## Vault関連スクリプト

* [scripts/encrypt.sh](scripts/encrypt.sh) / [scripts/decrypt.sh](scripts/decrypt.sh)
    * 引数のファイルを `ansible-vault encrypt/decrypt` する
    * カレントディレクトリに `.vault_password` があればそれをパスワードファイルとして使う(`.gitignore` 済み)
    * `exec.sh` が参照する `.vault_password` とファイル名は一致している
* [scripts/make-password.py](scripts/make-password.py)
    * `passlib` の `sha512_crypt` でパスワードハッシュを生成する対話スクリプト(vaultに入れる `ansible_password` 用ハッシュ作成などに利用と思われる)

## .gitignore

`.vault_password` と `ansible.log` を除外。秘密鍵(`ssh/` 配下)や `roles/` の中身は `.gitkeep` があるのみで、実体は git 管理対象外(未作成)。

## ディレクトリ構成(実際)

```text
.
|-- .gitignore
|-- ansible.cfg
|-- bootstrap.yml
|-- provisioning.yml
|-- exec.sh
|-- ssh_config
|-- TODO.md
|-- collections/
|   `-- requirements.yml
|-- group_vars/
|   |-- all.yml               (空)
|   `-- ubuntu2604_sudows.yml
|-- inventory/
|   |-- hosts.yml
|   |-- bootstrap.yml         (平文の初期ログイン情報)
|   `-- provisioning.yml
|-- roles/
|   `-- .gitkeep              (中身なし)
|-- scripts/
|   |-- decrypt.sh
|   |-- encrypt.sh
|   |-- install-collections.sh
|   `-- make-password.py
`-- ssh/
    `-- .gitkeep              (中身なし、秘密鍵の置き場)
```

## 既知の不整合・未実装項目

1. `bootstrap.yml` が参照する `provisioning_group` / `provisioning_user` 変数がどこにも定義されていない
2. `provisioning.yml` が参照する `roles: [timezone, hostname, hosts, ubuntu-base]` が `roles/` 配下に実体として存在しない
3. `inventory/bootstrap.yml` に初期ログインパスワードが平文で書かれている(`vault化` されていない。テンプレートとしては要注意)
4. `ssh_config` がどこからも実際には参照されていない

対応状況・タスクの追跡は [TODO.md](TODO.md) を参照してください。
