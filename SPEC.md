# SPEC

このリポジトリの現在の仕様まとめです。使い方(セットアップ手順・実行コマンド)は [README.md](README.md) を参照してください。

## 実行は exec.sh に一本化

* [exec.sh](exec.sh) が唯一の実行入口
    * `inventory/hosts.yml` / `inventory/bootstrap.yml` / `inventory/provisioning.yml` を使う

## exec.sh の実行フロー

1. `check_connect()`: `inventory/provisioning.yml` の変数(`ansible_user: ansible` など)を `--extra-vars` で渡し、`ansible -a uptime` で対象グループに接続できるか確認する
2. 接続できれば `do_provisioning()` に進み、`provisioning.yml` を実行する
3. 接続できなければ `initialize()` で `inventory/bootstrap.yml` の変数(`ansible_user: ubuntu` など)を使い `bootstrap.yml` を実行する
4. bootstrap後に再度 `check_connect()` を行い、成功すれば `do_provisioning()` を実行する。失敗したらエラー終了する
5. 実行末尾に `reboot_system()` が定義されているが呼び出しはコメントアウトされている(未使用)

引数: 第1引数がグループ/ホスト名として `GROUP` に入り、`ansible-playbook -l ${GROUP}` に渡される(省略時は `all`)。

Vaultパスワードは `./.vault_password` があれば `--vault-password-file` を使い、無ければ `--ask-vault-pass`。
`BOOTSTRAP_ASK_BECOME_PASS=1` を環境変数で指定すると bootstrap 実行時に `--ask-become-pass` を追加する。

## bootstrap.yml

* play名 `Setup Ansible User`、`hosts: all`、`become: false`(各タスクで個別に `become: true`)
* `provisioning_group.{group,gid}` でグループ作成
* `provisioning_user.{user,uid,group,groups,password}` でユーザー作成
* `provisioning_user.public_key` を `authorized_key` に登録
* `community.general.sudoers` で `provisioning_user.user` にNOPASSWDのsudoersを設定(name: `provisioning-user`)
* `provisioning_user.private_key` が定義されていれば、localhost側 `./ssh/{{ provisioning_user.user }}` が未作成の場合のみ書き出す(次回ログオン用)
* 変数は `group_vars/all.yml` に定義済み

## provisioning.yml

* Play1 `Update apt source`: `/etc/apt/sources.list` の `http://` または `mirror://` 始まりの行を `mirror://mirrors.ubuntu.com/mirrors.txt` に置換
* Play2 `Setup all hosts`:
    * `pre_tasks` で `apt update`(`cache_valid_time: 600`)+ `autoremove` + `upgrade: safe`
    * `roles: [timezone, hostname, hosts, ubuntu-base]` を適用
    * 追加パッケージとして `locales-all` をインストール

## roles 配下

* `roles/timezone`: `community.general.timezone` を用いたタイムゾーン設定 (デフォルト: `Asia/Tokyo`)
* `roles/hostname`: `ansible.builtin.hostname` を用いたホスト名設定 (`inventory_hostname`)
* `roles/hosts`: `/etc/hosts` の `127.0.0.1 localhost` および `127.0.1.1 {{ inventory_hostname }}` 設定
* `roles/ubuntu-base`: Ubuntu共通の基本パッケージ (`curl`, `wget`, `git`, `vim`, `htop`, `ca-certificates` 等) の導入

## inventory 配下

* [inventory/hosts.yml](inventory/hosts.yml)
    * グループ例: `webservers` (`web-01`, `web-02`), `dbservers` (`db-01`)
    * `vars` で `ansible_connection: ssh`, `ansible_port: 22`
* [inventory/bootstrap.yml](inventory/bootstrap.yml)
    * bootstrap用の初期ログイン変数 (`ansible_user`, `ansible_password`, `ansible_become_password`)
    * `scripts/encrypt.sh` により Ansible Vault で暗号化管理
* [inventory/provisioning.yml](inventory/provisioning.yml)
    * provisioning用ユーザー: `ansible_user: ansible`, `ansible_private_key_file: ./ssh/ansible`

## group_vars

* [group_vars/all.yml](group_vars/all.yml): `provisioning_group`, `provisioning_user` の共通定義

## ansible.cfg

* `host_key_checking = False`
* `log_path = ./ansible.log`
* `allow_world_readable_tmpfiles = True`
* `[ssh_connection]`:
    * `pipelining = True`
    * `ssh_args = -F ./ssh_config -o ControlMaster=auto -o ControlPersist=60s`
* `[privilege_escalation] become_flags = -H -S`

## ssh_config

リポジトリ直下の [ssh_config](ssh_config) はSSHクライアント向けの設定(`ForwardAgent`, `StrictHostKeyChecking no`, `UserKnownHostsFile /dev/null` など)。
`ansible.cfg` の `ssh_args` 経由で Ansible の SSH 接続時に自動適用されます。

## collections

[collections/requirements.yml](collections/requirements.yml): `ansible.posix`, `community.general`
`scripts/install-collections.sh` で `ansible-galaxy collection install -r collections/requirements.yml` を実行する。

## Vault関連スクリプト

* [scripts/encrypt.sh](scripts/encrypt.sh) / [scripts/decrypt.sh](scripts/decrypt.sh)
    * 引数のファイルを `ansible-vault encrypt/decrypt` する
    * カレントディレクトリに `.vault_password` があればそれをパスワードファイルとして使う(`.gitignore` 済み)
    * `exec.sh` が参照する `.vault_password` とファイル名は一致している
* [scripts/make-password.py](scripts/make-password.py)
    * `passlib` の `sha512_crypt` でパスワードハッシュを生成する対話スクリプト

## .gitignore

`.vault_password` と `ansible.log` を除外。秘密鍵(`ssh/` 配下)は実体は git 管理対象外。

## ディレクトリ構成

```text
.
|-- .gitignore
|-- .vault_password           (gitignore対象)
|-- ansible.cfg
|-- bootstrap.yml
|-- provisioning.yml
|-- exec.sh
|-- ssh_config
|-- TODO.md
|-- collections/
|   `-- requirements.yml
|-- group_vars/
|   `-- all.yml
|-- inventory/
|   |-- hosts.yml
|   |-- bootstrap.yml         (Ansible Vault暗号化済み)
|   `-- provisioning.yml
|-- roles/
|   |-- hostname/
|   |   `-- tasks/main.yml
|   |-- hosts/
|   |   `-- tasks/main.yml
|   |-- timezone/
|   |   |-- defaults/main.yml
|   |   `-- tasks/main.yml
|   `-- ubuntu-base/
|       |-- defaults/main.yml
|       `-- tasks/main.yml
|-- scripts/
|   |-- decrypt.sh
|   |-- encrypt.sh
|   |-- install-collections.sh
|   `-- make-password.py
`-- ssh/
    `-- .gitkeep              (秘密鍵の置き場)
```
