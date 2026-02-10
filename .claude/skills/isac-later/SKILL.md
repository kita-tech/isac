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

このスキルは `/isac-todo add "タスク内容"` と同じ動作をします。

**処理手順:**

1. 入力内容をsensitive-filterでチェック
2. 機密情報が含まれる場合は警告を表示
3. Memory Serviceに `type: todo` として保存

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

```bash
# プロジェクトIDとユーザーを取得
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "default")
USER_EMAIL=$(git config user.email || echo "${USER:-unknown}")
TASK_CONTENT="$1"  # 引数からタスク内容を取得

# sensitive-filterでチェック（プロジェクトルートからの相対パス）
FILTER_RESULT=$(echo "$TASK_CONTENT" | bash .claude/hooks/sensitive-filter.sh 2>/dev/null)
IS_SENSITIVE=$(echo "$FILTER_RESULT" | jq -r '.is_sensitive')

if [ "$IS_SENSITIVE" = "true" ]; then
    DETECTED=$(echo "$FILTER_RESULT" | jq -r '.detected | join(", ")')
    echo "⚠️ 機密情報が検出されました: $DETECTED"
    echo "このタスクを保存しますか？"
    # ユーザーに確認
fi

# Memory Serviceに保存
curl -s -X POST "${MEMORY_SERVICE_URL:-http://localhost:8100}/store" \
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
    }')"

echo "✅ タスクを追加しました"
echo ""
echo "「$TASK_CONTENT」"
echo ""
echo "/isac-todo list で一覧を確認できます。"
```

## 関連スキル

- `/isac-todo` - タスク管理（add/list/done）
- `/isac-suggest` - 未完了タスクも表示される
