# Lmod loads its site package from here. The package records each Neurodesk
# module a user loads (in ~/.local/state/neurodesk), which `neurodesk cite`
# turns into citations. A deployment's own LMOD_PACKAGE_PATH is kept.
# Login shells read this file; other interactive shells and the Jupyter
# server get it from /etc/bash.bashrc.d and before-notebook.d.
if [ -z "${LMOD_PACKAGE_PATH:-}" ]; then
    export LMOD_PACKAGE_PATH=/opt/neurodesk-cli/lmod
fi
