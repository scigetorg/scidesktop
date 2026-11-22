import { MainAreaWidget } from "@jupyterlab/apputils";
import { PageConfig } from "@jupyterlab/coreutils";
import { ABCWidgetFactory, DocumentWidget } from "@jupyterlab/docregistry";
import { IFileBrowserFactory } from "@jupyterlab/filebrowser";
import { ILauncher } from "@jupyterlab/launcher";
import { LabIcon } from "@jupyterlab/ui-components";
import { Widget } from "@lumino/widgets";

const FACTORY_NAME = "Neuroglancer";
const OPEN_LAUNCHER_CMD = "jupyterlab-neuroglancer:open";
const OPEN_DIR_CMD = "jupyterlab-neuroglancer:open-directory";
const OPEN_PARENT_CMD = "jupyterlab-neuroglancer:open-parent-directory";

const DATASET_METADATA_FILES = new Set([
  ".zattrs",
  ".zgroup",
  ".zarray",
  "zarr.json",
  "attributes.json",
]);

const NEUROGLANCER_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <rect x="2" y="2" width="20" height="20" rx="3" fill="#182232" stroke="#38bdf8" stroke-width="1.6"/>
  <line x1="12" y1="2.8" x2="12" y2="21.2" stroke="#38bdf8" stroke-width="1.2" opacity="0.8"/>
  <line x1="2.8" y1="12" x2="21.2" y2="12" stroke="#38bdf8" stroke-width="1.2" opacity="0.8"/>
  <circle cx="7.5" cy="7.5" r="2.2" fill="#22d3ee"/>
  <circle cx="16.5" cy="7.5" r="2.2" fill="#a78bfa"/>
  <circle cx="7.5" cy="16.5" r="2.2" fill="#34d399"/>
  <polygon points="16.5,14 19.5,18.8 13.5,18.8" fill="#fbbf24"/>
</svg>`;

const neuroglancerIcon = new LabIcon({
  name: "jupyterlab-neuroglancer:icon",
  svgstr: NEUROGLANCER_SVG,
});

function encodePath(relPath) {
  return String(relPath || "")
    .split("/")
    .filter((seg) => seg.length > 0)
    .map((seg) => encodeURIComponent(seg))
    .join("/");
}

function getViewerBaseUrl() {
  const baseUrl = PageConfig.getBaseUrl();
  return `${baseUrl}neuroglancer/`;
}

function getFileHttpUrl(relPath) {
  const baseUrl = PageConfig.getBaseUrl();
  const encoded = encodePath(relPath);
  return new URL(`${baseUrl}files/${encoded}`, window.location.origin).href;
}

function buildStateUrl(state) {
  const viewerUrl = getViewerBaseUrl();
  if (!state) {
    return viewerUrl;
  }
  return `${viewerUrl}#!${encodeURIComponent(JSON.stringify(state))}`;
}

function buildLayerState(sourceUrl, layerName) {
  return {
    layers: [
      {
        type: "auto",
        source: sourceUrl,
        name: layerName || "dataset",
      },
    ],
  };
}

async function detectDirectoryProtocol(app, dirPath) {
  const lower = dirPath.toLowerCase();
  try {
    const model = await app.serviceManager.contents.get(dirPath, {
      content: true,
    });
    if (Array.isArray(model.content)) {
      const names = new Set(model.content.map((entry) => entry.name));
      if (names.has("zarr.json")) {
        return "zarr3";
      }
      if (names.has(".zgroup") || names.has(".zarray")) {
        return "zarr2";
      }
      if (names.has("attributes.json")) {
        return "n5";
      }
      if (names.has("info")) {
        return "precomputed";
      }
    }
  } catch (err) {
    console.warn("Neuroglancer directory probe fell back to extension:", err);
  }
  if (lower.endsWith(".n5")) {
    return "n5";
  }
  return "zarr";
}

function protocolForFile(relPath) {
  const lower = relPath.toLowerCase();
  if (lower.endsWith(".nii") || lower.endsWith(".nii.gz")) {
    return "nifti";
  }
  if (lower.endsWith(".vtk")) {
    return "vtk";
  }
  if (lower.endsWith(".obj")) {
    return "obj";
  }
  if (lower.endsWith(".swc")) {
    return "swc";
  }
  return null;
}

class NeuroglancerIFrameWidget extends Widget {
  constructor(url) {
    super();
    this.addClass("jp-NeuroglancerWidget");
    this._iframe = document.createElement("iframe");
    this._iframe.setAttribute("allow", "fullscreen");
    this._iframe.setAttribute("title", "Neuroglancer");
    this.node.appendChild(this._iframe);
    if (url) {
      this.setUrl(url);
    }
  }

  setUrl(url) {
    this._iframe.src = url;
  }

  dispose() {
    if (this._iframe) {
      this._iframe.src = "about:blank";
      this._iframe.remove();
    }
    super.dispose();
  }
}

class NeuroglancerDocWidget extends NeuroglancerIFrameWidget {
  constructor(context) {
    super("");
    this._context = context;
    void this._loadContext();
    context.pathChanged.connect(() => {
      void this._loadContext();
    });
  }

  async _loadContext() {
    const relPath = this._context.path;
    const fileUrl = getFileHttpUrl(relPath);
    const name = relPath.split("/").pop() || relPath;
    if (relPath.toLowerCase().endsWith(".ngstate")) {
      try {
        const resp = await fetch(fileUrl, { credentials: "same-origin" });
        if (resp.ok) {
          const state = await resp.json();
          this.setUrl(buildStateUrl(state));
          return;
        }
      } catch (err) {
        console.error("Failed to load Neuroglancer state JSON:", err);
      }
      this.setUrl(getViewerBaseUrl());
      return;
    }
    const protocol = protocolForFile(relPath);
    if (protocol) {
      this.setUrl(buildStateUrl(buildLayerState(`${protocol}://${fileUrl}`, name)));
    } else {
      this.setUrl(getViewerBaseUrl());
    }
  }
}

class NeuroglancerDocFactory extends ABCWidgetFactory {
  createNewWidget(context) {
    const content = new NeuroglancerDocWidget(context);
    const widget = new DocumentWidget({ content, context });
    widget.title.icon = neuroglancerIcon;
    return widget;
  }
}

let tabCounter = 0;

function openNeuroglancerTab(app, url, label) {
  const content = new NeuroglancerIFrameWidget(url);
  const widget = new MainAreaWidget({ content });
  tabCounter += 1;
  widget.id = `neuroglancer-viewer-${Date.now()}-${tabCounter}`;
  widget.title.label = label || "Neuroglancer";
  widget.title.icon = neuroglancerIcon;
  widget.title.closable = true;
  app.shell.add(widget, "main");
  app.shell.activateById(widget.id);
  return widget;
}

async function openDirectoryInNeuroglancer(app, dirPath) {
  const protocol = await detectDirectoryProtocol(app, dirPath);
  const httpUrl = getFileHttpUrl(dirPath);
  const name = dirPath.split("/").filter(Boolean).pop() || "dataset";
  const url = buildStateUrl(buildLayerState(`${protocol}://${httpUrl}`, name));
  return openNeuroglancerTab(app, url, `Neuroglancer: ${name}`);
}

const plugin = {
  id: "jupyterlab-neuroglancer:plugin",
  description:
    "View OME-Zarr, N5, Precomputed, NIfTI and mesh datasets in Neuroglancer",
  autoStart: true,
  requires: [IFileBrowserFactory],
  optional: [ILauncher],
  activate: (app, browserFactory, launcher) => {
    const fileTypes = [
      {
        name: "ngstate",
        displayName: "Neuroglancer State",
        extensions: [".ngstate"],
        mimeTypes: ["application/json"],
      },
      {
        name: "neuroglancer-nii",
        displayName: "NIfTI Volume",
        extensions: [".nii"],
        mimeTypes: ["application/octet-stream"],
      },
      {
        name: "neuroglancer-nii-gz",
        displayName: "Compressed NIfTI Volume",
        extensions: [".nii.gz"],
        mimeTypes: ["application/gzip"],
      },
      {
        name: "neuroglancer-vtk",
        displayName: "VTK Mesh",
        extensions: [".vtk"],
        mimeTypes: ["application/octet-stream"],
      },
      {
        name: "neuroglancer-obj",
        displayName: "OBJ Mesh",
        extensions: [".obj"],
        mimeTypes: ["text/plain"],
      },
      {
        name: "neuroglancer-swc",
        displayName: "SWC Skeleton",
        extensions: [".swc"],
        mimeTypes: ["text/plain"],
      },
    ];

    for (const ft of fileTypes) {
      app.docRegistry.addFileType({
        ...ft,
        icon: neuroglancerIcon,
      });
    }

    const factory = new NeuroglancerDocFactory({
      name: FACTORY_NAME,
      fileTypes: fileTypes.map((ft) => ft.name),
      defaultFor: ["ngstate"],
      readOnly: true,
    });
    app.docRegistry.addWidgetFactory(factory);

    app.commands.addCommand(OPEN_LAUNCHER_CMD, {
      label: "Neuroglancer",
      caption: "Open Neuroglancer volumetric and OME-Zarr viewer",
      icon: neuroglancerIcon,
      execute: () => openNeuroglancerTab(app, getViewerBaseUrl(), "Neuroglancer"),
    });

    if (launcher) {
      launcher.add({
        command: OPEN_LAUNCHER_CMD,
        category: "Other",
        rank: 5,
      });
    }

    const selectedItem = () => {
      const widget = browserFactory.tracker.currentWidget;
      if (!widget) {
        return null;
      }
      const items = Array.from(widget.selectedItems());
      return items.length === 1 ? items[0] : null;
    };

    app.commands.addCommand(OPEN_DIR_CMD, {
      label: "Open in Neuroglancer",
      caption: "Open OME-Zarr, N5 or Precomputed folder in Neuroglancer",
      icon: neuroglancerIcon,
      isEnabled: () => {
        const item = selectedItem();
        return Boolean(item && item.type === "directory");
      },
      execute: async () => {
        const item = selectedItem();
        if (item && item.type === "directory") {
          await openDirectoryInNeuroglancer(app, item.path);
        }
      },
    });

    app.contextMenu.addItem({
      command: OPEN_DIR_CMD,
      selector: '.jp-DirListing-item[data-isdir="true"]',
      rank: 2,
    });

    app.commands.addCommand(OPEN_PARENT_CMD, {
      label: "Open Dataset in Neuroglancer",
      caption: "Open the parent Zarr/N5 dataset folder in Neuroglancer",
      icon: neuroglancerIcon,
      isVisible: () => {
        const item = selectedItem();
        if (!item || item.type !== "file") {
          return false;
        }
        return DATASET_METADATA_FILES.has(item.name) && item.path.includes("/");
      },
      execute: async () => {
        const item = selectedItem();
        if (!item || !item.path.includes("/")) {
          return;
        }
        const parentPath = item.path.slice(0, item.path.lastIndexOf("/"));
        await openDirectoryInNeuroglancer(app, parentPath);
      },
    });

    app.contextMenu.addItem({
      command: OPEN_PARENT_CMD,
      selector: '.jp-DirListing-item[data-isdir="false"]',
      rank: 2,
    });
  },
};

export default plugin;
