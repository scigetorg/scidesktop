# moleculardesktop

`scidesktop` for molecular imaging research: narrows sciget to the
`molecular-imaging` catalog (`sciget-molecular-imaging` — STIR, AMIDE, Clinica,
ANTs, ITK-SNAP, 3D Slicer, Elastix, Fiji, Convert3D, dcm2niix, BIDS tools, and
workflow utilities), adds [NiiVue](../../docs/viewers.md) (`jupyterlab-niivue`
and `vscode-niivue`) for volumetric PET/SPECT/CT/MRI NIfTI viewing, and ships a
locked Python 3.13 **Molecular Imaging** Jupyter kernel
(`/opt/molecular-imaging-env`) with `nibabel`, `nilearn`, `SimpleITK`,
`pydicom`, `highdicom`, `ipyniivue`, `scikit-image`, `scikit-learn`, and
`statsmodels`.

| Component | What it adds |
| --- | --- |
| `sciget-molecular-imaging` | narrows sciget to the molecular-imaging catalog |
| `vscode-niivue` | NiiVue VS Code extension for NIfTI and medical images |
| `jupyterlab-niivue` | NiiVue JupyterLab viewer (default for NIfTI files) |
| `molecular-imaging-env` | locked Python 3.13 molecular imaging kernel (`/opt/molecular-imaging-env`) |

```sh
docker buildx bake moleculardesktop
./test/image-smoke.sh moleculardesktop
```
