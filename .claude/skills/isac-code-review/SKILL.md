---
name: isac-code-review
description: コードを4人のペルソナで多角的にレビューし、スコアリングと改善点を明示します（日本語/英語セクション分離）。
---

# ISAC Code Review Skill

コードを4人のペルソナで多角的にレビューし、スコアリングと改善点を明示します。

## 使い方

```
/isac-code-review                    # Git: ブランチの変更全体（デフォルト）
/isac-code-review --staged           # Git: ステージング済みのみ
/isac-code-review src/auth.py        # 明示的にファイル指定
/isac-code-review [コードブロック]    # コード貼り付け
```

## 実行手順

### 1. 対象の判定フロー

```
1. 引数あり？
   ├─ Yes → ファイルパス or コードブロックとして処理
   └─ No → 2へ

2. Git管理下？（git rev-parse --git-dir）
   ├─ Yes → git diff でブランチの変更を取得
   └─ No → エラー「ファイルパスかコードを指定してください」

3. 変更ファイル数チェック
   ├─ 10ファイル超 → 警告を表示し確認
   └─ 10ファイル以下 → レビュー実行
```

### 2. 変更内容の取得

**Git管理下の場合:**

```bash
# ブランチの変更全体（デフォルト）
git diff $(git merge-base HEAD main)...HEAD --name-only  # 変更ファイル一覧
git diff $(git merge-base HEAD main)...HEAD              # 差分内容

# ステージング済みのみ（--staged）
git diff --cached --name-only
git diff --cached
```

**変更が多い場合の警告:**

```
⚠️ 変更ファイルが多いです（15ファイル）

変更ファイル:
  - src/auth/login.py
  - src/auth/logout.py
  - src/models/user.py
  ... (他12ファイル)

このまま全ファイルをレビューしますか？
- Yes: 全ファイルをレビュー
- No: 特定ファイルを指定して再実行
```

## スコアリング

### 評価観点と重み付け（デフォルト）

| 観点 | 重み | 評価内容 |
|------|------|----------|
| セキュリティ | 35% | 脆弱性、認証・認可、データ保護 |
| 保守性・可読性 | 30% | 命名、構造、DRY/SOLID原則 |
| パフォーマンス | 20% | 計算量、N+1問題、リソース効率 |
| テスト充足度 | 15% | テストカバレッジ、エッジケース |

### プロジェクトごとのカスタマイズ

`.isac.yaml` で重み付けを変更可能：

```yaml
review:
  weights:
    security: 35
    maintainability: 30
    performance: 20
    test_coverage: 15

  # オプション項目（有効化する場合、合計100%になるよう調整）
  optional:
    accessibility: 10    # フロントエンド向け
    operability: 10      # 本番サービス向け
```

## ペルソナ

| ペルソナ | 専門 | チェック観点 |
|---------|------|-------------|
| セキュリティ専門家 | 脆弱性診断 | 機密情報漏洩、インジェクション、認証・認可、入力検証、OWASP Top 10 |
| パフォーマンス専門家 | 最適化 | N+1問題、計算量、メモリ効率、キャッシュ、非同期処理、DBインデックス活用 |
| 品質・保守性専門家 | コード品質 | 可読性、命名、DRY/SOLID、テスト容易性、エラーハンドリング |
| 懐疑的レビュアー | 批判的検証 | 要件との乖離、過剰実装、見落とされたedge case、より単純な代替案の有無 |

> **注**: 懐疑的レビュアーはメタレビューとして機能し、スコアリングの重み付けには含まれません。指摘は「改善提案」として出力されます。
>
> **必須ルール**: 懐疑的レビュアーは常に含めること（ペルソナ数に関わらず最低1人）。

## 重要度の定義

| 重要度 | 説明 | 対応 | 減点目安 |
|--------|------|------|----------|
| 🔴 高 | セキュリティ脆弱性、本番障害の可能性 | 即時修正必須 | -15〜20点 |
| 🟡 中 | パフォーマンス問題、保守性の懸念 | 修正推奨 | -5〜10点 |
| 🟢 低 | 改善提案、ベストプラクティス | 検討 | -1〜3点 |

### 🌐 Severity Definitions

| Severity | Description | Action | Deduction |
|--------|------|------|----------|
| 🔴 Critical | Security vulnerability, potential production failure | Must fix immediately | -15〜20 |
| 🟡 Warning | Performance issue, maintainability concern | Recommended | -5〜10 |
| 🟢 Info | Suggestion, best practice | Consider | -1〜3 |

## 出力フォーマット（日本語/英語セクション分離）

**ルール**: ターミナル出力で、日本語のレビュー全体を先に出力し、`---` の区切り線の後に英語の同一内容を出力する。各セクション内では単一言語のみ使用する（行単位の併記は行わない）。

### ブランチ全体レビュー時

```
## 📊 レビュースコア: XX/100

### レビュー対象
- ブランチ: `feature/auth-improvement`
- ベース: `main`
- 変更ファイル: X個
- 追加行数: +XXX / 削除行数: -XXX

### 観点別スコア
| 観点 | スコア | 重み | 寄与 |
|------|--------|------|------|
| セキュリティ | XX | 35% | XX |
| 保守性・可読性 | XX | 30% | XX |
| パフォーマンス | XX | 20% | XX |
| テスト充足度 | XX | 15% | XX |

---

## 🔍 ファイル別レビュー

### 📄 src/auth/login.py (+45, -12)

**🔒 セキュリティ専門家**

| 重要度 | 行 | 指摘内容 | 減点 |
|--------|-----|---------|------|
| 🔴 高 | L23 | SQLインジェクションの可能性 | -15 |

**⚡ パフォーマンス専門家**

| 重要度 | 行 | 指摘内容 | 減点 |
|--------|-----|---------|------|
| 🟡 中 | L30 | N+1クエリ問題 | -7 |

---

### 📄 src/models/user.py (+20, -5)

**📐 品質・保守性専門家**

| 重要度 | 行 | 指摘内容 | 減点 |
|--------|-----|---------|------|
| 🟢 低 | L12 | マジックナンバーの使用 | -2 |

**🤔 懐疑的レビュアー**

| 重要度 | 行 | 指摘内容 | 減点 |
|--------|-----|---------|------|
| 🟡 中 | - | 要件に対して過剰な抽象化の可能性 | - |

---

## 🔧 改善点（+XX点の余地）

改善効果の高い順に記載：

### 1. src/auth/login.py:L23 - SQLインジェクション対策 (+15点)
- **現状**: 文字列結合でSQL組み立て
- **改善案**:
  ```python
  # Before
  query = f"SELECT * FROM users WHERE id = {user_id}"

  # After
  cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
  ```

### 2. src/auth/login.py:L30 - N+1クエリ解消 (+7点)
- **現状**: ループ内で都度DBアクセス
- **改善案**: `prefetch_related()` で一括取得

### 3. src/models/user.py:L12 - 定数化 (+2点)
- **現状**: `if retry > 3:`
- **改善案**: `MAX_RETRY = 3` として定数定義

---

## 📈 サマリー

| 重要度 | 件数 | 合計減点 |
|--------|------|----------|
| 🔴 高 | X件 | -XX点 |
| 🟡 中 | Y件 | -XX点 |
| 🟢 低 | Z件 | -XX点 |

**全て改善した場合の予想スコア: XX/100**

---

指摘事項を修正しますか？ (Yes/No)

---

## 🌐 English Version

## 📊 Review Score: XX/100

### Review Target
- Branch: `feature/auth-improvement`
- Base: `main`
- Changed files: X
- Additions: +XXX / Deletions: -XXX

### Score by Category
| Category | Score | Weight | Contribution |
|------|--------|------|------|
| Security | XX | 35% | XX |
| Maintainability | XX | 30% | XX |
| Performance | XX | 20% | XX |
| Test Coverage | XX | 15% | XX |

---

## 🔍 File-by-File Review

### 📄 src/auth/login.py (+45, -12)

**🔒 Security Expert**

| Severity | Line | Issue | Deduction |
|--------|-----|---------|------|
| 🔴 Critical | L23 | Potential SQL injection | -15 |

**⚡ Performance Expert**

| Severity | Line | Issue | Deduction |
|--------|-----|---------|------|
| 🟡 Warning | L30 | N+1 query problem | -7 |

---

### 📄 src/models/user.py (+20, -5)

**📐 Quality & Maintainability Expert**

| Severity | Line | Issue | Deduction |
|--------|-----|---------|------|
| 🟢 Info | L12 | Magic number usage | -2 |

**🤔 Skeptical Reviewer**

| Severity | Line | Issue | Deduction |
|--------|-----|---------|------|
| 🟡 Warning | - | Potentially over-abstracted for the requirements | - |

---

## 🔧 Improvements (+XX potential)

Listed by improvement impact:

### 1. src/auth/login.py:L23 - SQL injection fix (+15)
- **Current**: String concatenation for SQL construction
- **Suggestion**:
  ```python
  # Before
  query = f"SELECT * FROM users WHERE id = {user_id}"

  # After
  cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
  ```

### 2. src/auth/login.py:L30 - N+1 query fix (+7)
- **Current**: DB access in loop
- **Suggestion**: Use `prefetch_related()` for batch fetching

### 3. src/models/user.py:L12 - Use constant (+2)
- **Current**: `if retry > 3:`
- **Suggestion**: Define `MAX_RETRY = 3` as a constant

---

## 📈 Summary

| Severity | Count | Total Deduction |
|--------|------|----------|
| 🔴 Critical | X | -XX |
| 🟡 Warning | Y | -XX |
| 🟢 Info | Z | -XX |

**Potential score with all improvements: XX/100**

---

Fix the issues? (Yes/No)
```

## チェック項目詳細

### セキュリティ（🔒）

- [ ] SQLインジェクション
- [ ] XSS（クロスサイトスクリプティング）
- [ ] CSRF（クロスサイトリクエストフォージェリ）
- [ ] 認証・認可の不備
- [ ] 機密情報のハードコード
- [ ] 安全でない暗号化
- [ ] パストラバーサル
- [ ] コマンドインジェクション
- [ ] 安全でないデシリアライゼーション
- [ ] ログへの機密情報出力

### パフォーマンス（⚡）

- [ ] O(n²)以上の計算量
- [ ] N+1クエリ問題
- [ ] 不要なメモリ確保
- [ ] 同期処理のボトルネック
- [ ] キャッシュ未使用
- [ ] 不要なループ・再計算
- [ ] 大きなペイロード
- [ ] インデックス未使用のクエリ（WHERE句・JOIN条件・ORDER BY・GROUP BY）
- [ ] フルテーブルスキャンの発生
- [ ] 新規テーブル・カラム追加時のインデックス定義漏れ
- [ ] リソースリーク（未クローズ）
- [ ] 不要なデータ取得

### 品質・保守性（📐）

- [ ] 命名の不明確さ
- [ ] 関数の長さ（50行超）
- [ ] 循環的複雑度（10超）
- [ ] DRY原則違反
- [ ] SOLID原則違反
- [ ] エラーハンドリング不足
- [ ] マジックナンバー
- [ ] コメント不足/過剰
- [ ] テスト困難な構造
- [ ] 型ヒント/ドキュメント不足

### 懐疑的検証（🤔）

- [ ] 要件との乖離（実装が要件を正しく満たしているか）
- [ ] 過剰実装（YAGNI原則違反、不要な抽象化）
- [ ] 見落とされたedge case
- [ ] より単純な代替案の有無
- [ ] 変更の必要性（本当にこの変更が必要か）
- [ ] 暗黙の仮定（ドキュメント化されていない前提条件）

### テスト充足度（🧪）

- [ ] テストの有無
- [ ] 正常系のカバレッジ
- [ ] 異常系・エッジケース
- [ ] 境界値テスト
- [ ] モック/スタブの適切な使用
- [ ] テストの独立性
- [ ] テスト名の明確さ
- [ ] アサーションの適切さ

### ファイル横断チェック（ブランチレビュー時）

- [ ] インポート/エクスポートの整合性
- [ ] 型定義の一貫性
- [ ] 命名規則の統一
- [ ] 新規ファイルに対応するテストの有無

## CLAUDE.md 連携

プロジェクトの `CLAUDE.md` に記載されたコーディング規約も自動的にチェック対象に含めます。

## オプション

| 指定 | 説明 |
|------|------|
| `/isac-code-review` | ブランチの変更全体をレビュー（デフォルト） |
| `/isac-code-review --staged` | ステージング済みのみレビュー |
| `/isac-code-review --security` | セキュリティ観点のみ |
| `/isac-code-review --performance` | パフォーマンス観点のみ |
| `/isac-code-review --quality` | 品質・保守性観点のみ |
| `/isac-code-review [ファイルパス]` | 特定ファイルのみレビュー |

## 修正後の再レビュー

指摘事項を修正した後、再度 `/isac-code-review` を実行して修正を確認できます。

再レビュー時は前回スコアとの比較を表示：

```
## 📊 レビュースコア: 92/100 (前回: 68/100, +24点)

### 改善された項目
- ✅ src/auth/login.py:L23 - SQLインジェクション対策 (+15点)
- ✅ src/auth/login.py:L30 - N+1クエリ解消 (+7点)

### 残りの指摘事項
- 🟢 src/models/user.py:L12 - マジックナンバーの使用 (-2点)
```

## /isac-pr-review との違い

| 観点 | `/isac-code-review` | `/isac-pr-review` |
|------|---------------------|-------------------|
| 対象 | ローカルのGit変更 | GitHub上のPR |
| 出力 | ターミナル | PRコメント |
| 用途 | PR作成前のセルフチェック | PR作成後のチームレビュー |

## 関連スキル

- `/isac-pr-review` - GitHub PRレビュー（PRコメントに投稿）
- `/isac-review` - 設計レビュー（方針・アーキテクチャの検討）
- `/isac-autopilot` - 設計→実装→テスト→レビュー→Draft PR作成を自動実行
- `/isac-decide` - 決定の記録
- `/isac-memory` - 記憶の検索・管理
- `/isac-save-memory` - AI分析による保存形式提案
- `/isac-suggest` - 状況に応じたSkill提案
