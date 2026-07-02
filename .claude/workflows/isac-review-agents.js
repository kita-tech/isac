/**
 * isac-review エージェントチームモード（--agents）本実装
 *
 * 設計: docs/DESIGN_isac-review-agents.md（#1〜#5 確定 + PoC/Gemini 反映）
 *
 * フロー: Round1 ブラインド並列 → [既定ON] Round2 構造化相互反論（再spawn・匿名注入）→ JS 機械集計
 * 出力: 推奨レポート（recommendation）。★decision には保存しない（ガバナンス §11）。
 *
 * args（SKILL.md から渡す）:
 *   { topic: string, context: string, options?: string[], N?: number, blindOnly?: boolean }
 *   - topic:    レビュー議題（例「認証方式の選定」）
 *   - context:  レビュー材料（設計文/要約/差分など）
 *   - options:  離散選択肢（例 ["JWT","session"]）。あれば投票、なければオープン（人間が統合）
 *   - N:        レビュアー数（2/4/5/10。既定4）
 *   - blindOnly: true で Round2 を省略（独立性MAX・最安）
 *
 * 注（Gemini クロスレビュー反映・§7）:
 *   - Round2 入力は O(N²)（各体に他 N-1 体の意見を注入）。大 N は不相応に高コスト → コストガードは SKILL.md 側。
 *   - 実行検証は軽量・read-only を原則。stateful な検証が要る場合のみ各 agent に {isolation:'worktree'} を付ける
 *     （本スクリプトは既定で worktree を使わない＝コスト優先。必要時にこの行を有効化する）。
 */

export const meta = {
  name: 'isac-review-agents',
  description: 'isac-review --agents: ブラインド並列レビュー→構造化相互反論(再spawn)→JS機械集計。出力は推奨(decisionではない)',
  phases: [
    { title: 'Round1', detail: 'N体ブラインド並列レビュー(schema検証)' },
    { title: 'Round2', detail: '他体の匿名意見を注入し再spawnで再評価' },
    { title: 'Aggregate', detail: 'JSで投票集計・争点・🔴/懐疑ハイライト・provenance' },
  ],
}

// ---- args 正規化 ----
// tool 経由の args は JSON 文字列で届くことがあるため、文字列ならパースする
let A = args || {}
if (typeof A === 'string') {
  try { A = JSON.parse(A) } catch (e) { A = {} }
}
const TOPIC = A.topic || '(議題未指定)'
const CONTEXT = A.context || '(レビュー材料未指定)'
const OPTIONS = Array.isArray(A.options) ? A.options.filter(Boolean) : []
const HAS_OPTIONS = OPTIONS.length >= 2
const N = [2, 4, 5, 10].includes(A.N) ? A.N : 4
const BLIND_ONLY = A.blindOnly === true

// ---- 役割スケール（§6 / §12。懐疑役は必須）----
function rolesFor(n) {
  const skeptic = { label: '懐疑', stance: '批判的検証者。前提の妥当性・過剰実装・plausible-but-wrong（もっともらしい誤り）・実証の有無を問え。runnable な主張は検証を要求せよ。' }
  const lenses = [
    { label: '推進派×アーキ', stance: '採用/推進側を弁護。全体設計・拡張性・技術的負債の観点。' },
    { label: '反対派×運用', stance: '反対/慎重側を弁護。運用負荷・コスト・致命的欠点を探せば報われる。' },
    { label: '中立×実装', stance: '中立。実装容易性・保守性・後方互換から是々非々で。' },
    { label: 'セキュリティ', stance: 'セキュリティ・データ保護・入力検証・認可の観点。' },
    { label: 'パフォーマンス', stance: '計算量・N+1・リソース効率・スケールの観点。' },
    { label: 'UX/DX', stance: '利用者/開発者体験・学習コストの観点。' },
    { label: '保守性', stance: '可読性・命名・DRY/SOLID・テスト容易性の観点。' },
    { label: '推進派×挑戦的', stance: '挑戦的立場でアップサイド・機会を最大化する視点。' },
    { label: '反対派×保守的', stance: '保守的立場でダウンサイド・失敗モードを最小化する視点。' },
  ]
  return [...lenses.slice(0, Math.max(1, n - 1)), skeptic]
}
const ROLES = rolesFor(N)

// ---- schema（options があれば position を enum に）----
const positionSchema = HAS_OPTIONS ? { type: 'string', enum: OPTIONS } : { type: 'string' }
const R1_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['position', 'rationale', 'concerns', 'critical_risks', 'recommendation'],
  properties: {
    position: positionSchema,
    rationale: { type: 'string' },
    concerns: { type: 'array', items: { type: 'string' } },
    critical_risks: { type: 'array', items: { type: 'string' } }, // 🔴級（票に還元せず前面提示）
    recommendation: { type: 'string' },
    verified_claims: { type: 'array', items: { type: 'string' } }, // 実行検証した主張（#63）
  },
}
const R2_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['revised_position', 'changed', 'change_justification', 'refutations', 'new_risks', 'critical_risks'],
  properties: {
    revised_position: positionSchema,
    changed: { type: 'boolean' },
    change_justification: { type: 'string' }, // 変えないなら "unchanged"
    refutations: { type: 'array', items: { type: 'string' } },
    new_risks: { type: 'array', items: { type: 'string' } },
    critical_risks: { type: 'array', items: { type: 'string' } },
  },
}

const OPT_LINE = HAS_OPTIONS
  ? `選択肢（position はこの中から必ず1つ選べ）: ${OPTIONS.join(' / ')}`
  : `離散選択肢は無い。position には自分の推奨を短いラベルで書け（後で人間が統合する）。`

const COMMON = `【議題】${TOPIC}\n${OPT_LINE}\n\n【レビュー材料】\n${CONTEXT}\n\n` +
  `【検証ルール】runnable な事実主張（コマンド/シェル/SQL/正規表現の挙動、コスト試算等）は、可能な範囲で実際に確認し verified_claims に記せ。` +
  `検証は軽量・read-only を原則とする（重い/状態を変える検証はしない）。接地していない断定はしないこと。` +
  `致命的リスク（本番障害・セキュリティ・要件不成立級）は critical_risks に入れよ。`

// ================= Round 1（ブラインド並列）=================
phase('Round1')
const round1 = await parallel(ROLES.map((role) => () =>
  agent(
    `${COMMON}\n\n【あなたの立場/レンズ】${role.label} — ${role.stance}\n` +
    `他レビュアーの意見は見えていない。独立に評価せよ。`,
    { label: `R1:${role.label}`, phase: 'Round1', schema: R1_SCHEMA }
    // 状態を変える検証が要る場合のみ ↓ を有効化（Gemini race 対策・§7）
    // , { label: `R1:${role.label}`, phase: 'Round1', schema: R1_SCHEMA, isolation: 'worktree' }
  ).then((r) => ({ role: role.label, ...r }))
))
const r1 = round1.filter(Boolean)
log(`Round1完了: ${r1.length}/${ROLES.length}体` + (HAS_OPTIONS ? ` / position=${r1.map((v) => v.position).join(',')}` : ''))

// ================= Round 2（再spawn・匿名注入）=================
let r2 = null
if (!BLIND_ONLY && r1.length >= 2) {
  phase('Round2')
  const round2 = await parallel(ROLES.map((role, i) => () => {
    const own = r1[i]
    // 他体の意見を匿名化（肩書・人物を伏せ「意見1/2/3」。§5.2 抑制策1）
    const others = r1
      .filter((_, j) => j !== i)
      .map((o, k) => `意見${k + 1}: [position=${o.position}] ${o.rationale} / 懸念: ${(o.concerns || []).join('; ')}` +
        ((o.critical_risks || []).length ? ` / 🔴: ${o.critical_risks.join('; ')}` : ''))
      .join('\n')
    return agent(
      `${COMMON}\n\n【あなたのRound1の立場】position=${own ? own.position : '?'} — ${own ? own.rationale : ''}\n\n` +
      `【他レビュアーの意見（匿名・順不同）】\n${others}\n\n` +
      `これらを踏まえ再評価せよ。立場を変えるなら change_justification に動かした具体的論拠を書け（変えないなら "unchanged"）。` +
      `他意見で誤り・根拠薄弱と思うものは refutations に、新たに気づいた致命的リスクは critical_risks に、その他の新リスクは new_risks に。`,
      { label: `R2:${role.label}`, phase: 'Round2', schema: R2_SCHEMA }
    ).then((r) => ({ role: role.label, r1_position: own ? own.position : null, ...r }))
  }))
  r2 = round2.filter(Boolean)
} else {
  log(BLIND_ONLY ? 'Round2 省略（--blind-only）' : 'Round2 省略（有効レビュアー<2）')
}

// ================= 集計（JS・決定論。合成エージェント0体）=================
phase('Aggregate')
const finalRows = (r2 && r2.length)
  ? r2.map((v) => ({ role: v.role, position: v.revised_position, r1_position: v.r1_position, critical_risks: v.critical_risks || [] }))
  : r1.map((v) => ({ role: v.role, position: v.position, r1_position: v.position, critical_risks: v.critical_risks || [] }))

// 投票集計（options がある時のみ意味を持つ）
let vote = null, conclusion, split = false
if (HAS_OPTIONS) {
  vote = {}
  for (const o of OPTIONS) vote[o] = 0
  for (const row of finalRows) if (row.position in vote) vote[row.position] += 1
  const ranked = OPTIONS.slice().sort((a, b) => vote[b] - vote[a])
  const top = ranked[0]
  split = ranked.length > 1 && vote[ranked[0]] === vote[ranked[1]]
  conclusion = split ? 'SPLIT（要ユーザー裁定）' : top
} else {
  conclusion = 'OPEN（離散選択肢なし。各推奨を人間が統合）'
}

// provenance: 全員一致は「共有事実への反応」か「独立検証」かを人間が確認するよう注記（PoC反映・§5.1）
const positions = finalRows.map((r) => r.position)
const unanimous = HAS_OPTIONS && new Set(positions).size === 1 && finalRows.length > 1
const provenance = unanimous
  ? '全員一致だが、一致＝独立した複数検証とは限らない（同一の決定的事実に全員が反応した結果でありうる）。一致の実体を人間が確認すること。'
  : null

// 🔴/懐疑ハイライト: 票に還元せず前面提示（原則#7・§5.1/§5.3）
const criticalHighlights = []
for (const row of finalRows) for (const c of (row.critical_risks || [])) criticalHighlights.push({ role: row.role, risk: c })
// 懐疑役の指摘は必ず前面に
const skepticFinal = (r2 && r2.length ? r2 : r1).find((v) => v.role === '懐疑')
const skepticVoice = skepticFinal
  ? { position: skepticFinal.revised_position || skepticFinal.position, points: skepticFinal.refutations || skepticFinal.concerns || [], critical: skepticFinal.critical_risks || [] }
  : null

const changeLog = (r2 && r2.length)
  ? r2.filter((v) => v.changed).map((v) => ({ role: v.role, from: v.r1_position, to: v.revised_position, why: v.change_justification }))
  : []
const minority = HAS_OPTIONS && !split
  ? finalRows.filter((r) => r.position !== conclusion).map((r) => ({ role: r.role, position: r.position }))
  : []
const refutations = (r2 && r2.length) ? r2.flatMap((v) => (v.refutations || []).map((t) => ({ role: v.role, text: t }))) : []
const newRisks = (r2 && r2.length) ? r2.flatMap((v) => (v.new_risks || []).map((t) => ({ role: v.role, text: t }))) : []
const verified = r1.flatMap((v) => (v.verified_claims || []).map((t) => ({ role: v.role, text: t })))

return {
  topic: TOPIC,
  mode: `--agents${BLIND_ONLY ? ' --blind-only' : ''}`,
  participants: finalRows.length,
  rounds: (r2 && r2.length) ? 2 : 1,
  vote,
  conclusion,
  split,
  provenance,                 // 一致の実体注記（null なら該当なし）
  critical_highlights: criticalHighlights, // 🔴（票と別枠で前面）
  skeptic_voice: skepticVoice,             // 懐疑役の指摘（必ず前面）
  agreements: [],             // （将来: 全体一致点の抽出。現状は投票/争点で代替）
  contested: refutations,     // 争点＝相互反論（逐語）
  minority_report: minority,
  change_log: changeLog,
  new_risks: newRisks,
  verified_claims: verified,
  round1_positions: r1.map((v) => ({ role: v.role, position: v.position })),
  governance_note: 'これは推奨(recommendation)であり決定ではない。決定として残すかは人間が /isac-decide で確認・確定する（原則9・§11）。',
}
