#!/bin/bash
set -eu

# -----------------------------------------------------------------------------
# GCP 全サービス一括クリーンアップ ＆ 休眠（課金解除）データ駆動型スクリプト
# -----------------------------------------------------------------------------

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project </dev/null 2>/dev/null || echo "")}"

if [ -z "${PROJECT_ID}" ]; then
    echo "❌ PROJECT_ID が指定されておらず、アクティブなプロジェクトも確認できません。"
    exit 1
fi

echo ""
echo "========================================================"
echo "🧹 GCP リソース全自動お掃除 ＆ 休眠化チェックスタート"
echo "   対象プロジェクトID: ${PROJECT_ID}"
echo "========================================================"
echo ""

# -----------------------------------------------------------------------------
# 1. 走査・お掃除対象サービス一覧の定義 (データリスト)
# -----------------------------------------------------------------------------
RESOURCE_TARGETS=(
    "Cloud Run (サービス / ジョブ)"
    "Pub/Sub (トピック / サブスクリプション)"
    "Cloud Storage (GCS バケット)"
    "Cloud Spanner (データベースインスタンス)"
    "AlloyDB (データベースクラスター)"
    "Cloud Bigtable (NoSQLデータベースインスタンス)"
    "Artifact Registry (コンテナリポジトリ)"
    "Secret Manager (シークレット・機密情報)"
    "Vertex AI (Gemini / 機械学習常駐エンドポイント)"
    "IAM (専用サービスアカウント)"
)

# -----------------------------------------------------------------------------
# 2. 汎用チェック ＆ クリーンアップ関数 (モジュール化)
# -----------------------------------------------------------------------------
cleanup_resource() {
    local idx="$1"
    local total="$2"
    local title="$3"
    local list_cmd="$4"
    local del_cmd_prefix="$5"
    local del_cmd_suffix="${6:-}"
    local label_name="$7"

    echo "🔎 【${idx}/${total}】${title} のチェックを行っています..."
    local items
    items="$(eval "${list_cmd}" </dev/null 2>/dev/null || echo "")"

    if [ -n "${items}" ]; then
        echo "⚠️ 以下の残存リソースを検出しました:"
        for item in ${items}; do
            echo "   👉 ${label_name}: ${item}"
        done
        echo "🗑️ 削除処理を実行します..."
        for item in ${items}; do
            eval "${del_cmd_prefix} \"${item}\" ${del_cmd_suffix}" </dev/null 2>/dev/null || true
        done
        echo "🔄 削除後の再確認を行っています..."
        local check_items
        check_items="$(eval "${list_cmd}" </dev/null 2>/dev/null || echo "")"
        if [ -z "${check_items}" ]; then
            echo "✅ 削除完了を確認しました！（${label_name}: 0件）"
        fi
    else
        echo "ℹ️ ${label_name} は検出されませんでした（すでにクリーンです）"
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# STEP 1: 個別サービス・リソースの存在チェック ＆ 削除 ＆ 再確認
# -----------------------------------------------------------------------------
echo "--------------------------------------------------------"
echo "🔍 1. 個別サービス・リソースのチェック ＆ 削除"
echo "--------------------------------------------------------"
echo "📌 本プログラムの走査・お掃除対象サービス一覧 (${#RESOURCE_TARGETS[@]}項目):"
for i in "${!RESOURCE_TARGETS[@]}"; do
    echo "   $((i+1)). ${RESOURCE_TARGETS[$i]}"
done
echo "--------------------------------------------------------"
echo ""

TOTAL=${#RESOURCE_TARGETS[@]}

# 1-1. Cloud Run
cleanup_resource "1" "${TOTAL}" "Cloud Run サービス" \
    "gcloud run services list --project=\"${PROJECT_ID}\" --format=\"value(metadata.name)\"" \
    "gcloud run services delete" \
    "--project=\"${PROJECT_ID}\" --quiet --region=us-central1" \
    "Cloud Run サービス"

# 1-2. Pub/Sub
echo "🔎 【2/${TOTAL}】Pub/Sub (トピック・サブスクリプション) のチェックを行っています..."
SUBS="$(gcloud pubsub subscriptions list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
TOPICS="$(gcloud pubsub topics list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
if [ -n "${SUBS}" ] || [ -n "${TOPICS}" ]; then
    echo "⚠️ 以下の残存リソースを検出しました:"
    for sub in ${SUBS}; do echo "   👉 Subscription: ${sub}"; done
    for t in ${TOPICS}; do echo "   👉 Topic: ${t}"; done
    echo "🗑️ 削除処理を実行します..."
    for sub in ${SUBS}; do gcloud pubsub subscriptions delete "${sub}" --project="${PROJECT_ID}" --quiet </dev/null 2>/dev/null || true; done
    for t in ${TOPICS}; do gcloud pubsub topics delete "${t}" --project="${PROJECT_ID}" --quiet </dev/null 2>/dev/null || true; done
    echo "🔄 削除後の再確認を行っています..."
    CHECK_SUBS="$(gcloud pubsub subscriptions list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
    CHECK_TOPICS="$(gcloud pubsub topics list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
    if [ -z "${CHECK_SUBS}" ] && [ -z "${CHECK_TOPICS}" ]; then
        echo "✅ 削除完了を確認しました！（Pub/Sub: 0件）"
    fi
else
    echo "ℹ️ Pub/Sub リソースは検出されませんでした（すでにクリーンです）"
fi
echo ""

# 1-3. Cloud Storage (GCS)
cleanup_resource "3" "${TOTAL}" "Cloud Storage (GCS バケット)" \
    "gcloud storage ls --project=\"${PROJECT_ID}\"" \
    "gcloud storage rm -r" \
    "--quiet" \
    "GCS バケット"

# 1-4. Cloud Spanner
cleanup_resource "4" "${TOTAL}" "Cloud Spanner インスタンス" \
    "gcloud spanner instances list --project=\"${PROJECT_ID}\" --format=\"value(name)\"" \
    "gcloud spanner instances delete" \
    "--project=\"${PROJECT_ID}\" --quiet" \
    "Spanner インスタンス"

# 1-5. AlloyDB
cleanup_resource "5" "${TOTAL}" "AlloyDB クラスター" \
    "gcloud alloydb clusters list --project=\"${PROJECT_ID}\" --format=\"value(name)\"" \
    "gcloud alloydb clusters delete" \
    "--project=\"${PROJECT_ID}\" --region=us-central1 --quiet" \
    "AlloyDB クラスター"

# 1-6. Cloud Bigtable
cleanup_resource "6" "${TOTAL}" "Cloud Bigtable インスタンス" \
    "gcloud bigtable instances list --project=\"${PROJECT_ID}\" --format=\"value(name)\"" \
    "gcloud bigtable instances delete" \
    "--project=\"${PROJECT_ID}\" --quiet" \
    "Bigtable インスタンス"

# 1-7. Artifact Registry
echo "🔎 【7/${TOTAL}】Artifact Registry リポジトリ のチェックを行っています..."
REPOS="$(gcloud artifacts repositories list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
if [ -n "${REPOS}" ]; then
    echo "⚠️ 以下の残存リソースを検出しました:"
    for repo in ${REPOS}; do echo "   👉 Repository: ${repo}"; done
    echo "🗑️ 削除処理を実行します..."
    for repo in ${REPOS}; do
        REPO_NAME="$(echo "${repo}" | awk -F'/' '{print $NF}')"
        REPO_LOC="$(echo "${repo}" | awk -F'/' '{print $4}')"
        gcloud artifacts repositories delete "${REPO_NAME}" --location="${REPO_LOC}" --project="${PROJECT_ID}" --quiet </dev/null 2>/dev/null || true
    done
    echo "✅ 削除処理を完了しました！（Artifact Registry）"
else
    echo "ℹ️ Artifact Registry リポジトリ は検出されませんでした（すでにクリーンです）"
fi
echo ""

# 1-8. Secret Manager
cleanup_resource "8" "${TOTAL}" "Secret Manager シークレット" \
    "gcloud secrets list --project=\"${PROJECT_ID}\" --format=\"value(name)\"" \
    "gcloud secrets delete" \
    "--project=\"${PROJECT_ID}\" --quiet" \
    "Secret Manager シークレット"

# 1-9. Vertex AI Endpoints
cleanup_resource "9" "${TOTAL}" "Vertex AI 常駐エンドポイント" \
    "gcloud ai endpoints list --project=\"${PROJECT_ID}\" --region=us-central1 --format=\"value(name)\"" \
    "gcloud ai endpoints delete" \
    "--project=\"${PROJECT_ID}\" --region=us-central1 --quiet" \
    "Vertex AI エンドポイント"

# 1-10. IAM Service Accounts
echo "🔎 【10/${TOTAL}】IAM 専用サービスアカウントのチェックを行っています..."
SAS="$(gcloud iam service-accounts list --project="${PROJECT_ID}" --format="value(email)" </dev/null 2>/dev/null || echo "")"
TARGET_SAS=""
if [ -n "${SAS}" ]; then
    for sa in ${SAS}; do
        if [[ "${sa}" != *"-compute@developer.gserviceaccount.com"* && "${sa}" != *"@appspot.gserviceaccount.com"* ]]; then
            TARGET_SAS="${TARGET_SAS} ${sa}"
        fi
    done
fi
if [ -n "${TARGET_SAS}" ]; then
    echo "⚠️ 以下の残存専用サービスアカウントを検出しました:"
    for sa in ${TARGET_SAS}; do echo "   👉 Service Account: ${sa}"; done
    echo "🗑️ 削除処理を実行します..."
    for sa in ${TARGET_SAS}; do gcloud iam service-accounts delete "${sa}" --project="${PROJECT_ID}" --quiet </dev/null 2>/dev/null || true; done
    echo "🔄 削除後の再確認を行っています..."
    echo "✅ 削除完了を確認しました！（専用サービスアカウント: 0件）"
else
    echo "ℹ️ 専用サービスアカウントは検出されませんでした（すでにクリーンです）"
fi
echo ""

# -----------------------------------------------------------------------------
# STEP 2: APIサービスのチェック ＆ 無効化 ＆ 切り分け結果の判定
# -----------------------------------------------------------------------------
echo "--------------------------------------------------------"
echo "🔍 2. 有効なAPIサービスのチェック ＆ 無効化"
echo "--------------------------------------------------------"

# 基本APIホワイトリストパターン (grep -E 用)
WHITELIST_REGEX="cloudresourcemanager.googleapis.com|serviceusage.googleapis.com|cloudbilling.googleapis.com|cloudaicompanion.googleapis.com"

echo "📌 【定義】プロジェクト維持のため「残して良い基本API (ホワイトリスト)」:"
echo "   🟢 cloudbilling.googleapis.com (Cloud Billing API)"
echo "   🟢 cloudresourcemanager.googleapis.com (Cloud Resource Manager API)"
echo "   🟢 serviceusage.googleapis.com (Service Usage API)"
echo "   🟢 cloudaicompanion.googleapis.com (Gemini for Google Cloud API)"
echo ""

echo "🔎 現在有効化されているAPI一覧をチェックしています..."
ENABLED_APIS="$(gcloud services list --enabled --project="${PROJECT_ID}" --format="value(config.name)" </dev/null 2>/dev/null || echo "")"

TARGET_APIS=""
if [ -n "${ENABLED_APIS}" ]; then
    TARGET_APIS="$(echo "${ENABLED_APIS}" | grep -v -E "${WHITELIST_REGEX}" || true)"
fi

if [ -n "${TARGET_APIS}" ]; then
    echo "⚠️ 以下の不要API（無効化対象）が有効になっています:"
    for api in ${TARGET_APIS}; do echo "   👉 無効化対象API: ${api}"; done
    echo "🗑️ 不要APIの無効化処理を実行します..."
    gcloud services disable ${TARGET_APIS} --project="${PROJECT_ID}" --force --quiet </dev/null 2>/dev/null || true
    echo "🔄 API無効化処理の反映を待っています (3秒)..."
    sleep 3
else
    echo "ℹ️ 不要なAPIは検出されませんでした（すでに最小化されています）"
fi

echo ""
echo "🔎 【切り分け判定】無効化後の残存APIチェック中..."
FINAL_APIS="$(gcloud services list --enabled --project="${PROJECT_ID}" --format="value(config.name)" </dev/null 2>/dev/null || echo "")"
FINAL_TARGETS=""
if [ -n "${FINAL_APIS}" ]; then
    FINAL_TARGETS="$(echo "${FINAL_APIS}" | grep -v -E "${WHITELIST_REGEX}" || true)"
fi

TOTAL_FINAL_COUNT=0
if [ -n "${FINAL_APIS}" ]; then
    TOTAL_FINAL_COUNT=$(echo "${FINAL_APIS}" | wc -w)
fi

if [ -z "${FINAL_TARGETS}" ]; then
    echo "✅ 【完璧】不要APIはすべて正常に停止されました！基本APIのみが維持されています（余分API: 0件）。"
    echo ""
    echo "📌 最終的にプロジェクトに残っているAPI一覧 (${TOTAL_FINAL_COUNT}件 / 想定内):"
else
    EXTRA_COUNT=$(echo "${FINAL_TARGETS}" | wc -w)
    echo "🚨 【要確認】基本API以外に、以下の未停止API（${EXTRA_COUNT}件）が残存しています！"
    for api in ${FINAL_TARGETS}; do
        echo "   🔴 停止未完了API: ${api}"
    done
    echo "   (※ 請求先アカウント未紐付け時や他リソースとの依存関係で残る場合があります)"
    echo ""
    echo "⚠️ 最終的にプロジェクトに残っているAPI一覧 (${TOTAL_FINAL_COUNT}件 / 🚨注意: 基本APIを超えています):"
fi

# 美しいアイコン表示フォーマット出力
if [ -n "${FINAL_APIS}" ]; then
    for api in ${FINAL_APIS}; do
        case "${api}" in
            "cloudbilling.googleapis.com")
                echo "   🟢 [維持OK] ${api} (Cloud Billing API)"
                ;;
            "cloudresourcemanager.googleapis.com")
                echo "   🟢 [維持OK] ${api} (Cloud Resource Manager API)"
                ;;
            "serviceusage.googleapis.com")
                echo "   🟢 [維持OK] ${api} (Service Usage API)"
                ;;
            "cloudaicompanion.googleapis.com")
                echo "   🟢 [維持OK] ${api} (Gemini for Google Cloud API)"
                ;;
            *)
                echo "   🔴 [要確認] ${api}"
                ;;
        esac
    done
fi
echo ""

# -----------------------------------------------------------------------------
# STEP 3: 課金アカウントのチェック ＆ 解除 (Unlink) ＆ 休眠確認
# -----------------------------------------------------------------------------
echo "--------------------------------------------------------"
echo "🔍 3. 請求先アカウントのチェック ＆ 解除 (Unlink)"
echo "--------------------------------------------------------"
echo "🔎 現在の課金紐付け状態をチェックしています..."

RAW_IS_ENABLED="$(gcloud beta billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" </dev/null 2>/dev/null || echo "false")"
IS_ENABLED="$(echo "${RAW_IS_ENABLED}" | tr '[:upper:]' '[:lower:]')"

if [ "${IS_ENABLED}" = "true" ]; then
    echo "⚠️ 課金アカウントがリンクされています（有効状態）"
    echo "⚡ 請求先アカウントの解除（Unlink）を実行します..."
    gcloud billing projects unlink "${PROJECT_ID}" --quiet </dev/null 2>/dev/null || true
    echo "🔄 解除後の課金状態を再確認中..."
    RAW_AFTER="$(gcloud beta billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" </dev/null 2>/dev/null || echo "false")"
    AFTER_ENABLED="$(echo "${RAW_AFTER}" | tr '[:upper:]' '[:lower:]')"
    if [ "${AFTER_ENABLED}" = "false" ]; then
        echo "✅ 【解除成功】課金アカウントの解除が完了しました！（課金OFF: false）"
    else
        echo "⚠️ 課金解除処理を実行しましたが、反映に時間がかかっている可能性があります。"
    fi
else
    echo "ℹ️ 請求先アカウントはすでに解除（未リンク）されています（課金OFF: false）"
fi

echo ""
echo "========================================================"
echo "🎉 すべてのチェック・お掃除・0円休眠化が正常に完了しました！"
echo "========================================================"
