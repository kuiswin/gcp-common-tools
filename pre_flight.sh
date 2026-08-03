#!/bin/bash
set -eu

# -----------------------------------------------------------------------------
# GCP 共通プロビジョニング ＆ 事前チェック スクリプト
# -----------------------------------------------------------------------------

KEYWORD="${KEYWORD:-abcde}"
APP_PREFIX="${APP_PREFIX:-qm-app}"
ARTICLE_ID="${ARTICLE_ID:-171}"
PROJECT_NAME="${PROJECT_NAME:-PubSub Pipeline - ${KEYWORD}}"

# プロジェクトIDの自動組み立て（外部指定 PROJECT_ID があれば優先）
PROJECT_PREFIX=$(echo "${APP_PREFIX}-${KEYWORD}-${ARTICLE_ID}" | tr '[:upper:]' '[:lower:]')
PROJECT_ID="${PROJECT_ID:-${PROJECT_PREFIX}}"

echo ""
echo "----------------------------------------"
echo "📌 使用予定プロジェクトID: ${PROJECT_ID}"
echo "----------------------------------------"
echo ""

# プロジェクトの存在チェック ＆ 作成・確定
if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
    echo "⚡ 新規プロジェクトを作成しています: ${PROJECT_ID}"
    gcloud projects create "${PROJECT_ID}" --name="${PROJECT_NAME}" --quiet || true
else
    echo "ℹ️ 既存のプロジェクトを使用します: ${PROJECT_ID}"
fi

gcloud config set project "${PROJECT_ID}" --quiet >/dev/null 2>&1

echo ""
echo "----------------------------------------"
echo "🔍 0. 利用可能な有効請求先アカウント一覧"
echo "----------------------------------------"
echo "y" | gcloud beta billing accounts list --filter="open=true" || true

BILLING_ACCOUNT=$(echo "y" | gcloud beta billing accounts list --filter="open=true AND displayName ~ '${KEYWORD}'" --format="value(name)" 2>/dev/null | head -n 1 || true)
if [ -z "${BILLING_ACCOUNT}" ]; then
    BILLING_ACCOUNT=$(echo "y" | gcloud beta billing accounts list --filter="open=true" --format="value(name)" 2>/dev/null | head -n 1 || true)
fi

BILLING_ACCOUNT_NAME=""
if [ -n "${BILLING_ACCOUNT}" ]; then
    BILLING_ACCOUNT_NAME=$(echo "y" | gcloud beta billing accounts list --filter="name:${BILLING_ACCOUNT}" --format="value(displayName)" 2>/dev/null || true)
fi

echo ""
echo "----------------------------------------"
echo "📌 自動検出された請求先アカウント: ${BILLING_ACCOUNT} (${BILLING_ACCOUNT_NAME})"
echo "----------------------------------------"
echo ""

echo "----------------------------------------"
echo "🔍 1. 現在のアクティブプロジェクト確認"
echo "----------------------------------------"
gcloud config get-value project

echo ""
echo "----------------------------------------"
echo "🔍 2. 課金状態の確認（Link前）"
echo "----------------------------------------"
RAW_IS_ENABLED=$(gcloud beta billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" 2>/dev/null || echo "false")
IS_ENABLED=$(echo "${RAW_IS_ENABLED}" | tr '[:upper:]' '[:lower:]')

if [ "${IS_ENABLED}" = "true" ]; then
    echo "ℹ️ 課金状態: リンク済み（True）"
else
    echo "✅ 課金状態: 未リンク（False） - 【想定通り】現在課金は紐付けられていません（安全）"
fi

echo ""
echo "----------------------------------------"
echo "🔍 3. 有効なAPIサービス一覧の確認（プロビジョニング前）"
echo "----------------------------------------"
gcloud services list --enabled --project="${PROJECT_ID}" || true

echo ""
echo "----------------------------------------"
echo "🔍 4. プロジェクト内リソースの目視確認（プロビジョニング前）"
echo "----------------------------------------"
echo "y" | gcloud asset search-all-resources --scope="projects/${PROJECT_ID}" --query="NOT name:serviceusage AND NOT name:logging AND NOT name:cloudresourcemanager AND NOT name:cloudbilling" --format="table(name, assetType)" 2>/dev/null || echo "リソースなし"

echo ""
echo "----------------------------------------"
echo "⚡ 5. 課金アカウントの有効化（Link）"
echo "----------------------------------------"
if [ -n "${BILLING_ACCOUNT}" ]; then
    gcloud beta billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}" --quiet || true
else
    echo "⚠️ 有効な請求先アカウントが見つかりませんでした。"
fi

sleep 2

echo ""
echo "----------------------------------------"
echo "🔍 6. 課金状態の確認（Link後）"
echo "----------------------------------------"
RAW_AFTER=$(gcloud beta billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" 2>/dev/null || echo "false")
IS_ENABLED_AFTER=$(echo "${RAW_AFTER}" | tr '[:upper:]' '[:lower:]')

if [ "${IS_ENABLED_AFTER}" = "true" ]; then
    echo "✅ 課金状態: リンク完了（True） - 【成功】課金アカウントが正しく有効化されました！"
else
    echo "⚠️ 課金状態: 未リンク（False） - 請求先アカウントの紐付けを確認してください。"
fi
echo ""
