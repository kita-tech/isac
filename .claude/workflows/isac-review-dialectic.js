/**
 * isac-review 弁証法モード（dialectic）プロトタイプ
 *
 * 動機（docs/DESIGN_isac-review-agents.md §8.2/§8.3）: --agents(投票式)は投票させる限り
 * 収束し、負ける案（少数案）を確実には保持できない。弁証法は「投票をやめ、選択肢ごとに
 * advocate を割り当てて steelman を義務化」することで、負ける案が必ず最強の論拠で残る
 * ことを構造的に保証する。
 *
 * フロー: Phase1 擁護(選択肢ごとにsteelman) → Phase2 相互反駁(red/blue) → Phase3 独立ジャッジ
 * 出力: 投票ではなく「各案の最強ケース＋反駁＋中立ジャッジの推奨」。決定は人間(原則9)。
 *
 * args: { topic, context, options[] }（options は離散2つ以上が必須）
 */

export const meta = {
  name: 'isac-review-dialectic',
  description: '弁証法レビュー: 選択肢ごとにadvocate割当→steelman→相互反駁→独立ジャッジ。投票せず両案の最強ケースを保証',
  phases: [
    { title: 'Advocate', detail: '選択肢ごとに steelman(全力擁護)' },
    { title: 'Rebut', detail: '他案の最強ケースへ相互反駁(red/blue)' },
    { title: 'Judge', detail: '独立ジャッジが両サイドを weigh' },
  ],
}

let A = args || {}
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (e) { A = {} } }
const TOPIC = A.topic || '(議題未指定)'
const CONTEXT = A.context || '(材料未指定)'
// 重複除去＋文字列化（['A','A'] のような重複は照合を壊すため）
const OPTIONS = [...new Set((Array.isArray(A.options) ? A.options : []).filter(Boolean).map(String))]
if (OPTIONS.length < 2) {
  return { error: '弁証法モードは離散選択肢(2つ以上・重複除去後)が必須', received_options: OPTIONS }
}
// コストガード: advocate/rebut は選択肢数に比例(2N+1体)し Phase2 入力は O(N^2)。上限を設ける。
if (OPTIONS.length > 6) {
  return { error: `選択肢が多すぎます(${OPTIONS.length})。弁証法は6件以下向け（2N+1体・O(N^2)入力のため）`, received_options: OPTIONS }
}

const COMMON = `【議題】${TOPIC}\n【選択肢】${OPTIONS.join(' / ')}\n\n【材料】\n${CONTEXT}\n\n` +
  `【検証ルール】runnable な事実主張は可能な範囲で実際に確認せよ(read-only優先)。接地しない断定はしない。`

// NOTE: option はコード側(opt)で注入するため schema に含めない
//       （schema必須にすると agent が言い換えた値で下流の find(a.option===opt) が壊れる）
const ADV_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['strongest_case', 'key_evidence', 'preempted_objections'],
  properties: {
    strongest_case: { type: 'string' },
    key_evidence: { type: 'array', items: { type: 'string' } },
    preempted_objections: { type: 'array', items: { type: 'string' } },
  },
}
const REB_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['rebuttals_of_others', 'defenses'],
  properties: {
    rebuttals_of_others: { type: 'array', items: { type: 'string' } },
    defenses: { type: 'array', items: { type: 'string' } },
  },
}
const JUDGE_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['recommendation', 'confidence', 'decisive_factors', 'residual_risks', 'losing_option_standing'],
  properties: {
    recommendation: { type: 'string', enum: OPTIONS },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    decisive_factors: { type: 'array', items: { type: 'string' } },
    residual_risks: { type: 'array', items: { type: 'string' } },       // 推奨案に残るリスク
    losing_option_standing: { type: 'string' },                          // 負ける案に残る正当な論拠
  },
}

// ===== Phase1 擁護（選択肢ごとに1体・steelman義務）=====
phase('Advocate')
const advocates = (await parallel(OPTIONS.map((opt) => () =>
  agent(
    `${COMMON}\n\nあなたは【${opt}】の擁護者(advocate)。信念ではなく、割り当てられた ${opt} 側を全力で steelman せよ。` +
    `${opt} を選ぶ最強の論拠(strongest_case)、裏取りした証拠(key_evidence)、相手が出す最強の反論を先回りで封じる論点(preempted_objections)を出せ。` +
    `${opt} のデメリットは書かなくてよい(相手役が突く)。`,
    { label: `ADV:${opt}`, phase: 'Advocate', schema: ADV_SCHEMA }
  ).then((r) => (r ? { ...r, option: opt } : null))   // 失敗(null)は保持しつつ option はコード側を勝たせる
))).filter(Boolean)

// 部分失敗ガード: 擁護が2件未満なら弁証法が成立しない（負ける案の最強ケースを保証できない）
if (advocates.length < 2) {
  return {
    error: '擁護(advocate)が2件未満で弁証法が成立しません',
    degraded: true,
    survived_options: advocates.map((a) => a.option),
    governance_note: 'これは推奨(recommendation)であり決定ではない。',
  }
}

// 生存した選択肢のみを以降の対象にする。
// 重要: 擁護に失敗した選択肢を OPTIONS のまま残すと、steelman されていない（＝最強ケース空）の案を
// ジャッジが推奨候補にできてしまい、本 workflow の中核保証「負ける案が必ず最強の論拠で残る」が破れる。
const SURVIVED = advocates.map((a) => a.option)
const DROPPED = OPTIONS.filter((o) => !SURVIVED.includes(o))

// ===== Phase2 相互反駁（red team / blue team）=====
phase('Rebut')
// SURVIVED のみを反復（OPTIONS だと擁護に失敗した案にも反駁者を立ててしまい own が空になる）
const rebuttals = (await parallel(SURVIVED.map((opt) => () => {
  const own = advocates.find((a) => a.option === opt)
  const others = advocates.filter((a) => a.option !== opt)
    .map((a) => `【${a.option} の主張】${a.strongest_case}\n 証拠: ${(a.key_evidence || []).join('; ')}`).join('\n\n')
  return agent(
    `${COMMON}\n\nあなたは引き続き【${opt}】の擁護者。\nあなたの主張: ${own ? own.strongest_case : ''}\n\n` +
    `他案の最強の主張:\n${others}\n\n` +
    `他案の主張の弱点・誤り・過大評価を最強の反論(rebuttals_of_others)で突け。あわせて他案が出しうる反論から自案を守る論点(defenses)を出せ。`,
    { label: `REB:${opt}`, phase: 'Rebut', schema: REB_SCHEMA }
  ).then((r) => (r ? { ...r, option: opt } : null))   // 失敗(null)は保持
})).then((x) => x.filter(Boolean)))

// ===== Phase3 独立ジャッジ（擁護に不参加の別体）=====
phase('Judge')
// dossier も SURVIVED のみ。落ちた案は steelman が無いので比較対象にしない。
const dossier = SURVIVED.map((opt) => {
  const a = advocates.find((x) => x.option === opt) || {}
  const r = rebuttals.find((x) => x.option === opt) || {}
  return `=== ${opt} ===\n最強ケース: ${a.strongest_case || ''}\n証拠: ${(a.key_evidence || []).join('; ')}\n` +
    `先回り封じ: ${(a.preempted_objections || []).join('; ')}\n反駁(他案へ): ${(r.rebuttals_of_others || []).join('; ')}\n自案防御: ${(r.defenses || []).join('; ')}`
}).join('\n\n')

// recommendation の enum は SURVIVED に絞る（擁護不在の案を推奨できないようにする）
const judgeSchema = {
  ...JUDGE_SCHEMA,
  properties: { ...JUDGE_SCHEMA.properties, recommendation: { type: 'string', enum: SURVIVED } },
}
const droppedNote = DROPPED.length
  ? `\n\n【注】次の選択肢は擁護(steelman)を得られず比較から除外された: ${DROPPED.join(', ')}。これらは推奨できない。`
  : ''

const judge = await agent(
  `${COMMON}\n\nあなたは中立の独立ジャッジで、どの選択肢も擁護していない。以下は各案の擁護者による最強ケースと相互反駁。\n\n${dossier}${droppedNote}\n\n` +
  `両サイドを公平に weigh し、recommendation(擁護のあった選択肢から1つ)、confidence、決め手(decisive_factors)、` +
  `推奨案に残るリスク(residual_risks)、そして『負ける案に残る正当な論拠(losing_option_standing)』を出せ。` +
  `多数決ではなく論拠の強さで判断し、接地していない主張は割り引くこと。`,
  { label: 'JUDGE', phase: 'Judge', schema: judgeSchema }
)

return {
  topic: TOPIC,
  mode: 'dialectic',
  options: OPTIONS,
  dropped_options: DROPPED,   // 擁護に失敗し比較から除外された選択肢（部分失敗の可視化）
  advocates: advocates.map((a) => ({ option: a.option, strongest_case: a.strongest_case, key_evidence: a.key_evidence, preempted_objections: a.preempted_objections })),
  rebuttals: rebuttals.map((r) => ({ option: r.option, rebuttals_of_others: r.rebuttals_of_others, defenses: r.defenses })),
  judge,
  governance_note: 'これは推奨(recommendation)であり決定ではない。決定として残すかは人間が /isac-decide で確認・確定する(原則9)。',
}
