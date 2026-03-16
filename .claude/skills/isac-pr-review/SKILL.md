---
name: isac-pr-review
description: GitHub PRを4人のペルソナで多角的にレビューし、スコアリング結果をPRコメントに投稿します（英日併記）。
---

# ISAC PR Review Skill

GitHub PRを4人のペルソナ + PR固有のチェックでレビューし、結果をPRコメントに投稿します。

## 使い方

```
/isac-pr-review <PR番号>
/isac-pr-review <PR URL>
/isac-pr-review              # カレントブランチのPRを自動検出
```

## 前提条件

- `gh` CLI がインストールされていること
- GitHub に認証済みであること（`gh auth status` で確認）

## ローカル参照禁止ルール / Local Reference Restriction

**このスキルでは Read ツールによるローカルファイルの参照を禁止する。**

### 理由 / Rationale

1. **再現性 / Reproducibility**: 誰がどの環境で実行しても同じレビュー結果になる
2. **責務分離 / Separation of Concerns**: PR レビュー = 差分の妥当性、コードレビュー = コード全体の品質（`/isac-code-review` に委譲）
3. **セキュリティ / Security**: PRコメントへの機密情報混入リスクを最小化
4. **将来性 / Future-proofing**: CI 上での自動実行を視野に入れた設計

### 許可される情報源 / Allowed Information Sources

- `gh pr view` / `gh pr diff` によるPR情報
- `gh api` による GitHub API 経由のファイル取得（後述）
- PRコメント（`gh api repos/{owner}/{repo}/pulls/<PR番号>/comments` 等）

### 禁止される操作 / Prohibited Operations

- **Read ツールでのローカルファイル参照**（差分に含まれないファイルの直接読み取り）
- **Grep / Glob ツールでのローカルファイル検索**
- ローカルの `git` コマンドによるファイル内容の参照（`git show`、`git log -p` 等）

> **注**: PR差分だけでは文脈が不足し、より深い分析が必要な場合は、レビュー結果に `/isac-code-review` への委譲を記載する（「委譲ルール」セクション参照）。

## 実行手順

### 1. PR情報の取得

```bash
# PR番号から情報取得
gh pr view <PR番号> --json number,title,body,additions,deletions,changedFiles,commits,files

# 差分を取得
gh pr diff <PR番号>

# PRコメント（レビューコメント含む）を取得
gh api repos/{owner}/{repo}/pulls/<PR番号>/comments
gh api repos/{owner}/{repo}/issues/<PR番号>/comments
```

**取得する情報:**
- PRタイトル・説明文（body）
- コード差分
- PRコメント（一般コメント + レビューコメント）
- 変更ファイル一覧・統計情報

#### 周辺コンテキストの取得 / Retrieving Surrounding Context

差分だけでは変更の妥当性を判断できない場合、**GitHub API 経由**でファイル内容を取得する。ローカルファイルの Read は禁止。

```bash
# PRのベースブランチ（base ref）を取得
BASE_REF=$(gh pr view <PR番号> --json baseRefName -q '.baseRefName')

# GitHub API 経由でファイル内容を取得（ベースブランチから）
gh api repos/{owner}/{repo}/contents/{path}?ref={BASE_REF}

# レスポンスの content フィールドは Base64 エンコードされている
# jq でデコードする場合:
gh api repos/{owner}/{repo}/contents/{path}?ref={BASE_REF} -q '.content' | base64 -d
```

**使用する場面:**
- 変更されたファイルのインポート元・呼び出し元を確認したい場合
- 型定義やインターフェースの全体像を把握したい場合
- テストファイルの既存内容を確認したい場合

**注意:**
- 取得するファイルは差分に関連するものに限定すること（不必要な探索は行わない）
- 大量のファイルを取得する必要がある場合は、`/isac-code-review` への委譲を検討する

### 2. 評価観点と重み付け

| 観点 | 重み | 評価内容 |
|------|------|----------|
| コード品質 | 30% | 保守性、可読性、DRY/SOLID原則 |
| セキュリティ | 25% | 脆弱性、認証情報の誤コミット、データ保護 |
| テスト充足度 | 20% | テストファイルの追加・変更有無 |
| PR品質 | 15% | サイズ、説明文の質、説明と実装の整合性、コミット粒度 |
| 整合性 | 10% | ファイル間の整合性、変更の一貫性、PRコメントでの議論との整合性 |

### 3. PR固有のチェック項目

#### セキュリティ（機密情報検出）
- [ ] `.env` ファイルの誤コミット
- [ ] APIキー、パスワード、トークンのハードコード
- [ ] `credentials`, `secrets` を含むファイル
- [ ] 秘密鍵（`.pem`, `.key`）

#### テスト充足度
- [ ] 機能追加に対するテストの有無
- [ ] テストファイルの変更有無
- [ ] テストカバレッジへの影響

#### PR品質
- [ ] PRサイズ（推奨: 400行以下）
- [ ] コミット粒度（1コミット1目的）
- [ ] コミットメッセージの品質

#### PR説明文の評価
- [ ] 説明文の有無
- [ ] 変更理由（Why）の明確さ
- [ ] 変更内容（What）の説明
- [ ] 影響範囲の記載
- [ ] **説明文と実装の整合性**: 説明に書かれた内容と実際のコード変更が一致しているか

#### PRコメントの活用
レビュー時にPRコメントを参照し、以下を考慮：
- [ ] 既存のレビュー指摘事項が対応済みか
- [ ] 議論で決まった方針がコードに反映されているか
- [ ] 未解決の議論・質問がないか

#### データベース（クエリ変更がある場合）
- [ ] 新規クエリがインデックスを活用しているか
- [ ] WHERE句・JOIN条件のカラムにインデックスが存在するか
- [ ] フルテーブルスキャンを引き起こすクエリがないか
- [ ] ORDER BY / GROUP BY がインデックスを活用しているか
- [ ] 新規テーブル・カラム追加時にインデックス定義が適切か

#### 整合性
- [ ] インポート/エクスポートの整合性
- [ ] 型定義の一貫性
- [ ] 命名規則の統一

### 4. ペルソナ

| ペルソナ | 専門 | チェック観点 |
|---------|------|-------------|
| セキュリティ専門家 | 脆弱性診断 | 機密情報漏洩、インジェクション、認証・認可、入力検証、OWASP Top 10 |
| パフォーマンス専門家 | 最適化 | N+1問題、計算量、メモリ効率、キャッシュ、非同期処理、DBインデックス活用 |
| 品質・保守性専門家 | コード品質 | 可読性、命名、DRY/SOLID、テスト容易性、エラーハンドリング |
| 懐疑的レビュアー | 批判的検証 | 要件との乖離、過剰実装、見落とされたedge case、より単純な代替案の有無 |

> **注**: 懐疑的レビュアーはメタレビューとして機能し、スコアリングの重み付けには含まれません。指摘は「改善提案」として出力されます。
>
> **必須ルール**: 懐疑的レビュアーは常に含めること（ペルソナ数に関わらず最低1人）。

### 5. 出力フォーマット（PRコメント用・英日併記）

**ルール**: ヘッダー、テーブル見出し、指摘内容はすべて `English / 日本語` の併記とする。

```markdown
## 📊 ISAC PR Review: XX/100

### Score by Category / 観点別スコア
| Category / 観点 | Score | Weight | Contribution |
|------|--------|------|------|
| Code Quality / コード品質 | XX | 30% | XX |
| Security / セキュリティ | XX | 25% | XX |
| Test Coverage / テスト充足度 | XX | 20% | XX |
| PR Quality / PR品質 | XX | 15% | XX |
| Consistency / 整合性 | XX | 10% | XX |

### PR Info / PR情報
- Changed files / 変更ファイル数: X
- Additions / 追加行数: +XXX
- Deletions / 削除行数: -XXX
- Commits / コミット数: X

---

## 🔍 Detailed Review / 詳細レビュー

### 🔒 Security / セキュリティ
| Severity / 重要度 | File | Issue / 指摘内容 |
|--------|----------|---------|
| 🔴 Critical / 高 | `path/to/file` | English description / 日本語の説明 |

### ⚡ Performance / パフォーマンス
| Severity / 重要度 | File | Issue / 指摘内容 |
|--------|----------|---------|
| 🟡 Warning / 中 | `path/to/file` | English description / 日本語の説明 |

### 📐 Quality & Maintainability / 品質・保守性
| Severity / 重要度 | File | Issue / 指摘内容 |
|--------|----------|---------|
| 🟢 Info / 低 | `path/to/file` | English description / 日本語の説明 |

### 🤔 Skeptical Reviewer / 懐疑的レビュアー
| Severity / 重要度 | File | Issue / 指摘内容 |
|--------|----------|---------|
| 🟡 Warning / 中 | `path/to/file` | English description / 日本語の説明 |

---

## 🔧 Improvements / 改善点（+XX）

1. **filename: Issue title / 指摘タイトル** (+X)
   - Current / 現状: ...
   - Suggestion / 改善案: ...

---

## 📋 PR Quality Check / PR品質チェック

### Basics / 基本
- ✅ PR size / PRサイズ: Appropriate / 適切（XXX lines）
- ✅ Commit granularity / コミット粒度: Appropriate / 適切
- ⚠️ Tests / テスト: No tests for new features / 機能追加に対するテストがありません

### PR Description / PR説明文
- ✅ Description / 説明文: Present / あり
- ✅ Why / 変更理由: Clear / 明確
- ⚠️ Impact scope / 影響範囲: Not documented / 記載なし
- ✅ Description-Implementation consistency / 説明と実装の整合性: Matched / 一致

### PR Comments / PRコメント確認
- ✅ Existing feedback / 既存指摘: All addressed / 全て対応済み
- ✅ Unresolved discussions / 未解決の議論: None / なし

---

**Potential score with all improvements / 全て改善した場合の予想スコア: XX/100**

---

<!-- 以下は深い分析が必要な場合のみ出力する -->

## 🔬 Needs Deeper Analysis / 深い分析が必要な場合

> The following areas could not be fully evaluated from the PR diff alone. Consider running `/isac-code-review` for a comprehensive local analysis.
> 以下の項目はPR差分のみでは十分な評価ができませんでした。ローカルでの包括的な分析には `/isac-code-review` の実行を検討してください。

| Area / 領域 | Reason / 理由 |
|------|------|
| e.g. Architecture impact / アーキテクチャへの影響 | e.g. Changes to core module require full dependency analysis / コアモジュールの変更には依存関係の完全な分析が必要 |

**Recommended command / 推奨コマンド:**
```
/isac-code-review
```

---

> 🤖 Generated by ISAC `/isac-pr-review`
```

### 6. PRコメントへの投稿

レビュー結果をPRコメントとして投稿：

```bash
gh pr comment <PR番号> --body "$(cat <<'EOF'
<レビュー結果のMarkdown>
EOF
)"
```

## 重要度の定義 / Severity Definitions

| Severity / 重要度 | Description / 説明 | Action / 対応 | Deduction / 減点目安 |
|--------|------|------|----------|
| 🔴 Critical / 高 | Security vulnerability, credential leak / セキュリティ脆弱性、機密情報漏洩 | Must fix before merge / マージ前に必須修正 | -15〜20 |
| 🟡 Warning / 中 | Performance issue, insufficient tests / パフォーマンス問題、テスト不足 | Recommended / 修正推奨 | -5〜10 |
| 🟢 Info / 低 | Suggestion, best practice / 改善提案、ベストプラクティス | Consider / 検討 | -1〜3 |

## PRサイズの評価基準

| サイズ | 行数 | 評価 |
|--------|------|------|
| 🟢 Small | ~200行 | 理想的 |
| 🟡 Medium | 200-400行 | 適切 |
| 🟠 Large | 400-800行 | 分割を検討 |
| 🔴 X-Large | 800行超 | 分割を強く推奨 |

## オプション

| 指定 | 説明 |
|------|------|
| `/isac-pr-review` | フルレビュー（PRコメント投稿） |
| `/isac-pr-review --dry-run` | レビューのみ（コメント投稿なし） |
| `/isac-pr-review --security` | セキュリティ観点のみ |

## 使用例

### 例1: PR番号を指定
```
/isac-pr-review 123
```

### 例2: PR URLを指定
```
/isac-pr-review https://github.com/owner/repo/pull/123
```

### 例3: カレントブランチのPR
```
/isac-pr-review
```
→ `gh pr view --json number` で自動検出

## 委譲ルール / Delegation Rules

PR差分のみでは十分な評価ができない場合、レビュー結果に `/isac-code-review` への委譲を記載する。

### 委譲が必要なケース / When to Delegate

| ケース / Case | 説明 / Description |
|------|------|
| 大規模なアーキテクチャ変更 / Large architectural changes | コアモジュールの変更で、依存関係の全体像が差分だけでは把握できない場合 |
| 複雑なロジックの正確性検証 / Complex logic verification | アルゴリズムや状態遷移の正確性を、周辺コードの完全な文脈で検証する必要がある場合 |
| テストカバレッジの詳細分析 / Detailed test coverage analysis | 既存テストとの重複・漏れを、テストスイート全体で確認する必要がある場合 |
| パフォーマンスへの広範な影響 / Broad performance impact | 変更がシステム全体のパフォーマンスに影響する可能性があり、プロファイリングが必要な場合 |

### 委譲の記載方法 / How to Document Delegation

出力フォーマットの「Needs Deeper Analysis / 深い分析が必要な場合」セクションに記載する（該当する場合のみセクション自体を出力する）。

- 深い分析が必要な**領域**と**理由**をテーブルで列挙
- `/isac-code-review` の推奨コマンドを記載
- **該当しない場合はセクション自体を省略する**

## 関連スキル

- `/isac-code-review` - ローカルファイルのコードレビュー
- `/isac-review` - 設計レビュー（方針・アーキテクチャの検討）
- `/isac-autopilot` - 設計→実装→テスト→レビュー→Draft PR作成を自動実行
- `/isac-decide` - 決定の記録
- `/isac-memory` - 記憶の検索・管理
- `/isac-save-memory` - AI分析による保存形式提案
- `/isac-suggest` - 状況に応じたSkill提案
