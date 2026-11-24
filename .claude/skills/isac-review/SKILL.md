---
name: isac-review
description: 設計や技術選定を複数のペルソナで検討し、決定を記録します。
effort: high
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
/isac-review [議題]                    # 既定: インライン（1体が4ペルソナを演じる）。--quick / --full / --team で人数を変える
/isac-review --dialectic [議題]        # 選択肢の意思決定（A vs B）。選択肢ごとに擁護役を立てて独立ジャッジが比べる
/isac-review --agents [対象]           # 徹底レビュー。多レンズで対象の問題を網羅して洗い出す（issue-finding）
```

`--dialectic` / `--agents` の詳細は「モードの使い分け」以降を参照。指定が無ければ従来どおりインラインで動作する。

## 実行手順

### 1. ペルソナの設定

以下の4人のペルソナで議論を行います：

| ペルソナ | 役割 | 視点 |
|---------|------|------|
| 実装者 | バックエンド/フロントエンド開発者 | 実装の容易さ、保守性、コード品質 |
| 運用者 | SRE/DevOpsエンジニア | 運用負荷、監視、スケーラビリティ |
| アーキテクト | 技術リード/設計者 | 全体設計、拡張性、技術的負債 |
| 懐疑的レビュアー | 批判的検証者 | 要件との乖離、過剰設計、見落とされたリスク、より単純な代替案の有無、**もっともらしいが誤った事実主張（plausible-but-wrong）** |

> **重要（同一モデルの限界）**: このペルソナ4人は全員同じモデル（Claude）であり、**知識の盲点が相関する**。
> したがってペルソナ合意は「トレードオフ・考慮漏れ・設計判断」には有効だが、**事実の正しさ（correctness）を保証しない**。
> ツール・コマンド・ランタイムの挙動に関する断定（例:「`timeout` はシェル関数を実行できる」「この正規表現は POSIX 互換」）は、
> **合意ではなく実行で確認する対象**として扱うこと。懐疑的レビュアーはこうした事実主張を最優先で洗い出し、検証を要求する。

### 2. 議論フォーマット

各ペルソナは以下の形式で意見を述べます：

```
**👨‍💻 [名前]（[役割]）**
> [意見・主張]
>
> **懸念点**: [あれば]
> **推奨**: [A案/B案/その他]
```

### 2.5. 実行検証ゲート（runnable な成果物がある場合は必須）

議論で**実行可能な成果物**（シェルスクリプト、CI 設定、SQL、正規表現、コードスニペット、コマンド列）が
設計・結論に含まれる場合、**投票・結論を確定する前に実際に検証する**こと。議論だけで確定してはならない。

| 成果物 | 最低限の検証手段 |
|--------|----------------|
| シェル/Bash | `bash -n`（構文）＋ ダミーコマンドや stub で実走（retry ループ等はダミーで挙動確認） |
| 環境依存の挙動 | `docker run` で実機確認（`timeout` の有無/GNU vs BSD、`/etc/os-release`、coreutils 差異 等） |
| 正規表現 | 実データでマッチを実行（POSIX/PCRE の差異に注意） |
| SQL | 実 DB or スキーマに対して `EXPLAIN`／dry-run |
| コード片 | 最小ケースで実行し、戻り値・例外を観測 |

**ルール**:
- 検証した主張には ✅検証済、できなかった主張には ⚠️未検証 のラベルを必ず付ける。**未検証の事実主張を「確定」として提示しない**。
- 「もっともらしい補足説明」を足して考えてある感を出すのは禁止。**接地（実行）していない説明は誤りを覆い隠す**。
- 検証ツールが無い場合（例: ローカルに `shellcheck` なし）は、`docker` 等の代替手段を試みる。それも不可なら ⚠️未検証 と明記し、結論にリスクとして記載する。
- 組み込みの `/verify` スキル（アプリを実走して挙動確認）が使える場合は活用する。

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
if printf '%s\n' "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    MEMORY_ID=$(printf '%s\n' "$RESPONSE" | jq -r '.id')
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

## モードの使い分け（実測に基づく・重要）

`isac-review` のタスクは大きく2種類あり、**A/B 実測（N=5、`docs/DESIGN_isac-review-agents.md` §8）で最適モードが分かれた**：

| やりたいこと | 推奨モード | 実装 |
|-------------|-----------|------|
| **選択肢の意思決定**（A vs B を選ぶ） | **`--dialectic`（弁証法）** | `.claude/workflows/isac-review-dialectic.js` |
| **徹底レビュー**（設計/コードの問題を多レンズで網羅） | **`--agents`**（レビュー版・issue-finding） | `.claude/workflows/isac-review-issues.js` |
| 軽量レビュー・軽い相談 | **インライン**（既定） | このスキル本体 |

> **実測の要点**: 「A vs B の決定」では投票式は少数案が収束で潰れるため、**立場を割り当てて steelman を義務化する弁証法が少数案を最強のまま保持**し switching condition と較正 confidence を出す（N=5 で確認）。一方「問題の網羅レビュー」では**多レンズ並列（--agents）が inline の約2倍の issue を接地して拾う**（ただし severity インフレ傾向あり）。

## 弁証法モード（`--dialectic`）— 意思決定用

**目的**: 選択肢間の意思決定で、**負ける案を最強の論拠のまま保持**する（投票式が構造的にできなかったアンカリング対策）。各選択肢に advocate を割り当て（信念でなく割当てを steelman）→ 相互反駁 → 擁護に不参加の独立ジャッジが weigh。

**起動**: 議題が離散選択（例「JWT vs セッション」）のとき、Workflow を `{ name: "isac-review-dialectic", args: { topic, context, options: [...] } }` で起動（Skill が指示＝明示オプトイン）。選択肢は2〜6個・重複不可。

**出力（推奨レポート）**: 各案の steelman（strongest_case・key_evidence・先回り封じ）／相互反駁／独立ジャッジの `recommendation`・`confidence`（low/med/high）・`decisive_factors`・`residual_risks`（推奨案に残るリスク）・**`losing_option_standing`（負ける案の“勝ち条件”）**。**投票ではない。** 決定は人間が `/isac-decide` で確定（原則9）。

**エージェント数**: 擁護N＋反駁N＋ジャッジ1 ＝ 2N+1（二択で5体）。選択肢数でスケール。

**部分失敗の扱い**: 擁護に失敗した選択肢は比較から除外され、ジャッジも推奨できない（`dropped_options` に入る）。
`dropped_options` が空でなければ「この選択肢は擁護を得られず比較していない」とレポートに必ず明記する（負けたのではなく、比べていない）。
擁護が2件未満なら `error`（`degraded: true`）が返るので、推奨として扱わずユーザーに伝える。

## エージェントチームモード（`--agents`）— 徹底レビュー用（issue-finding）

**目的（実測で再定義）**: 当初は「アンカリング低減」を狙ったが、A/B 実測でそれは達成されず（決定用途は `--dialectic` が担当）。`--agents` の実価値は**多レンズ並列＋実行接地で対象の問題を網羅的に洗い出す“徹底レビュー”**にあった。実装 `.claude/workflows/isac-review-issues.js`、設計は `docs/DESIGN_isac-review-agents.md`。

> **用途**: 設計/コード/計画などの**レビュー（問題の網羅列挙）**。**A vs B の意思決定には使わない → `--dialectic` を使う**。
> **注**: severity インフレ対策の **adversarial-verify を実装済み**（`isac-review-issues.js` の Verify 段）。🔴High 指摘のみ独立反証者（迷ったら偽陽性/降格に倒す）が接地検証し、confirmed / downgrade / false_positive に再分類する。検証エージェント失敗(null)は安全側で🔴に昇格させない。出力の `verification.raw_high` vs `confirmed_high` で **インフレ量が可視化**される。med/low は対象外（コスト対効果）。偽陽性率の A/B 実測は次段階。
> **失敗の扱い**: 返却値に `error` があれば（対象の指定漏れ・全レンズ失敗など）レビュー結果として扱わず、内容をそのままユーザーに伝える（「指摘0件」と書かない）。
> `failed_lenses` が空でなければ「このレンズは失敗し未レビュー」と明記する。`verification.verify_failed` が1以上なら、🔴が0件でも「🔴なし」と書かず、検証できなかった🔴候補（`filtered_out_detail` の `verdict: "unverified"`）を一覧で示す。

### 実行手順（`--agents` 指定時）

1. **レビュー対象**を決める。ファイルなら `artifact_path`（レビュアーが実際に読む・構文チェックする）、会話中の設計文などなら `artifact` に本文を渡す。
2. **文脈(context)** を用意する（目的・前提・制約など。任意）。
3. **Workflow を起動**: `{ name: "isac-review-issues", args: { artifact_path | artifact, context } }`（Skill が指示する Workflow ＝明示オプトインに該当）。
   レンズは5つ固定（セキュリティ／信頼性・エラー処理／パフォーマンス・コスト／保守性・可読性／エッジケース・懐疑）。
4. 返却値を重大度別（🔴 `high` = 検証を通ったもののみ／🟡 `med`／🟢 `low`）に整形して提示する。上の「失敗の扱い」に従う。

### フラグの扱い

| フラグ | 扱い |
|--------|------|
| `--inline` | 明示インライン（`--agents` と相互排他）。`/isac-autopilot` 等が内部で isac-review を呼ぶ経路は `--inline` を明示する（`--agents` の追加コストが自動フローで静かに発生しないように） |
| `--quick` / `--full` / `--team` | **インラインの人数指定**（上の「オプション: ペルソナ数の変更」）。`--agents` と一緒に指定されても `--agents` のレンズ数（5つ固定）は変わらないので、無視する旨を一言伝える |
| `--blind-only` | **廃止**（旧・投票式 `--agents` 専用だった）。指定されたら、廃止済みであることと、レビューなら `--agents`、選択肢の意思決定なら `--dialectic` を使うことを伝える |

> **旧・投票式 `--agents`（`isac-review-agents` workflow）は起動しない。** 決定用途は `--dialectic` に、レビュー用途は issue-finding に置き換えた。
> 旧仕様（3直交軸のフラグ・投票集計・推奨レポートの形式）は記録として `docs/DESIGN_isac-review-agents.md` の付録に移した。

### ガバナンス（CLAUDE.md 原則9）
- `--agents` / `--dialectic` の出力は**推奨（recommendation）であって決定ではない**。`type=decision` として自動保存しない。
  決定として残すかはユーザーが `/isac-decide` で確認・確定する（レビュー結論を下書きに使ってよい）。

## 関連スキル

- `/isac-memory` - 記憶の検索・管理
- `/isac-decide` - 決定の直接記録（レビューなし）
- `/isac-code-review` - コードレビュー（実装の品質チェック）
- `/isac-pr-review` - GitHub PRレビュー（PRコメント投稿）
- `/isac-autopilot` - 設計→実装→テスト→レビュー→Draft PR作成を自動実行
- `/isac-save-memory` - AI分析による保存形式提案
- `/isac-suggest` - 状況に応じたSkill提案
