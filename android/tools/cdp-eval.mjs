// Evaluates JavaScript inside the Sketch3D WebView through the Chrome
// DevTools Protocol (works because wry enables WebView debugging).
//
//   adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>
//   node cdp-eval.mjs "typeof window.AndroidBridge"
//   node cdp-eval.mjs "window.AndroidBridge.saveToDownloads('a.txt','text/plain',btoa('hi'))"

const PORT = process.env.CDP_PORT || 9222;
const expression = process.argv.slice(2).join(' ');
if (!expression) {
  console.error('usage: node cdp-eval.mjs "<expression>"');
  process.exit(2);
}

const targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
const page = targets.find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
if (!page) {
  console.error('no page target found. Targets:', JSON.stringify(targets, null, 2));
  process.exit(1);
}

console.error(`target: ${page.url}`);

const ws = new WebSocket(page.webSocketDebuggerUrl);
const result = await new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error('timeout')), 20000);
  ws.addEventListener('open', () => {
    ws.send(JSON.stringify({
      id: 1,
      method: 'Runtime.evaluate',
      params: {
        expression,
        returnByValue: true,
        awaitPromise: true,
        userGesture: true,
      },
    }));
  });
  ws.addEventListener('message', (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id === 1) {
      clearTimeout(timer);
      resolve(msg);
    }
  });
  ws.addEventListener('error', (e) => {
    clearTimeout(timer);
    reject(new Error('websocket error: ' + (e.message || 'unknown')));
  });
});

ws.close();

if (result.result?.exceptionDetails) {
  console.error('EXCEPTION:', JSON.stringify(result.result.exceptionDetails, null, 2));
  process.exit(1);
}
console.log(JSON.stringify(result.result?.result?.value ?? result.result?.result?.description ?? null));
