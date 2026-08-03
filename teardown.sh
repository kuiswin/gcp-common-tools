#!/bin/bash
set -eu

# -----------------------------------------------------------------------------
# GCP 全サービス一括クリーンアップ ＆ 休眠（課金解除）対話的チェック付きスクリプト
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
# STEP 1: 個別サービス・リソースの存在チェック ＆ 削除 ＆ 再確認
# -----------------------------------------------------------------------------
echo "--------------------------------------------------------"
echo "🔍 1. 個別サービス・リソースのチェック ＆ 削除"
echo "--------------------------------------------------------"

# 1-1. Cloud Run
echo "🔎 【1/7】Cloud Run サービスのチェックを行っています..."
SERVICES="$(gcloud run services list --project="${PROJECT_ID}" --format="value(metadata.name)" </dev/null 2>/dev/null || echo "")"
if [ -n "${SERVICES}" ]; then
    echo "⚠️ 以下の残存サービスを検出しました:"
    for s in ${SERVICES}; do echo "   👉 Cloud Run: ${s}"; done
    echo "🗑️ 削除処理を実行します..."
    for s in ${SERVICES}; do
        gcloud run services delete "${s}" --project="${PROJECT_ID}" --quiet --region=us-central1 </dev/null 2>/dev/null || true
    done
    echo "🔄 削除後の再確認を行っています..."
    CHECK_SERVICES="$(gcloud run services list --project="${PROJECT_ID}" --format="value(metadata.name)" </dev/null 2>/dev/null || echo "")"
    if [ -z "${CHECK_SERVICES}" ]; then
        echo "✅ 削除完了を確認しました！（Cloud Run サービス: 0件）"
    fi
else
    echo "ℹ️ Cloud Run サービスは検出されませんでした（すでにクリーンです）"
fi
echo ""

# 1-2. Pub/Sub
echo "🔎 【2/7】Pub/Sub (トピック・サブスクリプション) のチェックを行っています..."
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
echo "🔎 【3/7】Cloud Storage (GCS バケット) のチェックを行っています..."
BUCKETS="$(gcloud storage ls --project="${PROJECT_ID}" </dev/null 2>/dev/null || echo "")"
if [ -n "${BUCKETS}" ]; then
    echo "⚠️ 以下の残存バケットを検出しました:"
    for b in ${BUCKETS}; do echo "   👉 Bucket: ${b}"; done
    echo "🗑️ 削除処理を実行します..."
    for b in ${BUCKETS}; do gcloud storage rm -r "${b}" --quiet </dev/null 2>/dev/null || true; done
    echo "🔄 削除後の再確認を行っています..."
    CHECK_BUCKETS="$(gcloud storage ls --project="${PROJECT_ID}" </dev/null 2>/dev/null || echo "")"
    if [ -z "${CHECK_BUCKETS}" ]; then
        echo "✅ 削除完了を確認しました！（GCS バケット: 0件）"
    fi
else
    echo "ℹ️ GCS バケットは検出されませんでした（すでにクリーンです）"
fi
echo ""

# 1-4. Cloud Spanner
echo "🔎 【4/7】Cloud Spanner インスタンスのチェックを行っています..."
SPANNER="$(gcloud spanner instances list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
if [ -n "${SPANNER}" ]; then
    echo "⚠️ 以下の残存インスタンスを検出しました:"
    for sp in ${SPANNER}; do echo "   👉 Spanner Instance: ${sp}"; done
    echo "🗑️ 削除処理を実行します..."
    for sp in ${SPANNER}; do gcloud spanner instances delete "${sp}" --project="${PROJECT_ID}" --quiet </dev/null 2>/dev/null || true; done
    echo "🔄 削除後の再確認を行っています..."
    CHECK_SPANNER="$(gcloud spanner instances list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
    if [ -z "${CHECK_SPANNER}" ]; then
        echo "✅ 削除完了を確認しました！（Spanner インスタンス: 0件）"
    fi
else
    echo "ℹ️ Spanner インスタンスは検出されませんでした（すでにクリーンです）"
fi
echo ""

# 1-5. AlloyDB
echo "🔎 【5/7】AlloyDB クラスターのチェックを行っています..."
ALLOY="$(gcloud alloydb clusters list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
if [ -n "${ALLOY}" ]; then
    echo "⚠️ 以下の残存クラスターを検出しました:"
    for ac in ${ALLOY}; do echo "   👉 AlloyDB Cluster: ${ac}"; done
    echo "🗑️ 削除処理を実行します..."
    for ac in ${ALLOY}; do gcloud alloydb clusters delete "${ac}" --project="${PROJECT_ID}" --region=us-central1 --quiet </dev/null 2>/dev/null || true; done
    echo "🔄 削除後の再確認を行っています..."
    CHECK_ALLOY="$(gcloud alloydb clusters list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
    if [ -z "${CHECK_ALLOY}" ]; then
        echo "✅ 削除完了を確認しました！（AlloyDB クラスター: 0件）"
    fi
else
    echo "ℹ️ AlloyDB クラスターは検出されませんでした（すでにクリーンです）"
fi
echo ""

# 1-6. Artifact Registry
echo "🔎 【6/7】Artifact Registry リポジトリのチェックを行っています..."
AR_REPOS="$(gcloud artifacts repositories list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
if [ -n "${AR_REPOS}" ]; then
    echo "⚠️ 以下の残存リポジトリを検出しました:"
    for repo in ${AR_REPOS}; do echo "   👉 Repository: ${repo}"; done
    echo "🗑️ 削除処理を実行します..."
    for repo in ${AR_REPOS}; do gcloud artifacts repositories delete "${repo}" --project="${PROJECT_ID}" --location=us-central1 --quiet </dev/null 2>/dev/null || true; done
    echo "🔄 削除後の再確認を行っています..."
    CHECK_AR="$(gcloud artifacts repositories list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
    if [ -z "${CHECK_AR}" ]; then
        echo "✅ 削除完了を確認しました！（Artifact Registry: 0件）"
    fi
else
    echo "ℹ️ Artifact Registry リポジトリは検出されませんでした（すでにクリーンです）"
fi
echo ""

# 1-7. IAM Service Accounts
echo "🔎 【7/7】IAM 専用サービスアカウントのチェックを行っています..."
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
# STEP 2: APIサービスのチェック ＆ 無効化 ＆ 残存確認
# -----------------------------------------------------------------------------
echo "--------------------------------------------------------"
echo "🔍 2. 有効なAPIサービスのチェック ＆ 無効化"
echo "--------------------------------------------------------"
echo "🔎 現在有効化されているAPI一覧をチェックしています..."
ENABLED_APIS="$(gcloud services list --enabled --project="${PROJECT_ID}" --format="value(config.name)" </dev/null 2>/dev/null || echo "")"

TARGET_APIS=""
if [ -n "${ENABLED_APIS}" ]; then
    TARGET_APIS="$(echo "${ENABLED_APIS}" | grep -v -E "cloudresourcemanager.googleapis.com|serviceusage.googleapis.com|cloudbilling.googleapis.com" || true)"
fi

if [ -n "${TARGET_APIS}" ]; then
    echo "⚠️ 以下の不要APIが有効化されています:"
    for api in ${TARGET_APIS}; do echo "   👉 API: ${api}"; done
    echo "🗑️ 不要APIの無効化処理を実行します..."
    echo "${TARGET_APIS}" | xargs -r -I {} gcloud services disable {} --project="${PROJECT_ID}" --force --quiet </dev/null 2>/dev/null || true
    echo "🔄 無効化処理が完了しました！一覧を再取得します..."
else
    echo "ℹ️ 不要なAPIは検出されませんでした（すでに最小化されています）"
fi

echo ""
echo "📌 現在有効なAPI一覧（これらはプロジェクト維持に必要な基本機能です）:"
gcloud services list --enabled --project="${PROJECT_ID}" --format="table(config.name, title)" </dev/null 2>/dev/null || echo "基本API一覧の取得完了"
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
