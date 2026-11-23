# syntax=docker/dockerfile:1
# scidesktop: JupyterLab, an IceWM desktop streamed by Selkies, Apptainer, Lmod,
# sciget (all domain catalogs), Slurm, coding agents,
# ACP adapters, T3 Code and T3 Connect on the OS layer. Built with
# `docker buildx bake`; every component is a named context (see docker-bake.hcl
# and docs/components.md). Domain images in images/ build FROM this one
# (docs/images.md).
#
# This file only assembles. Each component ships its own files, hooks, symlinks and
# manifest entry; what stays here is image metadata that only a Dockerfile can
# set. test/contract.py enforces that.
#
# Component layers use COPY --link, so they do not depend on the layers beneath
# them: a change to one component, or to the OS, leaves the other components' layers
# untouched on nodes that already have them. Components are ordered from least to
# most frequently changed.

FROM os

COPY --link --from=startup / /
COPY --link --from=lmod / /
COPY --link --from=apptainer / /
COPY --link --from=selkies / /
COPY --link --from=jupyter-env / /
COPY --link --from=sciget / /
COPY --link --from=slurm / /
COPY --link --from=virtualgl / /
COPY --link --from=datalad / /
COPY --link --from=code-server / /
COPY --link --from=vscode-core / /
COPY --link --from=scigethelpers-cli / /
COPY --link --from=jupyterlab-slurm / /
COPY --link --from=workflow-engines / /
COPY --link --from=sciget-all / /
COPY --link --from=eessi-cvmfs / /
COPY --link --from=coding-agents / /
COPY --link --from=acp-adapters / /
COPY --link --from=antigravity-acp / /
COPY --link --from=t3-code / /
COPY --link --from=t3-connect / /

LABEL maintainer="Sciget project <sciget.org>" \
      org.opencontainers.image.title="scidesktop" \
      org.opencontainers.image.description="scidesktop: multi-arch scientific desktop with JupyterLab, Selkies, Apptainer, Lmod, Slurm, VS Code, workflow engines, coding agents and all sciget domain catalogs" \
      org.opencontainers.image.url="https://github.com/scigetorg/scidesktop" \
      org.opencontainers.image.source="https://github.com/scigetorg/scidesktop" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Sciget project" \
      org.scidesktop.desktop_adapter="selkies" \
      org.scidesktop.manifest="/opt/scidesktop/manifest.d"

# Environment is image configuration, not files, so it cannot come from a
# component. Owners: CONDA_DIR, MAMBA_ROOT_PREFIX, PATH (jupyter-env); DISPLAY
# (selkies); XDG_DATA_DIRS (sciget); JUPYTER_* (jupyter-env);
# NVIDIA_DRIVER_CAPABILITIES (virtualgl / GPU runtimes).
ENV CONDA_DIR=/opt/conda \
    MAMBA_ROOT_PREFIX=/opt/conda \
    PATH=/opt/conda/bin:${PATH} \
    JUPYTER_PORT=8888 \
    DISPLAY=:20 \
    XDG_DATA_DIRS=/opt/sciget:/usr/local/share:/usr/share \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics,display

EXPOSE 8888
HEALTHCHECK --interval=3s --timeout=1s --start-period=3s --retries=3 \
    CMD ["/etc/jupyter/docker_healthcheck.py"]
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/start.sh"]
CMD ["start-notebook.py"]
WORKDIR "/home/${NB_USER}"
USER ${NB_UID}
