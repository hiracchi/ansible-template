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

`inventory/provisioning.yml` は `--extra-vars` で渡されるため、`host_vars` や `group_vars` の同名の変数
(`ansible_user` など)より優先される。特定のホストだけ接続情報を変えたいときは、その変数を
`provisioning.yml` から外すか、`-e` で明示的に上書きする。

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
    * 平文の初期パスワードをコミットしない。次のどちらかで Ansible Vault 暗号化する
        * ファイル全体: `scripts/encrypt-file.sh`(閲覧は `scripts/view.sh`)
        * 値ごと: `scripts/encrypt-string.sh -e ansible_password inventory/bootstrap.yml`(`ansible_user` は平文)。
          `bootstrap.sh` の `--extra-vars="@inventory/bootstrap.yml"` で復号できる。この場合 `view.sh` は使えず、
          確認は `./scripts/decrypt-string.sh ansible_password inventory/bootstrap.yml`
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
      実際の値を設定したら `scripts/encrypt-string.sh -e provisioning_user.password` で**この値だけ**を暗号化すること
      (該当行が `!vault` ブロックに直接置き換わる。現状はダミー値のプレースホルダーが平文で入っている)

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
    * 引数の形式で動作が変わる
        * `変数名` のみ(例: `password`): 入力した値を暗号化し、結果を標準出力に表示する。ファイルは変更しない
        * `キーパス [YAMLファイル]`(例: `provisioning_user.password`): 該当行を `!vault` ブロックで直接置き換える。
          ファイル省略時は `group_vars/all.yml`(例: `-e ansible_password inventory/bootstrap.yml`)。他の行・コメントは残す
        * `-e` を付けると、入力せずファイル内の現在値をそのまま暗号化する
    * 平文は隠し入力する(2回入力が一致した場合のみ処理する)
    * `my_users.<名前>.password` の場合は、入力値を SHA-512 ハッシュ(`openssl passwd -6`)に変換してから暗号化する
    * キーパスの書き換えは [scripts/yaml_vault_inplace.py](scripts/yaml_vault_inplace.py) が行う
      (リストの要素は `my_users.toshi.password` のように、`user: toshi` の項目を名前で指定する)
    * `.vault_password` があればそれをパスワードファイルとして使い、無ければ `--ask-vault-pass` で尋ねる(`.gitignore` 済み)
* [scripts/decrypt-string.sh](scripts/decrypt-string.sh)
    * 変数パスを指定し、復号した値を画面に平文で表示する(`ansible localhost -m debug` のラッパー)。第2引数で対象の YAML を指定できる(省略時は `group_vars/all.yml`。例: `./scripts/decrypt-string.sh ansible_password inventory/bootstrap.yml`)
    * `my_users.toshi.password` のように、`my_users` は名前で指定できる。引数なし・`-h` で使い方を表示する
    * ファイル全体がVault暗号化されているわけではないため、`ansible-vault view/decrypt` は使えない
* [scripts/hash-password.sh](scripts/hash-password.sh)
    * パスワードを2回入力し、SHA-512 crypt(`$6$...`)のハッシュを標準出力に出す(依存は `openssl` のみ)
* [scripts/view.sh](scripts/view.sh)
    * ファイル全体が `ansible-vault` で暗号化されたファイルを、復号せずに閲覧する(内部は `ansible-vault view`)
    * `inventory/bootstrap.yml` を値ごとに暗号化した場合や `group_vars/all.yml` には使えない("Input is not vault encrypted data" になる)
    * `.vault_password` の有無による挙動は `encrypt-file.sh` と同じ
* [scripts/yaml_vault_inplace.py](scripts/yaml_vault_inplace.py)
    * `encrypt-string.sh` から呼ばれる補助スクリプト(単体では使わない)。YAML の該当キーの値を読み書きする

## 運用スクリプト

* [scripts/node-health.sh](scripts/node-health.sh) / [scripts/node-health-remote.sh](scripts/node-health-remote.sh)
    * ホストの状態を読み取り専用で検査する。`node-health.sh` が Ansible で各ホストに `node-health-remote.sh` を実行し、結果を整形して表示する
    * 検査項目: 稼働状況、起動履歴(60 秒未満の起動の回数)、前回の終了が正常か、EDAC・MCE・rasdaemon のエラー、
      kdump(kdump-tools が入っているホストだけ)、SMART と SSD の寿命、ディスク使用率、失敗中のサービス、時刻同期、
      参考情報(BIOS・基板・DIMM・microcode・IPMI SEL など)
    * 表示は OK / WARN / NG / SKIP / INFO。設定は変更しない
    * 引数はノード名か `all`。`all` の対象は `DEFAULT_ALL_GROUP`(既定 `all`)か、`-g グループ名` で指定する
    * panic 系 sysctl の期待値の検査は、プロジェクトの方針なので、`--crash-checks` を付けるか
      `DEFAULT_CRASH_CHECKS=1` のときだけ行う
* [scripts/shutdown-nodes.sh](scripts/shutdown-nodes.sh)
    * ノードを `community.general.shutdown` で電源オフする。対象の指定は `node-health.sh` と同じ(`-g`、`DEFAULT_ALL_GROUP`)
    * 実行前に対象ホストを表示し、`yes` の入力を求める。`-n` は dry-run、`-d 分` は遅延、`-y` は確認の省略
* [scripts/collect-machine-specs.sh](scripts/collect-machine-specs.sh)
    * 各ホストに SSH(`~/.ssh/config` の Host 名、鍵認証)で接続し、OS・カーネル・CPU・メモリ・ディスク・GPU を Markdown の表にする
    * 役割(inventory グループ)は `inventory/hosts.yml` から取得する。既定の対象は inventory の全ホストから
      `DEFAULT_EXCLUDE_HOSTS` を除いたもの(`-x` で追加の除外も指定できる)
    * 出力先の既定は `docs/hosts/machine-specs.md`(`-o -` で標準出力)
* プロジェクトごとに変える設定は、各スクリプトの先頭にある次の変数にまとめている。

| 変数 | スクリプト | 意味 | 既定 |
|---|---|---|---|
| `DEFAULT_ALL_GROUP` | node-health.sh、shutdown-nodes.sh | `all` を指定したときの対象グループ | `all` |
| `DEFAULT_CRASH_CHECKS` | node-health.sh | panic 系 sysctl の検査を既定で行うか(1 で有効) | `0` |
| `DOC_TITLE` | collect-machine-specs.sh | 出力する表の見出しに使う名前 | `プロジェクト` |
| `DEFAULT_EXCLUDE_HOSTS` | collect-machine-specs.sh | 既定で対象から外すホスト(空白区切り) | 空 |

## ansible-core 2.21 での注意

* `ansible.builtin.shutdown` は存在しない。ノードを停止するときは `community.general.shutdown` を使う
* `paramiko` の接続プラグインはなく、パスワード認証の SSH には `sshpass` が必要
* リポジトリ直下に `requirements.yml` を置くと、`ansible-lint` が Galaxy からの導入を試みて失敗する。
  コレクションの一覧は `collections/requirements.yml` に置く

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
|   `-- all.yml                (秘密の値のみ encrypt-string.sh で !vault 暗号化)
|-- inventory/
|   |-- hosts.yml
|   |-- bootstrap.yml         (Ansible Vault暗号化済み)
|   `-- provisioning.yml      (秘密を含まないためVault暗号化不要)
|-- roles/
|   `-- .gitkeep              (中身なし、独自role追加用の置き場)
|-- scripts/
|   |-- collect-machine-specs.sh
|   |-- decrypt-file.sh
|   |-- decrypt-string.sh
|   |-- encrypt-file.sh
|   |-- encrypt-string.sh
|   |-- hash-password.sh
|   |-- install-collections.sh
|   |-- new-project.sh
|   |-- node-health-remote.sh
|   |-- node-health.sh
|   |-- shutdown-nodes.sh
|   |-- view.sh
|   `-- yaml_vault_inplace.py
`-- ssh/
    `-- .gitkeep              (秘密鍵の置き場)
```
