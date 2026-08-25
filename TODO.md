# TODO

現状の未実装・不整合項目の対応状況(詳細は [SPEC.md](SPEC.md) を参照)。

- [x] `inventory/bootstrap.yml` の平文パスワードをvault化する(`scripts/encrypt.sh` を使用)
- [x] `bootstrap.yml` が参照する `provisioning_group` / `provisioning_user` 変数を定義する(`group_vars/all.yml` に定義)
- [x] `ssh_config` を実際に使う経路を用意する(`ansible.cfg` の `ssh_args` に `-F ./ssh_config` を追加)

`roles/` は独自role追加用の置き場として意図的に空にしてあり、対応不要(詳細は [SPEC.md](SPEC.md) 参照)。
