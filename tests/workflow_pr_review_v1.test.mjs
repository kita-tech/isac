// isac-pr-review-issues.js（/isac-pr-review --agents）のスタブ実走テスト。
// Workflow ランタイムの agent()/parallel()/phase()/log() をスタブに差し替え、
// モデル指定の解決と「全レンズ失敗」の扱いを LLM なしで決定的に検証する。
// 実行: node tests/workflow_pr_review_v1.test.mjs
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import assert from 'node:assert/strict'

const here = dirname(fileURLToPath(import.meta.url))
const src = readFileSync(join(here, '..', '.claude', 'workflows', 'isac-pr-review-issues.js'), 'utf8')
  .replace('export const meta', 'const meta')
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const body = new AsyncFunction('args', 'agent', 'parallel', 'phase', 'log', src)

/** workflow を実行する。handler(prompt, opts) が各 agent の戻り値を決める。 */
async function run(args, handler) {
  const calls = []
  const agent = async (prompt, opts) => { calls.push({ prompt, opts }); return handler(prompt, opts) }
  const parallel = (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))
  const result = await body(args, agent, parallel, () => {}, () => {})
  return { result, calls }
}
const BASE = { diff: 'diff --git a/a.py b/a.py\n+x = 1', pr_number: 7 }
const EMPTY = () => ({ findings: [] })
const HIGH = { severity: 'high', file: 'a.py', area: 'x', issue: 'ISSUE', evidence: 'EVID', suggested_fix: 'FIX' }

let passed = 0
async function test(name, fn) {
  try { await fn(); passed++; console.log(`  ✓ ${name}`) }
  catch (e) { console.log(`  ✗ ${name}\n    ${e.message}`); process.exitCode = 1 }
}

console.log('isac-pr-review-issues workflow (v1 --agents)')

// ---------- モデル指定 ----------
await test('model 省略時はセッション継承（agent に model を渡さない）', async () => {
  const { result, calls } = await run(BASE, EMPTY)
  assert.equal(calls.length, 5)
  for (const c of calls) assert.equal(c.opts.model, undefined)
  assert.equal(result.model, 'inherit')
})
await test("'inherit' は表記ゆれ・前後空白でも継承扱い", async () => {
  for (const m of ['inherit', 'Inherit', ' INHERIT ', '', '   ']) {
    const { result, calls } = await run({ ...BASE, model: m }, EMPTY)
    for (const c of calls) assert.equal(c.opts.model, undefined, `model=${JSON.stringify(m)}`)
    assert.equal(result.model, 'inherit')
  }
})
await test('文字列以外の model は無視して継承', async () => {
  for (const m of [null, 123, {}, ['opus'], true]) {
    const { calls } = await run({ ...BASE, model: m }, EMPTY)
    for (const c of calls) assert.equal(c.opts.model, undefined)
  }
})
await test('エイリアス指定は正規化して Review と Verify の両方に渡す', async () => {
  const h = (p, o) => (o.label.startsWith('REV:') ? { findings: [HIGH] } : { verdict: 'confirmed', reasoning: 'r' })
  const { result, calls } = await run({ ...BASE, model: ' Opus ' }, h)
  const verify = calls.filter((c) => c.opts.label.startsWith('VERIFY'))
  assert.ok(verify.length > 0)
  for (const c of calls) assert.equal(c.opts.model, 'opus')
  assert.equal(result.model, 'opus')
})

// ---------- 全レンズ失敗（fail-closed） ----------
await test('全レンズ失敗（null）は「指摘0件」でなく error を返し、検証を起動しない', async () => {
  const { result, calls } = await run({ ...BASE, model: 'fable' }, () => null)
  assert.match(result.error, /全レンズ/)
  assert.equal(result.failed_lenses.length, 5)
  assert.equal(result.model, 'fable')
  assert.equal(result.counts, undefined)
  assert.equal(calls.length, 5)
})
await test('全レンズが例外で落ちても error を返す', async () => {
  const { result } = await run(BASE, () => { throw new Error('model unavailable') })
  assert.match(result.error, /全レンズ/)
  assert.equal(result.failed_lenses.length, 5)
})
await test('一部のレンズだけ失敗: 結果は返し、failed_lenses に失敗したレンズ名が入る', async () => {
  const h = (p, o) => (o.label === 'REV:セキュリティ' ? null : { findings: [] })
  const { result } = await run(BASE, h)
  assert.equal(result.error, undefined)
  assert.deepEqual(result.failed_lenses, ['セキュリティ'])
  assert.deepEqual(result.counts, { high: 0, med: 0, low: 0 })
})
await test('全レンズ成功・指摘0件は error にしない（failed_lenses は空）', async () => {
  const { result } = await run(BASE, EMPTY)
  assert.equal(result.error, undefined)
  assert.deepEqual(result.failed_lenses, [])
  assert.equal(result.total_findings, 0)
})

// ---------- 既存挙動の回帰 ----------
await test('diff が無ければ error を返し agent を呼ばない', async () => {
  const { result, calls } = await run({}, EMPTY)
  assert.match(result.error, /diff が必須/)
  assert.equal(calls.length, 0)
})
await test('🔴は検証 confirmed のみ。検証失敗は除外側', async () => {
  const h = (p, o) => (o.label.startsWith('REV:') ? { findings: o.label === 'REV:セキュリティ' ? [HIGH, { ...HIGH, file: 'b.py' }] : [] } : null)
  const ok = (p, o) => (o.label.startsWith('REV:') ? h(p, o) : (o.label.includes('a.py') ? { verdict: 'confirmed', reasoning: 'r' } : null))
  const { result } = await run(BASE, ok)
  assert.equal(result.counts.high, 1)
  assert.equal(result.high[0].file, 'a.py')
  assert.equal(result.verification.filtered_out, 1)
})

console.log(`\n${passed} passed${process.exitCode ? ', some FAILED' : ''}`)
