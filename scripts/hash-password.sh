#!/bin/bash

# パスワードを SHA-512 crypt($6$...)のハッシュにして標準出力に出すスクリプト。
# 平文は画面に表示せず、2回入力が一致したときだけハッシュを出力する。
# 依存は openssl のみ(python の passlib は不要)。
#
# 使い方: ./scripts/hash-password.sh
#   出力例: $6$xxxxxxxx$yyyy...(106文字程度)
#   my_users の password に使う場合は、そのまま貼る or encrypt-string.sh で暗号化する。
#   (encrypt-string.sh my_users.<名前>.password なら入力から自動でハッシュ化するので、このスクリプトは不要)

set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: $0"
    echo "  パスワードを2回入力し、SHA-512 crypt のハッシュを標準出力に出します。"
    exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl が見つかりません。" >&2
    exit 1
fi

read -r -s -p "パスワード: " PW </dev/tty
echo >&2
read -r -s -p "確認のためもう一度: " PW2 </dev/tty
echo >&2

if [ -z "$PW" ] || [ "$PW" != "$PW2" ]; then
    unset PW PW2
    echo "値が空、または一致しません。" >&2
    exit 1
fi

printf '%s' "$PW" | openssl passwd -6 -stdin
unset PW PW2
