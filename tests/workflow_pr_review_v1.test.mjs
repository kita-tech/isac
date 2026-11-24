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
await test('error 文言: model 指定時はモデル名と「省略して再実行」を案内する', async () => {
  const { result } = await run({ ...BASE, model: 'Fable' }, () => null)
  assert.match(result.error, /全レンズ（5体）/)
  assert.match(result.error, /model: fable/)
  assert.match(result.error, /利用上限/)
  assert.match(result.error, /model を省略して再実行/)
})
await test('error 文言: model 省略時は「model を省略して再実行」と誤誘導しない', async () => {
  for (const m of [undefined, 'inherit', ' Inherit ']) {
    const { result } = await run({ ...BASE, model: m }, () => null)
    assert.match(result.error, /セッションのモデル/)
    assert.match(result.error, /利用上限や一時的な障害/)
    assert.doesNotMatch(result.error, /省略して再実行/)
    assert.doesNotMatch(result.error, /model: /)
  }
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

// ---------- 作業場所（カレントブランチを汚さない） ----------
await test('作業場所: worktree があれば絶対パスで読み git -C を使う指示が Review と Verify の両方に入る', async () => {
  const wt = '/tmp/isac-pr-review-7'
  const h = (p, o) => (o.label.startsWith('REV:') ? { findings: o.label === 'REV:セキュリティ' ? [HIGH] : [] } : { verdict: 'confirmed', reasoning: 'r' })
  const { calls } = await run({ ...BASE, worktree_path: wt }, h)
  const review = calls.find((c) => c.opts.label.startsWith('REV:'))
  const verify = calls.find((c) => c.opts.label.startsWith('VERIFY'))
  assert.ok(verify, '検証エージェントが起動している')
  for (const c of [review, verify]) {
    assert.match(c.prompt, /【作業場所（厳守）】/)
    assert.ok(c.prompt.includes(`${wt}/...`), '絶対パスで読む指示')
    assert.ok(c.prompt.includes(`git -C ${wt}`), 'git -C の指示')
    assert.match(c.prompt, /起動時のカレントディレクトリは、レビューしている人の作業中のリポジトリ/)
  }
})
await test('禁止事項: 作業中のブランチを変える操作は worktree の有無に関係なく禁止', async () => {
  for (const extra of [{ worktree_path: '/tmp/wt' }, {}]) {
    const { calls } = await run({ ...BASE, ...extra }, EMPTY)
    assert.match(calls[0].prompt, /commit\/push\/checkout\/switch\/stash\/reset\/clean\/merge\/rebase/)
    assert.match(calls[0].prompt, /gh pr checkout を含む/)
  }
  const { calls } = await run(BASE, EMPTY)   // worktree 無しなら作業場所の指示は出さない
  assert.doesNotMatch(calls[0].prompt, /【作業場所（厳守）】/)
  assert.match(calls[0].prompt, /worktree 未提供/)
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
  assert.equal(result.verification.verify_failed, 1)
  assert.equal(result.verification.false_positive, 0)
})

// ---------- 検証失敗の可視化 ----------
const highsFrom = (n) => (p, o) => (o.label.startsWith('REV:')
  ? { findings: o.label === 'REV:セキュリティ' ? Array.from({ length: n }, (_, i) => ({ ...HIGH, file: `f${i}.py` })) : [] }
  : null)
await test('検証が全件失敗: 🔴0件でも verify_failed に件数が出る（「🔴なし」と区別できる）', async () => {
  const { result } = await run(BASE, highsFrom(3))
  assert.equal(result.error, undefined)
  assert.equal(result.counts.high, 0)
  assert.equal(result.verification.raw_high, 3)
  assert.equal(result.verification.verify_failed, 3)
  assert.equal(result.verification.false_positive, 0)
  assert.ok(result.verification.filtered_out_detail.every((d) => d.verdict === 'unverified'))
})
await test('検証失敗と偽陽性は別に数える（confirmed / downgrade は除外に入らない）', async () => {
  const verdicts = { 'f0.py': null, 'f1.py': { verdict: 'false_positive', reasoning: 'r' }, 'f2.py': { verdict: 'confirmed', reasoning: 'r' }, 'f3.py': { verdict: 'downgrade', adjusted_severity: 'low', reasoning: 'r' } }
  const h = (p, o) => {
    if (o.label.startsWith('REV:')) return highsFrom(4)(p, o)
    const key = Object.keys(verdicts).find((k) => o.label.includes(k))
    return verdicts[key]
  }
  const { result } = await run(BASE, h)
  assert.equal(result.counts.high, 1)
  assert.equal(result.verification.filtered_out, 2)
  assert.equal(result.verification.verify_failed, 1)
  assert.equal(result.verification.false_positive, 1)
  assert.equal(result.verification.downgraded, 1)
})
await test('🔴候補が無ければ verify_failed / false_positive は 0', async () => {
  const { result } = await run(BASE, EMPTY)
  assert.equal(result.verification.verify_failed, 0)
  assert.equal(result.verification.false_positive, 0)
})

console.log(`\n${passed} passed${process.exitCode ? ', some FAILED' : ''}`)
