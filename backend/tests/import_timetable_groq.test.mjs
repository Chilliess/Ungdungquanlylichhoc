// Node 22.13+: exercise the actual Edge handler with mocked Auth/DB/Groq.
// No credentials, network requests or real quota consumption.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const source = stripTypeScriptTypes(readFileSync(
  new URL('../functions/import-timetable/index.ts', import.meta.url), 'utf8')
  .replace(/^import .*createClient.*;\r?\n/m, ''));

const image = {
  mime_type: 'image/png',
  data: 'iVBORw0KGgo=',
};
const row = {
  title: 'Toán',
  date: '2026-09-10',
  start: '08:00',
  end: '09:00',
  room: 'A1',
};

test('authenticated image batches use Groq and aggregate up to 15 pages', async () => {
  const r = await run({
    images: Array.from({ length: 4 }, () => image),
    rowsByCall: [[row], [{ ...row, title: 'Vật lý' }]],
  });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.rows, [row, { ...row, title: 'Vật lý' }]);
  assert.deepEqual(r.rpcCalls, ['account_is_active', 'consume_assistant_request']);
  assert.equal(r.calls.length, 2);
  assert.equal(r.calls[0].url, 'https://api.groq.com/openai/v1/chat/completions');
  assert.equal(r.calls[0].headers.Authorization, 'Bearer test-groq-key');
  assert.equal(r.calls[0].body.model, 'qwen/qwen3.8-27b');
  assert.equal(r.calls[0].body.messages[0].content.filter((part) =>
    part.type === 'image_url').length, 3);
  assert.equal(r.calls[1].body.messages[0].content.filter((part) =>
    part.type === 'image_url').length, 1);
  assert.deepEqual(r.calls[0].body.response_format, { type: 'json_object' });
});

for (const [name, options, status] of [
  ['missing token', { noToken: true }, 401],
  ['inactive account', { inactive: true }, 403],
  ['missing Groq key', { env: { GROQ_API_KEY: '' } }, 503],
  ['invalid vision model', { env: { GROQ_VISION_MODEL: 'bad model' } }, 503],
  ['invalid JSON', { raw: '{' }, 400],
  ['too many pages', { images: Array.from({ length: 16 }, () => image) }, 400],
  ['invalid image signature', { images: [{ ...image, data: 'aGVsbG8=' }] }, 400],
  ['unsupported image type', { images: [{ ...image, mime_type: 'application/pdf' }] }, 400],
  ['quota exhausted', { exhausted: true }, 429],
  ['quota unavailable', { quotaError: true }, 503],
]) {
  test(`${name} never calls Groq`, async () => {
    const r = await run(options);
    assert.equal(r.status, status);
    assert.equal(r.calls.length, 0);
    assert.ok(!JSON.stringify(r.body).includes('test-groq-key'));
  });
}

test('oversized request is rejected before quota consumption', async () => {
  const r = await run({ raw: 'x'.repeat(7_100_001) });
  assert.equal(r.status, 413);
  assert.equal(r.calls.length, 0);
  assert.ok(!r.rpcCalls.includes('consume_assistant_request'));
});

test('Groq rate-limit errors are sanitized', async () => {
  const r = await run({ providerStatus: 429 });
  assert.equal(r.status, 429);
  assert.deepEqual(r.body, { error: 'Recognition rate limited' });
  assert.ok(!JSON.stringify(r.body).includes('provider-private-error'));
});

async function run(options = {}) {
  let handler;
  const calls = [];
  const rpcCalls = [];
  const env = {
    GROQ_API_KEY: 'test-groq-key',
    GROQ_VISION_MODEL: '',
    ...options.env,
  };
  const client = {
    auth: {
      getUser: async () => ({
        data: { user: options.signedOut ? null : { id: 'owner' } },
        error: options.authError ? {} : null,
      }),
    },
    rpc: async (name) => {
      rpcCalls.push(name);
      if (name === 'consume_assistant_request' && options.quotaError) {
        return { data: null, error: {} };
      }
      return {
        data: name === 'account_is_active' ? !options.inactive : !options.exhausted,
        error: null,
      };
    },
  };
  const fetchMock = async (url, init) => {
    calls.push({ url, ...init, body: JSON.parse(init.body) });
    if (options.providerStatus) {
      return Response.json({ error: 'provider-private-error' }, {
        status: options.providerStatus,
      });
    }
    const rows = options.rowsByCall?.[calls.length - 1] ?? [];
    return Response.json({
      choices: [{ message: { content: JSON.stringify({ rows }) } }],
    });
  };
  new Function('createClient', 'Deno', 'fetch', source)(
    () => client,
    {
      env: { get: (key) => env[key] },
      serve: (callback) => { handler = callback; },
    },
    fetchMock,
  );
  const headers = options.noToken ? {} : { Authorization: 'Bearer test-token' };
  const body = options.raw ?? JSON.stringify({
    images: options.images ?? [image],
  });
  const request = new Request('https://example.invalid', {
    method: 'POST',
    headers,
    body,
  });
  const response = await handler(request);
  return {
    status: response.status,
    body: await response.json(),
    calls,
    rpcCalls,
  };
}
