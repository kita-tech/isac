---
name: isac-review
description: 設計や技術選定を複数のペルソナで検討し、決定を記録します。
---

# ISAC Review Skill

設計や技術選定を複数のペルソナで検討し、決定を記録します。

## project_id の取得ルール

**重要**: project_id は必ず `.isac.yaml` ファイルから取得すること。`$CLAUDE_PROJECT` 環境変数は `.isac.yaml` が存在しない場合のフォールバックとしてのみ使用する。

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
```

決定の記録時に Memory Service へ保存する際は、この方法で取得した `$PROJECT_ID` を使用すること。

## 使い方

```
/isac-review [議題]
```

## 実行手順

### 1. ペルソナの設定

以下の4人のペルソナで議論を行います：

| ペルソナ | 役割 | 視点 |
|---------|------|------|
| 実装者 | バックエンド/フロントエンド開発者 | 実装の容易さ、保守性、コード品質 |
| 運用者 | SRE/DevOpsエンジニア | 運用負荷、監視、スケーラビリティ |
| アーキテクト | 技術リード/設計者 | 全体設計、拡張性、技術的負債 |
| 懐疑的レビュアー | 批判的検証者 | 要件との乖離、過剰設計、見落とされたリスク、より単純な代替案の有無 |

### 2. 議論フォーマット

各ペルソナは以下の形式で意見を述べます：

```
**👨‍💻 [名前]（[役割]）**
> [意見・主張]
>
> **懸念点**: [あれば]
> **推奨**: [A案/B案/その他]
```

### 3. 投票と結論

議論後、以下の形式で投票を集計：

```
## 📊 投票結果

| 選択肢 | 票数 | 支持者 |
|--------|------|--------|
| A案 | X | 名前, 名前 |
| B案 | Y | 名前 |

## 🎯 結論

[合意内容の要約]
```

### 4. 決定の記録（オプション）

議論の結論が出たら、ユーザーに確認：

「この決定をMemory Serviceに記録しますか？」

**Yes の場合**、以下の形式で Memory Service に保存：

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認（3秒タイムアウト）
if ! curl -s --max-time 3 "$MEMORY_URL/health" > /dev/null 2>&1; then
    echo "❌ Memory Service に接続できません（$MEMORY_URL）"
    echo "Docker が起動しているか確認してください: docker compose -f memory-service/docker-compose.yml up -d"
    exit 1
fi

RESPONSE=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "【決定】[決定内容]\n【理由】[主な理由]\n【検討過程】4人のペルソナでレビュー実施。[簡潔な経緯]" \
    --argjson importance 0.8 \
    --arg scope_id "$PROJECT_ID" \
    --arg category "[カテゴリ]" \
    '{
      content: $content,
      type: "decision",
      importance: $importance,
      scope: "project",
      scope_id: $scope_id,
      metadata: {
        category: $category,
        review_type: "persona_review",
        participants: 4
      }
    }')")

# 保存結果の確認
if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    MEMORY_ID=$(echo "$RESPONSE" | jq -r '.id')
    echo "✅ 決定を記録しました (ID: $MEMORY_ID)"
else
    echo "❌ 決定の記録に失敗しました"
    echo "$RESPONSE"
fi
```

## 重要度の目安

| 重要度 | 決定の影響範囲 |
|--------|---------------|
| 0.9 | アーキテクチャ全体に影響 |
| 0.8 | 複数コンポーネントに影響 |
| 0.7 | 特定機能に影響 |
| 0.6 | 軽微な決定 |

## 例

### 入力
```
/isac-review 認証方式の選定（JWT vs セッション）
```

### 出力例

```
## 🎭 4人のペルソナによる議論

### 議題: 認証方式の選定（JWT vs セッション）

---

**👨‍💻 田中（バックエンド開発者・5年目）**
> JWT推奨。ステートレスで実装がシンプル。
> トークンの検証だけで認証完了するのでDBアクセス不要。
>
> **懸念点**: トークン無効化が難しい
> **推奨**: JWT

---

**👩‍🔧 高橋（SRE・6年目）**
> 運用観点からもJWT。セッションストアの管理が不要。
> ただしトークンサイズに注意。
>
> **懸念点**: トークンが大きいとヘッダーサイズ増加
> **推奨**: JWT（短い有効期限 + リフレッシュトークン）

---

**👩‍🚀 加藤（アーキテクト・12年目）**
> マイクロサービス展開を考えるとJWT一択。
> サービス間認証にも使える。
>
> **懸念点**: 秘密鍵の管理
> **推奨**: JWT

---

**🤔 中村（懐疑的レビュアー・12年目）**
> 全員JWTに賛成だが、本当にマイクロサービス展開の予定はあるのか？
> 現時点でモノリスなら、セッションのほうがトークン無効化が容易で運用が楽。
> JWTを選ぶなら「なぜセッションではダメか」を明確にすべき。
>
> **懸念点**: YAGNI原則。将来の拡張を理由にした過剰設計のリスク
> **推奨**: JWT（ただし選定理由を明文化すること）

---

## 📊 投票結果

| 選択肢 | 票数 | 支持者 |
|--------|------|--------|
| JWT | 4 | 田中, 高橋, 加藤, 中村 |
| セッション | 0 | - |

## 🎯 結論

**JWTを採用**
- 短い有効期限（15分）+ リフレッシュトークン（7日）の構成
- 秘密鍵は環境変数で管理

---

この決定をMemory Serviceに記録しますか？ (Yes/No)
```

## オプション: ペルソナ数の変更

議題の重要度に応じてペルソナ数を変更できます：

| 指定 | ペルソナ数 | 用途 |
|------|-----------|------|
| `/isac-review` | 4人 | 標準的な設計レビュー |
| `/isac-review --quick` | 2人 | 軽微な決定 |
| `/isac-review --full` | 5人 | 重要なアーキテクチャ決定 |
| `/isac-review --team` | 10人 | 大きな技術選定 |

**必須ルール**: ペルソナ数に関わらず、**最低1人は懐疑的レビュアーを含めること**。`--quick`（2人）の場合でも、1人は専門家、1人は懐疑的レビュアーとする。

## 関連スキル

- `/isac-memory` - 記憶の検索・管理
- `/isac-decide` - 決定の直接記録（レビューなし）
- `/isac-code-review` - コードレビュー（実装の品質チェック）
- `/isac-pr-review` - GitHub PRレビュー（PRコメント投稿）
- `/isac-autopilot` - 設計→実装→テスト→レビュー→Draft PR作成を自動実行
- `/isac-save-memory` - AI分析による保存形式提案
- `/isac-suggest` - 状況に応じたSkill提案
