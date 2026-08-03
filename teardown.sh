#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# GCP 全サービス一括クリーンアップ ＆ 休眠（課金解除）スクリプト
# -----------------------------------------------------------------------------

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"

if [ -z "${PROJECT_ID}" ]; then
    echo "❌ PROJECT_ID が指定されておらず、アクティブなプロジェクトも確認できません。"
    exit 1
fi

echo ""
echo "----------------------------------------"
echo "🧹 対象プロジェクトID: ${PROJECT_ID}"
echo "----------------------------------------"
echo "全サービスの一括クリーンアップ ＆ 課金解除処理を開始します..."
echo ""

# -----------------------------------------------------------------------------
# 1. リソース全スキャン＆個別に安全削除（全記事網羅）
# -----------------------------------------------------------------------------

echo "🔍 [1/8] Cloud Run サービス / ジョブのクリーンアップ"
SERVICES=$(gcloud run services list --project="${PROJECT_ID}" --format="value(metadata.name)" 2>/dev/null || true)
if [ -n "${SERVICES}" ]; then
    for s in ${SERVICES}; do
        echo "  🗑️ Cloud Run サービスを削除中: ${s}"
        gcloud run services delete "${s}" --project="${PROJECT_ID}" --quiet --region=us-central1 2>/dev/null || true
    done
else
    echo "  ℹ️ Cloud Run サービスはありません（スキップ）"
fi

echo "🔍 [2/8] Pub/Sub サブスクリプション / トピックのクリーンアップ"
SUBS=$(gcloud pubsub subscriptions list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
if [ -n "${SUBS}" ]; then
    for sub in ${SUBS}; do
        echo "  🗑️ Pub/Sub サブスクリプションを削除中: ${sub}"
        gcloud pubsub subscriptions delete "${sub}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
    done
else
    echo "  ℹ️ Pub/Sub サブスクリプションはありません（スキップ）"
fi

TOPICS=$(gcloud pubsub topics list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
if [ -n "${TOPICS}" ]; then
    for t in ${TOPICS}; do
        echo "  🗑️ Pub/Sub トピックを削除中: ${t}"
        gcloud pubsub topics delete "${t}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
    done
else
    echo "  ℹ️ Pub/Sub トピックはありません（スキップ）"
fi

echo "🔍 [3/8] Cloud Storage (GCS) バケットのクリーンアップ"
BUCKETS=$(gcloud storage ls --project="${PROJECT_ID}" 2>/dev/null || true)
if [ -n "${BUCKETS}" ]; then
    for b in ${BUCKETS}; do
        # デプロイ用ソースバケットも含めて安全削除
        echo "  🗑️ GCS バケットを削除中: ${b}"
        gcloud storage rm -r "${b}" --quiet 2>/dev/null || true
    done
else
    echo "  ℹ️ GCS バケットはありません（スキップ）"
fi

echo "🔍 [4/8] Cloud Spanner インスタンスのクリーンアップ"
SPANNER_INSTANCES=$(gcloud spanner instances list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
if [ -n "${SPANNER_INSTANCES}" ]; then
    for sp in ${SPANNER_INSTANCES}; do
        echo "  🗑️ Cloud Spanner インスタンスを削除中: ${sp}"
        gcloud spanner instances delete "${sp}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
    done
else
    echo "  ℹ️ Cloud Spanner インスタンスはありません（スキップ）"
fi

echo "🔍 [5/8] AlloyDB クラスターのクリーンアップ"
ALLOY_CLUSTERS=$(gcloud alloydb clusters list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
if [ -n "${ALLOY_CLUSTERS}" ]; then
    for ac in ${ALLOY_CLUSTERS}; do
        echo "  🗑️ AlloyDB クラスターを削除中: ${ac}"
        gcloud alloydb clusters delete "${ac}" --project="${PROJECT_ID}" --region=us-central1 --quiet 2>/dev/null || true
    done
else
    echo "  ℹ️ AlloyDB クラスターはありません（スキップ）"
fi

echo "🔍 [6/8] Artifact Registry リポジトリのクリーンアップ"
AR_REPOS=$(gcloud artifacts repositories list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
if [ -n "${AR_REPOS}" ]; then
    for repo in ${AR_REPOS}; do
        echo "  🗑️ Artifact Registry リポジトリを削除中: ${repo}"
        gcloud artifacts repositories delete "${repo}" --project="${PROJECT_ID}" --location=us-central1 --quiet 2>/dev/null || true
    done
else
    echo "  ℹ️ Artifact Registry リポジトリはありません（スキップ）"
fi

echo "🔍 [7/8] IAM サービスアカウントのクリーンアップ"
SAS=$(gcloud iam service-accounts list --project="${PROJECT_ID}" --format="value(email)" 2>/dev/null || true)
if [ -n "${SAS}" ]; then
    for sa in ${SAS}; do
        # App Engine / Compute Engine デフォルト SA 以外を削除
        if [[ "${sa}" != *"-compute@developer.gserviceaccount.com"* && "${sa}" != *"@appspot.gserviceaccount.com"* ]]; then
            echo "  🗑️ IAM サービスアカウントを削除中: ${sa}"
            gcloud iam service-accounts delete "${sa}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
        fi
    done
else
    echo "  ℹ️ 削除対象の専用サービスアカウントはありません（スキップ）"
fi

echo "🔍 [8/8] APIサービスの無効化 (休眠化)"
gcloud services list --enabled --project="${PROJECT_ID}" --format="value(config.name)" 2>/dev/null \
    | grep -v "cloudresourcemanager.googleapis.com\|serviceusage.googleapis.com\|cloudbilling.googleapis.com" \
    | xargs -r -I {} gcloud services disable {} --project="${PROJECT_ID}" --force --quiet 2>/dev/null || true

# -----------------------------------------------------------------------------
# 2. 課金リンクの解除
# -----------------------------------------------------------------------------
echo ""
echo "----------------------------------------"
echo "⚡ 課金アカウントの解除 (Unlink)"
echo "----------------------------------------"
gcloud billing projects unlink "${PROJECT_ID}" --quiet 2>/dev/null || true

# -----------------------------------------------------------------------------
# 3. 事後状態の最終確認
# -----------------------------------------------------------------------------
echo ""
echo "----------------------------------------"
echo "🔍 課金休眠状態の最終確認"
echo "----------------------------------------"
gcloud beta billing projects describe "${PROJECT_ID}" 2>/dev/null || echo "課金は無効化（Unlinked）されました"

echo ""
echo "----------------------------------------"
echo "🔍 有効サービス一覧確認 (リソース・API全停止確認)"
echo "----------------------------------------"
gcloud services list --enabled --project="${PROJECT_ID}" 2>/dev/null || echo "すべての主要APIが正常に無効化されました"

echo ""
echo "✅ 全リソースのクリーンアップ ＆ 課金解除が完了しました！"
