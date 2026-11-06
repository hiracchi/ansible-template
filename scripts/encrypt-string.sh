#!/bin/bash

# ファイル全体ではなく特定の値だけを ansible-vault でインライン暗号化
# (`変数名: !vault |` 形式)するスクリプト。
# 平文はプロンプトで隠し入力するため、シェル履歴等に残らない。
# カレントディレクトリに .vault_password というファイルが存在すればそのファイルをパスワードファイルとして使用する。
#
# 使い方:
#   ./scripts/encrypt-string.sh <変数名>                          暗号化結果を標準出力に表示する(手動で貼り替える)
#   ./scripts/encrypt-string.sh <キーパス> [YAMLファイル]          値を入力して、YAMLファイル内の該当キーを置き換える
#   ./scripts/encrypt-string.sh -e <キーパス> [YAMLファイル]       入力せず、ファイルにある現在の値をそのまま暗号化して置き換える
#
#   キーパスは "." 区切り。ファイル省略時は group_vars/all.yml。
#   リストの要素は「いずれかのキーの値が一致するセグメント」で指定する。
#   (例: my_users.toshi.password は "user: toshi" の要素の password)
#
# 例: ./scripts/encrypt-string.sh password
#     ./scripts/encrypt-string.sh provisioning_user.password
#     ./scripts/encrypt-string.sh -e provisioning_user.private_key
#     ./scripts/encrypt-string.sh -e my_users.toshi.password
#     ./scripts/encrypt-string.sh -e ansible_password inventory/bootstrap.yml
#
# 置き換えは対象キーの行(既に複数行ブロックならそのブロック全体)だけを書き換え、
# 他の行・コメントはそのまま残す。

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER="${SCRIPT_DIR}/yaml_vault_inplace.py"

EXISTING=0
if [ "$1" = "-e" ] || [ "$1" = "--existing" ]; then
    EXISTING=1
    shift
fi

if [ $# -eq 0 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 [-e] <variable_name | key.path> [yaml_file]"
    exit 1
fi

KEY_PATH="$1"
TARGET_FILE="${2:-group_vars/all.yml}"
ANSIBLE_VAULT_PASSWORD_FILE=".vault_password"

VAULT_PASSWORD_OPTION="--ask-vault-pass"
if [ -f "$ANSIBLE_VAULT_PASSWORD_FILE" ]; then
    VAULT_PASSWORD_OPTION="--vault-password-file $ANSIBLE_VAULT_PASSWORD_FILE"
fi

# "." を含まず -e も無い場合は従来どおり、結果を表示するだけ
if [ "$EXISTING" -eq 0 ] && [[ "$KEY_PATH" != *.* ]]; then
    ansible-vault encrypt_string $VAULT_PASSWORD_OPTION --name "$KEY_PATH" --prompt
    exit $?
fi

if [ ! -f "$TARGET_FILE" ]; then
    echo "ファイルが見つかりません: $TARGET_FILE" >&2
    exit 1
fi

LEAF_NAME="${KEY_PATH##*.}"

if [ "$EXISTING" -eq 1 ]; then
    # ファイルの現在値をそのまま暗号化する。末尾改行を保つため、コマンド置換を通さず
    # 一時ファイル経由で受け取る。
    TMP_OUT=$(mktemp) || exit 1
    trap 'rm -f "$TMP_OUT"' EXIT
    set -o pipefail
    python3 "$HELPER" get "$KEY_PATH" "$TARGET_FILE" \
        | ansible-vault encrypt_string $VAULT_PASSWORD_OPTION --stdin-name "$LEAF_NAME" > "$TMP_OUT" \
        || { echo "暗号化に失敗しました。" >&2; exit 1; }
    ENCRYPTED=$(cat "$TMP_OUT")
else
    # 平文を端末から隠し入力する(--prompt は標準出力を取り込むとプロンプトも取り込まれて
    # 何も表示されなくなるため、ここで自前で読み取る)
    read -r -s -p "暗号化する値(${KEY_PATH}): " PLAIN </dev/tty || exit 1
    echo >&2
    read -r -s -p "確認のためもう一度: " PLAIN2 </dev/tty || exit 1
    echo >&2
    if [ -z "$PLAIN" ] || [ "$PLAIN" != "$PLAIN2" ]; then
        echo "値が空、または一致しません。" >&2
        unset PLAIN PLAIN2
        exit 1
    fi
    # my_users の password はハッシュ(system_users ロールがそのまま使う)のため、
    # 入力された平文を SHA-512 crypt($6$...)にしてから暗号化する。
    # provisioning_user.password は平文のままで良い(bootstrap.yml がハッシュ化する)。
    if [[ "$KEY_PATH" == my_users.* ]]; then
        PLAIN=$(printf '%s' "$PLAIN" | openssl passwd -6 -stdin | tr -d '\n') || exit 1
        echo "my_users 用に SHA-512 ハッシュへ変換して暗号化します。" >&2
    fi
    ENCRYPTED=$(printf '%s' "$PLAIN" | ansible-vault encrypt_string $VAULT_PASSWORD_OPTION --stdin-name "$LEAF_NAME") || {
        echo "暗号化に失敗しました。" >&2
        exit 1
    }
    unset PLAIN PLAIN2
fi

if [ -z "$ENCRYPTED" ]; then
    echo "暗号化結果が空です。" >&2
    exit 1
fi

printf '%s\n' "$ENCRYPTED" | python3 "$HELPER" replace "$KEY_PATH" "$TARGET_FILE"
