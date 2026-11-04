// Node 22.13+: exercise the actual Edge handler with mocked Auth/DB/Groq.
// No credentials, network requests or real quota consumption.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const source = stripTypeScriptTypes(readFileSync(
  new URL('../functions/study-assistant/index.ts', import.meta.url), 'utf8')
  .replace(/^import .*createClient.*;\r?\n/m, ''));

async function run(options = {}) {
  let handler;
  const calls = [];
  const rpcCalls = [];
  const logs = [];
  const env = { GROQ_API_KEY: 'test-key', GROQ_MODEL: 'openai/gpt-oss-120b', ...options.env };
  const client = {
    auth: { getUser: async () => ({ data: { user: options.signedOut ? null : { id: 'owner' } } }) },
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
    body: options.raw ?? JSON.stringify({ web_search: options.webSearch, messages: options.messages ?? [
      { role: 'user', content: 'Tôi thi thứ sáu' },
      { role: 'assistant', content: 'Bạn có bao nhiêu thời gian?' },
      { role: 'user', content: 'Hai giờ mỗi ngày' },
    ] }),
  });
  const response = await handler(request);
  return { status: response.status, body: await response.json(), calls, rpcCalls, logs };
}

test('Groq receives conversation roles and returns only visible text', async () => {
  const r = await run();
  assert.equal(r.status, 200);
  assert.equal(r.body.reply, 'Kế hoạch ôn thi');
  assert.equal(r.calls[0].url, 'https://api.groq.com/openai/v1/chat/completions');
  assert.equal(r.calls[0].headers.Authorization, 'Bearer test-key');
  assert.deepEqual(r.calls[0].body.messages.map((m) => m.role), ['system', 'user', 'assistant', 'user']);
  assert.match(r.calls[0].body.messages[0].content, /Ngày hiện tại tại Việt Nam:/);
  assert.match(r.calls[0].body.messages[0].content, /nếu thiếu chi tiết đã nói trước đó thì hỏi lại/);
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

test('web search is explicit and forwards only the built-in browser tool', async () => {
  const r = await run({ webSearch: true, env: { GROQ_ENABLE_SEARCH: 'true' } });
  assert.equal(r.status, 200);
  assert.deepEqual(r.calls[0].body.tools, [{ type: 'browser_search' }]);
  assert.equal(r.calls[0].body.tool_choice, 'required');
  assert.equal(r.calls[0].body.reasoning_effort, 'low');
});

test('normal free-tier chat does not request paid or browser tools', async () => {
  const r = await run();
  assert.equal(r.calls[0].body.tools, undefined);
  assert.equal(r.calls[0].body.tool_choice, undefined);
  assert.match(r.calls[0].body.messages[0].content, /không bật tra cứu web/);
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
