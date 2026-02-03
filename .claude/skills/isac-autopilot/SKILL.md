---
name: isac-autopilot
description: 要件から設計・実装・レビュー・テスト・Draft PR作成までを自動実行します。
---

# ISAC Autopilot Skill

要件を入力すると、設計→実装→レビュー→テスト→Draft PR作成までをバックグラウンドで自動実行します。

## 使い方

```
/isac-autopilot <要件>
/isac-autopilot <GitHub Issue URL>
```

## 重要: 実行方法

**このスキルはバックグラウンドで自動実行されます。**

Claude は以下の手順で実行してください：

1. **Task tool を `run_in_background: true` で起動**
2. **ユーザーには「バックグラウンドで実行中」と伝える**
3. **出力ファイルのパスを共有**
4. **完了を待たずに制御を返す**

### 実行コード例

```
Task tool を以下のパラメータで呼び出す:
- subagent_type: "general-purpose"
- run_in_background: true
- prompt: [下記の完全なプロンプトを渡す]
```

## バックグラウンドエージェントへのプロンプト

以下のプロンプトをそのまま Task tool に渡してください（{requirement} を実際の要件で置換）：

---

あなたは ISAC Autopilot エージェントです。以下の要件を完全に自動で実装してください。
**ユーザーへの質問や承認の要求は一切せず、自律的に判断して進めてください。**

## 要件

{requirement}

## 実行フロー

### Phase 1: 設計（自動）

1. 要件を分析
2. 変更対象ファイルを特定
3. 実装方針を決定
4. 出力: 設計サマリー

### Phase 2: 実装（自動）

1. コードを実装（Edit/Write tool使用）
2. 必要に応じてテストコードも作成
3. 出力: 変更ファイル一覧

### Phase 3: コードレビュー（自動）

以下の3つの観点でセルフレビュー：

1. **セキュリティ**: 脆弱性、入力検証、認証・認可
2. **パフォーマンス**: 効率性、リソース使用、スケーラビリティ
3. **保守性**: 可読性、テスタビリティ、設計パターン

スコアリング（100点満点）:
- 90点以上: Phase 4へ
- 90点未満: 指摘を修正して Phase 2 へ戻る（最大3回）

### Phase 4: テスト実行（自動）

1. テストコマンドを決定:
   - `.isac.yaml` の `autopilot.test_command` があれば使用
   - なければ自動検出（pytest, npm test, go test など）
2. テスト実行
3. 失敗時: 修正して Phase 2 へ戻る（最大3回）

### Phase 5: Draft PR作成（自動）

1. ブランチ作成: `autopilot/{date}-{short-desc}`
2. コミット作成（Co-Authored-By 付き）
3. Draft PR作成: `gh pr create --draft`
4. **PR本文に設計ドキュメントを含める**（Phase 1の設計内容を記載）

## 出力フォーマット

進捗を以下の形式で出力してください：

```
🚀 ISAC Autopilot 開始
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 要件: {要件の要約}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📐 Phase 1: 設計
  ✓ 変更対象: {ファイル一覧}
  ✓ 実装方針: {方針}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 Iteration 1/3

💻 Phase 2: 実装
  ✓ {変更内容}

📊 Phase 3: コードレビュー
  ✓ スコア: {score}/100
  {90点未満の場合: 指摘事項と修正内容}

🧪 Phase 4: テスト
  ✓ {テスト結果}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 Phase 5: Draft PR作成
  ✓ ブランチ: {branch}
  ✓ コミット: {message}

🎉 完了！

Draft PR: {URL}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
サマリー:
  - 総イテレーション: {count}回
  - 最終スコア: {score}/100
  - テスト結果: {passed/failed}
```

## PR本文フォーマット

Draft PR作成時は以下のフォーマットで本文を作成してください：

```markdown
## Summary

{要件の1-2行要約}

## Design

### 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| {path} | {概要} |

### 実装方針

{Phase 1で決定した実装方針を記載}

### 技術的な判断

{実装中に行った技術的な判断があれば記載}

## Changes

{変更内容の箇条書き}

## Review Score

- Final Score: {score}/100
- Review Iterations: {iteration_count}

### レビュー詳細

{最終レビューの詳細。指摘があった場合はどう対応したかも記載}

## Test Results

- Status: {Passed/Failed}
- Test Iterations: {test_iteration_count}
- Test Command: `{test_command}`

```
{テスト出力の抜粋（成功/失敗の要約）}
```

---

🤖 This PR was created by [ISAC Autopilot](https://github.com/kita-tech/isac)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

## 重要な制約

- **質問禁止**: ユーザーに質問や確認を求めない
- **自律判断**: 不明点は最善の判断で進める
- **エラー時も続行**: 可能な限り自動で解決を試みる
- **最大3回ループ**: 3回で完了しない場合は現状を報告して終了

## 失敗時の出力

3回ループしても完了しない場合：

```
⚠️ Autopilot: 3回の試行後も完了できませんでした。

現在の状態:
  - レビュースコア: {score}/100
  - テスト結果: {status}

最後の指摘事項:
  {issues}

変更はブランチ `{branch}` に保存されています。
手動での確認・修正をお願いします。
```

---

## ユーザーへの返答テンプレート

Claude は Task tool を起動した後、以下のように返答してください：

```
🚀 ISAC Autopilot をバックグラウンドで起動しました。

📋 要件: {要件の要約}

進捗確認:
  tail -f {output_file}

完了までお待ちください。Draft PR が作成されたら通知します。
```

## 設定

`.isac.yaml` でカスタマイズ可能:

```yaml
autopilot:
  # テストコマンド（自動検出をオーバーライド）
  test_command: "pytest -v"

  # レビュー合格スコア（デフォルト: 90）
  min_review_score: 90

  # 最大ループ回数（デフォルト: 3）
  max_iterations: 3

  # 自動コミットメッセージのプレフィックス
  commit_prefix: "feat"
```

## 制限事項

- 大規模な変更（10ファイル以上）は非推奨
- セキュリティクリティカルな変更は手動レビューを推奨
- CIが必要なプロジェクトでは、Draft PRマージ前に必ずCI通過を確認

## 関連スキル

- `/isac-code-review` - コードレビュー（単体実行）
- `/isac-review` - 設計レビュー
- `/isac-decide` - 決定の記録
