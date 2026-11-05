#!/usr/bin/env bash
# ノードの健康状態を読み取り専用で検査する。ノード名を指定するか、all(既定のグループ)を指定する。
#
# 使い方:
#   scripts/node-health.sh [-g グループ名] [--crash-checks | --no-crash-checks] <ノード名 | all>
#     -g グループ名       all の対象にするグループ(省略時は DEFAULT_ALL_GROUP)
#     --crash-checks      panic 系 sysctl の期待値も検査する
#     --no-crash-checks   上の検査を行わない(省略時は DEFAULT_CRASH_CHECKS に従う)
#
# 例:
#   scripts/node-health.sh <ノード名>      # 1 台を検査
#   scripts/node-health.sh all             # 既定のグループ全体を検査
#
# プロジェクトに合わせて、下の DEFAULT_ALL_GROUP と DEFAULT_CRASH_CHECKS を変える。
# 検査内容は scripts/node-health-remote.sh を参照。設定は変更しない。

set -euo pipefail

# プロジェクトごとに変える設定
DEFAULT_ALL_GROUP="all"   # all を指定したときの対象グループ(例: cluster_members に変える)
DEFAULT_CRASH_CHECKS=0                # 1 にすると、既定で panic 系 sysctl も検査する

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
cd "${REPO_ROOT}"

ANSIBLE="${REPO_ROOT}/.venv/bin/ansible"
REMOTE_SCRIPT="scripts/node-health-remote.sh"
ANSIBLE_ARGS=(-i inventory/hosts.yml --extra-vars="@inventory/provisioning.yml" --vault-password-file ./.vault_password)

if [[ ! -x "${ANSIBLE}" ]]; then
  echo "エラー: ${ANSIBLE} が見つかりません(mise run install を実行してください)" >&2
  exit 1
fi

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print} /^set /{exit}' "$0"
}

ALL_GROUP="${DEFAULT_ALL_GROUP}"
CRASH_CHECKS="${DEFAULT_CRASH_CHECKS}"
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -g)
      if [[ $# -lt 2 ]]; then usage; exit 2; fi
      ALL_GROUP="$2"
      shift 2
      ;;
    --crash-checks) CRASH_CHECKS=1; shift ;;
    --no-crash-checks) CRASH_CHECKS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "エラー: 不明なオプションです: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -n "${TARGET}" ]]; then
        echo "エラー: ノード名は 1 つだけ指定してください" >&2
        usage
        exit 2
      fi
      TARGET="$1"
      shift
      ;;
  esac
done

if [[ -z "${TARGET}" ]]; then
  usage
  exit 2
fi

# all は既定のグループ(または -g で指定したグループ)を指す
if [[ "${TARGET}" == "all" ]]; then
  PATTERN="${ALL_GROUP}"
else
  PATTERN="${TARGET}"
fi

REMOTE_ARGS=""
if [[ "${CRASH_CHECKS}" -eq 1 ]]; then
  REMOTE_ARGS=" --crash-checks"
fi

HOSTS=$("${ANSIBLE}" "${PATTERN}" "${ANSIBLE_ARGS[@]}" --list-hosts 2>/dev/null \
  | awk 'NR>1 {gsub(/^ +/, ""); print}' || true)
if [[ -z "${HOSTS}" ]]; then
  echo "エラー: 対象ノードが見つかりません: ${TARGET}" >&2
  exit 1
fi

# ノードごとの結果を受け取り、整形して表示する(接続できなかったノードも表示する)
RAW=$("${ANSIBLE}" "${PATTERN}" "${ANSIBLE_ARGS[@]}" -b \
  -m ansible.builtin.script -a "${REMOTE_SCRIPT}${REMOTE_ARGS}" 2>/dev/null || true)
printf '%s\n' "${RAW}" | python3 -c '
import json, re, sys
raw = sys.stdin.read()
# 各ホストの出力は「ホスト名 | 状態 => {JSON}」の形式で並ぶ
heads = list(re.finditer(r"^(\S+) \| (\w[\w!]*) => ", raw, re.M))
if not heads:
    print("エラー: 検査結果を取得できませんでした")
    sys.exit(0)
for i, h in enumerate(heads):
    end = heads[i + 1].start() if i + 1 < len(heads) else len(raw)
    body = raw[h.end():end].strip()
    print(f"== {h.group(1)} ({h.group(2)}) ==")
    try:
        res = json.loads(body)
    except ValueError:
        print("  接続・実行に失敗: " + body[:200].replace("\n", " "))
        print()
        continue
    if res.get("stdout_lines"):
        for line in res["stdout_lines"]:
            line = line.strip().replace("\t", " ")
            if line:
                print("  " + line)
    else:
        print("  接続・実行に失敗: " + str(res.get("msg", "不明"))[:200])
    print()
'

echo
echo "凡例: OK=問題なし  WARN=要確認  NG=問題あり  SKIP=検査不可  INFO=参考情報(判定には使わない)"
