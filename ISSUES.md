# レビュー結果まとめ

このテンプレートをレビューして見つかった問題点の一覧です。対応済み/未対応の状況を記録しています。

## 対応済み

| # | 内容 | 対応コミット |
|---|------|--------------|
| 1 | `ssh/` 配下の秘密鍵が `.gitignore` で除外されておらず、git管理対象に入り得た | `fe0704b` |
| 2 | `host_key_checking = False` + `StrictHostKeyChecking no` + `UserKnownHostsFile /dev/null` でホスト鍵検証を完全無効化していた(MITM検知不可) | `24ef2f7` |
| 3 | `ssh_config` の `Host *` に `ForwardAgent yes` / `ForwardX11(Trusted) yes` が既定で有効化されていた | `d6e36bd` |
| 4 | `ansible.cfg` の `allow_world_readable_tmpfiles = True` でリモートの一時ファイルがworld-readableになっていた | `4dedf02` |
| 5 | `provisioning_user` のsudoersが `NOPASSWD ALL` だった(SSH秘密鍵漏洩だけでroot化可能) | `fef18d2` |
| 6 | sshd_configが未強化(パスワード認証・root直接ログインが許可されたままになり得た) | `d9beaa3` |
| 7 | ファイアウォール未設定(全ポート無防備だった) | `ccbc010` |
| 8 | `exec.sh:60` の未定義変数 `${ASK_PASS}`、`scripts/encrypt.sh`/`decrypt.sh` の古いコメント(`.vault_pass.txt`)、壊れて未使用だった `reboot_system()`/`ask_yes_or_no()`(誤ったinventory参照 `-i inventory/provisioning.yml`、実在しない `reboot.yml` を呼んでいた) | `2f783ef` |
| 9 | sudoersが `runas: ALL` だった(root以外へのbecomeは使っていないのに昇格先が無制限) | `bootstrap.yml`等(未コミット) |

対応内容の詳細は各コミットメッセージ、および `SPEC.md` / `README.md` の該当箇所を参照。

## 未対応

### セキュリティ関連

- **sudoersの `commands: ALL` 自体は維持している**: Ansibleの各モジュールは実行のたびに一時パスのスクリプトや
  apt/systemctl/useradd等の多様なコマンドを呼び出すため、コマンド単位の許可リスト化は現実的でないという判断による
  意図的なトレードオフ(合意済み)。代わりに `runas: root` への限定 + 専用sudoログでリスクを下げている。
- **fail2ban/自動アップデート等、初期設定の定番項目がまだ未実装**(ファイアウォールはufwで対応済み)。`roles/` を意図的に空に
  している設計自体は妥当だが、サンプルroleが1つもないため、利用者が何を書けばいいか迷う可能性がある。

### 「OSの初期設定から」という目標に対するギャップ

- **Pythonが入っていない最小イメージへの対応がない**: `bootstrap.yml` はいきなり `gather_facts` や通常モジュールを使うため、
  Python未導入のホストには使えない。`ansible.builtin.raw` での事前インストールを検討する余地がある。

### GitHub運用に向けて

- CI(GitHub Actions)で `ansible-lint` / `yamllint` / `ansible-playbook --syntax-check` を回す仕組みがない
- `collections/requirements.yml` の `ansible.posix` にバージョン指定がなく、意図しないcollection更新でplaybookが壊れるリスクがある
  (`community.general` は `sudoers` の `defaults` パラメータ利用に伴い `>=13.1.0` を指定済み)

### 軽微

- `group_vars/all.yml` の `uid: 2000` / `gid: 2000` が環境によっては既存ユーザーと衝突する可能性がある
