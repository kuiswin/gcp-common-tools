# GCP Common Tools (Google Cloud プロビジョニング＆クリーンアップ共通ツール)

Google Cloud ハンズオン・連載記事（170〜174シリーズ）全共通で利用可能な、環境自動プロビジョニングおよび一括クリーンアップ用のシェルスクリプト集です。

---

## 🚀 収録スクリプト一覧

### 1. `pre_flight.sh` （事前チェック ＆ プロビジョニング）
ハンズオン開始時に実行します。
* プロジェクトの自動判定・確定
* 利用可能な有効請求先アカウントの自動特定 ＆ リンク
* 基本APIサービスの有効化
* プロジェクト内既存リソースの事前目視チェック

```bash
# 基本使用法（Gitワンライナー実行）
curl -sSL "https://raw.githubusercontent.com/kuiswin/gcp-common-tools/main/pre_flight.sh?$(date +%s)" | bash
```

```bash
# 環境変数を指定して実行する場合
export KEYWORD="abcde"
export ARTICLE_ID="171"
export PROJECT_ID="ferrous-iridium-286000" # 手動固定したい場合のみ指定

curl -sSL "https://raw.githubusercontent.com/kuiswin/gcp-common-tools/main/pre_flight.sh?$(date +%s)" | bash
```

---

### 2. `teardown.sh` （全サービス一括クリーンアップ ＆ 0円休眠）
ハンズオン終了時に実行します。
* 5記事（Pub/Sub, Cloud Run, GCS, Spanner, AlloyDB, BigQuery, Artifact Registry, IAM SA等）で作成されるすべてのリソースを一括全自動削除
* 「存在するものは削除、無いものは安全にスキップ」の安全設計
* 課金アカウントの自動解除（Unlink） ＆ APIサービスの全自動無効化による0円完全休眠

```bash
# 基本使用法（Gitワンライナー実行）
curl -sSL "https://raw.githubusercontent.com/kuiswin/gcp-common-tools/main/teardown.sh?$(date +%s)" | bash
```

---

## 💡 観点別チェック機能の構成

事前・事後のそれぞれのフェーズにおいて、以下の3つの観点（計6パターン）を総合的にチェック・制御します。

1. **環境・課金サービス観点**
   - 事前: 請求先アカウントの紐付け確認・実行
   - 事後: 請求先アカウントの安全な解除（Unlink）
2. **APIサービス観点**
   - 事前: 必須基本APIの有効化 ＆ 確認
   - 事後: 使ったAPIの全自動停止 ＆ 停止確認
3. **個別サービス・リソース観点**
   - 事前: 既存残存リソースの目視チェック
   - 事後: 各記事特有リソース（Pub/Sub, Cloud Run, GCS, Spanner, AlloyDB, BigQuery等）の安全一括削除
