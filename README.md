# ansible-template

Ansibleで環境設定を行う汎用テンプレートプロジェクトです。

* 詳しい仕様(各ファイルの役割、実行フロー、ディレクトリ構成)は [SPEC.md](SPEC.md) を参照してください。
* タスク対応状況は [TODO.md](TODO.md) を参照してください。

## 初期設定・セットアップ手順

1. `./scripts/install-collections.sh` で必要なAnsible Collectionをインストールする
2. `inventory/hosts.yml` を対象ホストに合わせて編集する
3. `group_vars/all.yml` の `provisioning_group` / `provisioning_user` を対象環境に合わせて編集する (作成するAnsibleユーザー、SSH公開鍵など)
4. `inventory/bootstrap.yml` の初期ログイン情報 (bootstrap用) を必要に応じて編集し、`./scripts/encrypt.sh inventory/bootstrap.yml` でVault暗号化する
5. `inventory/provisioning.yml` の `ansible_user` / `ansible_private_key_file` を設定する
6. `./ssh/{{ ansible_user }}` にプロビジョニング用の秘密鍵を配置する (または `bootstrap.yml` 実行時に自動配置)
7. カレントディレクトリに `.vault_password` を配置する (または `exec.sh` 実行時に入力)

## 実行例

```bash
./exec.sh                 # all グループに対して実行
./exec.sh webservers      # webservers グループに限定して実行
BOOTSTRAP_ASK_BECOME_PASS=1 ./exec.sh   # bootstrap時にbecomeパスワードを都度入力する
```
