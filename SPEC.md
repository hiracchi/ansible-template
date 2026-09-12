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

引数: 第1引数がグループ/ホスト名として `GROUP` に入り、`ansible-playbook -l ${GROUP}` に渡される(省略時は `all`)。

Vaultパスワードは `./.vault_password` があれば `--vault-password-file` を使い、無ければ `--ask-vault-pass`。
`BOOTSTRAP_ASK_BECOME_PASS=1` を環境変数で指定すると bootstrap 実行時に `--ask-become-pass` を追加する。

## bootstrap.yml

* play名 `Setup Ansible User`、`hosts: all`、`gather_facts: false`、`become: false`(各タスクで個別に `become: true`)
* `pre_tasks`(Debian/Ubuntu系前提):
    * Pythonが入っていない最小イメージにも対応するため、`gather_facts` の前に `ansible.builtin.raw` で `python3` の有無を確認し、なければ `apt-get install` する
    * その後 `ansible.builtin.setup` で明示的にfactsを収集する(play全体の `gather_facts: false` を、Python未導入ホストでも失敗しないようにするための代替)
* `provisioning_group.{group,gid}` でグループ作成(`gid` は省略可。未指定ならOSが自動採番する。既定はコメントアウトされている)
* `provisioning_user.{user,uid,group,groups,password}` でユーザー作成(`uid` も同様に省略可・既定はコメントアウト)
* `provisioning_user.public_key` を `authorized_key` に登録
* `community.general.sudoers` で `provisioning_user.user` のsudoersを設定(name: `provisioning-user`)
    * `commands: ALL` は維持している。Ansibleの各モジュールは実行のたびに一時パスに生成されるスクリプトや apt/systemctl/useradd 等の多様なコマンドを呼び出すため、コマンド単位の許可リスト化は現実的ではないため
    * `nopassword: false` により本人のパスワード認証を必須にしている(`community.general.sudoers` は `nopassword` を省略すると既定で `true`=NOPASSWDになる点に注意)
    * `runas: root` に限定(`ALL` にはしていない。このテンプレートではroot以外へのbecomeを使わないため、昇格先を絞ってリスクを下げる)
    * `defaults: ['logfile="/var/log/sudo-ansible.log"']` により、このユーザーのsudo実行内容を専用ログに記録する(`community.general` 13.1.0以降が必要。`collections/requirements.yml` でバージョン指定済み)
* `provisioning_user.private_key` が定義されていれば、localhost側 `./ssh/{{ provisioning_user.user }}` が未作成の場合のみ書き出す(次回ログオン用)
* 変数は `group_vars/all.yml` に定義済み

## provisioning.yml

* Play1 `Update apt source`: `/etc/apt/sources.list` の `http://` または `mirror://` 始まりの行を `mirror://mirrors.ubuntu.com/mirrors.txt` に置換(`os_family == Debian` の場合のみ)
* Play2 `Setup all hosts`:
    * `pre_tasks` で `apt update`(`cache_valid_time: 600`)+ `autoremove` + `upgrade: safe`
    * `roles:` は既定でコメントアウトされており未使用(下記「roles 配下」参照)
    * 追加パッケージとして `locales-all` をインストール
* Play3 `Harden sshd`(Debian/Ubuntu系前提、サービス名 `ssh`):
    * `/etc/ssh/sshd_config` に `Include /etc/ssh/sshd_config.d/*.conf` があることを保証(`lineinfile` + `sshd -t` で検証)
    * `/etc/ssh/sshd_config.d/00-ansible-hardening.conf` に `PasswordAuthentication no` / `ChallengeResponseAuthentication no` / `PermitRootLogin no` を配置(`sshd -t` で検証してから配置、変更時のみ `service ssh reload` を通知)
    * ファイル名を `00-` にしているのは、Ubuntuのcloud-init由来 `50-cloud-init.conf`(`PasswordAuthentication yes` を含むことが多い)より先に評価させるため(sshdは同一ディレクティブの最初の指定を採用する)
    * `provisioning.yml` は `exec.sh` の `check_connect()` が鍵認証での接続成功を確認した後にしか実行されないため、パスワード認証を無効化しても実行中の接続経路(鍵認証)を失うことはない
* Play4 `Configure firewall (ufw)`(Debian/Ubuntu系前提、RHEL系のfirewalldは対象外):
    * `ufw` パッケージをインストール
    * SSHポート(`ansible_port`、未設定なら22)を許可(**有効化より先に実行する順序を厳守**。逆にすると自分自身を締め出す)
    * デフォルトポリシーを `incoming: deny` / `outgoing: allow` に設定
    * `ufw` を有効化(`state: enabled`)
    * webservers等グループ限定で追加ポートを開けたい場合のサンプルをコメントアウトで用意(`community.general.ufw` の `rule`/`port`/`when` を使う)
* Play5 `Configure fail2ban`(Debian/Ubuntu系前提。`Configure firewall (ufw)` より後に実行する必要がある):
    * `fail2ban` パッケージをインストール
    * `/etc/fail2ban/jail.d/zz-ansible.local` に `sshd` jailの設定を配置(`banaction = ufw`、`bantime = 1h`、`findtime = 10m`、`maxretry = 5`)
        * ファイル名を `zz-` にしているのは、fail2banのjail.d配下はiniとして「後から読んだ設定が勝つ」ため、Debianパッケージ同梱の `defaults-debian.conf` より確実に後で読ませるため(sshd_config.dの「最初の指定が勝つ」とは逆のセマンティクスなので注意)
        * 管理者の固定IPを誤BANから除外したい場合の `ignoreip` 設定例をコメントアウトで用意
    * fail2banサービスを有効化・起動
    * 設定ミスはfail2ban自体の起動/reload失敗にとどまり、sshd_config/ufwと異なりSSH接続経路そのものは塞がないため、`sshd -t` のような事前検証は行っていない

## roles 配下

`roles/` は意図的に空(`.gitkeep` のみ)にしてあります。プロジェクトごとに必要な独自roleをここに追加し、
`provisioning.yml` の `roles:` セクション(コメントアウト済み)を有効化して列挙する運用です。
テンプレート自体は特定のroleを前提としません。

## inventory 配下

* [inventory/hosts.yml](inventory/hosts.yml)
    * グループ例: `webservers` (`web-01`, `web-02`), `dbservers` (`db-01`)
    * `vars` で `ansible_connection: ssh`, `ansible_port: 22`
* [inventory/bootstrap.yml](inventory/bootstrap.yml)
    * bootstrap用の初期ログイン変数 (`ansible_user`, `ansible_password`, `ansible_become_password`)
    * `scripts/encrypt.sh` により Ansible Vault で暗号化管理
* [inventory/provisioning.yml](inventory/provisioning.yml)
    * provisioning用ユーザー: `ansible_user: ansible`, `ansible_private_key_file: ./ssh/ansible`
    * `ansible_become_password`: sudo(become)用パスワード(平文)。`group_vars/all.yml` の `provisioning_user.password`(ハッシュ)と同じ平文パスワードを設定する
    * 実際の値を設定したら `scripts/encrypt.sh` で Vault 暗号化する運用(現状はダミー値のプレースホルダーが平文で入っている)

## group_vars

* [group_vars/all.yml](group_vars/all.yml): `provisioning_group`, `provisioning_user` の共通定義
    * **⚠ 注意**: `provisioning_user.public_key` はダミーのプレースホルダー鍵です。実ホストに対して `bootstrap.yml` を実行する前に、必ず実際の公開鍵に置き換えてください。
    * **⚠ 注意**: `provisioning_user.password` もダミーのプレースホルダーハッシュです。`scripts/make-password.py` で生成したハッシュに置き換え、その元になった平文パスワードを `inventory/provisioning.yml` の `ansible_become_password` に設定してください(sudoはNOPASSWDにしておらず、この2つが一致していないとbecomeが失敗します)。

## ansible.cfg

* `log_path = ./ansible.log`
* ホスト鍵検証(`host_key_checking`)や一時ファイルの権限(`allow_world_readable_tmpfiles`)は既定値(無効)のまま変更していない
* `[ssh_connection]`:
    * `pipelining = True`
    * `ssh_args = -F ./ssh_config -o ControlMaster=auto -o ControlPersist=60s`
* `[privilege_escalation] become_flags = -H -S`

## ssh_config

リポジトリ直下の [ssh_config](ssh_config) はSSHクライアント向けの設定(`StrictHostKeyChecking accept-new`, `UserKnownHostsFile ./ssh_known_hosts` など)。
`StrictHostKeyChecking accept-new` + プロジェクト直下の `ssh_known_hosts`(`.gitignore` 済み、ユーザー個人の `~/.ssh/known_hosts` とは分離)により、
初回接続時のホスト鍵は自動登録しつつ、後から鍵が変わった場合(中間者攻撃や差し替え)は検知できるようにしている。
`ForwardAgent` / `ForwardX11` は自動化に不要なため既定で無効にしている(必要な場合は個別ホスト/グループで設定を追加すること)。
`ansible.cfg` の `ssh_args` 経由で Ansible の SSH 接続時に自動適用されます。

## collections

[collections/requirements.yml](collections/requirements.yml): `ansible.posix`, `community.general`(`>=13.1.0`。`sudoers` モジュールの `defaults` パラメータを使用するため)
`scripts/install-collections.sh` で `ansible-galaxy collection install -r collections/requirements.yml` を実行する。

## Vault関連スクリプト

* [scripts/encrypt.sh](scripts/encrypt.sh) / [scripts/decrypt.sh](scripts/decrypt.sh)
    * 引数のファイルを `ansible-vault encrypt/decrypt` する
    * カレントディレクトリに `.vault_password` があればそれをパスワードファイルとして使う(`.gitignore` 済み)
    * `exec.sh` が参照する `.vault_password` とファイル名は一致している
* [scripts/make-password.py](scripts/make-password.py)
    * `passlib` の `sha512_crypt` でパスワードハッシュを生成する対話スクリプト

## .gitignore

`.vault_password` と `ansible.log` を除外。
秘密鍵本体(`ssh/` 配下、`.gitkeep` を除く)も `ssh/*` + `!ssh/.gitkeep` で除外しており、実体が git 管理対象に入らないようにしている。

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
|   `-- provisioning.yml      (ansible_become_password設定後はVault暗号化する)
|-- roles/
|   `-- .gitkeep              (中身なし、独自role追加用の置き場)
|-- scripts/
|   |-- decrypt.sh
|   |-- encrypt.sh
|   |-- install-collections.sh
|   `-- make-password.py
`-- ssh/
    `-- .gitkeep              (秘密鍵の置き場)
```
