# dermdesktop

`scidesktop` for dermatology research: narrows sciget to the `dermatology`
catalog (`sciget-dermatology` — QuPath, napari, TissUUmaps, Fiji, Icy, ilastik,
Cellpose, CellProfiler, JIPipe, OMERO, 3D Slicer, SlicerSALT, Blender, GIMP,
DICOM tools, medical image de-identification, XNAT, ANTs, Elastix, Panoptica, RStudio, Jamovi, and data
management/workflow tools), adds [Neuroglancer](../../docs/viewers.md)
(`jupyterlab-neuroglancer`) for WebGL2 multi-scale OME-Zarr whole-slide
viewing, and ships a locked Python 3.13 **Dermatology** Jupyter kernel
(`/opt/dermatology-env`) with `scikit-image`, `tifffile`, `imagecodecs`,
`zarr`, `ome-zarr`, `bioio`, `openslide`, `pydicom`, `colour-science`,
`trimesh`, `scikit-learn`, `statsmodels`, `dask`, and `xarray`.

| Component | What it adds |
| --- | --- |
| `sciget-dermatology` | narrows sciget to the dermatology catalog |
| `jupyterlab-neuroglancer` | Neuroglancer WebGL2 viewer for OME-Zarr whole-slide images |
| `dermatology-env` | locked Python 3.13 dermatology kernel (`/opt/dermatology-env`) |

```sh
docker buildx bake dermdesktop
./test/image-smoke.sh dermdesktop
```
