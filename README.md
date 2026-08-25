# ansible-template

Ansibleで環境設定を行うテンプレートプロジェクトです。

* 詳しい仕様(各ファイルの役割、実行フロー、既知の不整合・未実装項目)は [SPEC.md](SPEC.md) を参照してください。
* 未対応タスクの一覧は [TODO.md](TODO.md) を参照してください。

## 初期設定(現状のワークフローに沿う場合)

1. `./scripts/install-collections.sh` でcollectionをインストールする
2. `inventory/hosts.yml` を対象ホストに合わせて編集する
3. `inventory/bootstrap.yml` の初期ユーザー/パスワードを対象環境に合わせて編集する(本来はvault化推奨)
4. `inventory/provisioning.yml` の `ansible_user` / `ansible_private_key_file` を対象環境に合わせて編集する
5. `./ssh/{{ ansible_private_key_file の名前 }}` に秘密鍵を配置する
6. `provisioning.yml` が参照する roles(`timezone`, `hostname`, `hosts`, `ubuntu-base`)を `roles/` 配下に実装する(現状未実装、詳細は [SPEC.md](SPEC.md) 参照)
7. `bootstrap.yml` が参照する `provisioning_group` / `provisioning_user` 変数をどこかで定義する(現状未実装、詳細は [SPEC.md](SPEC.md) 参照)

## 実行例

```bash
./exec.sh                 # all グループに対して実行
./exec.sh frontend        # frontend グループに限定して実行
BOOTSTRAP_ASK_BECOME_PASS=1 ./exec.sh   # bootstrap時にbecomeパスワードを都度入力する
```
