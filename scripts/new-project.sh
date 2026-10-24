#!/usr/bin/env bash
# テンプレートから新しいプロジェクトを作成する。
#
# 使い方: ./scripts/new-project.sh <プロジェクト名> [作成先の親ディレクトリ]
#   作成先の親ディレクトリ省略時はカレントディレクトリ直下に作成する。
#
# テンプレートを clone し、履歴を消して新規 git リポジトリとして初期化する。
# テンプレートの取得元は環境変数 TEMPLATE_REPO_URL で変更できる。

set -euo pipefail

TEMPLATE_REPO_URL="${TEMPLATE_REPO_URL:-https://github.com/hiracchi/ansible-template.git}"

usage() {
    echo "使い方: $0 <プロジェクト名> [作成先の親ディレクトリ]" >&2
    exit 1
}

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
fi

PROJECT_NAME="$1"
PARENT_DIR="${2:-.}"

# プロジェクト名はディレクトリ名として使うため、英数字・ハイフン・アンダースコア・ドットに限定する
if ! [[ "${PROJECT_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "エラー: プロジェクト名には英数字・ハイフン・アンダースコア・ドットのみ使用できます: ${PROJECT_NAME}" >&2
    exit 1
fi

if [ ! -d "${PARENT_DIR}" ]; then
    echo "エラー: 作成先の親ディレクトリが存在しません: ${PARENT_DIR}" >&2
    exit 1
fi

TARGET_DIR="$(cd "${PARENT_DIR}" && pwd)/${PROJECT_NAME}"

if [ -e "${TARGET_DIR}" ]; then
    echo "エラー: 既に存在するため作成できません: ${TARGET_DIR}" >&2
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "エラー: git が見つかりません。インストールしてから再実行してください。" >&2
    exit 1
fi

# 途中で失敗した場合は作成途中のディレクトリを削除する
CLONED=0
cleanup() {
    if [ "${CLONED}" -eq 0 ] && [ -d "${TARGET_DIR}" ]; then
        rm -rf "${TARGET_DIR}"
    fi
}
trap cleanup EXIT

echo "テンプレートを取得しています: ${TEMPLATE_REPO_URL}"
git clone --quiet --depth 1 "${TEMPLATE_REPO_URL}" "${TARGET_DIR}"
CLONED=1

# テンプレートの履歴は引き継がず、新しいプロジェクトとして初期化する
rm -rf "${TARGET_DIR}/.git"
git -C "${TARGET_DIR}" init --quiet -b main

echo
echo "プロジェクトを作成しました: ${TARGET_DIR}"
echo
echo "次の手順:"
echo "  cd \"${TARGET_DIR}\""
echo "  mise install          # Python を取得する"
echo "  mise run install      # 依存関係と Ansible Collection をインストールする"
echo "  (inventory/hosts.yml, group_vars/all.yml などを環境に合わせて編集してください)"
