---
name: isac-todo
description: 個人の未完了タスクを管理します。翌日の作業継続に便利です。
---

# ISAC Todo Skill

個人の未完了タスクを管理します。「後でやる」タスクを記録し、翌日に続きから作業できます。

## 使い方

```
/isac-todo add "タスク内容"    # タスクを追加
/isac-todo list                # 未完了タスク一覧
/isac-todo done <番号>         # タスクを完了
/isac-todo clear               # 完了済みを削除
```

## サブコマンド

### add - タスクを追加

```
/isac-todo add "Skillsのテスト追加"
```

**処理手順:**

1. 入力内容をsensitive-filterでチェック
2. 機密情報が含まれる場合は警告を表示し、保存を中止するか確認
3. Memory Serviceに保存

**sensitive-filterチェック:**

```bash
# ~/.isac/hooks/sensitive-filter.sh を使用
FILTER_RESULT=$(echo "タスク内容" | bash ~/.isac/hooks/sensitive-filter.sh 2>/dev/null)
IS_SENSITIVE=$(echo "$FILTER_RESULT" | jq -r '.is_sensitive')
DETECTED=$(echo "$FILTER_RESULT" | jq -r '.detected | join(", ")')

if [ "$IS_SENSITIVE" = "true" ]; then
    echo "⚠️ 機密情報が検出されました: $DETECTED"
    echo "このタスクを保存しますか？機密情報はマスキングされません。"
    # ユーザーに確認を求める
fi
```

**保存するデータ:**

```json
{
  "content": "タスク内容",
  "type": "todo",
  "scope": "project",
  "scope_id": "<現在のプロジェクトID>",
  "importance": 0.5,
  "metadata": {
    "owner": "<git config user.email>",
    "status": "pending",
    "created_at": "<ISO8601>"
  }
}
```

**実行コマンド:**

```bash
# プロジェクトIDとユーザーを取得
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "default")
USER_EMAIL=$(git config user.email || echo "${USER:-unknown}")

# sensitive-filterでチェック
FILTER_RESULT=$(echo "タスク内容" | bash ~/.isac/hooks/sensitive-filter.sh)
IS_SENSITIVE=$(echo "$FILTER_RESULT" | jq -r '.is_sensitive')

if [ "$IS_SENSITIVE" = "true" ]; then
    echo "⚠️ 機密情報が検出されました。マスキングして保存しますか？"
    # ユーザー確認後、マスキング済みテキストを使用
fi

# Memory Serviceに保存
curl -s -X POST "${MEMORY_SERVICE_URL:-http://localhost:8100}/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "タスク内容" \
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
```

### list - 未完了タスク一覧

```
/isac-todo list
```

**処理手順:**

1. Memory Serviceから自分のpending todoを取得
2. 番号付きで表示

**実行コマンド:**

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "default")
USER_EMAIL=$(git config user.email || echo "${USER:-unknown}")

# /my/todos APIを使用（直接パイプで処理、変数代入時の文字化け回避）
curl -s "${MEMORY_SERVICE_URL:-http://localhost:8100}/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=pending" \
  | jq -r '.todos | to_entries | .[] | "\(.key + 1). [ ] \(.value.content | split("\n")[0] | .[0:60]) (ID: \(.value.id))"'
```

**出力例:**

```
## 📋 未完了タスク

1. [ ] Skillsのテスト追加 (ID: abc123)
2. [ ] isac doctorコマンド実装 (ID: def456)

合計: 2件
```

### done - タスクを完了

```
/isac-todo done 1
```

**処理手順:**

1. 番号からIDを特定
2. metadata.statusを "done" に更新

**実行コマンド:**

```bash
# まずlistで対象のIDを取得してから
MEMORY_ID="abc123"  # listで取得したID

# statusを更新（Memory ServiceのAPIで更新）
curl -s -X PATCH "${MEMORY_SERVICE_URL:-http://localhost:8100}/memory/$MEMORY_ID" \
  -H "Content-Type: application/json" \
  -d '{"metadata": {"status": "done", "completed_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}}'
```

### clear - 完了済みを削除

```
/isac-todo clear
```

完了済み（status: done）のタスクを削除します。

## 出力フォーマット

### add成功時

```
✅ タスクを追加しました

「Skillsのテスト追加」

/isac-todo list で一覧を確認できます。
```

### list結果

```
## 📋 未完了タスク（isacプロジェクト）

1. [ ] Skillsのテスト追加
2. [ ] isac doctorコマンド実装

---
合計: 2件
完了するには: /isac-todo done <番号>
```

### done成功時

```
✅ タスクを完了しました

「Skillsのテスト追加」

残り: 1件
```

### タスクがない場合

```
## 📋 未完了タスク

タスクはありません。

追加するには: /isac-todo add "タスク内容"
または: /isac-later "タスク内容"
```

## エイリアス

| エイリアス | 展開先 |
|-----------|--------|
| `/isac-later "内容"` | `/isac-todo add "内容"` |

## 注意事項

### owner は自動設定（手動変更禁止）

`metadata.owner` には `git config user.email` の値を自動設定する。
以下のような手動設定は**禁止**:

```bash
# NG: 手動で別の値を設定
metadata: { owner: "team", ... }
metadata: { owner: "shared", ... }
metadata: { owner: "other-user@example.com", ... }
```

### チーム共有タスクは Todo に入れない

チームで共有すべき課題・バックログは以下を使用:

| 用途 | 保存先 |
|------|--------|
| 個人の「後でやる」タスク | `/isac-todo` |
| チームの技術的課題 | `/isac-decide`（type: decision） |
| チームのバックログ | GitHub Issues |

## 関連スキル

- `/isac-suggest` - 未完了タスクも表示される
- `/isac-memory` - 記憶の検索・管理
- `/isac-decide` - 決定の記録
