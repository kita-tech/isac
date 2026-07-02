/**
 * isac-review レビュー(issue-finding)モード プロトタイプ
 *
 * 位置づけ(実測に基づく再定義): --agents は「A vs B の決定」用途では --dialectic に包含される。
 * 生き残る価値は「選択肢の無いレビュー＝多レンズで問題を網羅的に洗い出す issue-finding」。
 * 本 workflow はその検証用プロトタイプ。投票しない。各レンズが対象 artifact の問題を接地して列挙し、
 * JS が重大度別に集約する。
 *
 * args: { artifact_path?: string, artifact?: string, context?: string }
 *   - artifact_path: レビュー対象ファイル(レビュアーが読んで検証)。または artifact に本文を直接渡す。
 */

export const meta = {
  name: 'isac-review-issues',
  description: 'レビュー(issue-finding)モード: 多レンズで対象の問題を網羅列挙→重大度別に集約。決定でなくレビュー用',
  phases: [
    { title: 'Review', detail: '多レンズ並列で issue を接地列挙' },
    { title: 'Aggregate', detail: 'JSで重大度別に集約' },
  ],
}

let A = args || {}
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (e) { A = {} } }
const ARTIFACT_PATH = A.artifact_path || ''
const ARTIFACT = A.artifact || ''
const CONTEXT = A.context || ''
if (!ARTIFACT_PATH && !ARTIFACT) {
  return { error: 'artifact_path または artifact が必須' }
}

const TARGET = ARTIFACT_PATH
  ? `【レビュー対象ファイル】${ARTIFACT_PATH}\n（このファイルを実際に読み、必要なら実行/構文チェックして検証すること）`
  : `【レビュー対象（本文）】\n${ARTIFACT}`

const LENSES = [
  { key: 'security', label: 'セキュリティ', focus: '機密情報・インジェクション・入力検証・認可・危険な実行' },
  { key: 'reliability', label: '信頼性/エラー処理', focus: '失敗時の挙動・例外・部分失敗・リトライ・境界での破綻・冪等性' },
  { key: 'perf_cost', label: 'パフォーマンス/コスト', focus: '計算量・並列度・トークン/リソース消費・スケール時の破綻' },
  { key: 'maintainability', label: '保守性/可読性', focus: '命名・重複・複雑度・将来変更のしやすさ・ドキュメント整合' },
  { key: 'correctness_skeptic', label: 'エッジケース/懐疑', focus: '正しさの穴・plausible-but-wrong・見落とされた edge case・より単純な代替' },
]

const SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['severity', 'area', 'issue', 'evidence', 'suggested_fix'],
        properties: {
          severity: { type: 'string', enum: ['high', 'med', 'low'] }, // 🔴/🟡/🟢
          area: { type: 'string' },
          issue: { type: 'string' },
          evidence: { type: 'string' },      // 接地(コードの該当箇所/実行結果)
          suggested_fix: { type: 'string' },
        },
      },
    },
  },
}

// ===== Review（多レンズ並列・投票なし）=====
phase('Review')
const reviews = (await parallel(LENSES.map((L) => () =>
  agent(
    `${TARGET}\n${CONTEXT ? '【文脈】' + CONTEXT + '\n' : ''}\n` +
    `あなたは【${L.label}】レンズのレビュアー。観点: ${L.focus}\n` +
    `対象を精査し、問題(findings)を列挙せよ。各 finding は severity(high/med/low)、area、issue、evidence(コードの該当箇所や実行/構文チェック結果で接地)、suggested_fix を持つ。` +
    `runnable なら実際に読んで/走らせて確認し、接地しない断定はしない。問題が無ければ findings は空配列。`,
    { label: `REV:${L.label}`, phase: 'Review', schema: SCHEMA }
  ).then((r) => (r ? { ...r, lens: L.label } : null))   // 失敗(null)は保持・lensはコード側を勝たせる
))).filter(Boolean)

// ===== 集約（JS・重大度別。投票なし）=====
phase('Aggregate')
const all = []
for (const r of reviews) for (const f of (r.findings || [])) all.push({ lens: r.lens, ...f })
const bySev = { high: [], med: [], low: [] }
for (const f of all) (bySev[f.severity] || bySev.low).push(f)
// area 別のヒット・レンズ数（複数レンズが同 area を挙げたら注目度高）
const areaCount = {}
for (const f of all) areaCount[f.area] = (areaCount[f.area] || 0) + 1

return {
  mode: 'review(issue-finding)',
  target: ARTIFACT_PATH || '(inline artifact)',
  lenses: LENSES.map((l) => l.label),
  total_findings: all.length,
  counts: { high: bySev.high.length, med: bySev.med.length, low: bySev.low.length },
  high: bySev.high,
  med: bySev.med,
  low: bySev.low,
  multi_lens_areas: Object.entries(areaCount).filter(([, n]) => n >= 2).map(([a, n]) => ({ area: a, lenses: n })),
  governance_note: 'レビュー結果は指摘であり決定ではない。対応要否は人間が判断する。',
}
