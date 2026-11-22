#!/usr/bin/env python3
"""Share ipyniivue's frontend bundle and remove idle scene polling.

Ported from neurodesk/neurodesktop (config/jupyter/patch_ipyniivue.py, MIT) and
adapted for scidesktop's layered component architecture: the shared bundle is
stored in /opt/neuroimaging-env/static and served behind Jupyter's login at
<baseUrl>neuroimaging-ipyniivue/<asset_name>, leaving /opt/conda untouched.
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

BOOTSTRAP_MARKER = "scidesktop-ipyniivue-shared-bundle"
MODEL_CLEANUP_MARKER = "scidesktop-ipyniivue-model-cleanup"
SCENE_SYNC_MARKER = "scidesktop-ipyniivue-event-scene-sync"
SHARED_DISPOSER_MARKER = "scidesktop-ipyniivue-shared-disposer"
ASSET_PATTERN = re.compile(
    r"scidesktop-ipyniivue\.(?P<hash>[0-9a-f]{20})\.js"
)

STATE_BEFORE = "var vA,BC;async function BB"
STATE_AFTER = "async function BB"
SYNC_BEFORE = (
    'function S0(A,I){BC!==void 0&&(clearInterval(BC),BC=void 0);'
    'let B=I.get("scene"),C=!1;BC=setInterval(async()=>{if(!C)return;'
    'let E=I.get("this_model_id");if(!E)return;let t;try{'
    't=await I.widget_manager.get_model(E)}catch{return}let i={'
    'renderAzimuth:A.scene.renderAzimuth,'
    'renderElevation:A.scene.renderElevation,'
    'volScaleMultiplier:A.scene.volScaleMultiplier,'
    'crosshairPos:[...A.scene.crosshairPos],'
    'clipPlanes:A.scene.clipPlanes.map(a=>[...a]),'
    'clipPlaneDepthAziElevs:A.scene.clipPlaneDepthAziElevs.map(a=>[...a]),'
    'pan2Dxyzmm:[...A.scene.pan2Dxyzmm],gamma:A.scene.gamma||1},'
    'o=D2(B,i);Object.keys(o).length>0&&(e2(t,{scene:o}),B=i)},30);'
    'let Q=A.sync;A.sync=new Proxy(Q,{apply:(E,t,i)=>{if('
    'Reflect.apply(E,t,i),!A.gl){C=!1;return}if(!A.gl.canvas.matches('
    '":focus")){C=!1;return}C=!0}})}'
)
SYNC_AFTER = (
    f'function createWidgetDefinition(){{let vA,scidesktopDisposer;'
    f'function S0(A,I){{'
    f'/*{SCENE_SYNC_MARKER}*/let B=I.get("scene");const C=async()=>{{'
    'let g=I.get("this_model_id");if(!g)return;let Q;try{'
    'Q=await I.widget_manager.get_model(g)}catch{return}let E={'
    'renderAzimuth:A.scene.renderAzimuth,'
    'renderElevation:A.scene.renderElevation,'
    'volScaleMultiplier:A.scene.volScaleMultiplier,'
    'crosshairPos:[...A.scene.crosshairPos],'
    'clipPlanes:A.scene.clipPlanes.map(a=>[...a]),'
    'clipPlaneDepthAziElevs:A.scene.clipPlaneDepthAziElevs.map(a=>[...a]),'
    'pan2Dxyzmm:[...A.scene.pan2Dxyzmm],gamma:A.scene.gamma||1},'
    't=D2(B,E);Object.keys(t).length>0&&(e2(Q,{scene:t}),B=E)};'
    'let i=A.sync;A.sync=new Proxy(i,{apply:(o,a,e)=>{'
    'let D=Reflect.apply(o,a,e);return A.gl&&A.gl.canvas.matches('
    '":focus")&&C(),D}})}'
)
CLEANUP_BEFORE = "clearInterval(BC)}},async render"
CLEANUP_AFTER = (
    f"/*{MODEL_CLEANUP_MARKER}*/vA.cleanup(),"
    'vA.gl?.getExtension("WEBGL_lose_context")?.loseContext(),'
    "vA=void 0,scidesktopDisposer=void 0}},async render"
)
DISPOSER_INIT_BEFORE = "async initialize({model:A}){let I=new $B;"
DISPOSER_INIT_AFTER = (
    f"async initialize({{model:A}}){{/*{SHARED_DISPOSER_MARKER}*/"
    "let I=scidesktopDisposer=new $B;"
)
DISPOSER_RENDER_BEFORE = "let B=new $B;if(vA.canvas?.parentNode)"
DISPOSER_RENDER_AFTER = (
    "let B=scidesktopDisposer??(scidesktopDisposer=new $B);"
    "if(vA.canvas?.parentNode)"
)
EXPORT_BEFORE = "};export{Ih as default};"
EXPORT_AFTER = "};return Ih}export{createWidgetDefinition};"


def _replace_once(source: str, before: str, after: str, name: str) -> str:
    if source.count(before) != 1:
        raise ValueError(
            f"ipyniivue {name} anchor did not match exactly once; "
            "reassess the frontend workaround"
        )
    return source.replace(before, after)


def _bootstrap_source(asset_name: str) -> str:
    return f'''/*{BOOTSTRAP_MARKER}*/
const configElement = document.getElementById("jupyter-config-data");
if (!configElement) {{
  throw new Error("Jupyter page config is unavailable for ipyniivue");
}}
const {{baseUrl}} = JSON.parse(configElement.textContent || "{{}}");
if (!baseUrl) {{
  throw new Error("Jupyter baseUrl is unavailable for ipyniivue");
}}
const assetUrl = new URL(
  "neuroimaging-ipyniivue/{asset_name}",
  new URL(baseUrl, document.baseURI),
);
const {{createWidgetDefinition}} = await import(assetUrl.href);
export default createWidgetDefinition();
'''


def patch_ipyniivue(package_dir: Path, static_dir: Path) -> bool:
    package_dir = Path(package_dir)
    static_dir = Path(static_dir)
    widget_path = package_dir / "static/widget.js"
    source = widget_path.read_text(encoding="utf-8")

    if BOOTSTRAP_MARKER in source:
        assets = ASSET_PATTERN.findall(source)
        if len(assets) != 1:
            raise ValueError("patched ipyniivue bootstrap has an invalid asset anchor")
        asset_path = static_dir / f"scidesktop-ipyniivue.{assets[0]}.js"
        asset_source = asset_path.read_text(encoding="utf-8")
        asset_hash = hashlib.sha256(asset_source.encode("utf-8")).hexdigest()[:20]
        if (
            asset_hash != assets[0]
            or MODEL_CLEANUP_MARKER not in asset_source
            or SHARED_DISPOSER_MARKER not in asset_source
            or SCENE_SYNC_MARKER not in asset_source
            or "export{createWidgetDefinition};" not in asset_source
        ):
            raise ValueError("patched ipyniivue shared asset is incomplete")
        return False

    patched = _replace_once(source, STATE_BEFORE, STATE_AFTER, "state")
    patched = _replace_once(patched, SYNC_BEFORE, SYNC_AFTER, "scene sync")
    patched = _replace_once(
        patched, DISPOSER_INIT_BEFORE, DISPOSER_INIT_AFTER, "disposer init"
    )
    patched = _replace_once(
        patched, DISPOSER_RENDER_BEFORE, DISPOSER_RENDER_AFTER, "disposer render"
    )
    patched = _replace_once(patched, CLEANUP_BEFORE, CLEANUP_AFTER, "cleanup")
    patched = _replace_once(patched, EXPORT_BEFORE, EXPORT_AFTER, "export")

    asset_hash = hashlib.sha256(patched.encode("utf-8")).hexdigest()[:20]
    asset_name = f"scidesktop-ipyniivue.{asset_hash}.js"
    static_dir.mkdir(parents=True, exist_ok=True)
    (static_dir / asset_name).write_text(patched, encoding="utf-8")
    widget_path.write_text(_bootstrap_source(asset_name), encoding="utf-8")
    return True


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: patch_ipyniivue.py <ipyniivue_pkg_dir> <static_dir>", file=sys.stderr)
        return 2
    try:
        changed = patch_ipyniivue(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError) as exc:
        print(f"ERROR: failed to patch ipyniivue: {exc}", file=sys.stderr)
        return 1
    state = "applied" if changed else "already present"
    print(f"ipyniivue shared-bundle workaround {state}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
