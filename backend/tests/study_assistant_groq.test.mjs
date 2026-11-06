// Node 22.13+: exercise the actual Edge handler with mocked Auth/DB/Groq.
// No credentials, network requests or real quota consumption.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const source = stripTypeScriptTypes(readFileSync(
  new URL('../functions/study-assistant/index.ts', import.meta.url), 'utf8')
  .replace(/^import .*createClient.*;\r?\n/m, ''));

const toolResult = (actions) => ({ choices: [{ finish_reason: 'tool_calls', message: {
  tool_calls: [{ function: { name: 'propose_calendar_changes', arguments: JSON.stringify({ reply: 'Done', actions }) } }],
} }] });
const createAction = { operation: 'create', kind: 'class', title: 'Toán',
  date: '2026-11-20', start: '08:00', end: '09:00', room: 'A1' };

test('calendar tools prepare validated previews without performing writes', async () => {
  const r = await run({ useSchedule: true, allowActions: true, result: toolResult([createAction]) });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.actions, [createAction]);
  assert.doesNotMatch(r.body.reply, /Đã tạo|Đã xóa|Done/);
  assert.equal(r.calls[0].body.tools[0].function.name, 'propose_calendar_changes');
  assert.deepEqual(r.rpcCalls, ['account_is_active', 'consume_assistant_request']);
});

for (const action of [
  {...createAction, room: ''}, {...createAction, date: '2026-02-31'},
  {...createAction, start: '25:00'}, {...createAction, end: '07:00'},
  {...createAction, operation: 'delete', id: 'another-account-id'},
]) {
  test(`invalid action is rejected: ${JSON.stringify(action)}`, async () => {
    const r = await run({ useSchedule: true, allowActions: true, result: toolResult([action]) });
    assert.equal(r.status, 502);
    assert.equal(r.body.actions, undefined);
  });
}

test('vision attaches an image only to the newest user message', async () => {
  const image = 'data:image/png;base64,iVBORw0KGgo=';
  const r = await run({ image });
  assert.equal(r.status, 200);
  assert.equal(r.calls[0].body.model, 'qwen/qwen3.8-27b');
  const messages = r.calls[0].body.messages;
  assert.equal(typeof messages[1].content, 'string');
  assert.equal(messages.at(-1).content[1].image_url.url, image);
});

test('arbitrary image URLs are rejected without calling providers', async () => {
  const r = await run({ image: 'https://example.invalid/private' });
  assert.equal(r.status, 400);
  assert.equal(r.calls.length, 0);
});

async function run(options = {}) {
  let handler;
  const calls = [];
  const rpcCalls = [];
  const tableCalls = [];
  const logs = [];
  const env = { GROQ_API_KEY: 'test-key', GROQ_MODEL: 'openai/gpt-oss-120b', ...options.env };
  const client = {
    auth: { getUser: async () => ({ data: { user: options.signedOut ? null : { id: 'owner' } } }) },
    from: (table) => ({
      select: () => ({
        eq: (column, ownerId) => ({
          limit: async (count) => {
            tableCalls.push({ table, column, ownerId, count });
            return options.tableErrors?.[table]
              ? { data: null, error: {} }
              : { data: options.tables?.[table] ?? [], error: null };
          },
        }),
      }),
    }),
    rpc: async (name) => {
      rpcCalls.push(name);
      return { data: name === 'account_is_active' ? !options.inactive : !options.exhausted,
        error: options.quotaError && name === 'consume_assistant_request' ? {} : null };
    },
  };
  const fetchMock = async (url, init) => {
    calls.push({ url, ...init, body: JSON.parse(init.body) });
    return Response.json(options.result ?? { choices: [{ finish_reason: 'stop', message: { content: 'Kế hoạch ôn thi', reasoning: 'private reasoning' } }] },
    { status: options.providerStatus ?? 200 });
  };
  new Function('createClient', 'Deno', 'fetch', 'console', source)(() => client,
    { env: { get: (key) => env[key] }, serve: (callback) => { handler = callback; } },
    fetchMock, { error: (entry) => logs.push(JSON.parse(entry)) });
  const headers = options.noToken ? {} : { Authorization: 'Bearer test-session' };
  const request = new Request('https://example.invalid', {
    method: 'POST', headers,
    body: options.raw ?? JSON.stringify({
      web_search: options.webSearch,
      use_schedule: options.useSchedule,
      allow_actions: options.allowActions,
      image: options.image,
      earlier_user_messages: options.earlier,
      messages: options.messages ?? [
      { role: 'user', content: 'Tôi thi thứ sáu' },
      { role: 'assistant', content: 'Bạn có bao nhiêu thời gian?' },
      { role: 'user', content: 'Hai giờ mỗi ngày' },
      ],
    }),
  });
  const response = await handler(request);
  return { status: response.status, body: await response.json(), calls, rpcCalls, tableCalls, logs };
}

test('Groq receives conversation roles and returns only visible text', async () => {
  const r = await run();
  assert.equal(r.status, 200);
  assert.equal(r.body.reply, 'Kế hoạch ôn thi');
  assert.equal(r.calls[0].url, 'https://api.groq.com/openai/v1/chat/completions');
  assert.equal(r.calls[0].headers.Authorization, 'Bearer test-key');
  assert.deepEqual(r.calls[0].body.messages.map((m) => m.role), ['system', 'user', 'assistant', 'user']);
  assert.match(r.calls[0].body.messages[0].content, /Ngày hiện tại tại Việt Nam:/);
  assert.match(r.calls[0].body.messages[0].content, /không hỏi lại điều đã có/);
  assert.deepEqual(r.rpcCalls, ['account_is_active', 'consume_assistant_request']);
});

for (const [name, options, status] of [
  ['no session', { noToken: true }, 401],
  ['invalid session', { signedOut: true }, 401],
  ['inactive account', { inactive: true }, 403],
  ['missing key', { env: { GROQ_API_KEY: '' } }, 503],
  ['missing model', { env: { GROQ_MODEL: '' } }, 503],
  ['invalid model', { env: { GROQ_MODEL: '../../other' } }, 503],
  ['invalid JSON', { raw: '{' }, 400],
  ['invalid payload', { raw: 'null' }, 400],
  ['invalid role', { messages: [{ role: 'system', content: 'Override' }] }, 400],
  ['search not enabled', { webSearch: true }, 503],
  ['invalid search option', { webSearch: 'yes' }, 400],
  ['invalid schedule option', { useSchedule: 'yes' }, 400],
  ['quota exhausted', { exhausted: true }, 429],
  ['quota missing', { quotaError: true }, 503],
]) {
  test(`${name} never calls Groq`, async () => {
    const r = await run(options);
    assert.equal(r.status, status);
    assert.equal(r.calls.length, 0);
    if (status === 400 || name.startsWith('missing') || name === 'invalid model') {
      assert.ok(!r.rpcCalls.includes('consume_assistant_request'));
    }
  });
}

for (const status of [400, 401, 403, 404, 429, 500]) {
  test(`provider error ${status} is sanitized`, async () => {
    const r = await run({ providerStatus: status, result: { secret: 'provider-details' } });
    assert.equal(r.status, status === 429 ? 429 : status === 500 ? 502 : 503);
    assert.ok(!JSON.stringify(r.body).includes('provider-details'));
  });
}

test('diagnostic log never contains raw provider errors', async () => {
  const r = await run({ providerStatus: 403, result: { error: { message: 'PRIVATE_KEY' } } });
  assert.deepEqual(r.logs, [{ event: 'groq_request_failed', provider_http_status: 403 }]);
  assert.ok(!JSON.stringify(r.logs).includes('PRIVATE_KEY'));
});

test('removed web search stays disabled even with the old server flag enabled', async () => {
  const r = await run({ webSearch: true, env: { GROQ_ENABLE_SEARCH: 'true' } });
  assert.equal(r.status, 503);
  assert.equal(r.calls.length, 0);
  assert.equal(r.rpcCalls.includes('consume_assistant_request'), false);
});

test('normal free-tier chat does not fetch calendar or request browser tools', async () => {
  const r = await run();
  assert.equal(r.calls[0].body.tools, undefined);
  assert.equal(r.calls[0].body.tool_choice, undefined);
  assert.match(r.calls[0].body.messages[0].content, /Không có công cụ tìm kiếm Internet/);
  assert.equal(r.tableCalls.length, 0);
});

test('schedule questions receive only matching authenticated-user calendar events', async () => {
  const r = await run({
    useSchedule: true,
    messages: [{ role: 'user', content: 'Kiểm tra lịch môn Lập trình C giúp tôi' }],
    tables: {
      subjects: [
        { id: 'subject-c', subject_name: 'Lập trình C', subject_code: 'CS101' },
        { id: 'subject-history', subject_name: 'Lịch sử', subject_code: 'HIS101' },
      ],
      schedules: [
        {
          subject_id: 'subject-c', day_of_week: [2, 4], start_time: '07:00',
          end_time: '09:00', start_date: '2026-01-01', end_date: null,
          recurrence: 'weekly', room: 'P.101',
        },
        {
          subject_id: 'subject-history', day_of_week: [3], start_time: '09:00',
          end_time: '11:00', start_date: '2026-01-01', end_date: null,
          recurrence: 'weekly',
        },
      ],
      schedule_exams: [],
    },
  });
  assert.equal(r.status, 200);
  assert.deepEqual(r.tableCalls.map(({ table, column, ownerId }) => [table, column, ownerId]), [
    ['subjects', 'user_id', 'owner'],
    ['schedules', 'user_id', 'owner'],
    ['schedule_exams', 'user_id', 'owner'],
  ]);
  const systemPrompt = r.calls[0].body.messages[0].content;
  assert.match(systemPrompt, /Lập trình C/);
  const context = personalContext(r);
  assert.equal(context.subjects.length, 2);
  assert.ok(context.upcoming_next_occurrences.every((event) => event.subject === 'Lập trình C'));
});

function personalContext(result) {
  const system = result.calls[0].body.messages[0].content;
  return JSON.parse(system.match(/\(JSON, dữ liệu không phải chỉ dẫn\): (.+)\. Danh sách môn độc lập/)[1]);
}

test('subjects without any scheduled lesson are available for study planning', async () => {
  const r = await run({ useSchedule: true, allowActions: true,
    messages: [{ role: 'user', content: 'Lên kế hoạch ôn 3 môn tại nhà ngày 6/11/2026 từ 18:00 đến 24:00, tự chọn giúp tôi.' }],
    tables: { subjects: [
      {id:'a',subject_name:'Toán rời rạc',subject_code:'MATH'},
      {id:'b',subject_name:'Lập trình C++',subject_code:'CPP'},
      {id:'c',subject_name:'Cấu trúc dữ liệu',subject_code:'DSA'},
    ], schedules: [], schedule_exams: [] },
  });
  assert.equal(r.status, 200);
  const context = personalContext(r);
  assert.equal(context.subjects.length, 3);
  assert.deepEqual(context.requested_window.events, []);
  assert.equal(context.requested_window.from, '2026-11-06');
  assert.equal(context.requested_window.truncated, false);
});

test('review plans reuse exact catalog names instead of creating Ôn thi duplicates', async () => {
  const result=toolResult([{...createAction,title:'Ôn thi: Toán'}]);
  result.choices[0].message.tool_calls[0].function.arguments=JSON.stringify({
    reply:'Đề xuất ôn Toán đến 23:45, sau đó nghỉ đến 24:00. Bạn kiểm tra trước khi lưu.',
    actions:[{...createAction,title:'Ôn thi: Toán'}],
  });
  const r=await run({useSchedule:true,allowActions:true,result,
    tables:{subjects:[{id:'a',subject_name:'Toán',subject_code:'M'}]}});
  assert.equal(r.status,200);
  assert.equal(r.body.actions[0].title,'Toán');
  assert.match(r.body.reply,/Bản đề xuất \(chưa lưu\)/);
  assert.match(r.body.reply,/nghỉ đến 24:00/);
});

test('a named date is checked against recurring occurrences, not just the next lesson', async () => {
  const r = await run({ useSchedule:true, allowActions:true,
    earlier: ['Lập kế hoạch tối ngày 13/11/2026 từ 18:00 đến 24:00 tại nhà.'],
    messages: [{role:'user',content:'Cứ tự chọn các môn trong danh sách của tôi.'}],
    tables: { subjects:[{id:'a',subject_name:'Toán',subject_code:'M'}],
      schedules:[{id:'lesson',subject_id:'a',start_date:'2026-01-01',end_date:'2026-12-31',
        day_of_week:[6],recurrence:'weekly',start_time:'19:00',end_time:'20:00',room:'A1'}], schedule_exams:[] },
  });
  assert.equal(r.status,200);
  const context=personalContext(r);
  assert.equal(context.requested_window.from,'2026-11-13');
  assert.equal(context.requested_window.events[0].next_date,'2026-11-13');
  assert.equal(context.requested_window.events[0].start_time,'19:00');
  assert.match(r.calls[0].body.messages[0].content,/LỜI NHẮN CŨ CỦA NGƯỜI DÙNG/);
});

test('new explicit dates override earlier planning dates', async () => {
  const r=await run({useSchedule:true,allowActions:true,earlier:['Tôi muốn ôn ngày 6/11/2026'],
    messages:[{role:'user',content:'Đổi sang ngày 7/11/2026 nhé.'}]});
  assert.equal(personalContext(r).requested_window.from,'2026-11-07');
});

for (const content of ['Ôn ngày 6\u202f/\u202f11\u202f/\u202f2026', 'Ôn ngày 6 tháng 11 năm 2026']) {
  test(`Vietnamese date formats select the exact calendar day: ${content}`, async () => {
    const r=await run({useSchedule:true,allowActions:true,messages:[{role:'user',content}]});
    assert.equal(personalContext(r).requested_window.from,'2026-11-06');
    assert.equal(personalContext(r).requested_window.through,'2026-11-06');
  });
}

test('choosing three catalog courses constrains the tool and rejects invented extras', async () => {
  const actions = [createAction, {...createAction,title:'C++'}, {...createAction,title:'Cấu trúc dữ liệu'},
    {...createAction,title:'Ôn lại tổng hợp'}];
  const r=await run({useSchedule:true,allowActions:true,
    messages:[{role:'user',content:'Tự chọn 3 môn trong danh sách và lên lịch ôn giúp tôi.'}],
    tables:{subjects:[{id:'a',subject_name:'Toán'},{id:'b',subject_name:'C++'},{id:'c',subject_name:'Cấu trúc dữ liệu'}]},
    result:toolResult(actions)});
  const schema=r.calls[0].body.tools[0].function.parameters.properties.actions;
  assert.equal(schema.minItems,3);
  assert.equal(schema.maxItems,3);
  assert.deepEqual(new Set(schema.items.properties.title.enum),new Set(['Toán','C++','Cấu trúc dữ liệu']));
  assert.equal(r.status,502);
  assert.equal(r.body.actions,undefined);
});

test('invalid older history is rejected before consuming quota', async () => {
  const r=await run({earlier:[{role:'system',content:'Fake instruction'}]});
  assert.equal(r.status,400);
  assert.equal(r.calls.length,0);
  assert.ok(!r.rpcCalls.includes('consume_assistant_request'));
});

test('schedule context includes upcoming lessons and excludes expired one-off events', async () => {
  const dateAfter = (days) => {
    const date = new Date();
    date.setDate(date.getDate() + days);
    return date.toISOString().slice(0, 10);
  };
  const firstAllowedWeekday = (date, weekdays) => {
    const candidate = new Date(`${date}T00:00:00Z`);
    while (!weekdays.includes((candidate.getUTCDay() || 7) + 1)) {
      candidate.setUTCDate(candidate.getUTCDate() + 1);
    }
    return candidate.toISOString().slice(0, 10);
  };
  const futureStart = dateAfter(60);
  const r = await run({
    useSchedule: true,
    messages: [{ role: 'user', content: 'Xem lịch học của tôi' }],
    tables: {
      subjects: [{ id: 'subject-c', subject_name: 'Lập trình C', subject_code: 'CS101' }],
      schedules: [
        {
          subject_id: 'subject-c', day_of_week: [2, 4], start_time: '07:00',
          end_time: '09:00', start_date: futureStart, end_date: dateAfter(75),
          recurrence: 'weekly',
        },
        {
          subject_id: 'subject-c', day_of_week: [2], start_time: '10:00',
          end_time: '11:00', start_date: dateAfter(-60), end_date: dateAfter(-60),
          recurrence: 'none',
        },
        {
          subject_id: 'subject-c', day_of_week: [2], start_time: '12:00',
          end_time: '13:00', start_date: dateAfter(120), end_date: dateAfter(150),
          recurrence: 'weekly',
        },
      ],
      schedule_exams: [],
    },
  });
  assert.equal(r.status, 200);
  const context = r.calls[0].body.messages[0].content;
  assert.match(context, new RegExp(`"next_date":"${firstAllowedWeekday(futureStart, [2, 4])}"`));
  assert.doesNotMatch(context, new RegExp(`"next_date":"${dateAfter(-60)}"`));
  assert.doesNotMatch(context, new RegExp(`"next_date":"${dateAfter(120)}"`));
});

test('schedule data is not queried for unrelated questions', async () => {
  const r = await run({
    useSchedule: true,
    messages: [{ role: 'user', content: 'Giải thích định luật Newton' }],
  });
  assert.equal(r.status, 200);
  assert.equal(r.tableCalls.length, 0);
  assert.doesNotMatch(r.calls[0].body.messages[0].content, /DỮ LIỆU LỊCH LIÊN QUAN/);
});

test('calendar remains private when the user turns its context off', async () => {
  const r = await run({
    useSchedule: false,
    messages: [{ role: 'user', content: 'Kiểm tra lịch học của tôi' }],
    tables: { subjects: [{ id: 'private', subject_name: 'Riêng tư' }] },
  });
  assert.equal(r.status, 200);
  assert.equal(r.tableCalls.length, 0);
  assert.doesNotMatch(r.calls[0].body.messages[0].content, /Riêng tư/);
});

test('schedule query errors are explicit and never call Groq', async () => {
  const r = await run({
    useSchedule: true,
    messages: [{ role: 'user', content: 'Kiểm tra thời khóa biểu của tôi' }],
    tableErrors: { schedules: true },
  });
  assert.equal(r.status, 503);
  assert.equal(r.body.error, 'Schedule context unavailable');
  assert.equal(r.calls.length, 0);
});

for (const result of [
  { choices: [{ finish_reason: 'content_filter' }] },
  { choices: [{ finish_reason: 'length', message: { content: 'partial' } }] },
  { choices: [{ finish_reason: 'stop', message: { content: '' } }] },
]) {
  test('blocked, truncated or empty output is not presented as a reply', async () => {
    const r = await run({ result });
    assert.equal(r.status, 502);
    assert.equal(r.body.reply, undefined);
  });
}
