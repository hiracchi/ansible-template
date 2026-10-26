# SPEC

このリポジトリの現在の仕様まとめです。使い方(セットアップ手順・実行コマンド)は [README.md](README.md) を参照してください。

## 実行入口は bootstrap.sh と provision.sh の2つ

* [bootstrap.sh](bootstrap.sh): 新規ホストを初期化する専用の入口。`bootstrap.yml` を実行する
* [provision.sh](provision.sh): 初期化済みホストに `provisioning.yml` を適用する入口
* どちらも `inventory/hosts.yml` を使う。接続情報は `bootstrap.sh` が `inventory/bootstrap.yml`、`provision.sh` が `inventory/provisioning.yml` から読む

## bootstrap.sh の動作

1. 引数はホスト名のみ(1つ以上)。グループ名は指定できない
2. 各ホストに対して `provisioning_user` で `ansible.builtin.ping` を実行し、接続できるものがあれば「初期化済み」とみなして中止する
3. `bootstrap.yml` を `inventory/bootstrap.yml` の変数で実行する
4. 失敗時は終了コードを返す。成功後は `./provision.sh` を実行するよう案内する

## provision.sh の動作

1. 引数: 第1引数がグループ/ホスト名(省略時は `all`)。残りは `ansible-playbook` にそのまま渡す
2. `check_connect()`: `provisioning_user` で `ansible.builtin.ping` を全対象に実行する。1台でも接続できなければ中止する(初期化は自動では行わない)
3. `do_provisioning()`: `provisioning.yml` を実行する。失敗時は `ansible-playbook` の終了コードを返す

`bootstrap.sh` と `provision.sh` を分けているのは、初期ユーザーを無効化した後に自動で初期化を試みて失敗するのを防ぐため。
接続できないホストを自動で初期化しないことで、どの経路で接続しているかを明確にしている。

Vaultパスワードは `./.vault_password` があれば `--vault-password-file` を使い、無ければ `--ask-vault-pass`。
`BOOTSTRAP_ASK_BECOME_PASS=1` を環境変数で指定すると bootstrap 実行時に `--ask-become-pass` を追加する。

## bootstrap.yml

* play名 `Setup Ansible User`、`hosts: all`、`gather_facts: false`、`become: false`(各タスクで個別に `become: true`)
* `pre_tasks`(Debian/Ubuntu系前提):
    * Pythonが入っていない最小イメージにも対応するため、`gather_facts` の前に `ansible.builtin.raw` で `python3` の有無を確認し、なければ `apt-get install` する
    * その後 `ansible.builtin.setup` で明示的にfactsを収集する(play全体の `gather_facts: false` を、Python未導入ホストでも失敗しないようにするための代替)
* `provisioning_group.{group,gid}` でグループ作成(`gid` は省略可。未指定ならOSが自動採番する。既定はコメントアウトされている)
* `provisioning_user.{user,uid,group,groups,password}` でユーザー作成(`uid` も同様に省略可・既定はコメントアウト)
    * `provisioning_user.password` は平文パスワード。`ansible.builtin.user` の `password:` に渡す直前で
      `password_hash('sha512', '%04d' | format(65534 | random(seed=inventory_hostname)))` フィルタでハッシュ化する。salt は必ず4桁にそろえる(1〜2桁だと一部の環境で crypt が失敗したため)。
      salt を省略すると実行のたびに異なるハッシュ文字列になり `changed` が毎回発生するため、
      `inventory_hostname` をシードにした固定saltで冪等にしている(コントロールマシンに `passlib` が必要)
* `provisioning_user.public_key` を `authorized_key` に登録
* `community.general.sudoers` で `provisioning_user.user` のsudoersを設定(name: `provisioning-user`)
    * `commands: ALL` は維持している。Ansibleの各モジュールは実行のたびに一時パスに生成されるスクリプトや apt/systemctl/useradd 等の多様なコマンドを呼び出すため、コマンド単位の許可リスト化は現実的ではないため
    * `nopassword: false` により本人のパスワード認証を必須にしている(`community.general.sudoers` は `nopassword` を省略すると既定で `true`=NOPASSWDになる点に注意)
    * `runas: root` に限定(`ALL` にはしていない。このテンプレートではroot以外へのbecomeを使わないため、昇格先を絞ってリスクを下げる)
    * sudoの `logfile` 設定は使わない。Ubuntu 26.04 の既定の sudo(sudo-rs)は `Defaults logfile` を拒否して失敗するため
* `provisioning_user.private_key` が定義されていれば、localhost側 `./ssh/{{ provisioning_user.user }}` が未作成の場合のみ書き出す(次回ログオン用)
* 変数は `group_vars/all.yml` に定義済み

## provisioning.yml

* Play1 `Update apt source`: `/etc/apt/sources.list` の `http://` または `mirror://` 始まりの行を `mirror://mirrors.ubuntu.com/mirrors.txt` に置換(`os_family == Debian` の場合のみ)
* Play2 `Setup all hosts`:
    * `pre_tasks` で `apt update`(`cache_valid_time: 600`)+ `autoremove` + `upgrade: safe`
    * `roles:` には `disable_initial_user` のみ列挙している(下記「roles 配下」参照)
    * 追加パッケージとして `locales-all` をインストール
* Play3 `Harden sshd`(Debian/Ubuntu系前提、サービス名 `ssh`):
    * `/etc/ssh/sshd_config` に `Include /etc/ssh/sshd_config.d/*.conf` があることを保証(`lineinfile` + `sshd -t` で検証)
    * `/etc/ssh/sshd_config.d/00-ansible-hardening.conf` に `PasswordAuthentication no` / `ChallengeResponseAuthentication no` / `PermitRootLogin no` を配置(`sshd -t` で検証してから配置、変更時のみ `service ssh reload` を通知)
    * ファイル名を `00-` にしているのは、Ubuntuのcloud-init由来 `50-cloud-init.conf`(`PasswordAuthentication yes` を含むことが多い)より先に評価させるため(sshdは同一ディレクティブの最初の指定を採用する)
    * `provisioning.yml` は `provision.sh` の `check_connect()` が鍵認証での接続成功を確認した後にしか実行されないため、パスワード認証を無効化しても実行中の接続経路(鍵認証)を失うことはない
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
* Play6 `Configure automatic security updates`(Debian/Ubuntu系前提):
    * `unattended-upgrades` パッケージをインストール
    * `/etc/apt/apt.conf.d/20auto-upgrades` に `APT::Periodic::Update-Package-Lists`/`APT::Periodic::Unattended-Upgrade` を設定し、定期的なセキュリティ更新の自動適用を有効化
    * 自動再起動は既定で無効のまま(`unattended-upgrades` パッケージ同梱の `50unattended-upgrades` の既定設定に従う)。稼働中のサービス/セッションへの影響が大きいため、テンプレートとしては意図的に踏み込んでいない

## roles 配下

`roles/` には、テンプレートの標準 role として `disable_initial_user` を置いています。
プロジェクトごとに必要な独自roleを追加し、`provisioning.yml` の `roles:` セクションに列挙して有効化する運用です。

### disable_initial_user

* OS 初期化直後の初期ユーザー(`disable_initial_user_name`、既定 `ubuntu`)のログインを無効化する
    * ログインシェルを `/usr/sbin/nologin` にし、パスワードをロックする
    * ローカルアカウントが無ければ何もしない(NIS/LDAP 側のユーザーには触れない)
    * sudo 設定に名前が残っていれば警告を表示する
* `provisioning.yml` の「Setup all hosts」で実行する。provisioning ユーザーでの接続確認(`provision.sh`)の後にしか実行されないため、ロックアウトしない
* 無効化後は `bootstrap.sh` で初期化できなくなるため、初期ユーザー名は `inventory/bootstrap.yml` の `ansible_user` と一致させる
テンプレート自体は特定のroleを前提としません。

## inventory 配下

* [inventory/hosts.yml](inventory/hosts.yml)
    * グループ例: `webservers` (`web-01`, `web-02`), `dbservers` (`db-01`)
    * `vars` で `ansible_connection: ssh`, `ansible_port: 22`
* [inventory/bootstrap.yml](inventory/bootstrap.yml)
    * bootstrap用の初期ログイン変数 (`ansible_user`, `ansible_password`, `ansible_become_password`)
    * `scripts/encrypt-file.sh` / `scripts/encrypt-string.sh` により Ansible Vault で暗号化管理
* [inventory/provisioning.yml](inventory/provisioning.yml)
    * provisioning用ユーザー: `ansible_user: ansible`, `ansible_private_key_file: ./ssh/ansible`
    * `ansible_become_password: "{{ provisioning_user.password }}"`: `group_vars/all.yml` の
      `provisioning_user.password`(平文)を直接参照するため、このファイル自体は秘密を含まず、
      Vault暗号化は不要(以前はここに平文の `ansible_become_password` を直接書いてVault暗号化していたが、
      `provisioning_user.password` と2箇所に同じ平文を持つ必要があり、パスワード変更時に手動で同期する
      必要があった)

## group_vars

* [group_vars/all.yml](group_vars/all.yml): `provisioning_group`, `provisioning_user` の共通定義
    * **⚠ 注意**: `provisioning_user.public_key` はダミーのプレースホルダー鍵です。実ホストに対して `bootstrap.yml` を実行する前に、必ず実際の公開鍵に置き換えてください。
    * **⚠ 注意**: `provisioning_user.password` は**平文パスワード**です(ハッシュではありません)。
      `bootstrap.yml` がアカウント作成時に `password_hash` フィルタでハッシュ化し、
      `inventory/provisioning.yml` の `ansible_become_password` もこの値を直接参照するため、
      設定・ローテーションが必要な箇所はここ1箇所のみ。ファイル全体はVault暗号化していないため、
      実際の値を設定したら `scripts/encrypt-string.sh password` で**この値だけ**を暗号化し、
      出力(`password: !vault |` ブロック)で該当行を置き換えること(現状はダミー値の
      プレースホルダーが平文で入っている)

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

[collections/requirements.yml](collections/requirements.yml): `ansible.posix`(`>=1.5.0`)、`community.general`(`>=13.1.0`。`sudoers` モジュールの `defaults` パラメータを使用するため)
`mise run install`(または `scripts/install-collections.sh`)で `ansible-galaxy collection install -r collections/requirements.yml` を実行する。

## ツールと仮想環境(mise)

* [mise.toml](mise.toml): Python のバージョンを固定し、`.venv` を自動作成して有効化する(`_.python.venv`)
* [requirements.txt](requirements.txt): `ansible-core` / `ansible-lint` / `yamllint` / `passlib` をバージョン固定で記載する
* タスク: `install`(pip + collection)、`yamllint`、`syntax-check`、`ansible-lint`、`ci`(上の4つをまとめて実行)

## CI(ローカルのみ)

GitHub Actions は使用しない(ワークフローは削除済み。必要になった場合は git 履歴から復元できる)。
検査はローカルで `mise run ci` を実行する。`ci` タスクの内容は以下のとおり。
* `yamllint .`([.yamllint](.yamllint) 参照。`document-start` 無効化、`line-length` 緩和、Ansible流の `{ key: value }` インライン記法許容、ansible-lintとの互換設定、`.venv/` 除外を設定)
* `ansible-playbook --syntax-check`(`bootstrap.yml` / `provisioning.yml`)
* `ansible-lint`([.ansible-lint](.ansible-lint) 参照。`inventory/bootstrap.yml` はVault全体暗号化されており静的解析できないため対象外)

## Vault関連スクリプト

* [scripts/encrypt-file.sh](scripts/encrypt-file.sh) / [scripts/decrypt-file.sh](scripts/decrypt-file.sh)
    * 引数のファイルを `ansible-vault encrypt/decrypt` する(ファイル全体を暗号化)。失敗時は終了コード 1 を返す
    * カレントディレクトリに `.vault_password` があればそれをパスワードファイルとして使う(`.gitignore` 済み)
    * `provision.sh` / `bootstrap.sh` が参照する `.vault_password` とファイル名は一致している
* [scripts/encrypt-string.sh](scripts/encrypt-string.sh)
    * `ansible-vault encrypt_string` で特定の値だけを `変数名: !vault |` 形式にインライン暗号化する
      (ファイル全体を暗号化したくない場合に使う。例: `group_vars/all.yml` の `provisioning_user.password`)
    * 平文はプロンプトで隠し入力する(`--prompt`)。1行の値向け。複数行の値を暗号化したい場合は
      `ansible-vault encrypt_string --stdin-name <name> < ファイル` を直接使う
    * `.vault_password` の有無による挙動は `encrypt-file.sh` と同じ
* [scripts/decrypt-string.sh](scripts/decrypt-string.sh)
    * `group_vars/all.yml` 内のVault暗号化された値を復号して表示する(`ansible localhost -m debug` のラッパー)
    * ファイル全体がVault暗号化されているわけではないため `ansible-vault view/decrypt` は使えず、
      通常のvars解決経路(`-e @group_vars/all.yml` + `--vault-password-file`)で復号する
    * 引数には `provisioning_user.password` のようなドット区切りの変数パスを渡す
    * `.vault_password` の有無による挙動は `encrypt-file.sh`/`encrypt-string.sh` と同じ

## .gitignore

`.vault_password`、`ansible.log`、`.venv/` を除外。
秘密鍵本体(`ssh/` 配下、`.gitkeep` を除く)も `ssh/*` + `!ssh/.gitkeep` で除外しており、実体が git 管理対象に入らないようにしている。

## ディレクトリ構成

```text
.
|-- .ansible-lint
|-- .gitignore
|-- .vault_password           (gitignore対象)
|-- .venv/                    (mise が作成、gitignore対象)
|-- .yamllint
|-- ansible.cfg
|-- bootstrap.yml
|-- mise.toml
|-- provisioning.yml
|-- requirements.txt
|-- bootstrap.sh
|-- provision.sh
|-- ssh_config
|-- collections/
|   `-- requirements.yml
|-- group_vars/
|   `-- all.yml                (provisioning_user.passwordのみ ansible-vault encrypt_string で暗号化)
|-- inventory/
|   |-- hosts.yml
|   |-- bootstrap.yml         (Ansible Vault暗号化済み)
|   `-- provisioning.yml      (秘密を含まないためVault暗号化不要)
|-- roles/
|   `-- .gitkeep              (中身なし、独自role追加用の置き場)
|-- scripts/
|   |-- decrypt-file.sh
|   |-- decrypt-string.sh
|   |-- encrypt-file.sh
|   |-- encrypt-string.sh
|   `-- install-collections.sh
`-- ssh/
    `-- .gitkeep              (秘密鍵の置き場)
```
