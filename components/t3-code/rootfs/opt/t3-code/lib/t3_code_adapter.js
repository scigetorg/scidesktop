/* Runs in the T3 Code page before its modules capture fetch and WebSocket.
 * T3's client addresses its own server from the root of the origin; under the
 * notebook server it lives below PREFIX. Requests to other origins (remote
 * environments the user added) keep their URLs.
 */
(() => {
  const prefix = __T3_CODE_PREFIX__;
  function target(value) {
    const url = new URL(value, location.href);
    const protocol = url.protocol.replace(/^ws/, 'http');
    const local = url.host === location.host && protocol === location.protocol;
    if (local && !url.pathname.startsWith(prefix)) {
      url.pathname = prefix + url.pathname.replace(/^\//, '');
    }
    return { url: url.href, local };
  }
  window.__t3CodeTarget = target;
  const originalFetch = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const mapped = target(input instanceof Request ? input.url : input);
    if (!mapped.local) return originalFetch(input, init);
    if (!(input instanceof Request)) return originalFetch(mapped.url, init);
    // Passing a Request as RequestInit exposes its ReadableStream body, which
    // Firefox can stringify rather than upload. Only this branch reads the
    // body; fetch(url, init) keeps its Blob, FormData or stream as given.
    const request = new Request(input, init);
    return originalFetch(mapped.url, {
      method: request.method, headers: request.headers,
      body: request.body === null ? undefined : await request.arrayBuffer(),
      credentials: request.credentials, mode: request.mode, cache: request.cache,
      redirect: request.redirect, referrer: request.referrer,
      referrerPolicy: request.referrerPolicy, integrity: request.integrity,
      keepalive: request.keepalive, signal: request.signal
    });
  };
  const OriginalWebSocket = window.WebSocket;
  window.WebSocket = class extends OriginalWebSocket {
    constructor(url, protocols) {
      super(target(url).url, protocols);
    }
  };
  // T3's own Connect button signs in through t3.codes, which accepts its own
  // origins only, so here it could only spin. It is hidden. Where the image
  // sets up T3 Connect itself (docs/t3-connect.md), a button beside it opens
  // that page instead.
  const connect = __T3_CODE_CONNECT__;
  const replaceConnect = () => {
    for (const button of document.querySelectorAll('button:not([hidden])')) {
      if (button.dataset.sessionConnect || !button.textContent.includes('T3 Connect')) continue;
      button.hidden = true;
      if (!connect) continue;
      const replacement = button.cloneNode(false);
      replacement.hidden = false;
      replacement.dataset.sessionConnect = 'true';
      replacement.textContent = 'Set up T3 Connect';
      replacement.onclick = () => window.open(connect, '_blank', 'noopener');
      button.after(replacement);
    }
  };
  document.addEventListener('DOMContentLoaded', () => {
    new MutationObserver(replaceConnect).observe(document.body, { childList: true, subtree: true });
    replaceConnect();
  });
})();
