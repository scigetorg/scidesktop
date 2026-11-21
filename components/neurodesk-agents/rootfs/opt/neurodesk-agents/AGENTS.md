# Working in neurodesktop

This session is a neurodesktop container: JupyterLab, a Linux desktop and the
Neurodesk neuroimaging tools. You run as the notebook user without root. The
home folder persists between sessions; `/tmp` does not.

## Finding and running neuroimaging tools

The tools (FSL, FreeSurfer, ANTs, MRtrix3, AFNI, dcm2niix and many more) are
not installed in this image. Each one is a container, exposed as an Lmod
module. Do not install them with pip, conda or apt.

- `module` is defined in login and interactive shells only. Run tool commands
  through a login shell: `bash -lc 'module load fsl/6.0.7.16 && bet in.nii.gz out.nii.gz'`.
- Find a tool with `module spider <name>` and list everything with
  `module -t avail`. Load an exact `tool/version`, never a bare name, so the
  analysis can be repeated. Record the versions you used.
- On an arm64 machine (`arch` prints `aarch64`) use the modules whose
  name ends in `_arm64`, for example `niimath_arm64/1.0.20261016`. A module
  without that ending holds an amd64 container and does not run there. Only
  some tools have an arm64 container.
- `module -t avail` lists Neurodesk modules only when `/cvmfs/neurodesk.ardc.edu.au`
  is mounted. When it is not, `sciget find <name>` searches the same catalog
  and `sciget install <tool/version>` downloads the container and writes its
  module. A new login shell then finds it.
- A loaded tool runs inside its container through Apptainer. It sees the home
  folder, `/tmp`, the working directory and the folders in
  `APPTAINER_BINDPATH`, not the rest of this file system. Keep inputs and
  outputs under the home folder unless told otherwise.
- The first run of a tool reads its container over the network and can take
  minutes. That is not a hang.

## Data

- `datalad` and `git-annex` are installed. Use `datalad clone` and
  `datalad get <path>` for OpenNeuro and other DataLad datasets, and get only
  the files the task needs.
- Treat input data as read-only. Write results to a new folder.
- Never put participant data, tokens or passwords in a prompt, a commit or a
  log.

## Working style

- Write each analysis step as a script in the project folder and run the
  script, so the work can be repeated. Do not leave results that only exist
  because of commands typed into a shell.
- Check an image before and after a step (`fslinfo`, `mrinfo`, or `nibabel` in
  a Python environment you create) instead of assuming a step worked.
- Python packages for an analysis go into an environment in the home folder
  (`mamba create -p ~/envs/<name> ...`), not into `/opt/conda`.
- A single-node Slurm queue (`sbatch`, `srun`, `squeue`, `sinfo`) runs in every
  session for batch jobs and parallel workflows. Long interactive work belongs
  in `tmux` or a script the user can restart.
