import { ILayoutRestorer } from "@jupyterlab/application";
import {
  ICommandPalette,
  MainAreaWidget,
  WidgetTracker,
} from "@jupyterlab/apputils";
import { URLExt } from "@jupyterlab/coreutils";
import { ILauncher } from "@jupyterlab/launcher";
import { ServerConnection } from "@jupyterlab/services";
import { ISettingRegistry } from "@jupyterlab/settingregistry";
import { LabIcon } from "@jupyterlab/ui-components";
import { Widget } from "@lumino/widgets";

const PLUGIN_ID = "jupyterlab-scigethelpers:plugin";
const OPEN_CMD = "jupyterlab-scigethelpers:open";
const CITE_CMD = "jupyterlab-scigethelpers:cite";
const CHECK_CMD = "jupyterlab-scigethelpers:check";

const HELPERS_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <rect x="2" y="2" width="20" height="20" rx="4" fill="#172554" stroke="#38bdf8" stroke-width="1.5"/>
  <path d="M6.5 9.5L9.5 12L6.5 14.5" fill="none" stroke="#38bdf8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
  <line x1="11.5" y1="14.5" x2="17.5" y2="14.5" stroke="#a7f3d0" stroke-width="1.8" stroke-linecap="round"/>
  <circle cx="16.5" cy="8.5" r="2" fill="#34d399"/>
</svg>`;

const helpersIcon = new LabIcon({
  name: "jupyterlab-scigethelpers:icon",
  svgstr: HELPERS_SVG,
});

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) {
    node.className = className;
  }
  if (text !== undefined && text !== null) {
    node.textContent = String(text);
  }
  return node;
}

function clearNode(node) {
  while (node.firstChild) {
    node.removeChild(node.firstChild);
  }
}

async function apiRequest(endpoint, method = "GET", body = undefined) {
  const settings = ServerConnection.makeSettings();
  const url = URLExt.join(settings.baseUrl, "scigethelpers", "api", endpoint);
  const init = { method };
  if (body !== undefined) {
    init.body = JSON.stringify(body);
    init.headers = { "Content-Type": "application/json" };
  }
  const response = await ServerConnection.makeRequest(url, init, settings);
  const text = await response.text();
  let data = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = null;
    }
  }
  if (!response.ok) {
    const msg =
      (data && (data.message || data.error)) ||
      `Request failed (HTTP ${response.status})`;
    const err = new Error(msg);
    err.status = response.status;
    err.data = data;
    throw err;
  }
  return data;
}

async function copyToClipboard(text, button) {
  const original = button.textContent;
  try {
    await navigator.clipboard.writeText(text);
    button.textContent = "Copied";
  } catch {
    button.textContent = "Copy failed";
  }
  window.setTimeout(() => {
    button.textContent = original;
  }, 1500);
}

class SessionHelpersContent extends Widget {
  constructor(app, getShowOnStartup, setShowOnStartup) {
    super();
    this._app = app;
    this._getShowOnStartup = getShowOnStartup;
    this._setShowOnStartup = setShowOnStartup;
    this._overview = null;
    this._liveInfo = null;
    this._checks = null;
    this._citeMessage = "";
    this._citeError = false;
    this._busy = { overview: false, info: false, check: false, cite: false };
    this._overviewPending = false;

    this.addClass("jp-ScigetHelpers");
    this._container = el("div", "jp-ScigetHelpers-container");
    this.node.appendChild(this._container);

    this._buildShell();
    void this.refreshOverview();
  }

  _buildShell() {
    clearNode(this._container);

    const header = el("div", "jp-ScigetHelpers-header");
    const titleBox = el("div");
    titleBox.appendChild(el("h1", "jp-ScigetHelpers-title", "Session Helpers"));
    titleBox.appendChild(
      el(
        "p",
        "jp-ScigetHelpers-subtitle",
        "Environment status, health checks, tool citations, and container/uv kernel helpers backed by scigethelpers."
      )
    );
    header.appendChild(titleBox);

    const headerActions = el("div", "jp-ScigetHelpers-headerActions");

    const toggleLabel = el("label", "jp-ScigetHelpers-toggle");
    this._startupCheckbox = document.createElement("input");
    this._startupCheckbox.type = "checkbox";
    this._startupCheckbox.checked = Boolean(this._getShowOnStartup());
    this._startupCheckbox.addEventListener("change", () => {
      void this._setShowOnStartup(this._startupCheckbox.checked);
    });
    toggleLabel.appendChild(this._startupCheckbox);
    toggleLabel.appendChild(document.createTextNode("Show on startup"));
    headerActions.appendChild(toggleLabel);

    this._refreshBtn = el("button", "jp-ScigetHelpers-button", "Refresh");
    this._refreshBtn.type = "button";
    this._refreshBtn.addEventListener("click", () => {
      this._liveInfo = null;
      void this.refreshOverview();
    });
    headerActions.appendChild(this._refreshBtn);

    const termBtn = el("button", "jp-ScigetHelpers-button", "Open Terminal");
    termBtn.type = "button";
    termBtn.addEventListener("click", () => {
      void this._app.commands.execute("terminal:create-new");
    });
    headerActions.appendChild(termBtn);

    this._quickLinks = el("div", "jp-ScigetHelpers-actions");
    headerActions.appendChild(this._quickLinks);

    header.appendChild(headerActions);
    this._container.appendChild(header);

    const grid = el("div", "jp-ScigetHelpers-grid");

    // 1. Environment & Resources card
    const envCard = el("section", "jp-ScigetHelpers-card");
    const envHeader = el("div", "jp-ScigetHelpers-cardHeader");
    envHeader.appendChild(el("h2", "jp-ScigetHelpers-cardTitle", "Environment & Resources"));
    this._probeInfoBtn = el("button", "jp-ScigetHelpers-button", "Probe GPU & CVMFS");
    this._probeInfoBtn.type = "button";
    this._probeInfoBtn.addEventListener("click", () => void this.runLiveInfo());
    envHeader.appendChild(this._probeInfoBtn);
    envCard.appendChild(envHeader);
    this._envBody = el("div");
    envCard.appendChild(this._envBody);
    grid.appendChild(envCard);

    // 2. Health Checks card
    const checkCard = el("section", "jp-ScigetHelpers-card");
    const checkHeader = el("div", "jp-ScigetHelpers-cardHeader");
    checkHeader.appendChild(el("h2", "jp-ScigetHelpers-cardTitle", "Health Checks"));
    this._runCheckBtn = el(
      "button",
      "jp-ScigetHelpers-button jp-ScigetHelpers-buttonPrimary",
      "Run Environment Check"
    );
    this._runCheckBtn.type = "button";
    this._runCheckBtn.addEventListener("click", () => void this.runCheck());
    checkHeader.appendChild(this._runCheckBtn);
    checkCard.appendChild(checkHeader);
    this._checkBody = el("div");
    checkCard.appendChild(this._checkBody);
    grid.appendChild(checkCard);

    // 3. Citations card
    const citeCard = el("section", "jp-ScigetHelpers-card");
    const citeHeader = el("div", "jp-ScigetHelpers-cardHeader");
    citeHeader.appendChild(el("h2", "jp-ScigetHelpers-cardTitle", "Tool Citations"));
    const citeBtns = el("div", "jp-ScigetHelpers-actions");
    this._generateCiteBtn = el(
      "button",
      "jp-ScigetHelpers-button jp-ScigetHelpers-buttonPrimary",
      "Generate CITATIONS.md"
    );
    this._generateCiteBtn.type = "button";
    this._generateCiteBtn.addEventListener("click", () => void this.runCite());
    citeBtns.appendChild(this._generateCiteBtn);

    this._openCiteBtn = el("button", "jp-ScigetHelpers-button", "Open CITATIONS.md");
    this._openCiteBtn.type = "button";
    this._openCiteBtn.hidden = true;
    this._openCiteBtn.addEventListener("click", () => void this._openCitations());
    citeBtns.appendChild(this._openCiteBtn);
    citeHeader.appendChild(citeBtns);
    citeCard.appendChild(citeHeader);
    this._citeBody = el("div");
    citeCard.appendChild(this._citeBody);
    grid.appendChild(citeCard);

    // 4. Kernels & CLI Commands card
    const kernelCard = el("section", "jp-ScigetHelpers-card");
    const kernelHeader = el("div", "jp-ScigetHelpers-cardHeader");
    kernelHeader.appendChild(el("h2", "jp-ScigetHelpers-cardTitle", "Kernels & CLI Commands"));
    kernelCard.appendChild(kernelHeader);
    this._kernelBody = el("div");
    kernelCard.appendChild(this._kernelBody);
    grid.appendChild(kernelCard);

    this._container.appendChild(grid);
    this._renderAll();
  }

  syncStartupCheckbox(value) {
    if (this._startupCheckbox) {
      this._startupCheckbox.checked = Boolean(value);
    }
  }

  async refreshOverview() {
    if (this._busy.overview) {
      this._overviewPending = true;
      return;
    }
    this._busy.overview = true;
    this._refreshBtn.disabled = true;
    try {
      do {
        this._overviewPending = false;
        try {
          this._overview = await apiRequest("overview", "GET");
        } catch (error) {
          this._overview = { error: String(error.message || error) };
        }
        this._renderAll();
      } while (this._overviewPending);
    } finally {
      this._busy.overview = false;
      this._refreshBtn.disabled = false;
    }
  }

  async runLiveInfo() {
    if (this._busy.info) {
      return;
    }
    this._busy.info = true;
    this._probeInfoBtn.disabled = true;
    this._probeInfoBtn.textContent = "Probing...";
    try {
      this._liveInfo = await apiRequest("info", "POST", {});
    } catch (error) {
      this._liveInfo = { error: String(error.message || error) };
    } finally {
      this._busy.info = false;
      this._probeInfoBtn.disabled = false;
      this._probeInfoBtn.textContent = "Probe GPU & CVMFS";
      this._renderEnv();
    }
  }

  async runCheck() {
    if (this._busy.check) {
      return;
    }
    this._busy.check = true;
    this._runCheckBtn.disabled = true;
    this._runCheckBtn.textContent = "Running...";
    try {
      this._checks = await apiRequest("check", "POST", {});
    } catch (error) {
      this._checks = { error: String(error.message || error) };
    } finally {
      this._busy.check = false;
      this._runCheckBtn.disabled = false;
      this._runCheckBtn.textContent = "Run Environment Check";
      this._renderChecks();
    }
  }

  async runCite() {
    if (this._busy.cite) {
      return;
    }
    this._busy.cite = true;
    this._generateCiteBtn.disabled = true;
    this._generateCiteBtn.textContent = "Generating...";
    this._citeError = false;
    this._citeMessage = "";
    try {
      let result;
      try {
        result = await apiRequest("cite", "POST", {
          action: "generate",
          overwrite: false,
        });
      } catch (error) {
        if (error && error.status === 409 && error.data && error.data.needs_overwrite) {
          const target = error.data.output || "CITATIONS.md";
          const ok = window.confirm(
            `Replace your existing ${target} with freshly generated citations from the recorded module log?`
          );
          if (!ok) {
            this._citeMessage = "Kept existing CITATIONS.md.";
            this._citeError = false;
            return;
          }
          result = await apiRequest("cite", "POST", {
            action: "generate",
            overwrite: true,
          });
        } else {
          throw error;
        }
      }
      if (result && result.ok) {
        this._citeMessage = `Wrote citations for ${result.tool_count} tool version(s) to ${result.output}.`;
        this._citeError = false;
        await this.refreshOverview();
        if (result.relative_path) {
          await this._app.commands.execute("docmanager:open", {
            path: result.relative_path,
          });
        }
      } else {
        this._citeMessage =
          (result && result.error) || "No container module loads recorded yet.";
        this._citeError = true;
      }
    } catch (error) {
      this._citeMessage = String(error.message || error);
      this._citeError = true;
    } finally {
      this._busy.cite = false;
      this._generateCiteBtn.disabled = false;
      this._generateCiteBtn.textContent = "Generate CITATIONS.md";
      this._renderCite();
    }
  }

  async _openCitations() {
    const rel =
      this._overview &&
      this._overview.citations &&
      this._overview.citations.relative_path;
    if (!rel) {
      return;
    }
    try {
      await this._app.commands.execute("docmanager:open", { path: rel });
    } catch (error) {
      this._citeMessage = `Could not open ${rel}: ${String(error.message || error)}`;
      this._citeError = true;
      this._renderCite();
    }
  }

  _renderAll() {
    this._renderQuickLinks();
    this._renderEnv();
    this._renderChecks();
    this._renderCite();
    this._renderKernels();
  }

  _renderQuickLinks() {
    clearNode(this._quickLinks);
    const links = (this._overview && this._overview.links) || {};
    if (links.getting_started) {
      const btn = el("button", "jp-ScigetHelpers-button", "Getting Started");
      btn.type = "button";
      btn.addEventListener("click", () => {
        void this._app.commands.execute("docmanager:open", {
          path: links.getting_started,
        });
      });
      this._quickLinks.appendChild(btn);
    }
    if (links.t3_connect) {
      const settings = ServerConnection.makeSettings();
      const href = URLExt.join(settings.baseUrl, links.t3_connect);
      const btn = el("button", "jp-ScigetHelpers-button", "T3 Connect");
      btn.type = "button";
      btn.addEventListener("click", () => {
        window.open(href, "_blank", "noopener,noreferrer");
      });
      this._quickLinks.appendChild(btn);
    }
  }

  _renderEnv() {
    clearNode(this._envBody);
    if (this._overview && this._overview.error) {
      this._envBody.appendChild(
        el("p", "jp-ScigetHelpers-status jp-ScigetHelpers-statusError", this._overview.error)
      );
      return;
    }
    const info =
      (this._liveInfo && !this._liveInfo.error ? this._liveInfo : null) ||
      (this._overview && this._overview.info) ||
      null;
    if (!info) {
      this._envBody.appendChild(el("p", "jp-ScigetHelpers-muted", "Loading session summary..."));
      return;
    }

    const dl = el("dl", "jp-ScigetHelpers-kv");
    const addRow = (label, value) => {
      dl.appendChild(el("dt", null, label));
      dl.appendChild(el("dd", null, value));
    };

    const comps = Array.isArray(info.components) ? info.components : [];
    addRow("User", `${info.user || "unknown"} (${info.home || ""})`);
    addRow("CPUs / RAM", `${info.cpus || "?"} CPUs, ${info.memory || "unknown"}`);
    if (info.home_disk) {
      addRow(
        "Home disk",
        `${info.home_disk.free_gib} GiB free of ${info.home_disk.total_gib} GiB`
      );
    }

    const gpu = info.gpu || {};
    if (!gpu.probed) {
      addRow("GPU", "Not probed yet (click Probe GPU & CVMFS)");
    } else if (gpu.state === "ok" && Array.isArray(gpu.devices)) {
      addRow("GPU", gpu.devices.join("; "));
    } else if (gpu.state === "error") {
      addRow("GPU", `Error: ${gpu.error || "unknown"}`);
    } else {
      addRow("GPU", "None visible");
    }

    const cvmfs = info.cvmfs || {};
    if (cvmfs.mode === "disabled") {
      addRow("CVMFS", "Disabled");
    } else if (!Array.isArray(cvmfs.configured_repos) || cvmfs.configured_repos.length === 0) {
      addRow("CVMFS", "Not configured");
    } else if (!cvmfs.probed) {
      addRow("CVMFS", `${cvmfs.configured_repos.join(", ")} (not probed yet)`);
    } else {
      const summaries = (cvmfs.repos || []).map((r) =>
        r.ok
          ? `${r.repo} (mounted${r.host ? `, ${r.host}` : ""})`
          : `${r.repo} (${r.error || "unavailable"})`
      );
      addRow("CVMFS", summaries.join("; "));
    }

    addRow(
      "Components",
      comps.length > 0 ? `${comps.length} installed (${comps.join(", ")})` : "unknown"
    );

    this._envBody.appendChild(dl);
    if (this._liveInfo && this._liveInfo.error) {
      this._envBody.appendChild(
        el("p", "jp-ScigetHelpers-status jp-ScigetHelpers-statusError", this._liveInfo.error)
      );
    }
  }

  _renderChecks() {
    clearNode(this._checkBody);
    if (!this._checks) {
      this._checkBody.appendChild(
        el(
          "p",
          "jp-ScigetHelpers-muted",
          "Checks run on demand so startup stays fast. Click Run Environment Check or run `scigethelpers check` in a terminal."
        )
      );
      return;
    }
    if (this._checks.error) {
      this._checkBody.appendChild(
        el("p", "jp-ScigetHelpers-status jp-ScigetHelpers-statusError", this._checks.error)
      );
      return;
    }
    const ul = el("ul", "jp-ScigetHelpers-list");
    for (const item of this._checks.checks || []) {
      const li = el("li", "jp-ScigetHelpers-listItem");
      const status = String(item.status || "SKIP").toUpperCase();
      const cls =
        status === "PASS"
          ? "jp-ScigetHelpers-badge-pass"
          : status === "FAIL"
            ? "jp-ScigetHelpers-badge-fail"
            : "jp-ScigetHelpers-badge-skip";
      li.appendChild(el("span", `jp-ScigetHelpers-badge ${cls}`, status));
      li.appendChild(el("strong", null, String(item.name || "")));
      li.appendChild(el("span", null, String(item.detail || "")));
      ul.appendChild(li);
    }
    this._checkBody.appendChild(ul);
  }

  _renderCite() {
    clearNode(this._citeBody);
    const cite = this._overview && this._overview.citations;
    if (!cite) {
      this._openCiteBtn.hidden = true;
      this._citeBody.appendChild(el("p", "jp-ScigetHelpers-muted", "Loading citation status..."));
      return;
    }

    const canOpenInLab = Boolean(cite.citations_exists && cite.relative_path);
    this._openCiteBtn.hidden = !canOpenInLab;

    const dl = el("dl", "jp-ScigetHelpers-kv");
    const unique = Array.isArray(cite.unique_tools) ? cite.unique_tools : [];
    dl.appendChild(el("dt", null, "Recorded"));
    dl.appendChild(
      el(
        "dd",
        null,
        `${cite.load_count || 0} module load(s) across ${unique.length} unique tool version(s)`
      )
    );
    dl.appendChild(el("dt", null, "Output file"));
    if (cite.citations_exists) {
      const note = cite.relative_path
        ? `${cite.citations_path} (updated ${cite.citations_mtime || "unknown"})`
        : `${cite.citations_path} (outside Jupyter root_dir; open from a terminal)`;
      dl.appendChild(el("dd", null, note));
    } else {
      dl.appendChild(el("dd", null, `Not yet generated (${cite.citations_path || "~/CITATIONS.md"})`));
    }
    this._citeBody.appendChild(dl);

    if (unique.length > 0) {
      const ul = el("ul", "jp-ScigetHelpers-list");
      for (const tool of unique.slice(0, 8)) {
        const label = tool.version ? `${tool.name}/${tool.version}` : tool.name;
        ul.appendChild(el("li", "jp-ScigetHelpers-listItem", label));
      }
      if (unique.length > 8) {
        ul.appendChild(
          el("li", "jp-ScigetHelpers-muted", `… and ${unique.length - 8} more`)
        );
      }
      this._citeBody.appendChild(ul);
    }

    if (this._citeMessage) {
      this._citeBody.appendChild(
        el(
          "p",
          `jp-ScigetHelpers-status${this._citeError ? " jp-ScigetHelpers-statusError" : ""}`,
          this._citeMessage
        )
      );
    }
  }

  _renderKernels() {
    clearNode(this._kernelBody);
    const cKernels = (this._overview && this._overview.container_kernels) || [];
    const uvKernels = (this._overview && this._overview.uv_kernels) || [];

    const summary = el(
      "p",
      "jp-ScigetHelpers-muted",
      `Registered kernels: ${cKernels.length} container kernel(s), ${uvKernels.length} project uv kernel(s).`
    );
    this._kernelBody.appendChild(summary);

    if (cKernels.length > 0 || uvKernels.length > 0) {
      const ul = el("ul", "jp-ScigetHelpers-list");
      for (const k of cKernels) {
        const li = el("li", "jp-ScigetHelpers-listItem");
        li.appendChild(
          el(
            "span",
            `jp-ScigetHelpers-badge ${k.available ? "jp-ScigetHelpers-badge-pass" : "jp-ScigetHelpers-badge-fail"}`,
            k.available ? "CONTAINER" : "MISSING"
          )
        );
        li.appendChild(el("span", null, `${k.display_name || k.name} (${k.module || ""})`));
        ul.appendChild(li);
      }
      for (const k of uvKernels) {
        const li = el("li", "jp-ScigetHelpers-listItem");
        li.appendChild(
          el(
            "span",
            `jp-ScigetHelpers-badge ${k.available ? "jp-ScigetHelpers-badge-pass" : "jp-ScigetHelpers-badge-fail"}`,
            k.available ? "UV" : "MISSING"
          )
        );
        li.appendChild(el("span", null, `${k.display_name || k.name} (${k.project || ""})`));
        ul.appendChild(li);
      }
      this._kernelBody.appendChild(ul);
    }

    const commands = [
      "scigethelpers kernel add <module/version>",
      "scigethelpers uv init <project-folder>",
      "scigethelpers agent preflight",
      "scigethelpers --help",
    ];
    for (const cmd of commands) {
      const row = el("div", "jp-ScigetHelpers-cmdRow");
      row.appendChild(el("code", "jp-ScigetHelpers-code", cmd));
      const copyBtn = el("button", "jp-ScigetHelpers-button", "Copy");
      copyBtn.type = "button";
      copyBtn.addEventListener("click", () => void copyToClipboard(cmd, copyBtn));
      row.appendChild(copyBtn);
      this._kernelBody.appendChild(row);
    }
  }
}

function isDeepLinkUrl() {
  const path = window.location.pathname || "";
  return path.includes("/lab/tree/") || path.includes("/lab/workspaces/");
}

function isFreshLauncherOnlyShell(app) {
  if (isDeepLinkUrl()) {
    return false;
  }
  const widgets = Array.from(app.shell.widgets("main"));
  // Require at least one Launcher tab to already exist so we never occupy an
  // empty main area before JupyterLab opens its default Launcher.
  return widgets.length > 0 && widgets.every((w) => w.id.startsWith("launcher-"));
}

const plugin = {
  id: PLUGIN_ID,
  description: "Session Helpers panel for scigethelpers in JupyterLab",
  autoStart: true,
  optional: [ILauncher, ICommandPalette, ILayoutRestorer, ISettingRegistry],
  activate: async (app, launcher, palette, restorer, settingRegistry) => {
    let showOnStartup = true;
    let settingsObj = null;

    if (settingRegistry) {
      try {
        settingsObj = await settingRegistry.load(PLUGIN_ID);
        showOnStartup = Boolean(settingsObj.get("showOnStartup").composite);
      } catch (error) {
        console.warn("jupyterlab-scigethelpers: could not load settings", error);
      }
    }

    const tracker = new WidgetTracker({
      namespace: "jupyterlab-scigethelpers",
    });

    const getShowOnStartup = () => showOnStartup;
    const setShowOnStartup = async (value) => {
      showOnStartup = Boolean(value);
      if (settingsObj) {
        try {
          await settingsObj.set("showOnStartup", showOnStartup);
        } catch (error) {
          console.warn("jupyterlab-scigethelpers: could not save setting", error);
        }
      }
    };

    if (settingsObj) {
      settingsObj.changed.connect(() => {
        showOnStartup = Boolean(settingsObj.get("showOnStartup").composite);
        tracker.forEach((widget) => {
          widget.content.syncStartupCheckbox(showOnStartup);
        });
      });
    }

    const openPanel = (activate = true) => {
      let widget = tracker.currentWidget;
      if (!widget || widget.isDisposed) {
        const content = new SessionHelpersContent(
          app,
          getShowOnStartup,
          setShowOnStartup
        );
        widget = new MainAreaWidget({ content });
        widget.id = "jupyterlab-scigethelpers-panel";
        widget.title.label = "Session Helpers";
        widget.title.caption = "Environment info, checks, citations and kernel helpers";
        widget.title.icon = helpersIcon;
        widget.title.closable = true;
        void tracker.add(widget);
      }
      if (!widget.isAttached) {
        app.shell.add(widget, "main", { activate });
      } else if (activate) {
        app.shell.activateById(widget.id);
      }
      return widget;
    };

    if (restorer) {
      void restorer.restore(tracker, {
        command: OPEN_CMD,
        name: () => "session-helpers",
      });
    }

    app.commands.addCommand(OPEN_CMD, {
      label: "Session Helpers",
      caption: "Open scigethelpers environment status, health checks, and citations",
      icon: helpersIcon,
      execute: (args) => {
        const activate = args && args.activate === false ? false : true;
        return openPanel(activate);
      },
    });

    app.commands.addCommand(CITE_CMD, {
      label: "Generate CITATIONS.md",
      caption: "Generate tool citations for loaded container modules",
      icon: helpersIcon,
      execute: async () => {
        const widget = openPanel(true);
        await widget.content.runCite();
      },
    });

    app.commands.addCommand(CHECK_CMD, {
      label: "Run Environment Check",
      caption: "Run scigethelpers check (CVMFS, GPU, Slurm, T3)",
      icon: helpersIcon,
      execute: async () => {
        const widget = openPanel(true);
        await widget.content.runCheck();
      },
    });

    if (launcher) {
      launcher.add({
        command: OPEN_CMD,
        category: "Scidesktop",
        rank: 5,
      });
    }

    if (palette) {
      palette.addItem({ command: OPEN_CMD, category: "Sciget" });
      palette.addItem({ command: CITE_CMD, category: "Sciget" });
      palette.addItem({ command: CHECK_CMD, category: "Sciget" });
    }

    // Open once in the background ONLY after JupyterLab has created the
    // default Launcher on a fresh workspace, without stealing focus or
    // preventing the Launcher from opening.
    void app.restored.then(() => {
      if (!showOnStartup || tracker.size > 0 || isDeepLinkUrl()) {
        return;
      }
      const tryOpen = () => {
        if (!showOnStartup || tracker.size > 0) {
          return true;
        }
        const widgets = Array.from(app.shell.widgets("main"));
        if (widgets.length === 0) {
          return false;
        }
        if (isFreshLauncherOnlyShell(app)) {
          openPanel(false);
        }
        return true;
      };
      if (tryOpen()) {
        return;
      }
      const onChanged = () => {
        if (tryOpen()) {
          cleanup();
        }
      };
      const timer = window.setTimeout(() => {
        tryOpen();
        cleanup();
      }, 5000);
      const cleanup = () => {
        window.clearTimeout(timer);
        if (app.shell.currentChanged) {
          app.shell.currentChanged.disconnect(onChanged);
        }
      };
      if (app.shell.currentChanged) {
        app.shell.currentChanged.connect(onChanged);
      }
    });
  },
};

export default plugin;
