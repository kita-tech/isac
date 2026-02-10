---
name: isac-suggest
description: 現在の状況を分析し、適切なSkillを提案します。
---

# ISAC Suggest Skill

現在の状況を分析し、適切なSkillを提案します。

## 使い方

```
/isac-suggest
```

会話の文脈から、今実行すべきSkillを提案します。

## 実行手順

### 1. 未完了タスクの取得（最初に実行）

まず、Memory Serviceから未完了のTodoを取得して表示します：

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "default")
USER_EMAIL=$(git config user.email || echo "${USER:-unknown}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認（3秒タイムアウト）
if ! curl -s --max-time 3 "$MEMORY_URL/health" > /dev/null 2>&1; then
    echo "⚠️ Memory Service に接続できません（$MEMORY_URL）— 未完了タスクの取得をスキップします"
    echo ""
    # 接続失敗でもスキル提案は続行する
else
    # 1回の API 呼び出しで結果を取得
    RESULT=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=pending")
    COUNT=$(echo "$RESULT" | jq -r '.count')

    # COUNT が数値であることを確認
    if [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -gt 0 ]; then
        echo "## 📋 未完了タスク（${COUNT}件）"
        echo ""
        echo "$RESULT" | jq -r '.todos | to_entries | .[] | "\(.key + 1). [ ] \(.value.content | split("\n")[0] | .[0:60])"'
        echo ""
    fi
fi
```

### 2. 状況分析とSkill提案

未完了タスクを表示した後、会話の文脈を分析してSkillを提案します。

## 判断基準

以下の基準で適切なSkillを提案してください：

### /isac-review を提案する場合

- 設計方針について相談されている
- 技術選定で迷っている
- アーキテクチャの決定が必要
- 「どうすべきか」「どちらがいいか」という質問
- 複数の選択肢がある

**キーワード例**: 設計、アーキテクチャ、選定、方針、どちらが、比較、検討

### /isac-code-review を提案する場合

- コードが提示されている
- 実装が完了した報告
- PRを作成する前
- 「見てほしい」「チェックして」という依頼
- バグがないか確認したい

**キーワード例**: レビュー、チェック、見て、実装した、コード、PR、プルリクエスト

### /isac-decide を提案する場合

- 重要な決定が行われた
- 「〜にした」「〜に決めた」という報告
- 技術的な選択が確定した
- 後で参照したい決定事項

**キーワード例**: 決定、決めた、採用、確定、結論

### /isac-memory を提案する場合

- 過去の作業について質問
- 「前に何をしたか」を知りたい
- 類似の問題を過去に解決したか確認
- プロジェクトの経緯を知りたい

**キーワード例**: 前に、以前、過去、履歴、経緯、なぜ

### /isac-autopilot を提案する場合

- 要件が明確で、設計から実装・テスト・PRまで一気に進めたい
- 手動の介入を最小限にしたい
- 中規模の機能追加やバグ修正

**キーワード例**: 自動で、一気に、実装して、PR作って、autopilot

### /isac-pr-review を提案する場合

- GitHub上のPRに対してレビューコメントを投稿したい
- PRのURLが提示されている
- チームメンバーのPRをレビューしたい

**キーワード例**: PR #XX、プルリクエスト、レビューして、PRレビュー

### /isac-save-memory を提案する場合

- タスクが完了した直後
- 重要な作業内容を記録として残したい
- 学んだことや発見を保存したい

**キーワード例**: 完了、保存、記録、覚えておいて、メモ

### /isac-todo を提案する場合

- やることリストの管理
- タスクの追加・確認・完了
- 「後でやる」ことの記録

**キーワード例**: タスク、TODO、やること、後で、リスト

## 出力フォーマット

### 未完了タスクがある場合

```
## 💡 Skill提案

### 📋 未完了タスク（2件）

1. [ ] Skillsのテスト追加
2. [ ] isac doctorコマンド実装

→ 上記タスクに着手する場合は内容を伝えてください

---

現在の状況を分析しました。

### 推奨Skill

**[Skill名]** - [理由]

### 他の選択肢

- [別のSkill] - [こういう場合に有効]

---

実行する場合は `[Skill名]` と入力してください。
```

### 未完了タスクがない場合

```
## 💡 Skill提案

現在の状況を分析しました。

### 推奨Skill

**[Skill名]** - [理由]

### 他の選択肢

- [別のSkill] - [こういう場合に有効]

---

実行する場合は `[Skill名]` と入力してください。
```

## 出力例

### 例1: コードが提示された場合

```
## 💡 Skill提案

現在の状況を分析しました。

### 推奨Skill

**/isac-code-review** - コードが提示されているため、品質チェックをお勧めします。

### 他の選択肢

- /isac-review --quick - 設計面も確認したい場合

---

実行する場合は `/isac-code-review` と入力してください。
```

### 例2: 技術選定の相談

```
## 💡 Skill提案

現在の状況を分析しました。

### 推奨Skill

**/isac-review** - 技術選定の相談のため、複数のペルソナで検討することをお勧めします。

### 他の選択肢

- /isac-memory - 過去に同様の決定をしていないか確認する場合

---

実行する場合は `/isac-review [議題]` と入力してください。
```

### 例3: 決定報告

```
## 💡 Skill提案

現在の状況を分析しました。

### 推奨Skill

**/isac-decide** - 重要な決定が行われたため、Memory Serviceに記録することをお勧めします。

---

実行する場合は `/isac-decide` と入力してください。
```

### 例4: 該当なし

```
## 💡 Skill提案

現在の状況を分析しました。

### 結果

特定のSkillは必要なさそうです。このまま会話を続けてください。

### 利用可能なSkill一覧

| Skill | 用途 |
|-------|------|
| /isac-autopilot | 設計→実装→テスト→レビュー→Draft PR作成を自動実行 |
| /isac-todo | 個人タスク管理（add/list/done/clear） |
| /isac-later | 「後でやる」タスクを素早く記録 |
| /isac-memory | 記憶の検索・管理 |
| /isac-decide | 決定の記録 |
| /isac-review | 設計レビュー（ペルソナ議論） |
| /isac-code-review | コードレビュー（品質チェック） |
| /isac-pr-review | GitHub PRレビュー（PRコメント投稿） |
| /isac-save-memory | AI分析による保存形式提案 |
| /isac-notion-design | Notionの概要から設計を実行 |
| /isac-suggest | Skill提案（このSkill） |
```

## 複数提案する場合

状況によっては複数のSkillを順番に提案：

```
## 💡 Skill提案

現在の状況を分析しました。

### 推奨ステップ

1. **/isac-code-review** - まずコードの品質をチェック
2. **/isac-decide** - 問題なければ実装内容を記録

---

順番に実行することをお勧めします。
```

## 関連スキル

- `/isac-autopilot` - 設計→実装→テスト→レビュー→Draft PR作成を自動実行
- `/isac-todo` - 個人タスク管理（add/list/done/clear）
- `/isac-later` - 「後でやる」タスクを素早く記録
- `/isac-memory` - 記憶の検索・管理
- `/isac-decide` - 決定の記録
- `/isac-review` - 設計レビュー
- `/isac-code-review` - コードレビュー
- `/isac-pr-review` - GitHub PRレビュー
- `/isac-save-memory` - AI分析による保存形式提案
- `/isac-notion-design` - Notionの概要から設計を実行
