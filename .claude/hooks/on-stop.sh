#!/bin/bash
# on-stop.sh
# タスク完了時にClaudeが作業内容を分類し、Memory Serviceに保存
#
# Hook Type: prompt（Claudeに分類を依頼）
# Event: Stop
#
# 使用方法:
#   settings.yaml で以下のように設定:
#   hooks:
#     Stop:
#       - type: prompt
#         prompt_file: .claude/hooks/on-stop.sh
#
# 出力形式:
#   Claudeが以下のJSON形式で出力し、後続処理でMemory Serviceに保存

set -e

# 環境変数
ISAC_GLOBAL_DIR="${ISAC_GLOBAL_DIR:-$HOME/.isac}"
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# グローバル設定からMemory URLを取得
if [ -z "${MEMORY_SERVICE_URL:-}" ] && [ -f "${ISAC_GLOBAL_DIR}/config.yaml" ]; then
    CONFIGURED_URL=$(grep -E "^memory_service_url:" "${ISAC_GLOBAL_DIR}/config.yaml" 2>/dev/null | sed 's/memory_service_url:[[:space:]]*//' | tr -d '"' || true)
    if [ -n "$CONFIGURED_URL" ]; then
        MEMORY_URL="$CONFIGURED_URL"
    fi
fi

# Memory Serviceが起動していない場合はスキップ
if ! curl -s --connect-timeout 1 "$MEMORY_URL/health" > /dev/null 2>&1; then
    exit 0
fi

# プロジェクトIDを解決
PROJECT_ID="default"
TEAM_ID=""
if [ -f "$SCRIPT_DIR/resolve-project.sh" ]; then
    RESOLVE_RESULT=$(bash "$SCRIPT_DIR/resolve-project.sh" 2>/dev/null || echo '{"project_id":"default","team_id":""}')
    PROJECT_ID=$(echo "$RESOLVE_RESULT" | jq -r '.project_id // "default"' 2>/dev/null || echo "default")
    TEAM_ID=$(echo "$RESOLVE_RESULT" | jq -r '.team_id // ""' 2>/dev/null || echo "")
fi

# ユーザー情報取得
USER_ID=$(git config user.email 2>/dev/null || echo "${USER:-unknown}")

# Claudeへの分類リクエスト（prompt typeで使用）
cat << 'PROMPT_EOF'
今回のタスクが完了しました。作業内容を分析し、Memory Serviceに保存するための分類を行ってください。

【重要】タスクが些細な作業（1回の簡単な質問への回答、typo修正など）の場合は、
"skip": true を設定して記録をスキップしてください。

以下のJSON形式で出力してください（```json と ``` で囲んでください）:

```json
{
  "skip": false,
  "type": "work|decision|knowledge",
  "category": "backend|frontend|infra|security|database|api|ui|test|docs|architecture|other",
  "tags": ["タグ1", "タグ2"],
  "summary": "作業内容の1行要約（50文字以内）",
  "importance": 0.5
}
```

【分類ガイドライン】

■ type（記憶タイプ）:
- decision: 技術選定、設計方針、アーキテクチャ決定など重要な判断
- work: 実装作業、バグ修正、リファクタリングなど日常的な作業
- knowledge: 学習した知見、ベストプラクティス、チームで共有すべき情報

■ category（カテゴリ）:
- backend: サーバーサイド、API実装、データ処理
- frontend: UI/UX、クライアントサイド、Webアプリ
- infra: インフラ、CI/CD、Docker、デプロイ
- security: 認証、認可、セキュリティ対策
- database: DB設計、マイグレーション、クエリ最適化
- api: API設計、エンドポイント、OpenAPI
- ui: コンポーネント、スタイリング、レスポンシブ
- test: テスト、品質保証、カバレッジ
- docs: ドキュメント、README、コメント
- architecture: 全体設計、パターン、構造決定
- other: 上記に当てはまらないもの

■ tags（タグ）:
- 使用した技術やフレームワーク（例: python, react, fastapi）
- 作業の種類（例: bugfix, refactor, feature）
- 対象ドメイン（例: auth, payment, user）
- 最大5個まで

■ importance（重要度 0.0-1.0）:
- 0.9-1.0: 長期的に参照すべき重要な決定
- 0.6-0.8: チームで共有すべき知見
- 0.3-0.5: 通常の作業記録
- 0.1-0.2: 軽微な変更

■ skip（スキップ判定）:
以下の場合は "skip": true を設定:
- 簡単な質問への回答のみ
- 1行程度のtypo修正
- 情報の確認のみで変更なし
- テスト目的の一時的な作業
PROMPT_EOF

# 環境情報を追記（後続処理で使用）
cat << EOF

---
【環境情報】
project_id: ${PROJECT_ID}
team_id: ${TEAM_ID}
user_id: ${USER_ID}
memory_url: ${MEMORY_URL}
EOF
