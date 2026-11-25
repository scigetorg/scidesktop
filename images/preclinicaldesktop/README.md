# preclinicaldesktop

`scidesktop` for preclinical imaging research: narrows sciget to the
`preclinical` catalog (`sciget-preclinical` — BrkRaw, AIDAmri, RABIES, SAMRI,
AMIDE, ANTs, ITK-SNAP, 3D Slicer, STIR, Elastix, Fiji, Convert3D, dcm2niix,
and workflow tools), adds [NiiVue](../../docs/viewers.md) (`jupyterlab-niivue`
and `vscode-niivue`) for volumetric NIfTI viewing, and ships a locked
Python 3.13 **Preclinical** Jupyter kernel (`/opt/preclinical-env`) with
`nibabel`, `nilearn`, `SimpleITK`, `pydicom`, `brkraw`, `ipyniivue`,
`scikit-image`, `scikit-learn`, `statsmodels`, `tifffile`, `zarr`, `dask`, and
`xarray`.

| Component | What it adds |
| --- | --- |
| `sciget-preclinical` | narrows sciget to the preclinical catalog |
| `vscode-niivue` | NiiVue VS Code extension for NIfTI and medical images |
| `jupyterlab-niivue` | NiiVue JupyterLab viewer (default for NIfTI files) |
| `preclinical-env` | locked Python 3.13 preclinical imaging kernel (`/opt/preclinical-env`) |

```sh
docker buildx bake preclinicaldesktop
./test/image-smoke.sh preclinicaldesktop
```
