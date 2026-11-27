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
RUN set -e; chmod -R a+rX,go-w /rootfs; cd /src; r=/rootfs \
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
    && start.sh grep -qx 'NoNewPrivs:[[:space:]]*1' /proc/self/status \
    && start.sh grep -qx 'CapBnd:[[:space:]]*0000000000000000' /proc/self/status \
    && start.sh grep -qx 'CapAmb:[[:space:]]*0000000000000000' /proc/self/status \
    && start.sh grep -qx 'CapInh:[[:space:]]*0000000000000000' /proc/self/status \
    && out=$(runuser -u "${NB_USER}" -- start.sh id -un 2>&1) && echo "${out}" \
    && echo "${out}" | grep -q hook-ran \
    && echo "${out}" | tail -1 | grep -qx "${NB_USER}" \
    && runuser -u "${NB_USER}" -- start.sh grep -qx 'NoNewPrivs:[[:space:]]*1' /proc/self/status \
    && runuser -u "${NB_USER}" -- env _START_SH_EXECUTED=1 start.sh grep -qx 'NoNewPrivs:[[:space:]]*1' /proc/self/status \
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
    # /data symlink hook: links /data into ~/data when /data exists, without clobbering existing targets.
    && mkdir -p /data && start.sh true >/dev/null 2>&1 \
    && [ "$(readlink "/home/${NB_USER}/data")" = /data ] \
    && rm -f "/home/${NB_USER}/data" && rmdir /data \
    # Root-started session with renamed NB_USER resolves MPLCONFIGDIR to the renamed home.
    && useradd -m -u 22222 -g "${NB_GID}" alice \
    && out=$(env -u MPLCONFIGDIR HOME=/home/jovyan NB_USER=alice bash -ec \
        '. /usr/local/bin/before-notebook.d/05-resource-limits.sh >/dev/null; echo "$MPLCONFIGDIR"') \
    && [ "${out}" = "/home/alice/.config/matplotlib-mpldir" ] \
    && userdel -r alice \
    && [ "$(/opt/scidesktop/run-as-user id -un)" = "${NB_USER}" ] \
    && [ "$(runuser -u "${NB_USER}" -- /opt/scidesktop/run-as-user id -un)" = "${NB_USER}" ] \
    && test -r /opt/scidesktop/stop_supervisor.py \
    # Interactive shells get `ll` and `<flavour>-<version>:\w$ ` with /home/jovyan/.bashrc and with an empty HOME.
    && out=$(runuser -u "${NB_USER}" -- env SCIDESKTOP_FLAVOUR=scidesktop SCIDESKTOP_VERSION=2026-11-27 TERM=dumb \
        bash -lic 'type ll; printf "PS1=%s\n" "$PS1"' 2>/dev/null) \
    && grep -q "ll is aliased to" <<<"${out}" \
    && grep -qxF 'PS1=scidesktop-2026-11-27:\w\$ ' <<<"${out}" \
    && empty_home=$(mktemp -d) && chown "${NB_UID}:${NB_GID}" "${empty_home}" \
    && out=$(runuser -u "${NB_USER}" -- env HOME="${empty_home}" SCIDESKTOP_FLAVOUR=neurodesktop SCIDESKTOP_VERSION=2026-11-27 TERM=dumb \
        bash -lic 'type ll; printf "PS1=%s\n" "$PS1"' 2>/dev/null) \
    && rm -rf "${empty_home}" \
    && grep -q "ll is aliased to" <<<"${out}" \
    && grep -qxF 'PS1=neurodesktop-2026-11-27:\w\$ ' <<<"${out}" \
    # The OS layer has no Python; the smoke test parses these with Jupyter's.
    && test -x /usr/local/bin/start-notebook.py && test -x /usr/local/bin/start-singleuser.py
