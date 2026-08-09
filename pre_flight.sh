#!/bin/bash
set -eu

# -----------------------------------------------------------------------------
# GCP 共通プロビジョニング ＆ 事前チェック スクリプト
# -----------------------------------------------------------------------------

# 第1引数 ($1) または環境変数からの柔軟な値取得
INPUT_ARG="${1:-}"
KEYWORD="${KEYWORD:-abcde}"
APP_PREFIX="${APP_PREFIX:-qm-app}"

# 第1引数が数字（例: 170, 171）なら ARTICLE_ID、プロジェクトID文字列なら PROJECT_ID として自動判定
if [ -n "${INPUT_ARG}" ]; then
    if [[ "${INPUT_ARG}" =~ ^[0-9]+$ ]]; then
        ARTICLE_ID="${INPUT_ARG}"
    else
        PROJECT_ID="${INPUT_ARG}"
    fi
fi

# 現在のgcloudアクティブプロジェクトの自動取得
CURRENT_PROJECT="$(gcloud config get-value project </dev/null 2>/dev/null || echo "")"

# プロジェクトIDの決定優先順位:
# 1. 指定された PROJECT_ID
# 2. 引数/変数で決定された ARTICLE_ID に基づくプロジェクト名 (qm-app-abcde-170 など)
# 3. 現在の gcloud アクティブプロジェクト CURRENT_PROJECT
# 4. デフォルト (qm-app-abcde-170)
if [ -n "${PROJECT_ID:-}" ]; then
    RESOLVED_PROJECT_ID="${PROJECT_ID}"
elif [ -n "${ARTICLE_ID:-}" ]; then
    PROJECT_PREFIX=$(echo "${APP_PREFIX}-${KEYWORD}-${ARTICLE_ID}" | tr '[:upper:]' '[:lower:]')
    RESOLVED_PROJECT_ID="${PROJECT_PREFIX}"
elif [ -n "${CURRENT_PROJECT}" ] && [ "${CURRENT_PROJECT}" != "(unset)" ]; then
    RESOLVED_PROJECT_ID="${CURRENT_PROJECT}"
else
    ARTICLE_ID="170"
    PROJECT_PREFIX=$(echo "${APP_PREFIX}-${KEYWORD}-${ARTICLE_ID}" | tr '[:upper:]' '[:lower:]')
    RESOLVED_PROJECT_ID="${PROJECT_PREFIX}"
fi

PROJECT_ID="${RESOLVED_PROJECT_ID}"
PROJECT_NAME="${PROJECT_NAME:-GCP App - ${PROJECT_ID}}"

echo ""
echo "----------------------------------------"
echo "📌 使用予定プロジェクトID: ${PROJECT_ID}"
echo "----------------------------------------"
echo ""

# プロジェクトの存在チェック ＆ 作成・確定
if ! gcloud projects describe "${PROJECT_ID}" </dev/null >/dev/null 2>&1; then
    echo "⚡ 新規プロジェクトを作成しています: ${PROJECT_ID}"
    gcloud projects create "${PROJECT_ID}" --name="${PROJECT_NAME}" --quiet </dev/null || true
else
    echo "ℹ️ 既存のプロジェクトを使用します: ${PROJECT_ID}"
fi

gcloud config set project "${PROJECT_ID}" --quiet </dev/null >/dev/null 2>&1

echo ""
echo "----------------------------------------"
echo "🔍 0. 利用可能な有効請求先アカウント一覧"
echo "----------------------------------------"
gcloud billing accounts list --filter="open=true" --quiet </dev/null 2>/dev/null || true

BILLING_ACCOUNT=$(gcloud billing accounts list --filter="open=true AND displayName ~ '${KEYWORD}'" --format="value(name)" --limit=1 --quiet </dev/null 2>/dev/null || true)
if [ -z "${BILLING_ACCOUNT}" ]; then
    BILLING_ACCOUNT=$(gcloud billing accounts list --filter="open=true" --format="value(name)" --limit=1 --quiet </dev/null 2>/dev/null || true)
fi

BILLING_ACCOUNT_NAME=""
if [ -n "${BILLING_ACCOUNT}" ]; then
    BILLING_ACCOUNT_NAME=$(gcloud billing accounts list --filter="name:${BILLING_ACCOUNT}" --format="value(displayName)" --limit=1 --quiet </dev/null 2>/dev/null || true)
fi

echo ""
echo "----------------------------------------"
echo "📌 自動検出された請求先アカウント: ${BILLING_ACCOUNT} (${BILLING_ACCOUNT_NAME})"
echo "----------------------------------------"
echo ""

echo "----------------------------------------"
echo "🔍 1. 現在のアクティブプロジェクト確認"
echo "----------------------------------------"
gcloud config get-value project </dev/null

echo ""
echo "----------------------------------------"
echo "🔍 2. 課金状態の確認（Link前）"
echo "----------------------------------------"
RAW_ENABLED="$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" </dev/null 2>/dev/null || echo "false")"
IS_ENABLED="$(echo "${RAW_ENABLED}" | tr '[:upper:]' '[:lower:]')"

if [ "${IS_ENABLED}" = "true" ]; then
    echo "🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨"
    echo "⚠️  【警告】すでに課金アカウントがリンクされています！(billingEnabled: True)"
    echo "    ※想定: 本来は0円休眠状態 (False) から事前準備を行う流れです。"
    echo "    ※連続実行、または前回のハンズオンクリーンアップ未完了の可能性があります。"
    echo "🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨"
else
    echo "✅ 課金状態: 未リンク（False） - 【想定通り】現在課金は紐付けられていません（安全な休眠状態）"
fi

echo ""
echo "----------------------------------------"
echo "🔍 3. 有効なAPIの安全・分類チェック"
echo "----------------------------------------"
echo "📌 [期待される標準・無料基盤構成]:"
echo "  - ✅ 基本システムAPI: Billing, Resource Manager, Service Usage, IAM, Cloud Logging (完全無料)"
echo "  - ℹ️ Webコンソール自動アシスト: Gemini for Google Cloud / Gemini Cloud Assist (完全無料)"
echo ""
echo "📌 [現在有効なAPI一覧（分類表示）]:"
ACTUAL_APIS="$(gcloud services list --enabled --project="${PROJECT_ID}" --format="value(config.name)" </dev/null 2>/dev/null || echo "")"

PAID_RESOURCE_APIS=()
if [ -n "${ACTUAL_APIS}" ]; then
    while read -r api; do
        [ -z "${api}" ] && continue
        case "${api}" in
            cloudbilling.googleapis.com|cloudresourcemanager.googleapis.com|serviceusage.googleapis.com|iam.googleapis.com|iamcredentials.googleapis.com|logging.googleapis.com)
                echo "  ✅ [基本無料機能] ${api}"
                ;;
            cloudaicompanion.googleapis.com|geminicloudassist.googleapis.com)
                echo "  ℹ️ [画面操作で自動ON・無料] ${api}"
                ;;
            *)
                echo "  ⚠️ [有料/リソース拡張API] ${api}"
                PAID_RESOURCE_APIS+=("${api}")
                ;;
        esac
    done <<< "${ACTUAL_APIS}"
fi

echo ""
if [ ${#PAID_RESOURCE_APIS[@]} -eq 0 ]; then
    echo "✅ 【完全安全】有料リソース（DBやコンテナ等）の拡張APIは1つもありません！"
    echo "   安心してお進みいただけます。（完全な0円休眠状態からの復帰です）"
else
    echo "⚠️ 【確認】以下の有料/リソース拡張APIが残存しています: ${PAID_RESOURCE_APIS[*]}"
fi

echo ""
echo "----------------------------------------"
echo "⚡ 4. 請求先アカウントの有効化（Link）"
echo "----------------------------------------"
if [ -n "${BILLING_ACCOUNT}" ]; then
    gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}" --quiet </dev/null 2>/dev/null || true
    echo "🔄 紐付け処理の反映を待っています (2秒)..."
    sleep 2
else
    echo "❌ 有効な請求先アカウントが検出されませんでした。"
fi

echo ""
echo "----------------------------------------"
echo "🔍 5. 課金状態の最終確認（Link後）"
echo "----------------------------------------"
RAW_AFTER="$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" </dev/null 2>/dev/null || echo "false")"
AFTER_ENABLED="$(echo "${RAW_AFTER}" | tr '[:upper:]' '[:lower:]')"

if [ "${AFTER_ENABLED}" = "true" ]; then
    echo "✅ 課金状態: リンク完了（True） - 【成功】課金アカウントが正しく有効化されました！"
else
    echo "❌ 課金状態: 未リンク（False） - 課金アカウントの有効化に失敗したか保留中です"
fi

echo ""
echo "========================================================"
echo "🚀 事前準備 ＆ 課金ON（起爆）が完了しました！ハンズオンを開始できます。"
echo "========================================================"
