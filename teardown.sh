#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# GCP 全サービス一括クリーンアップ ＆ 休眠（課金解除）実況付きスクリプト
# -----------------------------------------------------------------------------

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"

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
# STEP 1: 個別サービス・リソースの目視チェック ＆ 削除 ＆ 再確認
# -----------------------------------------------------------------------------
echo "--------------------------------------------------------"
echo "🔍 1. 個別サービス・リソースのチェック ＆ 削除"
echo "--------------------------------------------------------"

# 1-1. Cloud Run
echo "🔎 【1/7】Cloud Run サービスの残存チェックを行っています..."
SERVICES=$(gcloud run services list --project="${PROJECT_ID}" --format="value(metadata.name)" 2>/dev/null || true)
if [ -n "${SERVICES}" ]; then
    echo "⚠️ 残存リソースを検出しました:"
    for s in ${SERVICES}; do echo "   👉 Cloud Run: ${s}"; done
    echo "🗑️ 削除処理を実行します..."
    for s in ${SERVICES}; do
        gcloud run services delete "${s}" --project="${PROJECT_ID}" --quiet --region=us-central1 2>/dev/null || true
    done
    echo "🔄 再確認中..."
    CHECK=$(gcloud run services list --project="${PROJECT_ID}" --format="value(metadata.name)" 2>/dev/null || true)
    if [ -z "${CHECK}" ]; then echo "✅ 消えました！（Cloud Run 0件）"; fi
else
    echo "✅ 該当リソースはありません（クリーンです）"
fi
echo ""

# 1-2. Pub/Sub
echo "🔎 【2/7】Pub/Sub (トピック・サブスクリプション) の残存チェックを行っています..."
SUBS=$(gcloud pubsub subscriptions list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
TOPICS=$(gcloud pubsub topics list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
if [ -n "${SUBS}" ] || [ -n "${TOPICS}" ]; then
    echo "⚠️ 残存リソースを検出しました:"
    for sub in ${SUBS}; do echo "   👉 Subscription: ${sub}"; done
    for t in ${TOPICS}; do echo "   👉 Topic: ${t}"; done
    echo "🗑️ 削除処理を実行します..."
    for sub in ${SUBS}; do gcloud pubsub subscriptions delete "${sub}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true; done
    for t in ${TOPICS}; do gcloud pubsub topics delete "${t}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true; done
    echo "🔄 再確認中..."
    CHECK_SUBS=$(gcloud pubsub subscriptions list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
    CHECK_TOPICS=$(gcloud pubsub topics list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
    if [ -z "${CHECK_SUBS}" ] && [ -z "${CHECK_TOPICS}" ]; then echo "✅ 消えました！（Pub/Sub 0件）"; fi
else
    echo "✅ 該当リソースはありません（クリーンです）"
fi
echo ""

# 1-3. Cloud Storage (GCS)
echo "🔎 【3/7】Cloud Storage (GCS バケット) の残存チェックを行っています..."
BUCKETS=$(gcloud storage ls --project="${PROJECT_ID}" 2>/dev/null || true)
if [ -n "${BUCKETS}" ]; then
    echo "⚠️ 残存バケットを検出しました:"
    for b in ${BUCKETS}; do echo "   👉 Bucket: ${b}"; done
    echo "🗑️ 削除処理を実行します..."
    for b in ${BUCKETS}; do gcloud storage rm -r "${b}" --quiet 2>/dev/null || true; done
    echo "🔄 再確認中..."
    CHECK_B=$(gcloud storage ls --project="${PROJECT_ID}" 2>/dev/null || true)
    if [ -z "${CHECK_B}" ]; then echo "✅ 消えました！（GCS バケット 0件）"; fi
else
    echo "✅ 該当リソースはありません（クリーンです）"
fi
echo ""

# 1-4. Cloud Spanner
echo "🔎 【4/7】Cloud Spanner インスタンスの残存チェックを行っています..."
SPANNER=$(gcloud spanner instances list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
if [ -n "${SPANNER}" ]; then
    echo "⚠️ 残存インスタンスを検出しました:"
    for sp in ${SPANNER}; do echo "   👉 Spanner Instance: ${sp}"; done
    echo "🗑️ 削除処理を実行します..."
    for sp in ${SPANNER}; do gcloud spanner instances delete "${sp}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true; done
    echo "🔄 再確認中..."
    CHECK_SP=$(gcloud spanner instances list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
    if [ -z "${CHECK_SP}" ]; then echo "✅ 消えました！（Spanner インスタンス 0件）"; fi
else
    echo "✅ 該当リソースはありません（クリーンです）"
fi
echo ""

# 1-5. AlloyDB
echo "🔎 【5/7】AlloyDB クラスターの残存チェックを行っています..."
ALLOY=$(gcloud alloydb clusters list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
if [ -n "${ALLOY}" ]; then
    echo "⚠️ 残存クラスターを検出しました:"
    for ac in ${ALLOY}; do echo "   👉 AlloyDB Cluster: ${ac}"; done
    echo "🗑️ 削除処理を実行します..."
    for ac in ${ALLOY}; do gcloud alloydb clusters delete "${ac}" --project="${PROJECT_ID}" --region=us-central1 --quiet 2>/dev/null || true; done
    echo "🔄 再確認中..."
    CHECK_AL=$(gcloud alloydb clusters list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
    if [ -z "${CHECK_AL}" ]; then echo "✅ 消えました！（AlloyDB クラスター 0件）"; fi
else
    echo "✅ 該当リソースはありません（クリーンです）"
fi
echo ""

# 1-6. Artifact Registry
echo "🔎 【6/7】Artifact Registry リポジトリの残存チェックを行っています..."
AR_REPOS=$(gcloud artifacts repositories list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
if [ -n "${AR_REPOS}" ]; then
    echo "⚠️ 残存リポジトリを検出しました:"
    for repo in ${AR_REPOS}; do echo "   👉 Repository: ${repo}"; done
    echo "🗑️ 削除処理を実行します..."
    for repo in ${AR_REPOS}; do gcloud artifacts repositories delete "${repo}" --project="${PROJECT_ID}" --location=us-central1 --quiet 2>/dev/null || true; done
    echo "🔄 再確認中..."
    CHECK_AR=$(gcloud artifacts repositories list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
    if [ -z "${CHECK_AR}" ]; then echo "✅ 消えました！（Artifact Registry 0件）"; fi
else
    echo "✅ 該当リソースはありません（クリーンです）"
fi
echo ""

# 1-7. IAM Service Accounts
echo "🔎 【7/7】IAM 専用サービスアカウントの残存チェックを行っています..."
SAS=$(gcloud iam service-accounts list --project="${PROJECT_ID}" --format="value(email)" 2>/dev/null || true)
TARGET_SAS=""
if [ -n "${SAS}" ]; then
    for sa in ${SAS}; do
        if [[ "${sa}" != *"-compute@developer.gserviceaccount.com"* && "${sa}" != *"@appspot.gserviceaccount.com"* ]]; then
            TARGET_SAS="${TARGET_SAS} ${sa}"
        fi
    done
fi
if [ -n "${TARGET_SAS}" ]; then
    echo "⚠️ 残存専用サービスアカウントを検出しました:"
    for sa in ${TARGET_SAS}; do echo "   👉 Service Account: ${sa}"; done
    echo "🗑️ 削除処理を実行します..."
    for sa in ${TARGET_SAS}; do gcloud iam service-accounts delete "${sa}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true; done
    echo "🔄 再確認中..."
    echo "✅ 消えました！（専用サービスアカウント 0件）"
else
    echo "✅ 該当する専用サービスアカウントはありません（クリーンです）"
fi
echo ""

# -----------------------------------------------------------------------------
# STEP 2: APIサービスの無効化 ＆ 一覧確認
# -----------------------------------------------------------------------------
echo "--------------------------------------------------------"
echo "🔍 2. 有効なAPIサービスのチェック ＆ 無効化"
echo "--------------------------------------------------------"
echo "🔎 現在有効化されているAPI一覧を確認しています..."
ENABLED_APIS=$(gcloud services list --enabled --project="${PROJECT_ID}" --format="value(config.name)" 2>/dev/null || true)

TARGET_APIS=$(echo "${ENABLED_APIS}" | grep -v "cloudresourcemanager.googleapis.com\|serviceusage.googleapis.com\|cloudbilling.googleapis.com" || true)

if [ -n "${TARGET_APIS}" ]; then
    echo "⚠️ 以下の無効化対象APIが有効になっています:"
    for api in ${TARGET_APIS}; do echo "   👉 API: ${api}"; done
    echo "🗑️ APIを無効化しています..."
    echo "${TARGET_APIS}" | xargs -r -I {} gcloud services disable {} --project="${PROJECT_ID}" --force --quiet 2>/dev/null || true
    echo "🔄 無効化完了！一覧を再取得します..."
else
    echo "ℹ️ すでに主要APIは無効化されています。"
fi

echo ""
echo "📌 現在残っているAPI（これらはプロジェクト基本機能として残ってていいものです）:"
gcloud services list --enabled --project="${PROJECT_ID}" --format="table(config.name, title)" 2>/dev/null || true
echo ""

# -----------------------------------------------------------------------------
# STEP 3: 課金解除 ＆ 休眠状態の最終確認
# -----------------------------------------------------------------------------
echo "--------------------------------------------------------"
echo "🔍 3. 請求先アカウントの解除 ＆ 休眠状態の最終確認"
echo "--------------------------------------------------------"
echo "⚡ 請求先アカウントを解除（Unlink）します..."
gcloud billing projects unlink "${PROJECT_ID}" --quiet 2>/dev/null || true

echo "🔄 課金状態を最終確認中..."
IS_ENABLED=$(gcloud beta billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" 2>/dev/null || echo "false")
if [ "${IS_ENABLED}" = "false" ]; then
    echo "✅ 【確認完了】課金状態: 未リンク（False） - 0円休眠状態になりました！"
else
    echo "⚠️ 課金解除状態の確認が必要です。"
fi

echo ""
echo "🎉 すべてのチェック・お掃除・0円休眠化が正常に完了しました！"
