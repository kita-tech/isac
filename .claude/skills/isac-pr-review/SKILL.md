---
name: isac-pr-review
description: GitHub PRを4人のペルソナで多角的にレビューし、スコアリング結果をPRコメントに投稿します（日本語/英語セクション分離）。
effort: high
---

# ISAC PR Review Skill

GitHub PRを4人のペルソナ + PR固有のチェックでレビューし、結果をPRコメントに投稿します。

## 使い方

```
/isac-pr-review <PR番号>              # 既定: インライン4ペルソナ（現行動作）
/isac-pr-review <PR URL>
/isac-pr-review                       # カレントブランチのPRを自動検出
/isac-pr-review --agents <PR番号>     # 徹底レビュー（多レンズ並列＋独立反証者検証。既定は投稿しない）
```

`--agents` の詳細は「徹底レビューモード（`--agents`）」を参照。指定が無ければ従来どおりインラインで動作する（後方互換）。

## 前提条件

- `gh` CLI がインストールされていること
- GitHub に認証済みであること（`gh auth status` で確認）
- `git` が利用可能であること（worktree の作成に必要）

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

### 1.5. レビュー環境の構築（worktree）

PRブランチを git worktree でチェックアウトし、コード全体を参照可能な環境を構築する。

差分の正確性を担保するため、`gh pr diff` による差分取得は GitHub API から行う。worktree は周辺コンテキストの参照用。

```bash
# 1. PRブランチを取得
git fetch origin pull/<PR番号>/head:pr-review-<PR番号>

# 2. worktree を作成（/tmp 配下に一時ディレクトリ）
git worktree add /tmp/isac-pr-review-<PR番号> pr-review-<PR番号>
```

worktree の作成に失敗した場合は、worktree なしで `gh pr diff` の差分のみでレビューを続行する。

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
| 懐疑的レビュアー | 批判的検証 | 要件との乖離、過剰実装、見落とされたedge case、より単純な代替案の有無、**もっともらしいが誤った事実主張（plausible-but-wrong）** |

> **注**: 懐疑的レビュアーはメタレビューとして機能し、スコアリングの重み付けには含まれません。指摘は「改善提案」として出力されます。
>
> **必須ルール**: 懐疑的レビュアーは常に含めること（ペルソナ数に関わらず最低1人）。
>
> **同一モデルの限界と実行検証**: 4ペルソナは全員同じモデルで盲点が相関するため、合意は事実の正しさを保証しない。
> ツール/コマンド/ランタイム挙動の断定は実行で確認すること。worktree（手順1.5）が作成できている場合は、
> 指摘対象のコード/コマンドを実際に動かして（`bash -n`／最小ケース実行／`docker` で環境依存挙動）検証する。
> 検証した指摘は ✅検証済、未検証の事実主張は ⚠️未検証 とラベルし、未検証を「確定」として投稿しない。

### 5. 出力フォーマット（PRコメント用・日本語/英語セクション分離）

**ルール**: 1つのPRコメント内で、日本語のレビュー全体を先に出力し、`---` の区切り線の後に英語の同一内容を出力する。各セクション内では単一言語のみ使用する（行単位の併記は行わない）。

```markdown
## 📊 ISAC PR Review: XX/100

### 観点別スコア
| 観点 | スコア | 重み | 寄与 |
|------|--------|------|------|
| コード品質 | XX | 30% | XX |
| セキュリティ | XX | 25% | XX |
| テスト充足度 | XX | 20% | XX |
| PR品質 | XX | 15% | XX |
| 整合性 | XX | 10% | XX |

### PR情報
- 変更ファイル数: X
- 追加行数: +XXX
- 削除行数: -XXX
- コミット数: X

---

## 🔍 詳細レビュー

### 🔒 セキュリティ
| 重要度 | ファイル | 指摘内容 |
|--------|----------|---------|
| 🔴 高 | `path/to/file` | 日本語の説明 |

### ⚡ パフォーマンス
| 重要度 | ファイル | 指摘内容 |
|--------|----------|---------|
| 🟡 中 | `path/to/file` | 日本語の説明 |

### 📐 品質・保守性
| 重要度 | ファイル | 指摘内容 |
|--------|----------|---------|
| 🟢 低 | `path/to/file` | 日本語の説明 |

### 🤔 懐疑的レビュアー
| 重要度 | ファイル | 指摘内容 |
|--------|----------|---------|
| 🟡 中 | `path/to/file` | 日本語の説明 |

---

## 🔧 改善点（+XX）

1. **filename: 指摘タイトル** (+X)
   - 現状: ...
   - 改善案: ...

---

## 📋 PR品質チェック

### 基本
- ✅ PRサイズ: 適切（XXX行）
- ✅ コミット粒度: 適切
- ⚠️ テスト: 機能追加に対するテストがありません

### PR説明文
- ✅ 説明文: あり
- ✅ 変更理由: 明確
- ⚠️ 影響範囲: 記載なし
- ✅ 説明と実装の整合性: 一致

### PRコメント確認
- ✅ 既存指摘: 全て対応済み
- ✅ 未解決の議論: なし

---

**全て改善した場合の予想スコア: XX/100**

---

## 🌐 English Version

## 📊 ISAC PR Review: XX/100

### Score by Category
| Category | Score | Weight | Contribution |
|------|--------|------|------|
| Code Quality | XX | 30% | XX |
| Security | XX | 25% | XX |
| Test Coverage | XX | 20% | XX |
| PR Quality | XX | 15% | XX |
| Consistency | XX | 10% | XX |

### PR Info
- Changed files: X
- Additions: +XXX
- Deletions: -XXX
- Commits: X

---

## 🔍 Detailed Review

### 🔒 Security
| Severity | File | Issue |
|--------|----------|---------|
| 🔴 Critical | `path/to/file` | English description |

### ⚡ Performance
| Severity | File | Issue |
|--------|----------|---------|
| 🟡 Warning | `path/to/file` | English description |

### 📐 Quality & Maintainability
| Severity | File | Issue |
|--------|----------|---------|
| 🟢 Info | `path/to/file` | English description |

### 🤔 Skeptical Reviewer
| Severity | File | Issue |
|--------|----------|---------|
| 🟡 Warning | `path/to/file` | English description |

---

## 🔧 Improvements (+XX)

1. **filename: Issue title** (+X)
   - Current: ...
   - Suggestion: ...

---

## 📋 PR Quality Check

### Basics
- ✅ PR size: Appropriate (XXX lines)
- ✅ Commit granularity: Appropriate
- ⚠️ Tests: No tests for new features

### PR Description
- ✅ Description: Present
- ✅ Why: Clear
- ⚠️ Impact scope: Not documented
- ✅ Description-Implementation consistency: Matched

### PR Comments
- ✅ Existing feedback: All addressed
- ✅ Unresolved discussions: None

---

**Potential score with all improvements: XX/100**

> 🤖 Generated by ISAC `/isac-pr-review`
```

### 6. PRコメントへの投稿

レビュー結果をPRコメントとして投稿する。PRコメントにはリポジトリ相対パスを使用すること（worktree のローカルパスは含めない）。

```bash
gh pr comment <PR番号> --body "$(cat <<'EOF'
<レビュー結果のMarkdown>
EOF
)"
```

### 7. クリーンアップ

レビュー完了後（PRコメント投稿後）、worktree を削除する。クリーンアップに失敗した場合は警告を出力して続行する。

```bash
git worktree remove /tmp/isac-pr-review-<PR番号> --force
git branch -D pr-review-<PR番号>
```

## 重要度の定義

| 重要度 | 説明 | 対応 | 減点目安 |
|--------|------|------|----------|
| 🔴 高 | セキュリティ脆弱性、機密情報漏洩 | マージ前に必須修正 | -15〜20 |
| 🟡 中 | パフォーマンス問題、テスト不足 | 修正推奨 | -5〜10 |
| 🟢 低 | 改善提案、ベストプラクティス | 検討 | -1〜3 |

### 🌐 Severity Definitions

| Severity | Description | Action | Deduction |
|--------|------|------|----------|
| 🔴 Critical | Security vulnerability, credential leak | Must fix before merge | -15〜20 |
| 🟡 Warning | Performance issue, insufficient tests | Recommended | -5〜10 |
| 🟢 Info | Suggestion, best practice | Consider | -1〜3 |

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
| `/isac-pr-review` | フルレビュー（インライン4ペルソナ・PRコメント投稿） |
| `/isac-pr-review --dry-run` | レビューのみ（コメント投稿なし） |
| `/isac-pr-review --security` | セキュリティ観点のみ |
| `/isac-pr-review --agents` | 徹底レビュー（多レンズ並列＋🔴独立検証）。**既定は投稿しない**（要 `--post`） |

## 徹底レビューモード（`--agents`）

**目的**: 既定のインライン4ペルソナ（1体が4役を順に演じる）は役間の盲点が相関し網羅の天井が低い。`--agents` は
PR の diff を**多レンズで別コンテキスト並列レビュー**し、issue を網羅的に洗い出す。A/B 実測(N=5)で inline 比
**約2倍の issue coverage** を接地発見。実装は Workflow `.claude/workflows/isac-pr-review-issues.js`、設計は
`docs/DESIGN_isac-review-agents.md` §8。`/isac-review --agents`（設計レビュー版）の PR 版に当たる。

> **なぜ検証(verify)が必須か**: 多レンズは **severity インフレ傾向**（🔴を過大に付ける）を持つ。実測では
> raw High 19件中 confirmed 6件（本物のセキュリティバグは接地確認して通り、盛られた🔴は降格/除外）。
> PRコメントは**公開・不可逆**なので、盛られた🔴を投稿すると作者体験と信頼を損なう。そのため本 workflow は
> 🔴High を**独立反証者**（迷ったら偽陽性/降格に倒す）で検証し、**confirmed のみを🔴として返す**。

### 実行手順（`--agents` 指定時）

1. **PR 情報取得と worktree 構築**は通常フローと同じ（手順1・1.5）。差分は `gh pr diff <PR>` で取得。
2. **Workflow を起動**（Skill が指示＝明示オプトイン）:
   `{ name: "isac-pr-review-issues", args: { pr_number, diff, worktree_path, context } }`
   - `diff`: `gh pr diff <PR>` の全出力（必須）
   - `worktree_path`: 手順1.5 の worktree（周辺コード参照・実行接地に使う。無い場合は省略）
   - `context`: PR タイトル・説明・議論コメント
3. **結果整形**: 返却オブジェクトの `high`（= confirmed のみ）/`med`/`low` を、既存の日英 PRコメント形式
   （手順5 のテーブル）の各レンズ欄に流し込む。**🔴は confirmed_high のみ**を載せる。
4. **ラベル義務（弁証法ジャッジの移行条件）**:
   - 各指摘に **✅検証済 / ⚠️未検証** を明示する（`verification` の confirmed は✅、diff範囲のみ等は⚠️）。
   - `verification.raw_high` vs `confirmed_high` を **透明性のため併記**（例「レビュアー指摘🔴 8件のうち検証通過 2件」）。
   - `filtered_out`（偽陽性/未確定で🔴から落ちたもの）は🔴には載せず、末尾に「検証で除外/降格した指摘」として任意で注記。
5. **既定は投稿しない（`--dry-run` 相当）**: `--agents` 単体では **PRコメントを投稿せず**、整形結果を提示するに留める。
   投稿するには **`--agents --post` を明示**する（公開・不可逆な操作の暴発防止。「AIはPRをマージしない」と同型の慎重運用）。
6. **クリーンアップ**は通常フロー（手順7）と同じく worktree を削除。

### コスト注意

`--agents` は 5レンズ＋🔴の数だけ検証エージェントを spawn する（inline の約5倍のトークン）。
高頻度の軽量 PR には既定インラインを使い、**重要・大型・セキュリティ重要な PR** に限って `--agents` を使うこと。

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

### 例4: 徹底レビュー（重要・大型PR）
```
/isac-pr-review --agents 123          # 多レンズ＋🔴検証。結果を提示のみ（投稿しない）
/isac-pr-review --agents --post 123   # 検証済み結果を PRコメントに投稿
```

## 関連スキル

- `/isac-code-review` - ローカルファイルのコードレビュー
- `/isac-review` - 設計レビュー（方針・アーキテクチャの検討）
- `/isac-autopilot` - 設計→実装→テスト→レビュー→Draft PR作成を自動実行
- `/isac-decide` - 決定の記録
- `/isac-memory` - 記憶の検索・管理
- `/isac-save-memory` - AI分析による保存形式提案
- `/isac-suggest` - 状況に応じたSkill提案
