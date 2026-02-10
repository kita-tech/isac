---
name: isac-later
description: 「後でやる」タスクを素早く記録します。/isac-todo add のエイリアスです。
---

# ISAC Later Skill

「後でやる」タスクを素早く記録します。`/isac-todo add` のショートカットです。

## 使い方

```
/isac-later "タスク内容"
```

## 動作

このスキルは `/isac-todo add "タスク内容"` と完全に同じ動作をします。

**処理手順:**

1. Memory Service の接続を確認（`/isac-todo` の「共通: Memory Service 接続確認」と同一）
2. 入力内容を sensitive-filter でチェック
3. 機密情報が含まれる場合:
   - **ユーザーが「マスキングして保存」を選択**: `filtered` フィールドのマスキング済みテキストで保存
   - **ユーザーが「保存を中止」を選択**: 保存せずに終了
4. Memory Service に `type: todo` として保存
5. 保存結果を確認（成功/失敗を表示）

## 実行例

```
/isac-later "Skillsのテスト追加"
```

**出力:**

```
✅ タスクを追加しました

「Skillsのテスト追加」

/isac-todo list で一覧を確認できます。
```

## 実行コマンド

`/isac-todo add` と完全に同じ処理です。詳細は `/isac-todo` SKILL.md の `add` セクションを参照してください。

```bash
# プロジェクトIDとユーザーを取得
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "default")
USER_EMAIL=$(git config user.email || echo "${USER:-unknown}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"
TASK_CONTENT="$1"  # 引数からタスク内容を取得

# Memory Service 接続確認（/isac-todo「共通: Memory Service 接続確認」と同一）
if ! curl -s --max-time 3 "$MEMORY_URL/health" > /dev/null 2>&1; then
    echo "❌ Memory Service に接続できません（$MEMORY_URL）"
    echo ""
    echo "確認事項:"
    echo "  - Docker が起動しているか: docker ps"
    echo "  - Memory Service が起動しているか: docker compose -f memory-service/docker-compose.yml up -d"
    echo ""
    echo "Memory Service を起動してから再実行してください。"
    exit 1
fi

# sensitive-filter でチェック（プロジェクトルートからの相対パス）
FILTER_RESULT=$(echo "$TASK_CONTENT" | bash .claude/hooks/sensitive-filter.sh 2>/dev/null)
IS_SENSITIVE=$(echo "$FILTER_RESULT" | jq -r '.is_sensitive')

if [ "$IS_SENSITIVE" = "true" ]; then
    DETECTED=$(echo "$FILTER_RESULT" | jq -r '.detected | join(", ")')
    FILTERED_TEXT=$(echo "$FILTER_RESULT" | jq -r '.filtered')
    echo "⚠️ 機密情報が検出されました: $DETECTED"
    echo ""
    echo "選択肢:"
    echo "  1. マスキングして保存（マスキング後: $FILTERED_TEXT）"
    echo "  2. 保存を中止"
    # ユーザーの選択を確認
    # → 1 の場合: TASK_CONTENT="$FILTERED_TEXT"
    # → 2 の場合: echo "保存を中止しました。" && exit 0
fi

# Memory Service に保存
RESPONSE=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "$TASK_CONTENT" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$USER_EMAIL" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      importance: 0.5,
      metadata: {
        owner: $owner,
        status: "pending",
        created_at: $created_at
      }
    }')")

# 保存結果の確認
if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    echo "✅ タスクを追加しました"
    echo ""
    echo "「$TASK_CONTENT」"
    echo ""
    echo "/isac-todo list で一覧を確認できます。"
else
    echo "❌ タスクの保存に失敗しました"
    echo "$RESPONSE"
fi
```

## 関連スキル

- `/isac-todo` - タスク管理（add/list/done/clear）
- `/isac-suggest` - 未完了タスクも表示される
- `/isac-memory` - 記憶の検索・管理
