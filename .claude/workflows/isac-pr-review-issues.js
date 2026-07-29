/**
 * isac-pr-review 徹底レビュー版（--agents）workflow
 *
 * 位置づけ: isac-review-issues.js（issue-finding＋adversarial-verify）の PR レビュー版。
 * A/B 実測(N=5)で「多レンズ並列は inline 比 約2倍の issue を接地発見」「raw High の較正には
 * 独立反証者が有効(raw19→confirmed6・本物のセキュリティバグは confirmed・盛られた🔴は降格)」
 * と実証された（docs/DESIGN_isac-review-agents.md §8）。それを PR の diff に適用する。
 *
 * PR レビューは出力が「公開・不可逆な PR コメント」になるため、verify（🔴の偽陽性ゲート）を
 * inline 以上に重視する。SKILL 側は本 workflow の confirmed High のみを🔴として提示し、
 * --dry-run 既定＋✅検証済/⚠️未検証ラベルを義務づけること（弁証法ジャッジの移行条件）。
 *
 * args: { pr_number?, diff, worktree_path?, context?, model? }
 *   - diff: `gh pr diff <PR>` の出力（レビューの一次対象・必須）
 *   - worktree_path: PR ブランチを checkout した worktree（周辺コード参照・実行接地に使う）
 *   - context: PR タイトル/説明/議論など補助文脈
 *   - model: レビュー/検証エージェントのモデル（既定 'fable'。'inherit' でセッション継承に戻す）
 *
 * モデル方針（CLAUDE.md「Skill ごとの model は原則 inherit」の明示的例外）:
 *   本 workflow の Review/Verify は既定で Fable 5 に固定する。理由は (1) 出力が公開・不可逆な PR
 *   コメントであり、issue 発見の網羅性と🔴偽陽性ゲートの判定精度が成果物の質に直結する、(2) その質を
 *   セッション側のモデル選択に左右させたくない、の2点（＝例外条項「品質の問題が観測された/技術的必然」に該当）。
 *   固定はエイリアス（'fable'）であり具体 model ID ではないため世代交代で腐らない（agents の 'haiku' と同型）。
 *   対応外プランのメンバーは args.model で上書きできる（配布事故の回避策）。
 */

export const meta = {
  name: 'isac-pr-review-issues',
  description: 'PRレビュー徹底版: PR diff を多レンズで issue-finding→🔴を独立反証者で検証→file/重大度別に集約',
  phases: [
    { title: 'Review', detail: '多レンズ並列で PR diff の issue を接地列挙' },
    { title: 'Verify', detail: '🔴High指摘を独立反証者で偽陽性チェック（公開前ゲート）' },
    { title: 'Aggregate', detail: 'JSで file/重大度別に集約' },
  ],
}

let A = args || {}
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (e) { A = {} } }
const PR_NUMBER = A.pr_number || ''
const DIFF = A.diff || ''
const WORKTREE = A.worktree_path || ''
const CONTEXT = A.context || ''
// 既定 Fable 5 固定。'inherit' 指定時のみ undefined = セッション継承（詳細は冒頭のモデル方針）。
const MODEL = A.model === 'inherit' ? undefined : (A.model || 'fable')
if (!DIFF) {
  return { error: 'diff が必須（gh pr diff <PR> の出力を渡すこと）' }
}

const GROUND = WORKTREE
  ? `\n【周辺コード参照】PR ブランチが ${WORKTREE} に checkout 済み。diff だけで判断せず、必要なら worktree 内のファイルを実際に読み、runnable なら構文チェック/実行して接地せよ。`
  : `\n【注意】worktree 未提供。diff の範囲でのみ判断し、diff 外への断定は避けること。`

const TARGET = `【レビュー対象: PR${PR_NUMBER ? ' #' + PR_NUMBER : ''} の差分】\n${DIFF}${GROUND}`

// PR レビューは公開・不可逆ゆえセキュリティ・機密漏洩の見落としコストが高い。5レンズで網羅。
const LENSES = [
  { key: 'security', label: 'セキュリティ', focus: '機密情報の混入・インジェクション・入力検証・認可・危険な実行・秘密のハードコード' },
  { key: 'reliability', label: '信頼性/エラー処理', focus: '失敗時の挙動・例外・部分失敗・リトライ・境界での破綻・冪等性・後方互換' },
  { key: 'perf_cost', label: 'パフォーマンス/コスト', focus: 'N+1・計算量・並列度・インデックス・リソース消費・スケール時の破綻' },
  { key: 'maintainability', label: '保守性/可読性', focus: '命名・重複(DRY)・複雑度・テスト有無・説明と実装の整合・将来変更のしやすさ' },
  { key: 'correctness_skeptic', label: 'エッジケース/懐疑', focus: '正しさの穴・plausible-but-wrong・見落とされた edge case・過剰実装・より単純な代替' },
]

const FINDING_PROPS = {
  severity: { type: 'string', enum: ['high', 'med', 'low'] }, // 🔴/🟡/🟢
  file: { type: 'string' },          // リポジトリ相対パス（PRコメントに載せる）
  area: { type: 'string' },
  issue: { type: 'string' },
  evidence: { type: 'string' },      // 接地(diffの該当行/worktreeのコード/実行結果)
  suggested_fix: { type: 'string' },
}
const SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['severity', 'file', 'area', 'issue', 'evidence', 'suggested_fix'],
        properties: FINDING_PROPS,
      },
    },
  },
}

// ===== Review（多レンズ並列・投票なし）=====
phase('Review')
const reviews = (await parallel(LENSES.map((L) => () =>
  agent(
    `${TARGET}\n${CONTEXT ? '\n【PR文脈(タイトル/説明/議論)】' + CONTEXT + '\n' : ''}\n` +
    `あなたは【${L.label}】レンズの PR レビュアー。観点: ${L.focus}\n` +
    `この PR の差分を精査し、問題(findings)を列挙せよ。各 finding は severity(high/med/low)、file(リポジトリ相対パス)、area、issue、evidence(diffの該当行や worktree のコード・実行/構文チェック結果で接地)、suggested_fix を持つ。\n` +
    `runnable なら実際に読んで/走らせて確認し、接地しない断定はしない。🔴High は「マージ前必須修正」級に限る。問題が無ければ findings は空配列。`,
    { label: `REV:${L.label}`, phase: 'Review', schema: SCHEMA, model: MODEL }
  ).then((r) => (r ? { ...r, lens: L.label } : null))   // 失敗(null)は保持・lensはコード側を勝たせる
))).filter(Boolean)

const all = []
for (const r of reviews) for (const f of (r.findings || [])) all.push({ lens: r.lens, ...f })

// ===== Verify（🔴High のみ独立反証者で偽陽性チェック。公開前ゲート）=====
// PRコメントは公開・不可逆。severity インフレ(実測で raw High の約7割が非High)を通さない。
// 反証者は「迷ったら偽陽性/降格に倒す」。検証失敗(null)は安全側=unverified(🔴に昇格させない)。
phase('Verify')
const VERIFY_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['verdict', 'reasoning'],
  properties: {
    verdict: { type: 'string', enum: ['confirmed', 'downgrade', 'false_positive'] },
    adjusted_severity: { type: 'string', enum: ['med', 'low'] }, // downgrade 時の落とし先
    reasoning: { type: 'string' },
  },
}
const rawHigh = all.filter((f) => f.severity === 'high')
const verified = rawHigh.length === 0 ? [] : (await parallel(rawHigh.map((f, i) => () =>
  agent(
    `${TARGET}\n` +
    `あなたは独立した検証者(skeptic)で、この指摘を出したレビュアーとは別人。以下の🔴High指摘が本当に「マージ前必須修正」級か、偽陽性・過大評価でないかを反証せよ。\n` +
    `【指摘(${f.lens}レンズ)】file: ${f.file}\narea: ${f.area}\nissue: ${f.issue}\nevidence: ${f.evidence}\nsuggested_fix: ${f.suggested_fix}\n\n` +
    `${WORKTREE ? 'worktree のコードを実際に読んで/走らせて接地して判断せよ。' : 'diff の範囲で接地して判断せよ。'}` +
    `verdict は confirmed(接地でき真に High) / downgrade(実在するが過大→adjusted_severity で med/low) / false_positive(誤り・的外れ)。` +
    `迷ったら confirmed にせず downgrade か false_positive に倒すこと（公開 PR コメントに載る🔴なので偽陽性を通さない側に倒す）。`,
    { label: `VERIFY:${f.file || f.area}#${i}`, phase: 'Verify', schema: VERIFY_SCHEMA, model: MODEL }
  ).then((v) => (v
    ? { ...f, verdict: v.verdict, adjusted_severity: v.adjusted_severity, verify_reasoning: v.reasoning }
    : { ...f, verdict: 'unverified', verify_reasoning: '検証エージェント失敗のため安全側で未確定扱い' }))
)))

// ===== 集約（JS・file/重大度別。high は検証を通ったものだけ）=====
phase('Aggregate')
const bySev = { high: [], med: [], low: [] }
for (const f of all) if (f.severity !== 'high') bySev[f.severity].push(f)
const filteredOut = []   // 偽陽性・未確定（🔴から除外され公開しない）
for (const v of verified) {
  if (v.verdict === 'confirmed') bySev.high.push(v)
  else if (v.verdict === 'downgrade') bySev[v.adjusted_severity || 'med'].push({ ...v, downgraded_from: 'high' })
  else filteredOut.push(v)   // false_positive / unverified
}
// file 別に複数レンズが指摘したか（注目度）
const fileCount = {}
for (const f of all) if (f.file) fileCount[f.file] = (fileCount[f.file] || 0) + 1

return {
  mode: 'pr-review(issue-finding)',
  pr_number: PR_NUMBER || null,
  model: MODEL || 'inherit',   // レビュー/検証に使ったモデル（レポートに併記して再現性を担保）
  lenses: LENSES.map((l) => l.label),
  total_findings: all.length,
  counts: { high: bySev.high.length, med: bySev.med.length, low: bySev.low.length },
  high: bySev.high,   // confirmed のみ = 公開🔴に載せてよいもの
  med: bySev.med,
  low: bySev.low,
  // severity インフレの可視化: レビュアーの raw High と、検証を通った confirmed High の差
  verification: {
    raw_high: rawHigh.length,
    confirmed_high: bySev.high.length,
    downgraded: verified.filter((v) => v.verdict === 'downgrade').length,
    filtered_out: filteredOut.length,
    filtered_out_detail: filteredOut.map((v) => ({ file: v.file, area: v.area, lens: v.lens, verdict: v.verdict, reason: v.verify_reasoning })),
  },
  multi_lens_files: Object.entries(fileCount).filter(([, n]) => n >= 2).map(([f, n]) => ({ file: f, findings: n })),
  governance_note: 'レビュー結果は指摘であり決定ではない。🔴High は独立反証者の検証(confirmed)を通ったもののみ。公開投稿の可否・スコアは人間が判断する。',
}
