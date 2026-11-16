# syntax=docker/dockerfile:1
# docker-stacks' entrypoint and launch scripts, laid out where the runtime
# contract expects them, and the hook directories other components drop into.
# See VENDOR.md.

ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS rootfs
COPY docker-stacks/ /src/
COPY VENDOR.md /src/
RUN set -e; cd /src; r=/rootfs \
    && install -D -m 0755 -t "${r}/usr/local/bin" _docker_stacks_log.sh start.sh \
        run-hooks.sh fix-permissions start-notebook.py start-notebook.sh \
        start-singleuser.py start-singleuser.sh \
    && install -D -m 0755 -t "${r}/etc/jupyter" docker_healthcheck.py \
    && install -D -m 0644 -t "${r}/etc/jupyter" jupyter_server_config.py \
    && install -D -m 0644 -t "${r}/usr/local/share/doc/docker-stacks" LICENSE.md VENDOR.md \
    && install -d -m 0755 "${r}/usr/local/bin/start-notebook.d" "${r}/usr/local/bin/before-notebook.d" \
    && commit="$(sed -n 's/^Commit: \([0-9a-f]*\).*/\1/p' VENDOR.md)" && test -n "${commit}" \
    && install -d -m 0755 "${r}/opt/scidesktop/manifest.d" \
    && printf '{"docker-stacks": "%s"}\n' "${commit}" > "${r}/opt/scidesktop/manifest.d/startup.json"

FROM scratch AS component
COPY --from=rootfs /rootfs/ /

# start.sh reaches its command as the notebook user and as root (dropping to
# the notebook user), and runs hooks in both directories.
FROM os AS test
COPY --from=component / /
ENV CONDA_DIR=/opt/conda
RUN printf '#!/bin/bash\necho hook-ran\n' > /usr/local/bin/before-notebook.d/10-probe \
    && chmod +x /usr/local/bin/before-notebook.d/10-probe \
    && out=$(start.sh id -un 2>&1) && echo "${out}" \
    && echo "${out}" | grep -q hook-ran \
    && echo "${out}" | tail -1 | grep -qx "${NB_USER}" \
    && out=$(runuser -u "${NB_USER}" -- start.sh id -un 2>&1) && echo "${out}" \
    && echo "${out}" | tail -1 | grep -qx "${NB_USER}" \
    && bash -n /usr/local/bin/run-hooks.sh \
    && python3 -c 'import ast,sys; [ast.parse(open(f).read()) for f in sys.argv[1:]]' \
        /usr/local/bin/start-notebook.py /usr/local/bin/start-singleuser.py
