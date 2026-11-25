# dermdesktop

`scidesktop` for dermatology research: narrows sciget to the `dermatology`
catalog (`sciget-dermatology` — dermoscopy & clinical photography via ISIC CLI,
Colour-Science, Darktable, GIMP, and LabelMe; dermatopathology & WSI via QuPath,
WSIdicomizer, Bioformats2raw, TIAToolbox, InstanSeg, HistoQC, LazySlide,
Slideflow, StarDist, VALIS, nnU-Net v2, Cellpose, CellProfiler, ilastik, Fiji,
TissUUmaps, Icy, JIPipe, and OMERO; 3D total-body photography & morphometry via
MeshLab, CloudCompare, COLMAP, Open3D, 3D Slicer, SlicerSALT, and Blender;
non-invasive optical & volumetric imaging via napari, HyperSpy, Spectral,
PhasorPy, ITK-SNAP, Skan, TeraStitcher, VesselVio, and VesSynth; DICOM/PHI
curation via DICOM Validator, DICOM tools, MEDE, DataLad, Globus, OpenRefine,
and XNAT; plus registration and statistics via ANTs, Convert3D, Elastix,
NiftyReg, Panoptica, RStudio, Jamovi, IRkernel, and LibreOffice), adds
[Neuroglancer](../../docs/viewers.md) (`jupyterlab-neuroglancer`) for WebGL2
multi-scale OME-Zarr whole-slide viewing, and ships a locked Python 3.13
**Dermatology** Jupyter kernel (`/opt/dermatology-env`) with `scikit-image`,
`tifffile`, `imagecodecs`, `zarr`, `ome-zarr`, `bioio`, `openslide`, `pydicom`,
`colour-science`, `trimesh`, `scikit-learn`, `statsmodels`, `dask`, and
`xarray`.

| Component | What it adds |
| --- | --- |
| `sciget-dermatology` | narrows sciget to the dermatology catalog |
| `jupyterlab-neuroglancer` | Neuroglancer WebGL2 viewer for OME-Zarr whole-slide images |
| `dermatology-env` | locked Python 3.13 dermatology kernel (`/opt/dermatology-env`) |

```sh
docker buildx bake dermdesktop
./test/image-smoke.sh dermdesktop
```
