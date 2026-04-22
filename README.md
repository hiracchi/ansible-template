# ansible-template

READMEの方針に沿ったAnsible雛形です。

## 現在の仕様まとめ

### 実行フロー

1. [site.yml](site.yml) で、各ホストに対して `provisioner_name` のSSH接続可否をローカルから判定する
2. 接続不可ホストを `bootstrap_required` に分類する
3. [bootstrap.yml](bootstrap.yml) で `bootstrap_required` に対して bootstrap を実行する
4. bootstrap結果にかかわらず [provisioning.yml](provisioning.yml) で全ホストに provisioning を試行する

### run-playbook.sh の仕様

* 対象スクリプト: [scripts/run-playbook.sh](scripts/run-playbook.sh)
* playbook選択オプション:
    * `--site` (デフォルト)
    * `--bootstrap-only`
    * `--provisioning-only`
* 位置引数はホスト名/グループ名として解釈され、`--limit` に変換される
    * 例: `./scripts/run-playbook.sh web01 db` は `--limit web01,db` として実行される
* 位置引数と `-l/--limit` の同時指定はエラー
* Vaultオプション未指定時は `.vault_pass.txt` があれば `--vault-password-file`、なければ `--ask-vault-pass` を自動選択

### 主要変数（inventories/production/group_vars/all/main.yml）

* `bootstrap_user`: 初期接続に使うユーザー
* `provisioner_name`: provisioningに使うユーザー名
* `provisioner_uid`: provisionerユーザーのUID（空なら自動割当）
* `provisioner_primary_group`: provisionerのprimary group
* `provisioner_primary_group_gid`: primary groupのGID（空なら自動割当）
* `provisioner_groups`: supplementary groups（配列）
* `provisioner_shell`: provisionerユーザーのログインシェル
* `provisioner_private_key_file`: SSH秘密鍵パス
* `provisioner_public_key_file`: SSH公開鍵パス（bootstrap時の authorized_keys 登録で使用）
* `provisioner_passwordless_sudo`: sudoersを作成するか
* `ssh_connect_timeout`: 接続判定時のSSHタイムアウト秒数

### Vault変数

* サンプル: [inventories/production/group_vars/all/vault.yml.example](inventories/production/group_vars/all/vault.yml.example)
* `vault_bootstrap_initial_password`: `bootstrap_user` のログインパスワード
* `vault_bootstrap_become_password`: sudo昇格パスワード（未設定時は初期パスワードを利用）

### Ansible出力設定

* [ansible.cfg](ansible.cfg) で `stdout_callback=default` と `result_format=yaml` を使用
* `community.general.yaml` には依存しない

## これまでの作業内容

このリポジトリでは、READMEの要件に合わせて以下の雛形を作成しました。

* Ansibleの基本設定として [ansible.cfg](ansible.cfg) を追加した
* inventoryの雛形として [inventories/production/hosts.yml](inventories/production/hosts.yml) と group_vars を追加した
* 秘密情報を平文で管理しないため、vaultの雛形として [inventories/production/group_vars/all/vault.yml.example](inventories/production/group_vars/all/vault.yml.example) を追加した
* bootstrap用roleとして [roles/bootstrap/tasks/main.yml](roles/bootstrap/tasks/main.yml) を追加し、ansible用ユーザー作成、公開鍵登録、sudoers設定を実装した
* provisioning用の共通roleとして [roles/common/tasks/main.yml](roles/common/tasks/main.yml) を追加した
* ansible.posix の利用を明示するため、[collections/requirements.yml](collections/requirements.yml) を追加した
* 一時ファイルやvaultパスワードファイルをgit登録しないため、[.gitignore](.gitignore) を追加した

また、playbookの責務を分けるために以下の構成に整理しています。

* [site.yml](site.yml)
    * provisioner_name で接続できるかを判定する
    * bootstrap と provisioning の呼び出し順を制御する
* [bootstrap.yml](bootstrap.yml)
    * bootstrap_required に分類されたホストに対して bootstrap を実行する
    * 途中で失敗したホストも後段で再評価できるように host error state をクリアする
* [provisioning.yml](provisioning.yml)
    * bootstrap の成否にかかわらず、provisioner_name で provisioning を試行する

実行フローは次の通りです。

1. [site.yml](site.yml) が各ホストに対して provisioner_name でSSH接続できるかをローカルから確認する
2. 接続できなかったホストだけを bootstrap_required として [bootstrap.yml](bootstrap.yml) で処理する
3. bootstrapの成否にかかわらず、[provisioning.yml](provisioning.yml) で全ホストに対して provisioning を試行する
4. provisioningの具体的な処理は [roles/common/tasks/main.yml](roles/common/tasks/main.yml) に追加していく

このテンプレートでは、以下の流れでセットアップを行います。

* LinuxまたはmacOS上のAnsible実行端末から接続する
* まずAnsible実行端末から、対象ホストへ provisioner_name でSSH接続できるかを確認する
* 接続できない場合は、OS導入時の初期ユーザーとパスワードで接続し、ansible用ユーザーをbootstrapする
* bootstrapの成否にかかわらず、その後のprovisioningは provisioner_name で実行を試行する
* パスワードなどの秘密情報は、gitに平文で登録せず、ansible-vaultで管理する前提にする

## ディレクトリ構成

```text
.
|-- .gitignore
|-- ansible.cfg
|-- bootstrap.yml
|-- collections/
|   `-- requirements.yml
|-- inventories/
|   `-- production/
|       |-- hosts.yml
|       `-- group_vars/
|           |-- all/
|           |   |-- main.yml
|           |   `-- vault.yml.example
|           `-- linux.yml
|-- roles/
|   |-- bootstrap/
|   |   |-- defaults/main.yml
|   |   `-- tasks/main.yml
|   `-- common/
|       |-- defaults/main.yml
|       `-- tasks/main.yml
|-- scripts/
|   |-- install-collections.sh
|   `-- run-playbook.sh
|-- provisioning.yml
`-- site.yml
```

## 各ファイルの役割

* [site.yml](site.yml)
    * provisioner_name の接続可否をローカルから判定する
    * bootstrap と provisioning の実行順を制御する
* [bootstrap.yml](bootstrap.yml)
    * 接続不可ホストに対して bootstrap を実行する
    * bootstrapで失敗したホストも再度有効化する
* [provisioning.yml](provisioning.yml)
    * provisioner_name で共通provisioningを実行する
* [scripts/install-collections.sh](scripts/install-collections.sh)
    * collection依存をインストールする
* [scripts/run-playbook.sh](scripts/run-playbook.sh)
    * site/bootstrap/provisioning の各playbookをオプションで実行する
    * 引数未指定時は site を実行する
    * 位置引数でホスト名またはグループ名を渡すと、その対象に限定して実行する
    * Vault指定が未指定なら .vault_pass.txt の有無で --vault-password-file と --ask-vault-pass を自動切り替えする
* [inventories/production/hosts.yml](inventories/production/hosts.yml)
    * 対象ホストとグループを定義する
* [inventories/production/group_vars/all/main.yml](inventories/production/group_vars/all/main.yml)
    * 初期ユーザー名、ansible用ユーザー名、SSH鍵パス、共通変数を定義する
* [inventories/production/group_vars/all/vault.yml.example](inventories/production/group_vars/all/vault.yml.example)
    * vault化すべき秘密情報の雛形
* [roles/bootstrap/tasks/main.yml](roles/bootstrap/tasks/main.yml)
    * ansible用ユーザー作成、公開鍵登録、sudoers設定を行う
* [roles/common/tasks/main.yml](roles/common/tasks/main.yml)
    * provision時に共通適用したい設定の置き場

## 初期設定

1. [inventories/production/hosts.yml](inventories/production/hosts.yml) のサンプルホストを実環境に合わせて変更する
2. collectionをインストールする
    ```bash
    ./scripts/install-collections.sh
    ```
3. [inventories/production/group_vars/all/main.yml](inventories/production/group_vars/all/main.yml) の以下を環境に合わせて変更する
    * bootstrap_user
    * provisioner_name
    * provisioner_private_key_file
4. [inventories/production/group_vars/all/vault.yml.example](inventories/production/group_vars/all/vault.yml.example) を参考に、vault用の inventories/production/group_vars/all/vault.yml を作成して暗号化する
5. provision用秘密鍵の公開鍵が [inventories/production/group_vars/all/main.yml](inventories/production/group_vars/all/main.yml) の provisioner_public_key_file で参照できることを確認する

vaultファイル作成例:

```bash
cp inventories/production/group_vars/all/vault.yml.example inventories/production/group_vars/all/vault.yml
ansible-vault encrypt inventories/production/group_vars/all/vault.yml
```

## 実行例

通常実行:

```bash
./scripts/run-playbook.sh
```

特定ホストまたはグループを指定して実行する場合:

```bash
./scripts/run-playbook.sh web01
./scripts/run-playbook.sh app db
```

bootstrapだけを実行する場合:

```bash
./scripts/run-playbook.sh --bootstrap-only
```

provisioningだけを実行する場合:

```bash
./scripts/run-playbook.sh --provisioning-only
```

## 変数の考え方

ホスト・グループごとの差分は、inventory配下のgroup_varsやhost_varsで上書きします。

例:

* 初期ユーザー名がグループごとに違う場合
* ansible用ユーザー名を環境ごとに変えたい場合
* Linuxディストリビューションごとに管理者グループ名が違う場合

たとえば、sudoではなくwheelを使う環境では、対象グループまたはホストで以下を上書きします。

```yaml
provisioner_primary_group: wheel
provisioner_groups: []
```

primary groupのGIDを固定したい場合は、以下も設定できます。

```yaml
provisioner_primary_group_gid: "1001"
```

provisionerユーザーのUIDを固定したい場合は、以下を設定できます。

```yaml
provisioner_uid: "1001"
```

## 補足

* [roles/common/tasks/main.yml](roles/common/tasks/main.yml) は最低限の雛形です。パッケージ導入やディレクトリ作成など、作業単位ごとにroleを追加して分割してください。
* SSH秘密鍵そのものはgitに登録しません。必要な秘密情報はvaultに入れるか、実行端末上で参照する運用にしてください。
* sudoersのvalidateでは /usr/sbin/visudo を使っています。対象OSでパスが異なる場合は調整してください。
