// Sends raw Chrome DevTools Protocol commands to the Sketch3D WebView.
//
//   node cdp-call.mjs commands.json
//   echo '[{"method":"Input.dispatchTouchEvent","params":{...}}]' | node cdp-call.mjs
//
// Useful because the Android input stack on the emulator can be blocked by
// system overlays, while CDP input goes straight into the WebView.

import { readFileSync } from 'node:fs';

const PORT = process.env.CDP_PORT || 9222;

const stripBom = (text) => text.replace(/^\uFEFF/, '');

async function readCommands() {
  const arg = process.argv[2];
  if (arg && !arg.trim().startsWith('[')) {
    return JSON.parse(stripBom(readFileSync(arg, 'utf8')));
  }
  if (arg) return JSON.parse(stripBom(arg));
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return JSON.parse(stripBom(Buffer.concat(chunks).toString('utf8')));
}

const commands = await readCommands();

const targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
const page = targets.find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
if (!page) {
  console.error('no page target found');
  process.exit(1);
}

const ws = new WebSocket(page.webSocketDebuggerUrl);
let nextId = 1;
const pending = new Map();

ws.addEventListener('message', (event) => {
  const msg = JSON.parse(event.data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    if (msg.error) reject(new Error(JSON.stringify(msg.error)));
    else resolve(msg.result);
  }
});

const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
    setTimeout(() => {
      if (pending.has(id)) {
        pending.delete(id);
        reject(new Error(`timeout on ${method}`));
      }
    }, 15000);
  });

await new Promise((resolve, reject) => {
  ws.addEventListener('open', resolve, { once: true });
  ws.addEventListener('error', () => reject(new Error('websocket error')), { once: true });
});

const results = [];
for (const cmd of commands) {
  try {
    results.push(await send(cmd.method, cmd.params));
  } catch (e) {
    results.push({ error: e.message });
  }
}
ws.close();

console.log(JSON.stringify(results, null, 2));
