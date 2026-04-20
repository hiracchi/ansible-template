# ansible-template

READMEの方針に沿ったAnsible雛形です。

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
    * bootstrap_ansible_user で接続できるかを判定する
    * bootstrap と provisioning の呼び出し順を制御する
* [bootstrap.yml](bootstrap.yml)
    * bootstrap_required に分類されたホストに対して bootstrap を実行する
    * 途中で失敗したホストも後段で再評価できるように host error state をクリアする
* [provisioning.yml](provisioning.yml)
    * bootstrap の成否にかかわらず、bootstrap_ansible_user で provisioning を試行する

実行フローは次の通りです。

1. [site.yml](site.yml) が各ホストに対して bootstrap_ansible_user でSSH接続できるかをローカルから確認する
2. 接続できなかったホストだけを bootstrap_required として [bootstrap.yml](bootstrap.yml) で処理する
3. bootstrapの成否にかかわらず、[provisioning.yml](provisioning.yml) で全ホストに対して provisioning を試行する
4. provisioningの具体的な処理は [roles/common/tasks/main.yml](roles/common/tasks/main.yml) に追加していく

このテンプレートでは、以下の流れでセットアップを行います。

* LinuxまたはmacOS上のAnsible実行端末から接続する
* まずAnsible実行端末から、対象ホストへ bootstrap_ansible_user でSSH接続できるかを確認する
* 接続できない場合は、OS導入時の初期ユーザーとパスワードで接続し、ansible用ユーザーをbootstrapする
* bootstrapの成否にかかわらず、その後のprovisioningは bootstrap_ansible_user で実行を試行する
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
    * bootstrap_ansible_user の接続可否をローカルから判定する
    * bootstrap と provisioning の実行順を制御する
* [bootstrap.yml](bootstrap.yml)
    * 接続不可ホストに対して bootstrap を実行する
    * bootstrapで失敗したホストも再度有効化する
* [provisioning.yml](provisioning.yml)
    * bootstrap_ansible_user で共通provisioningを実行する
* [scripts/install-collections.sh](scripts/install-collections.sh)
    * collection依存をインストールする
* [scripts/run-playbook.sh](scripts/run-playbook.sh)
    * site/bootstrap/provisioning の各playbookを引数付きで実行する
    * 引数未指定時は site を実行する
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
     * bootstrap_initial_user
     * bootstrap_ansible_user
     * provision_ssh_private_key_file
4. [inventories/production/group_vars/all/vault.yml.example](inventories/production/group_vars/all/vault.yml.example) を参考に、vault用の inventories/production/group_vars/all/vault.yml を作成して暗号化する
5. provision用秘密鍵の公開鍵が [inventories/production/group_vars/all/main.yml](inventories/production/group_vars/all/main.yml) の provision_ssh_public_key_file で参照できることを確認する

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

bootstrapだけを実行する場合:

```bash
./scripts/run-playbook.sh bootstrap
```

provisioningだけを実行する場合:

```bash
./scripts/run-playbook.sh provisioning
```

## 変数の考え方

ホスト・グループごとの差分は、inventory配下のgroup_varsやhost_varsで上書きします。

例:

* 初期ユーザー名がグループごとに違う場合
* ansible用ユーザー名を環境ごとに変えたい場合
* Linuxディストリビューションごとに管理者グループ名が違う場合

たとえば、sudoではなくwheelを使う環境では、対象グループまたはホストで以下を上書きします。

```yaml
bootstrap_admin_group: wheel
```

## 補足

* [roles/common/tasks/main.yml](roles/common/tasks/main.yml) は最低限の雛形です。パッケージ導入やディレクトリ作成など、作業単位ごとにroleを追加して分割してください。
* SSH秘密鍵そのものはgitに登録しません。必要な秘密情報はvaultに入れるか、実行端末上で参照する運用にしてください。
* sudoersのvalidateでは /usr/sbin/visudo を使っています。対象OSでパスが異なる場合は調整してください。
