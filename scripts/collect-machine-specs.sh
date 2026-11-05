#!/bin/bash

# ホストのスペックを読み取り専用で収集し、Markdown の一覧表を出力するスクリプト
# 役割（グループ）は inventory/hosts.yml から取得する。sudo は使わない。
# 使い方:
#   ./scripts/collect-machine-specs.sh                         # inventory の全ホストを docs/hosts/machine-specs.md に出力
#   ./scripts/collect-machine-specs.sh -o -                    # 標準出力に出す
#   ./scripts/collect-machine-specs.sh -o out.md <ホスト名>     # 対象とパスを指定する
#   ./scripts/collect-machine-specs.sh -x <ホスト名>            # 対象から除外する(複数回指定できる)
# 対象の既定は、inventory のホストから DEFAULT_EXCLUDE_HOSTS を除いたもの。
# 接続は ~/.ssh/config の Host 名で行う(BatchMode のため鍵認証が必要)。
# プロジェクトに合わせて、下の DOC_TITLE と DEFAULT_EXCLUDE_HOSTS を変える。

# プロジェクトごとに変える設定
DOC_TITLE="プロジェクト"                   # 出力する表の見出しに使う名前
DEFAULT_EXCLUDE_HOSTS=""                 # 既定で対象から外すホスト(空白区切り)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_PATH="${ANSIBLE_DIR}/docs/hosts/machine-specs.md"
EXCLUDE_HOSTS="${DEFAULT_EXCLUDE_HOSTS}"

while getopts "o:x:h" opt; do
    case $opt in
        o) OUT_PATH="$OPTARG" ;;
        x) EXCLUDE_HOSTS="${EXCLUDE_HOSTS} ${OPTARG}" ;;
        *) echo "Usage: $0 [-o <path>|-] [-x <hostname>] [<hostname> ...]"; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
ARG_HOSTS="$*"

# ホストごとに実行する読み取り専用の収集処理。結果は「|」区切り 1 行で返す
REMOTE_COLLECT=$(cat <<'REMOTE'
. /etc/os-release 2>/dev/null
os="${PRETTY_NAME:-unknown}"
kernel=$(uname -r)
cpu=""
sockets=""
cps=""
if command -v lscpu >/dev/null 2>&1; then
    cpu=$(lscpu | awk -F: '/^Model name/{sub(/^ +/,"",$2); print $2; exit}')
    sockets=$(lscpu | awk -F: '/^Socket\(s\)/{gsub(/ /,"",$2); print $2}')
    cps=$(lscpu | awk -F: '/^Core\(s\) per socket/{gsub(/ /,"",$2); print $2}')
fi
if [ -z "$cpu" ]; then
    cpu=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')
fi
logical=$(nproc)
if [ -n "$sockets" ] && [ "$sockets" -gt 1 ] 2>/dev/null; then
    cores="${logical} (${sockets} ソケット × ${cps} コア)"
else
    cores="${logical}"
fi
mem=$(free -h | awk '/^Mem:/{print $2}')
disk=$(lsblk -dn -o SIZE,MODEL,TYPE 2>/dev/null | awk '$NF=="disk"{ $NF=""; sub(/ +$/,""); printf "%s; ", $0 }' | sed 's/; $//')
gpu=$(lspci 2>/dev/null | grep -iE 'vga|3d controller|display' | sed 's/^[^ ]* [^:]*: //' | paste -sd ';' | sed 's/;/; /g')
if command -v nvidia-smi >/dev/null 2>&1; then
    gpu="${gpu}; NVIDIA driver: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | paste -sd ';' | sed 's/;/, /g')"
else
    gpu="${gpu}; nvidia-smi 未導入"
fi
echo "${os}|${kernel}|${cpu}|${cores}|${mem}|${disk}|${gpu}"
REMOTE
)

# inventory からホストごとの所属グループを取得する (children を含む)
VAULT_OPTION=""
if [ -f "${ANSIBLE_DIR}/.vault_password" ]; then
    VAULT_OPTION="--vault-password-file ${ANSIBLE_DIR}/.vault_password"
fi
GROUPS_JSON=$(cd "$ANSIBLE_DIR" && ansible-inventory -i inventory/hosts.yml $VAULT_OPTION --list 2>/dev/null)

# 対象ホスト: 引数があればそれ、無ければ inventory の全ホストから除外対象を引いたもの
if [ -n "$ARG_HOSTS" ]; then
    HOSTS="$ARG_HOSTS"
else
    HOSTS=$(python3 -c '
import json, sys
inv = json.load(sys.stdin)
exclude = set(sys.argv[1].split())
hosts = sorted(h for h in inv.get("_meta", {}).get("hostvars", {}) if h not in exclude)
print(" ".join(hosts))
' "$EXCLUDE_HOSTS" <<<"$GROUPS_JSON")
fi
if [ -z "$HOSTS" ]; then
    echo "対象ホストが見つかりません" >&2
    exit 1
fi

host_roles() {
    python3 -c '
import json, sys
inv = json.load(sys.stdin)
host = sys.argv[1]
def members(group, seen):
    g = inv.get(group, {})
    found = set(g.get("hosts", []))
    for child in g.get("children", []):
        if child not in seen:
            seen.add(child)
            found |= members(child, seen)
    return found
skip = {"all", "ungrouped", "_meta"}
roles = sorted(
    name for name in inv
    if name not in skip and host in members(name, {name})
)
print(", ".join(roles) if roles else "-")
' "$1" <<<"$GROUPS_JSON"
}

ROWS=""
for host in $HOSTS; do
    roles=$(host_roles "$host")
    if result=$(timeout 60 ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" 'bash -s' 2>/dev/null <<<"$REMOTE_COLLECT"); then
        IFS='|' read -r os kernel cpu cores mem disk gpu <<<"$result"
    else
        os="取得失敗"; kernel="-"; cpu="-"; cores="-"; mem="-"; disk="-"; gpu="-"
    fi
    ROWS+="| ${host} | ${roles} | ${os} | ${kernel} | ${cpu} | ${cores} | ${mem} | ${disk} | ${gpu} |"$'\n'
done

MARKDOWN=$(
    echo "# ${DOC_TITLE} 機器スペック一覧"
    echo
    echo "取得日: $(date +%Y-%m-%d)（読み取り専用で各ホストに接続して収集）"
    echo
    echo "| ホスト | 役割（inventory グループ） | OS | カーネル | CPU | コア / スレッド | メモリ | ディスク | GPU |"
    echo "| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |"
    printf "%s" "$ROWS"
)

if [ "$OUT_PATH" = "-" ]; then
    printf "%s\n" "$MARKDOWN"
else
    mkdir -p "$(dirname "$OUT_PATH")"
    printf "%s\n" "$MARKDOWN" > "$OUT_PATH"
    echo "wrote: $OUT_PATH"
fi
