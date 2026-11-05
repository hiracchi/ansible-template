#!/usr/bin/env bash
# provisioning_user.password を新しいパスワードで設定する。
#
# 平文は隠し入力で受け取り、ansible-vault でインライン暗号化して
# group_vars/all.yml の provisioning_user.password の行を置き換える。
# 置き換え対象は `password: CHANGE_ME` でも既存の `password: !vault |` でもよい。
# 平文はファイルにもコマンドライン引数にも書き出さない。
# 暗号文は一時ファイル経由で渡し、検証後に all.yml へ反映する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

TARGET="group_vars/all.yml"
VAULT_PASS_FILE=".vault_password"
NEW_FILE="${TARGET}.tmp.$$"
WORK_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${WORK_DIR}"
    rm -f "${NEW_FILE}"
}
trap cleanup EXIT

die() {
    echo "エラー: $*" >&2
    exit 1
}

for cmd in ansible-vault python3; do
    command -v "${cmd}" >/dev/null 2>&1 || die "${cmd} が見つかりません(mise run install を実行してください)"
done
[ -f "${VAULT_PASS_FILE}" ] || die "${VAULT_PASS_FILE} が見つかりません"
[ -f "${TARGET}" ] || die "${TARGET} が見つかりません"

read -rsp "新しいパスワード: " PW1
echo
read -rsp "確認のため再入力: " PW2
echo
[ -n "${PW1}" ] || die "空のパスワードは設定できません"
[ "${PW1}" = "${PW2}" ] || die "入力したパスワードが一致しません"
unset PW2

# 1. 平文を stdin 経由で暗号化する(引数には載せない)
printf '%s' "${PW1}" | ansible-vault encrypt_string \
    --vault-password-file "${VAULT_PASS_FILE}" \
    --stdin-name password > "${WORK_DIR}/enc.yml"

# 2. 暗号文だけを取り出す(ヘッダ行 `password: !vault |` を除く)
python3 - "${WORK_DIR}/enc.yml" "${WORK_DIR}/cipher.txt" <<'EOF'
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
if not lines or lines[0].strip() != "password: !vault |":
    sys.exit("encrypt_string の出力形式が想定と異なります")
body = [l.strip() for l in lines[1:] if l.strip()]
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(body) + "\n")
EOF

# 3. 暗号文を復号し、入力したパスワードと一致することを確認する
DECRYPTED="$(ansible-vault decrypt \
    --vault-password-file "${VAULT_PASS_FILE}" \
    --output=- "${WORK_DIR}/cipher.txt" 2>/dev/null)" || die "暗号文の復号に失敗しました"
[ "${DECRYPTED}" = "${PW1}" ] || die "暗号文の復号結果が入力値と一致しません"
unset PW1 DECRYPTED

# 4. provisioning_user.password の行を暗号文ブロックに置き換えた内容を作る
python3 - "${TARGET}" "${WORK_DIR}/cipher.txt" "${NEW_FILE}" <<'EOF'
import re
import sys

target, cipher_path, out_path = sys.argv[1:4]
lines = open(target, encoding="utf-8").read().splitlines(keepends=True)
cipher = [l.rstrip("\n") for l in open(cipher_path, encoding="utf-8") if l.strip()]


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


# トップレベルの provisioning_user: ブロックの範囲
start = next((i for i, l in enumerate(lines) if l.rstrip("\n") == "provisioning_user:"), None)
if start is None:
    sys.exit("provisioning_user: が見つかりません")
end = next(
    (i for i in range(start + 1, len(lines)) if lines[i].strip() and indent_of(lines[i]) == 0),
    len(lines),
)

# provisioning_user の直下(インデント2)にある password: の行
pw = None
for i in range(start + 1, end):
    m = re.match(r"^( +)password:", lines[i])
    if m and len(m.group(1)) == 2:
        pw = i
        break
if pw is None:
    sys.exit("provisioning_user.password が見つかりません")

indent = " " * indent_of(lines[pw])
# 既存の値の終端: 同じか浅いインデントの行(または空行)まで
stop = pw + 1
while stop < len(lines) and lines[stop].strip() and indent_of(lines[stop]) > len(indent):
    stop += 1

block = [f"{indent}password: !vault |\n"] + [f"{indent}  {c}\n" for c in cipher]
lines[pw:stop] = block
open(out_path, "w", encoding="utf-8").write("".join(lines))
print(f"置き換え: {target} の {pw + 1} 行目から {stop} 行目まで")
EOF

# 5. 差し替えと構文チェック
chmod --reference="${TARGET}" "${NEW_FILE}"
mv "${NEW_FILE}" "${TARGET}"

if command -v ansible-playbook >/dev/null 2>&1; then
    # 警告(非推奨の通知など)は表示しない。失敗したときだけログを出す
    if ! ansible-playbook --syntax-check -i inventory/hosts.yml provisioning.yml \
        > "${WORK_DIR}/syntax.log" 2>&1; then
        cat "${WORK_DIR}/syntax.log" >&2
        die "構文チェックに失敗しました(${TARGET} は更新済みです。内容を確認してください)"
    fi
    echo "構文チェック: OK"
fi

echo "完了: provisioning_user.password を新しい値で暗号化して設定しました。"
