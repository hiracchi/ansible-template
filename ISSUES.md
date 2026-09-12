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
| 7 | ファイアウォール未設定(全ポート無防備だった) | `provisioning.yml`(未コミット) |

対応内容の詳細は各コミットメッセージ、および `SPEC.md` / `README.md` の該当箇所を参照。

## 未対応

### セキュリティ関連

- **sudoersのNOPASSWD ALL自体は「全コマンド許可」のまま**: パスワード認証は必須にしたが、許可コマンド自体はALLのまま。
  鍵+パスワードの両方が漏れた場合の被害はrootフル権限になる点は変わらない(トレードオフとして許容する方針で合意済み)。
- **fail2ban/自動アップデート等、初期設定の定番項目がまだ未実装**(ファイアウォールはufwで対応済み)。`roles/` を意図的に空に
  している設計自体は妥当だが、サンプルroleが1つもないため、利用者が何を書けばいいか迷う可能性がある。

### バグ・整合性

- `exec.sh:60` の `${ASK_PASS}` が未定義変数のまま残っている(死んだ変数、実害はないが紛らわしい)
- `scripts/encrypt.sh:4` / `scripts/decrypt.sh:4` のコメントに古いファイル名 `.vault_pass.txt` が残っている(実際は `.vault_password`)
- `reboot_system()`(`exec.sh:86-96`)が定義だけで呼び出しはコメントアウトのまま放置されている

### 「OSの初期設定から」という目標に対するギャップ

- **Pythonが入っていない最小イメージへの対応がない**: `bootstrap.yml` はいきなり `gather_facts` や通常モジュールを使うため、
  Python未導入のホストには使えない。`ansible.builtin.raw` での事前インストールを検討する余地がある。

### GitHub運用に向けて

- CI(GitHub Actions)で `ansible-lint` / `yamllint` / `ansible-playbook --syntax-check` を回す仕組みがない
- `collections/requirements.yml` にバージョン指定がなく、意図しないcollection更新でplaybookが壊れるリスクがある

### 軽微

- `group_vars/all.yml` の `uid: 2000` / `gid: 2000` が環境によっては既存ユーザーと衝突する可能性がある
