# syntax=docker/dockerfile:1
# docker-stacks' entrypoint and launch scripts, laid out where the runtime
# contract expects them, the hook directories other components drop into, and
# generic start-up hooks of its own (rootfs/: resource limits, home defaults).
# See VENDOR.md.

ARG UBUNTU_IMAGE

FROM ${UBUNTU_IMAGE} AS rootfs
COPY docker-stacks/ /src/
COPY VENDOR.md /src/
COPY rootfs/ /rootfs/
RUN set -e; chmod -R go-w /rootfs; cd /src; r=/rootfs \
    && install -D -m 0755 -t "${r}/usr/local/bin" _docker_stacks_log.sh start.sh \
        run-hooks.sh fix-permissions start-notebook.py start-notebook.sh \
        start-singleuser.py start-singleuser.sh \
    && install -D -m 0755 -t "${r}/etc/jupyter" docker_healthcheck.py \
    && install -D -m 0644 -t "${r}/etc/jupyter" jupyter_server_config.py \
    && install -D -m 0644 -t "${r}/usr/local/share/doc/docker-stacks" LICENSE.md VENDOR.md \
    && install -d -m 0755 "${r}/usr/local/bin/start-notebook.d" "${r}/usr/local/bin/before-notebook.d" \
        "${r}/etc/scidesktop/home-defaults" \
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
    # Resource limits from a cgroup: whole CPUs, memory, thread counts.
    && mkdir -p /tmp/cg && echo "150000 100000" > /tmp/cg/cpu.max && echo 2147483648 > /tmp/cg/memory.max \
    && out=$(env -u CPU_LIMIT -u MEM_LIMIT -u OMP_NUM_THREADS SCIDESKTOP_CGROUP_ROOT=/tmp/cg bash -ec \
        '. /usr/local/bin/before-notebook.d/05-resource-limits.sh >/dev/null; echo "$CPU_LIMIT $MEM_LIMIT $OMP_NUM_THREADS"') \
    && [ "${out}" = "2 2147483648 2" ] \
    && echo "max 100000" > /tmp/cg/cpu.max && echo max > /tmp/cg/memory.max \
    && out=$(env -u CPU_LIMIT -u MEM_LIMIT SCIDESKTOP_CGROUP_ROOT=/tmp/cg bash -ec \
        '. /usr/local/bin/before-notebook.d/05-resource-limits.sh; echo "${CPU_LIMIT:-none} ${MEM_LIMIT:-none}"') \
    && [ "${out}" = "none none" ] \
    # Home defaults are copied once and never overwrite the user's files.
    && printf 'default\n' > /etc/scidesktop/home-defaults/.probe \
    && mkdir -p /etc/scidesktop/home-defaults/.config/probe && printf 'nested\n' > /etc/scidesktop/home-defaults/.config/probe/x \
    && start.sh true >/dev/null 2>&1 \
    && [ "$(cat "/home/${NB_USER}/.probe")" = default ] && [ -f "/home/${NB_USER}/.config/probe/x" ] \
    && [ "$(stat -c %U "/home/${NB_USER}/.probe")" = "${NB_USER}" ] \
    && printf 'mine\n' > "/home/${NB_USER}/.probe" && start.sh true >/dev/null 2>&1 \
    && [ "$(cat "/home/${NB_USER}/.probe")" = mine ] \
    && python3 -c 'import ast,sys; [ast.parse(open(f).read()) for f in sys.argv[1:]]' \
        /usr/local/bin/start-notebook.py /usr/local/bin/start-singleuser.py
