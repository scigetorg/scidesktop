import { URLExt } from "@jupyterlab/coreutils";
import { ILauncher } from "@jupyterlab/launcher";
import { ServerConnection } from "@jupyterlab/services";
import { LabIcon } from "@jupyterlab/ui-components";

const WEBKNOSSOS_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <rect x="2" y="2" width="20" height="20" rx="4" fill="#132238" stroke="#38bdf8" stroke-width="1.5"/>
  <polygon points="12,4.6 18.6,8.4 12,12.2 5.4,8.4" fill="#38bdf8" opacity="0.9"/>
  <polygon points="5.4,8.4 12,12.2 12,19.4 5.4,15.6" fill="#0284c7" opacity="0.95"/>
  <polygon points="18.6,8.4 12,12.2 12,19.4 18.6,15.6" fill="#818cf8" opacity="0.9"/>
  <path d="M8.4,11.2 L12,13.2 L15.6,11.2" fill="none" stroke="#f8fafc" stroke-width="1.2" stroke-linecap="round"/>
</svg>`;

const EXTERNAL_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <rect x="2" y="2" width="20" height="20" rx="4" fill="#182232" stroke="#60a5fa" stroke-width="1.5"/>
  <path d="M13 6h5v5M18 6l-7.5 7.5" fill="none" stroke="#38bdf8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M17 13.5v3.5a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1h3.5" fill="none" stroke="#93c5fd" stroke-width="1.6" stroke-linecap="round"/>
</svg>`;

const ICONS = {
  webknossos: new LabIcon({
    name: "scidesktop-launcher-links:webknossos",
    svgstr: WEBKNOSSOS_SVG,
  }),
  external: new LabIcon({
    name: "scidesktop-launcher-links:external",
    svgstr: EXTERNAL_SVG,
  }),
};

function isSafeHttpUrl(raw) {
  try {
    const parsed = new URL(String(raw));
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch {
    return false;
  }
}

async function registerLinks(app, launcher) {
  const settings = ServerConnection.makeSettings();
  const endpoint = URLExt.join(
    settings.baseUrl,
    "scidesktop-launcher-links",
    "links"
  );
  let payload;
  try {
    const resp = await ServerConnection.makeRequest(endpoint, {}, settings);
    if (!resp.ok) {
      console.warn("scidesktop-launcher-links: server returned", resp.status);
      return;
    }
    payload = await resp.json();
  } catch (err) {
    console.warn("scidesktop-launcher-links: failed to load links", err);
    return;
  }
  const links = Array.isArray(payload?.links) ? payload.links : [];
  for (const item of links) {
    if (!item || typeof item.title !== "string" || !isSafeHttpUrl(item.url)) {
      continue;
    }
    const cmdId = `scidesktop-launcher-links:open-${item.id || item.title}`;
    const icon = ICONS[item.icon] || ICONS.external;
    const targetUrl = item.url;
    if (!app.commands.hasCommand(cmdId)) {
      app.commands.addCommand(cmdId, {
        label: `${item.title} [\u2197]`,
        caption: item.caption || `Open ${item.title}`,
        icon,
        execute: () => {
          window.open(targetUrl, "_blank", "noopener,noreferrer");
        },
      });
    }
    launcher.add({
      command: cmdId,
      category: item.category || "Scidesktop",
      rank: typeof item.rank === "number" ? item.rank : 20,
    });
  }
}

const plugin = {
  id: "scidesktop-launcher-links:plugin",
  description: "Operator-configured external launcher tiles (e.g. WEBKNOSSOS)",
  autoStart: true,
  optional: [ILauncher],
  activate: (app, launcher) => {
    if (!launcher) {
      return;
    }
    void registerLinks(app, launcher);
  },
};

export default plugin;
