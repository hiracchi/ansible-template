# TODO

現状の未実装・不整合項目の対応状況(詳細は [SPEC.md](SPEC.md) を参照)。

- [x] `inventory/bootstrap.yml` の平文パスワードをvault化する(`scripts/encrypt.sh` を使用)
- [x] `bootstrap.yml` が参照する `provisioning_group` / `provisioning_user` 変数を定義する(`group_vars/all.yml` に定義)
- [x] `ssh_config` を実際に使う経路を用意する(`ansible.cfg` の `ssh_args` に `-F ./ssh_config` を追加)
- [x] `ssh/` 配下の秘密鍵が `.gitignore` で除外されておらず git 管理対象に入り得た不整合を修正(`ssh/*` + `!ssh/.gitkeep` を追加)
- [x] ホスト鍵検証を無効化していた設定(`host_key_checking = False`, `StrictHostKeyChecking no`, `UserKnownHostsFile /dev/null`)をTOFU方式(`accept-new` + プロジェクト直下の `ssh_known_hosts`)に変更
- [x] `ssh_config` で全ホストに既定有効化されていた `ForwardAgent` / `ForwardX11` を無効化(自動化に不要なため)
- [x] `ansible.cfg` の `allow_world_readable_tmpfiles = True` を削除し、リモートの一時ファイルが world-readable にならない既定値に戻した
- [x] `provisioning_user` のsudoersがNOPASSWD ALLだったのをやめ、`group_vars/all.yml` の `provisioning_user.password`(ハッシュ)+ `inventory/provisioning.yml` の `ansible_become_password`(Vault管理)によるパスワード認証必須のsudoに変更
- [x] sshd_configの強化(`PasswordAuthentication no` / `ChallengeResponseAuthentication no` / `PermitRootLogin no`)を `provisioning.yml` の `Harden sshd` play で対応
- [x] ファイアウォール(ufw)の設定を `provisioning.yml` の `Configure firewall (ufw)` play で対応(SSHポート許可 → デフォルトdeny → 有効化の順)
- [x] `exec.sh` の未定義変数 `${ASK_PASS}` を削除
- [x] `scripts/encrypt.sh` / `scripts/decrypt.sh` のコメントの古いファイル名 `.vault_pass.txt` を `.vault_password` に修正
- [x] 未使用かつ壊れていた(誤ったinventory参照、実在しない `reboot.yml` を呼ぶ)`reboot_system()` / `ask_yes_or_no()` を `exec.sh` から削除
- [x] sudoersの `commands: ALL` は維持しつつ(Ansibleの汎用性上、コマンド許可リスト化は非現実的)、`runas: ALL` → `runas: root` に限定し、専用ログ(`/var/log/sudo-ansible.log`)で可観測性を確保
- [x] fail2banを `provisioning.yml` の `Configure fail2ban` play で導入(`sshd` jail、`banaction = ufw` で既存のufwと連携)
- [x] `group_vars/all.yml` の `uid`/`gid` 固定値(2000)を既定でコメントアウトし省略可に変更(未指定ならOSが自動採番。既存ユーザーとの衝突リスクを解消)
- [x] `bootstrap.yml` がPython未導入の最小イメージに対応できるよう、`gather_facts` 前に `raw` モジュールで `python3` を確認・インストールするよう変更
- [x] 自動セキュリティ更新(unattended-upgrades)を `provisioning.yml` の `Configure automatic security updates` play で導入
- [x] CI(GitHub Actions)で `yamllint` / `ansible-playbook --syntax-check` / `ansible-lint` を実行する仕組みを追加(`.github/workflows/ci.yml`、`.yamllint`、`.ansible-lint`)
- [x] `collections/requirements.yml` の `ansible.posix` にバージョン下限(`>=1.5.0`)を追加
- [x] `group_vars/all.yml` の `provisioning_user.password`(ハッシュ)と `inventory/provisioning.yml` の
      `ansible_become_password`(平文)を別々に持ち、パスワード変更のたびに手動で同期する必要があった問題を解消。
      `provisioning_user.password` を平文に一本化し(`bootstrap.yml` が `password_hash` フィルタで実行時にハッシュ化)、
      `ansible_become_password` はこの値を直接参照するように変更。`group_vars/all.yml` はファイル全体を
      Vault暗号化していないため、`password` の値だけを暗号化する `scripts/encrypt-string.sh` を追加し、
      不要になった `scripts/make-password.py` を削除

`roles/` は独自role追加用の置き場として意図的に空にしてあり、対応不要(詳細は [SPEC.md](SPEC.md) 参照)。
