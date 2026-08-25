# TODO

現状の未実装・不整合項目(詳細は [SPEC.md](SPEC.md) の「既知の不整合・未実装項目」を参照)。

- [ ] `inventory/bootstrap.yml` の平文パスワードをvault化する(`scripts/encrypt.sh` を使用)
- [ ] `bootstrap.yml` が参照する `provisioning_group` / `provisioning_user` 変数を定義する(未定義のため現状 bootstrap.yml は実行時エラーになる)
- [ ] `provisioning.yml` が参照する roles(`timezone`, `hostname`, `hosts`, `ubuntu-base`)を `roles/` 配下に実装する
- [ ] `ssh_config` を実際に使う経路を用意する(`ansible.cfg` からの参照、または利用手順の明記)。不要なら削除も検討
