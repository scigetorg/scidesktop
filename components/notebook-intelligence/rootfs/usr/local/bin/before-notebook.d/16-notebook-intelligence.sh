# Guard against an unreachable OLLAMA_HOST. notebook_intelligence probes the
# Ollama API synchronously while Jupyter loads its server extensions, and a
# host that silently drops packets (e.g. host.docker.internal without a route
# on Linux) can stall server startup for 60s+. When the configured endpoint is
# not reachable within 1s, repoint this server process at 127.0.0.1.
if [ -n "${OLLAMA_HOST:-}" ]; then
    if ! curl -so /dev/null --connect-timeout 1 --max-time 2 "${OLLAMA_HOST%/}/api/version" 2>/dev/null; then
        echo "[notebook-intelligence] OLLAMA_HOST=${OLLAMA_HOST} is unreachable; using http://127.0.0.1:11434 so extension startup does not stall."
        export OLLAMA_HOST="http://127.0.0.1:11434"
    fi
fi
