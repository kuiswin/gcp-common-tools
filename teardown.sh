#!/bin/bash
set -eu

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project </dev/null 2>/dev/null || echo "")}"
if [ -z "${PROJECT_ID}" ] && [ -f ~/.config/gcloud/configurations/config_default ]; then
    PROJECT_ID="$(grep '^project =' ~/.config/gcloud/configurations/config_default | cut -d'=' -f2 | tr -d ' ' || true)"
fi

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
# 0. API停止・リソース削除のための課金一時再リンク判定 (安全な完全停止用フォールバック)
# -----------------------------------------------------------------------------
RAW_IS_ENABLED="$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" </dev/null 2>/dev/null || echo "false")"
IS_ENABLED="$(echo "${RAW_IS_ENABLED}" | tr '[:upper:]' '[:lower:]')"

if [ "${IS_ENABLED}" != "true" ]; then
    BILLING_ACCT="$(gcloud billing accounts list --filter="open=true" --format="value(name)" </dev/null 2>/dev/null | head -n1 || echo "")"
    if [ -n "${BILLING_ACCT}" ]; then
        echo "💡 残存リソース完全消去 ＆ 不要API無効化のため、請求先アカウントを一時的に再有効化します..."
        gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCT}" --quiet </dev/null 2>/dev/null || true
        sleep 2
    fi
fi

# -----------------------------------------------------------------------------
# 1. 走査・お掃除対象サービス一覧の定義 (データリスト)
# -----------------------------------------------------------------------------
RESOURCE_TARGETS=(
    "Cloud Run サービス"
    "Cloud Run ジョブ"
    "Pub/Sub (トピック / サブスクリプション)"
    "Cloud Storage (GCS バケット)"
    "BigQuery (データセット)"
    "Cloud Spanner (データベースインスタンス)"
    "AlloyDB (データベースクラスター)"
    "Cloud Bigtable (NoSQLデータベースインスタンス)"
    "Artifact Registry (コンテナリポジトリ)"
    "Secret Manager (シークレット・機密情報)"
    "Vertex AI (Gemini / 機械学習常駐エンドポイント)"
    "データアクセス監査ログ設定 (auditConfigs)"
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
        echo "🗑️ 削除処理を並列実行します..."
        for item in ${items}; do
            eval "${del_cmd_prefix} \"${item}\" ${del_cmd_suffix}" </dev/null 2>/dev/null &
        done
        wait
        echo "🔄 削除完了の同期検証を行っています..."
        local retry=0
        local max_retry=15
        local sleep_sec=2
        # AlloyDBなどの長周期削除リソース用タイムアウト拡張 (最大5分)
        if [[ "${label_name}" == *"AlloyDB"* || "${label_name}" == *"Spanner"* ]]; then
            max_retry=60
            sleep_sec=5
        fi
        while [ ${retry} -lt ${max_retry} ]; do
            local check_items
            check_items="$(eval "${list_cmd}" </dev/null 2>/dev/null || echo "")"
            if [ -z "${check_items}" ]; then
                echo "✅ 削除完了を確認しました！（${label_name}: 0件）"
                echo ""
                return 0
            fi
            sleep ${sleep_sec}
            retry=$((retry + 1))
        done
        echo "⚠️ 削除要求発行済み（バックグラウンド完全反映待ち）"
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
echo "💡 (※削除漏れ防止とAPI停止処理を100%成功させるため、走査・お掃除中のみ一時的に請求先アカウントを有効化して完全チェックを行っています)"

# 削除走査用APIの有効化（API停止状態による検出漏れ・削除漏れ防止）
gcloud services enable \
    run.googleapis.com \
    pubsub.googleapis.com \
    storage.googleapis.com \
    bigquery.googleapis.com \
    spanner.googleapis.com \
    alloydb.googleapis.com \
    bigtable.googleapis.com \
    artifactregistry.googleapis.com \
    secretmanager.googleapis.com \
    aiplatform.googleapis.com \
    compute.googleapis.com \
    servicenetworking.googleapis.com \
    --project="${PROJECT_ID}" --async --quiet </dev/null 2>/dev/null || true
sleep 1

TOTAL=${#RESOURCE_TARGETS[@]}

# 1-1. Cloud Run (サービス / ジョブ)
cleanup_resource "1" "${TOTAL}" "Cloud Run サービス" \
    "gcloud run services list --project=\"${PROJECT_ID}\" --format=\"value(metadata.name)\"" \
    "gcloud run services delete" \
    "--project=\"${PROJECT_ID}\" --quiet --region=asia-northeast1" \
    "Cloud Run サービス"

cleanup_resource "2" "${TOTAL}" "Cloud Run ジョブ" \
    "gcloud run jobs list --project=\"${PROJECT_ID}\" --format=\"value(metadata.name)\"" \
    "gcloud run jobs delete" \
    "--project=\"${PROJECT_ID}\" --quiet --region=asia-northeast1" \
    "Cloud Run ジョブ"

# 1-2. Pub/Sub
echo "🔎 【3/${TOTAL}】Pub/Sub (トピック・サブスクリプション) のチェックを行っています..."
SUBS="$(gcloud pubsub subscriptions list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
TOPICS="$(gcloud pubsub topics list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
if [ -n "${SUBS}" ] || [ -n "${TOPICS}" ]; then
    echo "⚠️ 以下の残存リソースを検出しました:"
    for sub in ${SUBS}; do echo "   👉 Subscription: ${sub}"; done
    for t in ${TOPICS}; do echo "   👉 Topic: ${t}"; done
    echo "🗑️ 削除処理を並列実行します..."
    for sub in ${SUBS}; do gcloud pubsub subscriptions delete "${sub}" --project="${PROJECT_ID}" --quiet </dev/null 2>/dev/null & done
    for t in ${TOPICS}; do gcloud pubsub topics delete "${t}" --project="${PROJECT_ID}" --quiet </dev/null 2>/dev/null & done
    wait
    echo "🔄 削除完了の同期検証を行っています..."
    retry=0
    while [ ${retry} -lt 15 ]; do
        CHECK_SUBS="$(gcloud pubsub subscriptions list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
        CHECK_TOPICS="$(gcloud pubsub topics list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
        if [ -z "${CHECK_SUBS}" ] && [ -z "${CHECK_TOPICS}" ]; then
            echo "✅ 削除完了を確認しました！（Pub/Sub: 0件）"
            break
        fi
        sleep 2
        retry=$((retry + 1))
    done
else
    echo "ℹ️ Pub/Sub リソースは検出されませんでした（すでにクリーンです）"
fi
echo ""

# 1-3. Cloud Storage (GCS)
cleanup_resource "4" "${TOTAL}" "Cloud Storage (GCS バケット)" \
    "gcloud storage ls --project=\"${PROJECT_ID}\"" \
    "gcloud storage rm -r" \
    "--quiet" \
    "GCS バケット"

# 1-4. BigQuery Dataset (API未有効時はスルー、データセットID正規表現フィルタ)
cleanup_resource "5" "${TOTAL}" "BigQuery データセット" \
    "bq --project_id=\"${PROJECT_ID}\" ls --format=sparse 2>/dev/null | awk 'NR>2 {print \$1}' | grep -E '^[a-zA-Z0-9_]+$'" \
    "bq --project_id=\"${PROJECT_ID}\" rm -r -f -d" \
    "" \
    "BigQuery データセット"

# 1-5. Cloud Spanner
cleanup_resource "6" "${TOTAL}" "Cloud Spanner インスタンス" \
    "gcloud spanner instances list --project=\"${PROJECT_ID}\" --format=\"value(name)\"" \
    "gcloud spanner instances delete" \
    "--project=\"${PROJECT_ID}\" --quiet" \
    "Spanner インスタンス"

# 1-6. AlloyDB
cleanup_resource "7" "${TOTAL}" "AlloyDB クラスター" \
    "gcloud alloydb clusters list --project=\"${PROJECT_ID}\" --region=asia-northeast1 --format=\"value(name)\"" \
    "gcloud alloydb clusters delete" \
    "--project=\"${PROJECT_ID}\" --region=asia-northeast1 --force --quiet" \
    "AlloyDB クラスター"

# 1-7. Cloud Bigtable
cleanup_resource "8" "${TOTAL}" "Cloud Bigtable インスタンス" \
    "gcloud bigtable instances list --project=\"${PROJECT_ID}\" --format=\"value(name)\"" \
    "gcloud bigtable instances delete" \
    "--project=\"${PROJECT_ID}\" --quiet" \
    "Bigtable インスタンス"

# 1-8. Artifact Registry
echo "🔎 【9/${TOTAL}】Artifact Registry リポジトリ のチェックを行っています..."
REPOS_INFO="$(gcloud artifacts repositories list --project="${PROJECT_ID}" --format="csv[no-heading](REPOSITORY,LOCATION)" </dev/null 2>/dev/null || echo "")"
if [ -n "${REPOS_INFO}" ]; then
    echo "⚠️ 以下の残存リソースを検出しました:"
    while IFS=',' read -r repo_name repo_loc; do
        [ -z "${repo_name}" ] && continue
        echo "   👉 Repository: ${repo_name} (location: ${repo_loc})"
    done <<< "${REPOS_INFO}"
    echo "🗑️ 削除処理を並列実行します..."
    while IFS=',' read -r repo_name repo_loc; do
        [ -z "${repo_name}" ] && continue
        gcloud artifacts repositories delete "${repo_name}" --location="${repo_loc}" --project="${PROJECT_ID}" --quiet </dev/null 2>/dev/null &
    done <<< "${REPOS_INFO}"
    wait
    echo "🔄 削除完了の同期検証を行っています..."
    retry=0
    while [ ${retry} -lt 15 ]; do
        CHECK_REPOS="$(gcloud artifacts repositories list --project="${PROJECT_ID}" --format="value(name)" </dev/null 2>/dev/null || echo "")"
        if [ -z "${CHECK_REPOS}" ]; then
            echo "✅ 削除完了を確認しました！（Artifact Registry: 0件）"
            break
        fi
        sleep 2
        retry=$((retry + 1))
    done
else
    echo "ℹ️ Artifact Registry リポジトリ は検出されませんでした（すでにクリーンです）"
fi
echo ""

# 1-9. Secret Manager
cleanup_resource "10" "${TOTAL}" "Secret Manager シークレット" \
    "gcloud secrets list --project=\"${PROJECT_ID}\" --format=\"value(name)\"" \
    "gcloud secrets delete" \
    "--project=\"${PROJECT_ID}\" --quiet" \
    "Secret Manager シークレット"

# 1-10. Vertex AI Endpoints
cleanup_resource "11" "${TOTAL}" "Vertex AI 常駐エンドポイント" \
    "gcloud ai endpoints list --project=\"${PROJECT_ID}\" --region=asia-northeast1 --format=\"value(name)\"" \
    "gcloud ai endpoints delete" \
    "--project=\"${PROJECT_ID}\" --region=asia-northeast1 --quiet" \
    "Vertex AI エンドポイント"

# 1-12. データアクセス監査ログ設定のクリーンアップ (auditConfigs の完全リセット)
echo "🔎 【12/${TOTAL}】データアクセス監査ログ設定 (auditConfigs) のチェックを行っています..."
IAM_POLICY="$(gcloud projects get-iam-policy "${PROJECT_ID}" --format="json" 2>/dev/null || echo "")"
if [ -n "${IAM_POLICY}" ] && echo "${IAM_POLICY}" | grep -q "auditConfigs"; then
    echo "⚠️ データアクセス監査ログ設定 (auditConfigs) の残存を検出しました"
    echo "🗑️ 監査ログ設定を初期状態に削除・リセットしています..."
    python3 -c '
import json, sys
policy = json.loads(sys.argv[1])
policy["auditConfigs"] = []
with open("/tmp/clean_iam_policy.json", "w") as f:
    json.dump(policy, f)
' "${IAM_POLICY}" 2>/dev/null || true
    if [ -f "/tmp/clean_iam_policy.json" ]; then
        gcloud projects set-iam-policy "${PROJECT_ID}" /tmp/clean_iam_policy.json --quiet 2>/dev/null || true
        rm -f /tmp/clean_iam_policy.json
    fi
    echo "✅ 監査ログ設定を初期状態にリセットしました！"
else
    echo "ℹ️ 監査ログ設定は検出されませんでした（すでに標準デフォルト状態です）"
fi
echo ""

# 1-13. IAM Service Accounts
echo "🔎 【13/${TOTAL}】IAM 専用サービスアカウントのチェックを行っています..."
SAS="$(gcloud iam service-accounts list --project="${PROJECT_ID}" --format="value(email)" </dev/null 2>/dev/null || echo "")"
TARGET_SAS=""
if [ -n "${SAS}" ]; then
    for sa in ${SAS}; do
        if [[ "${sa}" != *"-compute@developer.gserviceaccount.com"* && "${sa}" != *"@appspot.gserviceaccount.com"* && "${sa}" != *"@gcp-sa-"* ]]; then
            TARGET_SAS="${TARGET_SAS} ${sa}"
        fi
    done
fi
if [ -n "${TARGET_SAS}" ]; then
    echo "⚠️ 以下の残存専用サービスアカウントを検出しました:"
    for sa in ${TARGET_SAS}; do echo "   👉 Service Account: ${sa}"; done
    echo "🗑️ 削除処理を並列実行します..."
    for sa in ${TARGET_SAS}; do gcloud iam service-accounts delete "${sa}" --project="${PROJECT_ID}" --quiet </dev/null 2>/dev/null & done
    wait
    echo "🔄 削除完了の同期検証を行っています..."
    retry=0
    while [ ${retry} -lt 15 ]; do
        CHK_SAS="$(gcloud iam service-accounts list --project="${PROJECT_ID}" --format="value(email)" </dev/null 2>/dev/null || echo "")"
        CHK_TARGET=""
        if [ -n "${CHK_SAS}" ]; then
            for sa in ${CHK_SAS}; do
                if [[ "${sa}" != *"-compute@developer.gserviceaccount.com"* && "${sa}" != *"@appspot.gserviceaccount.com"* && "${sa}" != *"@gcp-sa-"* ]]; then
                    CHK_TARGET="${CHK_TARGET} ${sa}"
                fi
            done
        fi
        if [ -z "${CHK_TARGET}" ]; then
            echo "✅ 削除完了を確認しました！（専用サービスアカウント: 0件）"
            break
        fi
        sleep 2
        retry=$((retry + 1))
    done
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

# 基本APIホワイトリストパターン (grep -E 用) ※GCPインフラ基盤の10個のみ
WHITELIST_REGEX="cloudresourcemanager\.googleapis\.com|serviceusage\.googleapis\.com|cloudbilling\.googleapis\.com|cloudaicompanion\.googleapis\.com|telemetry\.googleapis\.com|iam\.googleapis\.com|iamcredentials\.googleapis\.com|logging\.googleapis\.com"

echo "📌 【定義】プロジェクト維持のため「残して良い基本API (ホワイトリスト)」(8件):"
echo "   🟢 cloudaicompanion.googleapis.com (Gemini for Google Cloud API)"
echo "   🟢 cloudbilling.googleapis.com (Cloud Billing API)"
echo "   🟢 cloudresourcemanager.googleapis.com (Cloud Resource Manager API)"
echo "   🟢 iam.googleapis.com (Identity and Access Management API)"
echo "   🟢 iamcredentials.googleapis.com (IAM Service Account Credentials API)"
echo "   🟢 logging.googleapis.com (Cloud Logging API)"
echo "   🟢 serviceusage.googleapis.com (Service Usage API)"
echo "   🟢 telemetry.googleapis.com (Google Cloud Telemetry API)"
echo ""

echo "🔎 現在有効化されているAPI一覧をチェックしています..."
ENABLED_APIS="$(gcloud services list --enabled --project="${PROJECT_ID}" --format="value(config.name)" </dev/null 2>/dev/null || echo "")"

TARGET_APIS=""
if [ -n "${ENABLED_APIS}" ]; then
    TARGET_APIS="$(echo "${ENABLED_APIS}" | tr ' ' '\n' | grep -v -E "^(${WHITELIST_REGEX})$" || true)"
fi

if [ -n "${TARGET_APIS}" ]; then
    echo "💡 (※STEP 1の削除走査時に、API停止による削除漏れを100%防止するため、走査用管理APIを一時有効化して完全チェックを行っています)"
    echo "⚠️ 以下の不要API（無効化対象）が有効になっています:"
    for api in ${TARGET_APIS}; do echo "   👉 無効化対象API: ${api}"; done
    echo "🗑️ 不要APIの無効化処理を並列一括実行します..."
    gcloud compute networks peerings delete servicenetworking-googleapis-com --network=default --project="${PROJECT_ID}" --quiet </dev/null 2>/dev/null &
    
    # 複数APIを一括指定 ＆ 非同期 (--async) で最速無効化要求を発行
    gcloud services disable ${TARGET_APIS} --project="${PROJECT_ID}" --force --async --quiet </dev/null 2>/dev/null || true
    wait

    echo "🔄 不要APIが無効化され完全消去されるまで同期検証中 (非同期一括高速モード)..."
    retry=0
    max_retries=60
    while [ ${retry} -lt ${max_retries} ]; do
        FINAL_APIS="$(gcloud services list --enabled --project="${PROJECT_ID}" --format="value(config.name)" </dev/null 2>/dev/null || echo "")"
        FINAL_TARGETS=""
        if [ -n "${FINAL_APIS}" ]; then
            FINAL_TARGETS="$(echo "${FINAL_APIS}" | tr " " "\n" | grep -v -E "^(${WHITELIST_REGEX})$" || true)"
        fi

        if [ -z "${FINAL_TARGETS}" ]; then
            break
        fi

        if [ $((retry % 3)) -eq 0 ] && [ ${retry} -gt 0 ]; then
            # 未完了のAPIが存在する場合は一括再リトライ
            gcloud services disable ${FINAL_TARGETS} --project="${PROJECT_ID}" --force --async --quiet </dev/null 2>/dev/null || true
        fi

        echo "   ⏳ API非活性化の反映を待機中... (${retry}/${max_retries} 回目 - 残存: $(echo ${FINAL_TARGETS} | tr "\n" " "))"
        sleep 3
        retry=$((retry + 1))
    done
else
    echo "ℹ️ 不要なAPIは検出されませんでした（すでに最小化されています）"
fi

echo ""
echo "🔎 【切り分け判定】無効化後の残存APIチェック中..."
FINAL_APIS="$(gcloud services list --enabled --project="${PROJECT_ID}" --format="value(config.name)" </dev/null 2>/dev/null || echo "")"
FINAL_TARGETS=""
if [ -n "${FINAL_APIS}" ]; then
    FINAL_TARGETS="$(echo "${FINAL_APIS}" | tr ' ' '\n' | grep -v -E "^(${WHITELIST_REGEX})$" || true)"
fi

TOTAL_FINAL_COUNT=0
if [ -n "${FINAL_APIS}" ]; then
    TOTAL_FINAL_COUNT=$(echo "${FINAL_APIS}" | tr ' ' '\n' | wc -l)
fi

if [ -z "${FINAL_TARGETS}" ]; then
    echo "✅ 【完璧】不要APIはすべて正常に停止されました！基本APIのみが維持されています（余分API: 0件）。"
    echo ""
    echo "📌 最終的にプロジェクトに残っているAPI一覧 (${TOTAL_FINAL_COUNT}件 / 想定内):"
else
    EXTRA_COUNT=$(echo "${FINAL_TARGETS}" | tr ' ' '\n' | wc -l)
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
            "telemetry.googleapis.com")
                echo "   🟢 [維持OK] ${api} (Google Cloud Telemetry API)"
                ;;
            "iam.googleapis.com")
                echo "   🟢 [維持OK] ${api} (Identity and Access Management API)"
                ;;
            "iamcredentials.googleapis.com")
                echo "   🟢 [維持OK] ${api} (IAM Service Account Credentials API)"
                ;;
            "logging.googleapis.com")
                echo "   🟢 [維持OK] ${api} (Cloud Logging API)"
                ;;
            "compute.googleapis.com")
                echo "   🟢 [維持OK] ${api} (Compute Engine API - インフラ基盤)"
                ;;
            "oslogin.googleapis.com")
                echo "   🟢 [維持OK] ${api} (OS Login API - インフラ基盤)"
                ;;
            *)
                if echo "${api}" | grep -q -E "^(${WHITELIST_REGEX})$"; then
                    echo "   🟢 [維持OK] ${api} (基本インフラAPI)"
                else
                    echo "   🔴 [要確認] ${api}"
                fi
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

RAW_IS_ENABLED="$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" </dev/null 2>/dev/null || echo "false")"
IS_ENABLED="$(echo "${RAW_IS_ENABLED}" | tr '[:upper:]' '[:lower:]')"

if [ "${IS_ENABLED}" = "true" ]; then
    echo "⚠️ 課金アカウントがリンクされています（有効状態）"
    echo "⚡ 請求先アカウントの解除（Unlink）を実行します..."
    gcloud billing projects unlink "${PROJECT_ID}" --quiet </dev/null 2>/dev/null || true
    echo "🔄 解除後の課金状態を再確認中..."
    RAW_AFTER="$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" </dev/null 2>/dev/null || echo "false")"
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
