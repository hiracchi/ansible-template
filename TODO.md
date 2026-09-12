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

`roles/` は独自role追加用の置き場として意図的に空にしてあり、対応不要(詳細は [SPEC.md](SPEC.md) 参照)。
