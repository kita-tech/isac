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
/isac-todo clear               # 完了済みを廃止（deprecate）
```

## 共通: Memory Service 接続確認

全サブコマンドの実行前に、Memory Service の接続を確認する。

```bash
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# 接続確認（3秒タイムアウト）
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
```

## サブコマンド

### add - タスクを追加

```
/isac-todo add "Skillsのテスト追加"
```

**処理手順:**

1. Memory Service の接続を確認（共通処理）
2. 入力内容を sensitive-filter でチェック
3. 機密情報が含まれる場合:
   - **ユーザーが「マスキングして保存」を選択**: `filtered` フィールドのマスキング済みテキストで保存
   - **ユーザーが「保存を中止」を選択**: 保存せずに終了
4. Memory Service に保存

**sensitive-filter チェック:**

```bash
# .claude/hooks/sensitive-filter.sh を使用（プロジェクトルートからの相対パス）
FILTER_RESULT=$(echo "タスク内容" | bash .claude/hooks/sensitive-filter.sh 2>/dev/null)
IS_SENSITIVE=$(echo "$FILTER_RESULT" | jq -r '.is_sensitive')
DETECTED=$(echo "$FILTER_RESULT" | jq -r '.detected | join(", ")')
FILTERED_TEXT=$(echo "$FILTER_RESULT" | jq -r '.filtered')

if [ "$IS_SENSITIVE" = "true" ]; then
    echo "⚠️ 機密情報が検出されました: $DETECTED"
    echo ""
    echo "選択肢:"
    echo "  1. マスキングして保存（マスキング後: $FILTERED_TEXT）"
    echo "  2. 保存を中止"
    # ユーザーに確認を求める
    # → 1 の場合: TASK_CONTENT="$FILTERED_TEXT" として保存処理に進む
    # → 2 の場合: 「保存を中止しました。」と表示して終了
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
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"
TASK_CONTENT="タスク内容"

# Memory Service 接続確認
if ! curl -s --max-time 3 "$MEMORY_URL/health" > /dev/null 2>&1; then
    echo "❌ Memory Service に接続できません（$MEMORY_URL）"
    echo "Docker が起動しているか確認してください: docker compose -f memory-service/docker-compose.yml up -d"
    exit 1
fi

# sensitive-filter でチェック
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
else
    echo "❌ タスクの保存に失敗しました"
    echo "$RESPONSE"
fi
```

### list - 未完了タスク一覧

```
/isac-todo list
```

**処理手順:**

1. Memory Service の接続を確認（共通処理）
2. Memory Service から自分の pending todo を取得
3. 0件の場合は「タスクはありません」と表示
4. 1件以上の場合は番号付き・ID付きで表示

**実行コマンド:**

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "default")
USER_EMAIL=$(git config user.email || echo "${USER:-unknown}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認
if ! curl -s --max-time 3 "$MEMORY_URL/health" > /dev/null 2>&1; then
    echo "❌ Memory Service に接続できません（$MEMORY_URL）"
    echo "Docker が起動しているか確認してください: docker compose -f memory-service/docker-compose.yml up -d"
    exit 1
fi

# /my/todos API を使用（直接パイプで処理、変数代入時の文字化け回避）
RESULT=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=pending")
COUNT=$(echo "$RESULT" | jq -r '.count')

if [ "$COUNT" = "0" ] || [ -z "$COUNT" ] || [ "$COUNT" = "null" ]; then
    echo "## 📋 未完了タスク"
    echo ""
    echo "タスクはありません。"
    echo ""
    echo "追加するには: /isac-todo add \"タスク内容\""
    echo "または: /isac-later \"タスク内容\""
else
    echo "## 📋 未完了タスク（${PROJECT_ID}プロジェクト）"
    echo ""
    echo "$RESULT" | jq -r '.todos | to_entries | .[] | "\(.key + 1). [ ] \(.value.content | split("\n")[0] | .[0:60]) (ID: \(.value.id))"'
    echo ""
    echo "---"
    echo "合計: ${COUNT}件"
    echo "完了するには: /isac-todo done <番号>"
fi
```

**出力例:**

```
## 📋 未完了タスク（isacプロジェクト）

1. [ ] Skillsのテスト追加 (ID: abc123)
2. [ ] isac doctorコマンド実装 (ID: def456)

---
合計: 2件
完了するには: /isac-todo done <番号>
```

### done - タスクを完了

```
/isac-todo done 1
```

**処理手順:**

1. Memory Service の接続を確認（共通処理）
2. `/my/todos` API で pending タスク一覧を取得（list と同じ）
3. 指定された番号でインデックスし、対応する ID を特定
4. 番号が範囲外の場合はエラーを表示
5. `PATCH /memory/{id}` で metadata.status を "done" に更新
6. 更新後、残りの pending タスク件数を取得して表示

**実行コマンド:**

```bash
TARGET_NUM=1  # ユーザーが指定した番号
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "default")
USER_EMAIL=$(git config user.email || echo "${USER:-unknown}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認
if ! curl -s --max-time 3 "$MEMORY_URL/health" > /dev/null 2>&1; then
    echo "❌ Memory Service に接続できません（$MEMORY_URL）"
    echo "Docker が起動しているか確認してください: docker compose -f memory-service/docker-compose.yml up -d"
    exit 1
fi

# pending タスク一覧を取得
RESULT=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=pending")
COUNT=$(echo "$RESULT" | jq -r '.count')

# 番号の範囲チェック
if [ "$TARGET_NUM" -lt 1 ] || [ "$TARGET_NUM" -gt "$COUNT" ] 2>/dev/null; then
    echo "❌ 番号が範囲外です（1〜${COUNT}の範囲で指定してください）"
    echo ""
    echo "/isac-todo list で一覧を確認してください。"
    exit 1
fi

# 番号からIDを特定（0-indexed に変換）
INDEX=$((TARGET_NUM - 1))
MEMORY_ID=$(echo "$RESULT" | jq -r ".todos[$INDEX].id")
TASK_CONTENT=$(echo "$RESULT" | jq -r ".todos[$INDEX].content | split(\"\n\")[0] | .[0:60]")

# status を更新
RESPONSE=$(curl -s -X PATCH "$MEMORY_URL/memory/$MEMORY_ID" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{metadata: {status: "done", completed_at: $completed_at}}')")

# 更新結果の確認
if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    # 残件数を取得
    REMAINING=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=pending" | jq -r '.count')
    echo "✅ タスクを完了しました"
    echo ""
    echo "「$TASK_CONTENT」"
    echo ""
    echo "残り: ${REMAINING}件"
else
    echo "❌ タスクの完了処理に失敗しました"
    echo "$RESPONSE"
fi
```

### clear - 完了済みを廃止

```
/isac-todo clear
```

完了済み（status: done）のタスクを廃止（deprecate）します。

**注意**: Memory Service に物理削除用の DELETE API は使用せず、`PATCH /memory/{id}/deprecate` で廃止扱いにします。廃止された記憶は検索結果から除外されますが、`include_deprecated=true` で履歴として参照でき、必要に応じて復元も可能です。

**処理手順:**

1. Memory Service の接続を確認（共通処理）
2. `/my/todos` API で自分の owner かつ status=done のタスクを取得
3. 対象が0件の場合は「完了済みタスクはありません」と表示して終了
4. 件数と対象タスク一覧を表示し、ユーザーに確認
5. ユーザーが確認後、各タスクを `PATCH /memory/{id}/deprecate` で廃止
6. 結果を表示

**実行コマンド:**

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "default")
USER_EMAIL=$(git config user.email || echo "${USER:-unknown}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認
if ! curl -s --max-time 3 "$MEMORY_URL/health" > /dev/null 2>&1; then
    echo "❌ Memory Service に接続できません（$MEMORY_URL）"
    echo "Docker が起動しているか確認してください: docker compose -f memory-service/docker-compose.yml up -d"
    exit 1
fi

# 完了済みタスクを取得（自分の owner かつ status=done）
RESULT=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=done")
COUNT=$(echo "$RESULT" | jq -r '.count')

# 0件チェック
if [ "$COUNT" = "0" ] || [ -z "$COUNT" ] || [ "$COUNT" = "null" ]; then
    echo "完了済みタスクはありません。"
    exit 0
fi

# 対象一覧を表示してユーザーに確認
echo "以下の完了済みタスク ${COUNT}件 を廃止します:"
echo ""
echo "$RESULT" | jq -r '.todos | to_entries | .[] | "  \(.key + 1). [x] \(.value.content | split("\n")[0] | .[0:60]) (ID: \(.value.id))"'
echo ""
echo "※ 廃止されたタスクは検索結果から除外されますが、履歴として残ります。"
# ユーザーに確認を求める（「実行しますか？ y/n」）
# → n の場合: echo "キャンセルしました。" && exit 0

# 各タスクを deprecate
SUCCESS_COUNT=0
FAIL_COUNT=0
for ID in $(echo "$RESULT" | jq -r '.todos[].id'); do
    RESP=$(curl -s -X PATCH "$MEMORY_URL/memory/$ID/deprecate" \
      -H "Content-Type: application/json" \
      -d '{"deprecated": true}')
    if echo "$RESP" | jq -e '.id' > /dev/null 2>&1; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo "🧹 完了済みタスクを廃止しました: ${SUCCESS_COUNT}件"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "⚠️ 廃止に失敗: ${FAIL_COUNT}件"
fi
```

## 出力フォーマット

### add 成功時

```
✅ タスクを追加しました

「Skillsのテスト追加」

/isac-todo list で一覧を確認できます。
```

### add 機密情報検出時

```
⚠️ 機密情報が検出されました: api_key, password

選択肢:
  1. マスキングして保存（マスキング後: [MASKED:api_key] の設定を変更する）
  2. 保存を中止
```

### list 結果

```
## 📋 未完了タスク（isacプロジェクト）

1. [ ] Skillsのテスト追加 (ID: abc123)
2. [ ] isac doctorコマンド実装 (ID: def456)

---
合計: 2件
完了するには: /isac-todo done <番号>
```

### done 成功時

```
✅ タスクを完了しました

「Skillsのテスト追加」

残り: 1件
```

### done 完了失敗時

```
❌ タスクの完了処理に失敗しました
```

### done 番号範囲外エラー

```
❌ 番号が範囲外です（1〜2の範囲で指定してください）

/isac-todo list で一覧を確認してください。
```

### clear 成功時

```
以下の完了済みタスク 3件 を廃止します:

  1. [x] Skillsのテスト追加 (ID: abc123)
  2. [x] isac doctorコマンド実装 (ID: def456)
  3. [x] READMEの更新 (ID: ghi789)

※ 廃止されたタスクは検索結果から除外されますが、履歴として残ります。

🧹 完了済みタスクを廃止しました: 3件
```

### clear 対象なし

```
完了済みタスクはありません。
```

### タスクがない場合

```
## 📋 未完了タスク

タスクはありません。

追加するには: /isac-todo add "タスク内容"
または: /isac-later "タスク内容"
```

### Memory Service 未接続時（全サブコマンド共通）

```
❌ Memory Service に接続できません（http://localhost:8100）

確認事項:
  - Docker が起動しているか: docker ps
  - Memory Service が起動しているか: docker compose -f memory-service/docker-compose.yml up -d

Memory Service を起動してから再実行してください。
```

## エイリアス

| エイリアス | 展開先 | 動作 |
|-----------|--------|------|
| `/isac-later "内容"` | `/isac-todo add "内容"` | `add` サブコマンドと完全に同じ処理を実行する。sensitive-filter チェック、Memory Service 接続確認、保存処理の全てが同一。 |

`/isac-later` は「後でやる」タスクを素早く記録するためのショートカットです。内部的には `/isac-todo add` と同じ処理を実行するため、機密情報チェック・Memory Service 接続確認・保存処理の動作は全て同一です。詳細は `.claude/skills/isac-later/SKILL.md` を参照してください。

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
