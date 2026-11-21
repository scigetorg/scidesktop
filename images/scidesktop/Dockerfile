# syntax=docker/dockerfile:1
# scidesktop: JupyterLab, an IceWM desktop streamed by Selkies, Apptainer, Lmod
# and sciget on the OS layer. Built with `docker buildx bake`; every component is a
# named context (see docker-bake.hcl and docs/components.md). Domain images in
# images/ build FROM this one (docs/images.md).
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

LABEL maintainer="Sciget project <sciget.org>" \
      org.scidesktop.status="experimental" \
      org.scidesktop.desktop_adapter="selkies" \
      org.scidesktop.manifest="/opt/scidesktop/manifest.d"

# Environment is image configuration, not files, so it cannot come from a
# component. Owners: CONDA_DIR, MAMBA_ROOT_PREFIX, PATH (jupyter-env); DISPLAY
# (selkies); XDG_DATA_DIRS (sciget); JUPYTER_* (jupyter-env).
ENV CONDA_DIR=/opt/conda \
    MAMBA_ROOT_PREFIX=/opt/conda \
    PATH=/opt/conda/bin:${PATH} \
    JUPYTER_PORT=8888 \
    JUPYTER_DISABLE_RESOURCE_USAGE=1 \
    DISPLAY=:20 \
    XDG_DATA_DIRS=/opt/sciget:/usr/local/share:/usr/share

EXPOSE 8888
HEALTHCHECK --interval=3s --timeout=1s --start-period=3s --retries=3 \
    CMD ["/etc/jupyter/docker_healthcheck.py"]
ENTRYPOINT ["tini", "-g", "--", "start.sh"]
CMD ["start-notebook.py"]
WORKDIR "/home/${NB_USER}"
USER ${NB_UID}
