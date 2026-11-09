#!/usr/bin/env bash
# ノードを電源オフ(または -r で再起動)する。ノード名を指定するか、all(既定のグループ)を指定する。
#
# 使い方:
#   scripts/shutdown-nodes.sh [-g グループ名] [-d 分] [-r] [-n] [-y] <ノード名 | all>
#     -g グループ名  all の対象にするグループ(省略時は DEFAULT_ALL_GROUP)
#     -d 分          指定した分数の後に実行する(省略時は即時)
#     -r             電源オフではなく再起動する(ノードが SSH で戻るまで待つ)
#     -n             実行せず、対象ノードの一覧だけ表示する(dry-run)
#     -y             確認プロンプトを省略する
#
# 例:
#   scripts/shutdown-nodes.sh <ノード名>      # 1 台を即時電源オフ
#   scripts/shutdown-nodes.sh -d 10 all       # 既定のグループ全体を 10 分後に電源オフ
#   scripts/shutdown-nodes.sh -r <ノード名>   # 1 台を再起動し、復帰を待つ
#   scripts/shutdown-nodes.sh -n all          # 対象一覧の確認だけ
#
# プロジェクトに合わせて、下の DEFAULT_ALL_GROUP を変える。

set -euo pipefail

# プロジェクトごとに変える設定
DEFAULT_ALL_GROUP="all"   # all を指定したときの対象グループ(例: cluster_members に変える)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
cd "${REPO_ROOT}"

ANSIBLE_BIN="${REPO_ROOT}/.venv/bin"
INVENTORY="inventory/hosts.yml"
PROVISIONING_VARS="@inventory/provisioning.yml"
VAULT_FILE="./.vault_password"

DELAY_MIN=0
DRY_RUN=false
REBOOT=false
ASSUME_YES=false

if [[ ! -x "${ANSIBLE_BIN}/ansible" ]]; then
  echo "エラー: ${ANSIBLE_BIN}/ansible が見つかりません(mise run install を実行してください)" >&2
  exit 1
fi

ALL_GROUP="${DEFAULT_ALL_GROUP}"

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print} /^set /{exit}' "$0"
}

# オプションはノード名の前後どちらに置いてもよい
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d)
      if [[ $# -lt 2 ]]; then usage; exit 2; fi
      DELAY_MIN="$2"
      shift 2
      ;;
    -g)
      if [[ $# -lt 2 ]]; then usage; exit 2; fi
      ALL_GROUP="$2"
      shift 2
      ;;
    -r) REBOOT=true; shift ;;
    -n) DRY_RUN=true; shift ;;
    -y) ASSUME_YES=true; shift ;;
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

if ! [[ "${DELAY_MIN}" =~ ^[0-9]+$ ]]; then
  echo "エラー: -d には 0 以上の整数(分)を指定してください: ${DELAY_MIN}" >&2
  exit 2
fi

# all は既定のグループ(または -g で指定したグループ)を指す
if [[ "${TARGET}" == "all" ]]; then
  PATTERN="${ALL_GROUP}"
else
  PATTERN="${TARGET}"
fi

ANSIBLE_ARGS=(-i "${INVENTORY}" --extra-vars="${PROVISIONING_VARS}" --vault-password-file "${VAULT_FILE}")

# 対象ホストを解決する(存在しないノード名はここで止める)
HOSTS=$("${ANSIBLE_BIN}/ansible" "${PATTERN}" "${ANSIBLE_ARGS[@]}" --list-hosts 2>/dev/null \
  | awk 'NR>1 {gsub(/^ +/, ""); print}' || true)
if [[ -z "${HOSTS}" ]]; then
  echo "エラー: 対象ノードが見つかりません: ${TARGET}" >&2
  exit 1
fi

if [[ "${DELAY_MIN}" -eq 0 ]]; then
  WHEN="即時"
else
  WHEN="${DELAY_MIN} 分後"
fi

echo "対象: ${TARGET}(${PATTERN})"
echo "ホスト:"
printf '  - %s\n' ${HOSTS}
if "${REBOOT}"; then ACTION="再起動"; else ACTION="電源オフ"; fi
echo "${ACTION}: ${WHEN}"

if "${DRY_RUN}"; then
  echo "(dry-run のため、実行しません)"
  exit 0
fi

if ! "${ASSUME_YES}"; then
  read -r -p "本当に${ACTION}しますか?(yes と入力): " answer
  if [[ "${answer}" != "yes" ]]; then
    echo "中止しました。"
    exit 1
  fi
fi

DELAY_SEC=$((DELAY_MIN * 60))
if "${REBOOT}"; then
  # reboot モジュールは、ノードが SSH で戻るまで待つ(最大 15 分)
  "${ANSIBLE_BIN}/ansible" "${PATTERN}" "${ANSIBLE_ARGS[@]}" \
    -b -m ansible.builtin.reboot \
    -a "pre_reboot_delay=${DELAY_SEC} reboot_timeout=900 msg=reboot-by-ansible"
else
  "${ANSIBLE_BIN}/ansible" "${PATTERN}" "${ANSIBLE_ARGS[@]}" \
    -b -m community.general.shutdown \
    -a "delay=${DELAY_SEC} msg=shutdown-by-ansible"
fi
