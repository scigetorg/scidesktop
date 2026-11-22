# Neurodesk-specific defaults for neuroimaging shells and sessions:
# FreeSurfer subjects directory and nf-neuro Nextflow modules location.
export APPTAINERENV_SUBJECTS_DIR="${APPTAINERENV_SUBJECTS_DIR:-${HOME}/freesurfer-subjects-dir}"
export NF_NEURO_MODULES_DIR="${NF_NEURO_MODULES_DIR:-/opt/nf-neuro/modules}"
