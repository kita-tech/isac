// isac-review の3つの Workflow（issues / dialectic / agents）のスタブ実走テスト。
// agent()/parallel()/phase()/log() をスタブに差し替え、部分失敗時の扱いを LLM なしで決定的に検証する。
// 実行: node tests/workflow_review.test.mjs
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import assert from 'node:assert/strict'

const here = dirname(fileURLToPath(import.meta.url))
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
function load(name) {
  const src = readFileSync(join(here, '..', '.claude', 'workflows', name), 'utf8').replace('export const meta', 'const meta')
  return new AsyncFunction('args', 'agent', 'parallel', 'phase', 'log', src)
}
const W = {
  issues: load('isac-review-issues.js'),
  dialectic: load('isac-review-dialectic.js'),
  agents: load('isac-review-agents.js'),
}

/** workflow を実行する。handler(prompt, opts) が各 agent の戻り値を決める（throw は失敗扱い）。 */
async function run(wf, args, handler) {
  const calls = []
  const agent = async (prompt, opts) => { calls.push({ prompt, opts }); return handler(prompt, opts) }
  const parallel = (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))
  const result = await W[wf](args, agent, parallel, () => {}, () => {})
  return { result, calls }
}
const is = (o, prefix) => o.label.startsWith(prefix)

let passed = 0
async function test(name, fn) {
  try { await fn(); passed++; console.log(`  ✓ ${name}`) }
  catch (e) { console.log(`  ✗ ${name}\n    ${e.message}`); process.exitCode = 1 }
}

// ======================================================================
console.log('isac-review-issues workflow（--agents レビュー版）')
const ART = { artifact: 'function f() {}' }
const HIGH = (area) => ({ severity: 'high', area, issue: 'I', evidence: 'E', suggested_fix: 'F' })

await test('対象が無ければ error を返し agent を呼ばない', async () => {
  for (const a of [undefined, {}, 'not json', { artifact: '' }]) {
    const { result, calls } = await run('issues', a, () => ({ findings: [] }))
    assert.match(result.error, /artifact_path または artifact が必須/)
    assert.equal(calls.length, 0)
  }
})
await test('全レンズ失敗は「指摘0件」でなく error。検証は起動しない', async () => {
  for (const h of [() => null, () => { throw new Error('limit') }]) {
    const { result, calls } = await run('issues', ART, h)
    assert.match(result.error, /全レンズ（5体）が失敗/)
    assert.match(result.error, /指摘0件ではない/)
    assert.equal(result.failed_lenses.length, 5)
    assert.equal(result.counts, undefined)
    assert.equal(calls.length, 5)
  }
})
await test('一部のレンズ失敗: 結果は返し、failed_lenses に名前が入る', async () => {
  const { result } = await run('issues', ART, (p, o) => (o.label === 'REV:セキュリティ' ? null : { findings: [] }))
  assert.equal(result.error, undefined)
  assert.deepEqual(result.failed_lenses, ['セキュリティ'])
})
await test('Verify: 🔴だけを検証し、confirmed / downgrade / false_positive / 失敗 を振り分ける', async () => {
  const verdicts = {
    a: { verdict: 'confirmed', reasoning: 'r' },
    b: { verdict: 'downgrade', adjusted_severity: 'low', reasoning: 'r' },
    c: { verdict: 'false_positive', reasoning: 'r' },
    d: null,
    e: { verdict: 'downgrade', reasoning: 'r' },   // adjusted_severity 省略 → med
  }
  const h = (p, o) => {
    if (is(o, 'REV:')) return o.label === 'REV:セキュリティ'
      ? { findings: ['a', 'b', 'c', 'd', 'e'].map(HIGH).concat([{ severity: 'med', area: 'm', issue: 'I', evidence: 'E', suggested_fix: 'F' }]) }
      : { findings: [] }
    return verdicts[o.label.slice('VERIFY:'.length, o.label.indexOf('#'))]
  }
  const { result, calls } = await run('issues', ART, h)
  assert.equal(calls.filter((c) => is(c.opts, 'VERIFY:')).length, 5)   // med は検証しない
  assert.deepEqual(result.high.map((f) => f.area), ['a'])
  assert.deepEqual(result.low.map((f) => f.area), ['b'])
  assert.deepEqual(result.med.map((f) => f.area).sort(), ['e', 'm'])
  assert.equal(result.med.find((f) => f.area === 'e').downgraded_from, 'high')
  assert.equal(result.verification.raw_high, 5)
  assert.equal(result.verification.confirmed_high, 1)
  assert.equal(result.verification.downgraded, 2)
  assert.equal(result.verification.filtered_out, 2)
  assert.equal(result.verification.false_positive, 1)
  assert.equal(result.verification.verify_failed, 1)
})
await test('Verify が全件失敗: 🔴0件でも verify_failed に件数が出る（「🔴なし」と区別できる）', async () => {
  const h = (p, o) => (is(o, 'REV:') ? { findings: o.label === 'REV:セキュリティ' ? [HIGH('x'), HIGH('y')] : [] } : null)
  const { result } = await run('issues', ART, h)
  assert.equal(result.counts.high, 0)
  assert.equal(result.verification.verify_failed, 2)
})
await test('Verify の反証者には対象と主張が渡り、「迷ったら倒す」指示がある', async () => {
  const h = (p, o) => (is(o, 'REV:') ? { findings: o.label === 'REV:セキュリティ' ? [HIGH('auth')] : [] } : { verdict: 'confirmed', reasoning: 'r' })
  const { calls } = await run('issues', { artifact_path: '/tmp/x.js' }, h)
  const v = calls.find((c) => is(c.opts, 'VERIFY:'))
  assert.match(v.prompt, /\/tmp\/x\.js/)
  assert.match(v.prompt, /area: auth/)
  assert.match(v.prompt, /迷ったら confirmed にせず/)
})
await test('🔴が無ければ検証エージェントを起動しない', async () => {
  const { result, calls } = await run('issues', ART, () => ({ findings: [] }))
  assert.equal(calls.length, 5)
  assert.equal(result.verification.verify_failed, 0)
  assert.deepEqual(result.failed_lenses, [])
})

// ======================================================================
console.log('isac-review-dialectic workflow（--dialectic）')
const DIA = { topic: 'T', context: 'C', options: ['JWT', 'session', 'cookie'] }
const adv = (o) => ({ strongest_case: `CASE-${o}`, key_evidence: [`EV-${o}`], preempted_objections: [] })
/** failAdv に入れた選択肢の擁護だけ失敗させるハンドラ */
const diaHandler = (failAdv = [], judge = { recommendation: 'JWT', confidence: 'medium', decisive_factors: [], residual_risks: [], losing_option_standing: 's' }) => (p, o) => {
  if (is(o, 'ADV:')) return failAdv.includes(o.label.slice(4)) ? null : adv(o.label.slice(4))
  if (is(o, 'REB:')) return { rebuttals_of_others: [], defenses: [] }
  return judge
}

await test('選択肢が2未満・7以上・重複のみなら error', async () => {
  for (const options of [undefined, ['A'], ['A', 'A'], ['A', '', null]]) {
    const { result, calls } = await run('dialectic', { options }, diaHandler())
    assert.match(result.error, /2つ以上/)
    assert.equal(calls.length, 0)
  }
  const { result } = await run('dialectic', { options: ['1', '2', '3', '4', '5', '6', '7'] }, diaHandler())
  assert.match(result.error, /多すぎます\(7\)/)
})
await test('全員擁護成功: dropped_options は空、ジャッジは全選択肢から選べる', async () => {
  const { result, calls } = await run('dialectic', DIA, diaHandler())
  assert.deepEqual(result.dropped_options, [])
  const j = calls.find((c) => c.opts.label === 'JUDGE')
  assert.deepEqual(j.opts.schema.properties.recommendation.enum, ['JWT', 'session', 'cookie'])
  assert.equal(calls.length, 7)   // 擁護3＋反駁3＋ジャッジ1
})
await test('擁護失敗の選択肢: 反駁者を立てず、ジャッジの候補と比較材料から外し、dropped_options に出す', async () => {
  const { result, calls } = await run('dialectic', DIA, diaHandler(['cookie']))
  assert.deepEqual(result.dropped_options, ['cookie'])
  assert.deepEqual(calls.filter((c) => is(c.opts, 'REB:')).map((c) => c.opts.label).sort(), ['REB:JWT', 'REB:session'])
  const j = calls.find((c) => c.opts.label === 'JUDGE')
  assert.deepEqual(j.opts.schema.properties.recommendation.enum, ['JWT', 'session'])
  assert.doesNotMatch(j.prompt, /=== cookie ===/)
  assert.match(j.prompt, /擁護\(steelman\)を得られず比較から除外された: cookie/)
  assert.deepEqual(result.options, ['JWT', 'session', 'cookie'])   // 入力の選択肢は残す
  assert.deepEqual(result.advocates.map((a) => a.option), ['JWT', 'session'])
})
await test('元の JUDGE スキーマは変更しない（擁護失敗時も他の必須項目はそのまま）', async () => {
  const { calls } = await run('dialectic', DIA, diaHandler(['session']))
  const s = calls.find((c) => c.opts.label === 'JUDGE').opts.schema
  assert.deepEqual(s.required, ['recommendation', 'confidence', 'decisive_factors', 'residual_risks', 'losing_option_standing'])
  assert.deepEqual(s.properties.confidence.enum, ['low', 'medium', 'high'])
})
await test('擁護が2件未満なら error（degraded）で、反駁・ジャッジを起動しない', async () => {
  const { result, calls } = await run('dialectic', DIA, diaHandler(['session', 'cookie']))
  assert.match(result.error, /2件未満/)
  assert.equal(result.degraded, true)
  assert.deepEqual(result.survived_options, ['JWT'])
  assert.equal(calls.length, 3)
})
await test('反駁の一部失敗はジャッジまで進む（その案の反駁欄は空）', async () => {
  const h = (p, o) => (o.label === 'REB:session' ? null : diaHandler()(p, o))
  const { result } = await run('dialectic', DIA, h)
  assert.deepEqual(result.rebuttals.map((r) => r.option).sort(), ['JWT', 'cookie'])
  assert.ok(result.judge)
})

// ======================================================================
console.log('isac-review-agents workflow（旧・投票式 --agents）')
const AG = { topic: 'T', context: 'C', options: ['A', 'B'], N: 4 }   // 役割: 推進派×アーキ / 反対派×運用 / 中立×実装 / 懐疑
const r1 = (pos) => ({ position: pos, rationale: `R-${pos}`, concerns: [], critical_risks: [], recommendation: 'x' })
const r2 = (pos) => ({ revised_position: pos, changed: false, change_justification: 'unchanged', refutations: [], new_risks: [], critical_risks: [] })
/** R1 の役割ごとの結果（null は失敗）と、R2 の応答を決めるハンドラ */
const agHandler = (r1ByRole, r2Fn = (o) => r2('A')) => (p, o) => (is(o, 'R1:') ? r1ByRole[o.label.slice(3)] : r2Fn(o, p))

await test('Round1 の一部失敗: Round2 は生存者だけを起動し、各自の立場と役割が一致する', async () => {
  const byRole = { '推進派×アーキ': r1('A'), '反対派×運用': null, '中立×実装': r1('B'), '懐疑': { ...r1('B'), rationale: 'SKEPTIC-OWN' } }
  const { result, calls } = await run('agents', AG, agHandler(byRole))
  const round2 = calls.filter((c) => is(c.opts, 'R2:'))
  assert.deepEqual(round2.map((c) => c.opts.label).sort(), ['R2:中立×実装', 'R2:懐疑', 'R2:推進派×アーキ'])
  const sk = round2.find((c) => c.opts.label === 'R2:懐疑')
  assert.match(sk.prompt, /あなたのRound1の立場】position=B — SKEPTIC-OWN/)
  assert.doesNotMatch(sk.prompt.split('【他レビュアーの意見')[1], /SKEPTIC-OWN/)   // 自分の意見を他人の意見として受け取らない
  assert.match(sk.prompt, /R-A/)
  assert.deepEqual(result.failed_roles, ['反対派×運用'])
  assert.equal(result.participants, 3)
})
await test('Round1 の失敗(null)が {role} だけの行として紛れ込まない', async () => {
  const byRole = { '推進派×アーキ': r1('A'), '反対派×運用': null, '中立×実装': r1('A'), '懐疑': r1('B') }
  const { result } = await run('agents', { ...AG, blindOnly: true }, agHandler(byRole))
  assert.deepEqual(result.round1_positions.map((x) => x.role), ['推進派×アーキ', '中立×実装', '懐疑'])
  assert.ok(result.round1_positions.every((x) => x.position))
})
await test('Round2 の一部失敗: 失敗者は集計に入らず、役割名もずれない', async () => {
  const byRole = { '推進派×アーキ': r1('A'), '反対派×運用': r1('B'), '中立×実装': r1('A'), '懐疑': r1('B') }
  const { result } = await run('agents', AG, agHandler(byRole, (o) => (o.label === 'R2:反対派×運用' ? null : r2(o.label === 'R2:懐疑' ? 'B' : 'A'))))
  assert.equal(result.rounds, 2)
  assert.equal(result.participants, 3)
  assert.deepEqual(result.vote, { A: 2, B: 1 })
  assert.equal(result.skeptic_voice.position, 'B')
})
await test('Round1 全員失敗は「0票の SPLIT」でなく error', async () => {
  const byRole = { '推進派×アーキ': null, '反対派×運用': null, '中立×実装': null, '懐疑': null }
  const { result, calls } = await run('agents', AG, agHandler(byRole))
  assert.match(result.error, /全レビュアー（4体）が失敗/)
  assert.equal(result.failed_roles.length, 4)
  assert.equal(result.conclusion, undefined)
  assert.equal(calls.length, 4)
})
await test('全員成功: failed_roles は空で、Round2 は全員分起動する', async () => {
  const byRole = { '推進派×アーキ': r1('A'), '反対派×運用': r1('B'), '中立×実装': r1('A'), '懐疑': r1('B') }
  const { result, calls } = await run('agents', AG, agHandler(byRole))
  assert.deepEqual(result.failed_roles, [])
  assert.equal(calls.filter((c) => is(c.opts, 'R2:')).length, 4)
})

console.log(`\n${passed} passed${process.exitCode ? ', some FAILED' : ''}`)
