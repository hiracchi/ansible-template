# description

OS 初期化時の初期ユーザー(既定 `pdf00`)のログインを無効化します。

- ログインシェルを `/usr/sbin/nologin` に変更します。
- パスワードをロックします。
- ローカルアカウントが無い場合は何もしません(NIS/LDAP 側のユーザーには触れません)。
- sudo 設定に残っている場合は警告を表示します。

# variables

```
disable_initial_user_name: ubuntu
```

`inventory/bootstrap.yml` の `ansible_user` に合わせて設定してください。

# remarks

- `provisioning.yml` の「Setup all hosts」で実行します。provisioning ユーザーで接続できた後に行われます。
- 無効化後は、このユーザーでは SSH ログインできません。`bootstrap.sh` での初期化も行えなくなります。
- 無効化の前に provisioning ユーザーで接続できていることを確認するため、`provision.sh` の接続確認の後に実行されます。
