#!/usr/bin/env node
// Real headless Chrome/Chromium + SwiftShader WebGL2 smoke check over CDP.
// Uses only Node.js built-ins (no npm packages required).
//
// Usage:
//   node test/browser-check.mjs <base-url> <token> [--has-vscode]

import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";

const BASE_URL = (process.argv[2] || "").replace(/\/+$/, "");
const TOKEN = process.argv[3] || "";
const HAS_VSCODE = process.argv.includes("--has-vscode");

if (!BASE_URL || !TOKEN) {
  console.error("usage: browser-check.mjs <base-url> <token> [--has-vscode]");
  process.exit(2);
}

let failed = 0;
const pass = (msg) => console.log(`  ok    ${msg}`);
const fail = (msg, detail = "") => {
  console.log(`  FAIL  ${msg}`);
  if (detail) {
    for (const line of String(detail).trim().split("\n").slice(0, 10)) {
      console.log(`        ${line}`);
    }
  }
  failed += 1;
};

function findBrowser() {
  const candidates = [
    process.env.BROWSER_BIN,
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/snap/bin/chromium",
  ].filter(Boolean);
  for (const bin of candidates) {
    if (fs.existsSync(bin)) return bin;
  }
  return null;
}

class CDP {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
    ws.addEventListener("message", (ev) => {
      const msg = JSON.parse(ev.data.toString());
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        if (msg.error) reject(new Error(`${msg.error.message} (${msg.error.code})`));
        else resolve(msg.result);
      } else if (msg.method) {
        for (const fn of this.listeners.get(msg.method) || []) fn(msg.params, msg.sessionId);
      }
    });
  }

  on(method, fn) {
    if (!this.listeners.has(method)) this.listeners.set(method, []);
    this.listeners.get(method).push(fn);
  }

  send(method, params = {}, sessionId = undefined) {
    const id = this.nextId++;
    const payload = { id, method, params };
    if (sessionId) payload.sessionId = sessionId;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP timeout on ${method}`));
      }, 30000);
      this.pending.set(id, {
        resolve: (v) => { clearTimeout(timer); resolve(v); },
        reject: (e) => { clearTimeout(timer); reject(e); },
      });
      this.ws.send(JSON.stringify(payload));
    });
  }

  close() {
    try { this.ws.close(); } catch { /* ignore */ }
  }
}

async function launchChrome(browserBin, userDataDir) {
  const args = [
    "--headless=new",
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--disable-gpu-sandbox",
    "--use-gl=angle",
    "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader",
    "--enable-webgl",
    "--ignore-gpu-blocklist",
    "--window-size=1280,900",
    "--remote-debugging-port=0",
    `--user-data-dir=${userDataDir}`,
    "about:blank",
  ];
  const proc = spawn(browserBin, args, { stdio: ["ignore", "pipe", "pipe"] });
  let stderr = "";
  const wsUrl = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Chrome failed to start:\n${stderr}`)), 25000);
    proc.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
      const m = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (m) {
        clearTimeout(timer);
        resolve(m[1]);
      }
    });
    proc.on("exit", (code) => {
      clearTimeout(timer);
      reject(new Error(`Chrome exited early (${code}):\n${stderr}`));
    });
  });
  const ws = new WebSocket(wsUrl);
  await new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve, { once: true });
    ws.addEventListener("error", (e) => reject(new Error(`WebSocket error: ${e.message || e}`)), { once: true });
  });
  return { proc, cdp: new CDP(ws) };
}

async function openTab(cdp) {
  const { targetId } = await cdp.send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await cdp.send("Target.attachToTarget", { targetId, flatten: true });
  const errors = [];
  const server5xx = [];
  cdp.on("Runtime.exceptionThrown", (params, sid) => {
    if (sid !== sessionId) return;
    const d = params.exceptionDetails || {};
    const text = d.exception?.description || d.text || "uncaught exception";
    errors.push(text.split("\n")[0]);
  });
  cdp.on("Network.responseReceived", (params, sid) => {
    if (sid !== sessionId) return;
    const r = params.response || {};
    if (r.status >= 500) server5xx.push(`${r.status} ${r.url}`);
  });
  await cdp.send("Page.enable", {}, sessionId);
  await cdp.send("Runtime.enable", {}, sessionId);
  await cdp.send("Network.enable", {}, sessionId);
  await cdp.send("Emulation.setDeviceMetricsOverride", {
    width: 1280, height: 900, deviceScaleFactor: 1, mobile: false,
  }, sessionId);
  return {
    targetId,
    sessionId,
    errors,
    server5xx,
    async goto(url) {
      await cdp.send("Page.navigate", { url }, sessionId);
    },
    async eval(expression) {
      const res = await cdp.send("Runtime.evaluate", {
        expression,
        awaitPromise: true,
        returnByValue: true,
      }, sessionId);
      if (res.exceptionDetails) {
        throw new Error(res.exceptionDetails.exception?.description || res.exceptionDetails.text);
      }
      return res.result?.value;
    },
    async clickAt(x, y, clicks = 1) {
      for (let i = 1; i <= clicks; i++) {
        await cdp.send("Input.dispatchMouseEvent", {
          type: "mouseMoved", x, y,
        }, sessionId);
        await cdp.send("Input.dispatchMouseEvent", {
          type: "mousePressed", x, y, button: "left", clickCount: i,
        }, sessionId);
        await cdp.send("Input.dispatchMouseEvent", {
          type: "mouseReleased", x, y, button: "left", clickCount: i,
        }, sessionId);
        if (i < clicks) await new Promise((r) => setTimeout(r, 60));
      }
    },
    async typeAtSign() {
      await cdp.send("Input.dispatchKeyEvent", {
        type: "keyDown", key: "@", code: "Digit2", text: "@", unmodifiedText: "@", windowsVirtualKeyCode: 50, modifiers: 8,
      }, sessionId);
      await cdp.send("Input.dispatchKeyEvent", {
        type: "keyUp", key: "@", code: "Digit2", windowsVirtualKeyCode: 50, modifiers: 8,
      }, sessionId);
    },
    async waitFor(fnExpr, timeoutMs = 45000, pollMs = 300) {
      const deadline = Date.now() + timeoutMs;
      while (Date.now() < deadline) {
        try {
          const val = await this.eval(fnExpr);
          if (val) return val;
        } catch { /* page navigating */ }
        await new Promise((r) => setTimeout(r, pollMs));
      }
      return null;
    },
    async screenshotClip(clip) {
      const { data } = await cdp.send("Page.captureScreenshot", {
        format: "png",
        clip: { ...clip, scale: 1 },
      }, sessionId);
      return Buffer.from(data, "base64");
    },
    async close() {
      try { await cdp.send("Target.closeTarget", { targetId }); } catch { /* ignore */ }
    },
  };
}

// Decode a standard 8-bit RGB/RGBA PNG buffer and count distinct quantized colors.
function pngColorStats(buf) {
  let off = 8;
  let width = 0;
  let height = 0;
  let colorType = 6;
  const idat = [];
  while (off < buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString("ascii", off + 4, off + 8);
    const chunk = buf.subarray(off + 8, off + 8 + len);
    if (type === "IHDR") {
      width = chunk.readUInt32BE(0);
      height = chunk.readUInt32BE(4);
      colorType = chunk[9];
    } else if (type === "IDAT") {
      idat.push(chunk);
    } else if (type === "IEND") {
      break;
    }
    off += 12 + len;
  }
  const bpp = colorType === 6 ? 4 : colorType === 2 ? 3 : 4;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * bpp;
  const recon = Buffer.alloc(height * stride);
  const filter4Predictor = (a, b, c) => {
    const p = a + b - c;
    const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
    return (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
  };
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const rowOff = y * (stride + 1) + 1;
    const outOff = y * stride;
    for (let x = 0; x < stride; x++) {
      const v = raw[rowOff + x];
      const a = x >= bpp ? recon[outOff + x - bpp] : 0;
      const b = y > 0 ? recon[outOff - stride + x] : 0;
      const c = (x >= bpp && y > 0) ? recon[outOff - stride + x - bpp] : 0;
      let val = v;
      if (filter === 1) val = (v + a) & 0xff;
      else if (filter === 2) val = (v + b) & 0xff;
      else if (filter === 3) val = (v + ((a + b) >> 1)) & 0xff;
      else if (filter === 4) val = (v + filter4Predictor(a, b, c)) & 0xff;
      recon[outOff + x] = val;
    }
  }
  const buckets = new Set();
  let bright = 0;
  let dark = 0;
  for (let y = 0; y < height; y += 2) {
    for (let x = 0; x < width; x += 2) {
      const i = y * stride + x * bpp;
      const r = recon[i], g = recon[i + 1], b = recon[i + 2];
      buckets.add(`${r >> 4},${g >> 4},${b >> 4}`);
      const lum = (r + g + b) / 3;
      if (lum > 80) bright += 1;
      if (lum < 40) dark += 1;
    }
  }
  return { width, height, distinctColors: buckets.size, bright, dark };
}

async function pollRenderedPixels(tab, rect, label) {
  let stats = null;
  for (let i = 0; i < 20; i++) {
    await new Promise((r) => setTimeout(r, 500));
    const png = await tab.screenshotClip(rect);
    stats = pngColorStats(png);
    if (stats.distinctColors >= 4 && stats.bright > 20 && stats.dark > 20) {
      pass(`${label} (${stats.width}x${stats.height}, ${stats.distinctColors} tones, bright=${stats.bright}, dark=${stats.dark})`);
      return true;
    }
  }
  fail(label, JSON.stringify(stats));
  return false;
}

async function main() {
  const browserBin = findBrowser();
  if (!browserBin) {
    console.error("  FAIL  no Chrome/Chromium binary found (set BROWSER_BIN)");
    process.exit(1);
  }
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "scidesktop-cdp-"));
  const { proc, cdp } = await launchChrome(browserBin, userDataDir);
  try {
    // 1. JupyterLab boot, WebGL2 availability, and launcher tiles
    const lab = await openTab(cdp);
    await lab.goto(`${BASE_URL}/lab?token=${encodeURIComponent(TOKEN)}`);
    const launcher = await lab.waitFor(`(() => {
      const panel = document.querySelector('#jp-main-dock-panel');
      const cards = [...document.querySelectorAll('.jp-LauncherCard-label')].map(e => e.textContent.trim());
      if (!panel || cards.length < 3) return null;
      return { cards };
    })()`, 60000);

    if (launcher) {
      pass(`JupyterLab rendered launcher (${launcher.cards.length} tiles)`);
      for (const expected of ["Desktop", "scigent.ai", "Chat"]) {
        if (launcher.cards.some((c) => c.toLowerCase().includes(expected.toLowerCase()))) {
          pass(`launcher offers "${expected}" tile`);
        } else {
          fail(`launcher offers "${expected}" tile`, `saw: ${launcher.cards.join(", ")}`);
        }
      }
      if (HAS_VSCODE) {
        if (launcher.cards.some((c) => c.toLowerCase().includes("vs code"))) {
          pass('launcher offers "VS Code" tile');
        } else {
          fail('launcher offers "VS Code" tile', `saw: ${launcher.cards.join(", ")}`);
        }
      }
    } else {
      fail("JupyterLab rendered launcher");
    }

    const webgl2 = await lab.eval(`(() => {
      const c = document.createElement('canvas');
      const gl = c.getContext('webgl2');
      return gl ? gl.getParameter(gl.VERSION) : null;
    })()`);
    if (webgl2) pass(`WebGL2 active (${webgl2})`);
    else fail("WebGL2 active in headless Chrome");

    // 2. NiiVue WebGL2 rendering: ensure file browser is visible, double-click smoke_brain.nii.gz
    await lab.eval(`(() => {
      const tab = document.querySelector('.jp-SideBar [data-id="filebrowser"]');
      if (tab && !tab.classList.contains('lm-mod-current')) tab.click();
    })()`);
    const filePt = await lab.waitFor(`(() => {
      const node = [...document.querySelectorAll('.jp-DirListing-itemText')]
        .find(n => (n.textContent || '').includes('smoke_brain.nii.gz'));
      if (!node) return null;
      node.scrollIntoView({ block: 'center' });
      const r = node.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) return null;
      return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) };
    })()`, 30000);

    if (filePt) {
      await lab.clickAt(filePt.x, filePt.y, 2);
      const niivueRect = await lab.waitFor(`(() => {
        const el = document.querySelector('.jp-NiivueWidget iframe');
        if (!el) return null;
        const r = el.getBoundingClientRect();
        if (r.width < 150 || r.height < 150) return null;
        return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
      })()`, 30000);
      if (niivueRect) {
        await pollRenderedPixels(lab, niivueRect, "NiiVue rendered NIfTI volume pixels");
      } else {
        fail("NiiVue opened smoke_brain.nii.gz on double-click");
      }
    } else {
      const items = await lab.eval(`[...document.querySelectorAll('.jp-DirListing-itemText')].map(n => n.textContent.trim())`);
      fail("smoke_brain.nii.gz appeared in JupyterLab file browser", JSON.stringify(items));
    }

    // 3. Jupyter AI Chat UI + ACP personas (OpenCode, Codex, Claude)
    // Switch back to the Launcher tab and click the Chat launcher card.
    const launcherTab = await lab.eval(`(() => {
      const t = [...document.querySelectorAll('.lm-TabBar-tabLabel')].find(n => n.textContent.trim() === 'Launcher');
      if (!t) return null;
      const r = t.getBoundingClientRect();
      return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) };
    })()`);
    if (launcherTab) await lab.clickAt(launcherTab.x, launcherTab.y, 1);

    const chatCard = await lab.waitFor(`(() => {
      const label = [...document.querySelectorAll('.jp-LauncherCard-label')]
        .find(n => n.textContent.trim().toLowerCase() === 'chat');
      if (!label) return null;
      const card = label.closest('.jp-LauncherCard') || label;
      card.scrollIntoView({ block: 'center' });
      const r = card.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) return null;
      return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) };
    })()`, 15000);

    if (chatCard) {
      await lab.clickAt(chatCard.x, chatCard.y, 1);
      // Confirm creation dialog if JupyterLab prompts for a chat filename.
      const okBtn = await lab.waitFor(`(() => {
        const b = document.querySelector('.jp-Dialog-button.jp-mod-accept');
        if (!b) return null;
        const r = b.getBoundingClientRect();
        return r.width > 0 ? { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) } : null;
      })()`, 3000);
      if (okBtn) await lab.clickAt(okBtn.x, okBtn.y, 1);

      const chatInput = await lab.waitFor(`(() => {
        const el = document.querySelector('.jp-chat-input-container textarea[placeholder]')
          || document.querySelector('.jp-chat-input-container textarea');
        if (!el) return null;
        const r = el.getBoundingClientRect();
        return r.width > 0 ? { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) } : null;
      })()`, 30000);

      if (chatInput) {
        pass("Jupyter AI Chat panel opened from Launcher");
        // Wait briefly for PersonaManagerExtension to initialize the chat room's
        // personas, then open the persona selector in the chat toolbar (labeled
        // "No one" when no default persona is set) to verify all 3 personas appear.
        await new Promise((r) => setTimeout(r, 1500));
        const personaBtn = await lab.eval(`(() => {
          const btn = [...document.querySelectorAll('.jp-chat-input-toolbar button, .jp-chat-widget button')]
            .find(b => /no one|persona|claude|codex|opencode/i.test(b.textContent || b.getAttribute('aria-label') || ''));
          if (!btn) return null;
          const r = btn.getBoundingClientRect();
          return r.width > 0 ? { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) } : null;
        })()`);
        if (personaBtn) {
          await lab.clickAt(personaBtn.x, personaBtn.y, 1);
        } else {
          await lab.clickAt(chatInput.x, chatInput.y, 1);
          await lab.typeAtSign();
        }
        const foundPersonas = await lab.waitFor(`(() => {
          const text = (document.body.innerText || '').toLowerCase();
          const found = ['opencode', 'codex', 'claude'].filter(p => text.includes(p));
          return found.length === 3 ? found : null;
        })()`, 15000, 400);
        if (foundPersonas) {
          pass(`Jupyter AI Chat offers all 3 agent personas (${foundPersonas.join(", ")})`);
        } else {
          const domHint = await lab.eval(`(() => {
            const items = [...document.querySelectorAll('[role="option"], [role="menuitem"], [role="listbox"], .MuiMenu-list, .jp-chat-input-toolbar')].map(e => e.textContent.trim()).filter(Boolean);
            return items.slice(0, 10).join(' | ') || (document.body.innerText || '').slice(-400);
          })()`);
          fail("Jupyter AI Chat offers OpenCode, Codex, and Claude personas", domHint);
        }
      } else {
        fail("Jupyter AI Chat panel opened from Launcher");
      }
    } else {
      fail("Chat launcher card clickable");
    }

    if (lab.server5xx.length === 0) pass("JupyterLab + NiiVue + Chat had zero HTTP 5xx responses");
    else fail("JupyterLab + NiiVue + Chat had zero HTTP 5xx responses", lab.server5xx.join("\n"));
    await lab.close();

    // 4. FreeBrowse WebGL2 app loading the real NIfTI volume
    const fb = await openTab(cdp);
    let volStatus = 0;
    cdp.on("Network.responseReceived", (params, sid) => {
      if (sid === fb.sessionId && (params.response?.url || "").includes("smoke_brain.nii.gz")) {
        volStatus = params.response.status;
      }
    });
    const volUrl = `${BASE_URL}/files/smoke_brain.nii.gz`;
    await fb.goto(`${BASE_URL}/freebrowse/?vol=${encodeURIComponent(volUrl)}`);
    const fbRect = await fb.waitFor(`(() => {
      const c = [...document.querySelectorAll('canvas')]
        .find(n => { const r = n.getBoundingClientRect(); return r.width >= 150 && r.height >= 150; });
      if (!c) return null;
      const r = c.getBoundingClientRect();
      return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
    })()`, 30000);
    // Wait for the volume fetch response so a fast canvas mount cannot race a slower download.
    for (let i = 0; i < 40 && volStatus === 0; i++) {
      await new Promise((r) => setTimeout(r, 250));
    }
    if (fbRect && volStatus === 200) {
      await pollRenderedPixels(fb, fbRect, "FreeBrowse downloaded and rendered NIfTI volume pixels");
    } else {
      fail("FreeBrowse downloaded and rendered NIfTI volume pixels", `rect=${JSON.stringify(fbRect)} volStatus=${volStatus}`);
    }
    if (fb.server5xx.length === 0 && fb.errors.length === 0) {
      pass("FreeBrowse loaded with zero HTTP 5xx and zero uncaught exceptions");
    } else {
      fail("FreeBrowse loaded cleanly", [...fb.server5xx, ...fb.errors].join("\n"));
    }
    await fb.close();

    // 5. T3 Code SPA through base-path adapter (/t3-code/)
    // The initial cold-start request to /t3-code/ intentionally returns HTTP 503
    // with Refresh: 2 while T3 boots; any 5xx on assets/API or uncaught JS error fails.
    const t3 = await openTab(cdp);
    await t3.goto(`${BASE_URL}/t3-code/`);
    const t3Ok = await t3.waitFor(`(() => {
      const root = document.querySelector('#root');
      const txt = (document.body.innerText || '').trim();
      if (!root || !txt || txt.includes('T3 Code is starting')) return null;
      return { len: txt.length };
    })()`, 45000);
    if (t3Ok) pass(`T3 Code SPA rendered through base-path proxy (${t3Ok.len} chars)`);
    else fail("T3 Code SPA rendered through base-path proxy");
    const unexpectedT35xx = t3.server5xx.filter((e) => !/^503 https?:\/\/[^/]+\/t3-code\/?$/.test(e));
    if (unexpectedT35xx.length === 0 && t3.errors.length === 0) {
      pass("T3 Code loaded with zero unexpected HTTP 5xx and zero uncaught JS exceptions");
    } else {
      fail("T3 Code loaded cleanly", [...unexpectedT35xx, ...t3.errors].join("\n"));
    }
    await t3.close();

    // 6. VS Code (code-server) workbench when installed
    if (HAS_VSCODE) {
      const vsc = await openTab(cdp);
      await vsc.goto(`${BASE_URL}/vscode/`);
      const vscOk = await vsc.waitFor(`(() => {
        const wb = document.querySelector('.monaco-workbench');
        return wb ? { ok: true } : null;
      })()`, 45000);
      if (vscOk) pass("VS Code workbench rendered");
      else fail("VS Code workbench rendered");
      if (vsc.server5xx.length === 0) pass("VS Code had zero HTTP 5xx responses");
      else fail("VS Code had zero HTTP 5xx responses", vsc.server5xx.join("\n"));
      await vsc.close();
    }
  } finally {
    cdp.close();
    proc.kill("SIGKILL");
    await new Promise((r) => setTimeout(r, 200));
    try { fs.rmSync(userDataDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }

  console.log();
  if (failed === 0) {
    console.log("browser smoke: all checks passed");
    process.exit(0);
  } else {
    console.log(`browser smoke: ${failed} check(s) failed`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(`  FAIL  browser smoke crashed: ${err.stack || err}`);
  process.exit(1);
});
