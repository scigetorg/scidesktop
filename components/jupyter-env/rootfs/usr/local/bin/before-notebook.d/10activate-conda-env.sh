#!/bin/bash
# Replaces the docker-stacks hook of the same name, which runs
# `eval "$(conda shell.bash hook)"` -- that spawns python and evals its output
# on every container start. The server does not need it: /opt/conda/bin is
# already on PATH and jupyter is invoked by absolute path. Setting the
# variables directly and sourcing activate.d gives the same environment.
#
# Interactive shells are unaffected; ~/.bashrc sets up the conda function.

export CONDA_PREFIX="${CONDA_DIR:-/opt/conda}"
export CONDA_DEFAULT_ENV=base
export CONDA_SHLVL=1
export CONDA_PYTHON_EXE="${CONDA_PREFIX}/bin/python"

# Do not source user-writable conda activate.d scripts while running as root
# (before start.sh drops privileges); non-root startup sources them directly.
if [ "$(/usr/bin/id -u)" -ne 0 ]; then
    for _activate_script in "${CONDA_PREFIX}/etc/conda/activate.d/"*.sh; do
        [ -r "${_activate_script}" ] && . "${_activate_script}"
    done
    unset _activate_script
fi
