#!/usr/bin/env bash

set -u

COMFYUI_HOME="${COMFYUI_HOME:-/opt/ComfyUI}"
WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"

log()
{
    printf '[comfyui-start] %s\n' "$*"
}

prepare_workspace()
{
    log "Preparing persistent workspace"

    mkdir -p \
        "${WORKSPACE}/models/checkpoints" \
        "${WORKSPACE}/models/loras" \
        "${WORKSPACE}/models/vae" \
        "${WORKSPACE}/models/controlnet" \
        "${WORKSPACE}/models/t2i_adapter" \
        "${WORKSPACE}/models/text_encoders" \
        "${WORKSPACE}/models/clip" \
        "${WORKSPACE}/models/clip_vision" \
        "${WORKSPACE}/models/diffusion_models" \
        "${WORKSPACE}/models/unet" \
        "${WORKSPACE}/models/upscale_models" \
        "${WORKSPACE}/models/embeddings" \
        "${WORKSPACE}/input" \
        "${WORKSPACE}/output" \
        "${WORKSPACE}/user" \
        "${WORKSPACE}/workflows"

    log "Workspace ready"
}

print_runtime_info()
{
    log "Python: $(python --version 2>&1)"

    python - <<'PY'
import torch

print("[comfyui-start] PyTorch:", torch.__version__)
print("[comfyui-start] CUDA runtime:", torch.version.cuda)
print("[comfyui-start] CUDA available:", torch.cuda.is_available())

if torch.cuda.is_available():
    print("[comfyui-start] GPU:", torch.cuda.get_device_name(0))
    print(
        "[comfyui-start] Compute capability:",
        torch.cuda.get_device_capability(0),
    )
PY
}

start_comfyui()
{
    local log_file="${WORKSPACE}/comfyui.log"
    local pid_file="${WORKSPACE}/comfyui.pid"
    local database_file="${WORKSPACE}/user/comfyui.db"

    if [[ -f "${pid_file}" ]]; then
        local existing_pid
        existing_pid="$(cat "${pid_file}" 2>/dev/null || true)"

        if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
            log "ComfyUI is already running with PID ${existing_pid}"
            return 0
        fi

        log "Removing stale PID file"
        rm -f "${pid_file}"
    fi

    log "Starting ComfyUI"
    log "Address: 127.0.0.1:${COMFYUI_PORT}"
    log "Database: ${database_file}"
    log "Log: ${log_file}"

    cd "${COMFYUI_HOME}" || {
        log "ERROR: Cannot enter ${COMFYUI_HOME}"
        return 1
    }

    nohup python main.py \
        --listen 127.0.0.1 \
        --port "${COMFYUI_PORT}" \
        --extra-model-paths-config /etc/comfyui/extra_model_paths.yaml \
        --input-directory "${WORKSPACE}/input" \
        --output-directory "${WORKSPACE}/output" \
        --user-directory "${WORKSPACE}/user" \
        --database-url "sqlite:///${database_file}" \
        --disable-auto-launch \
        > "${log_file}" 2>&1 &

    local pid=$!

    printf '%s\n' "${pid}" > "${pid_file}"

    sleep 3

    if kill -0 "${pid}" 2>/dev/null; then
        log "ComfyUI started successfully with PID ${pid}"
        return 0
    fi

    log "WARNING: ComfyUI terminated during startup"
    log "Last log lines:"

    tail -n 100 "${log_file}" 2>/dev/null || true

    rm -f "${pid_file}"

    return 1
}

main()
{
    log "ComfyUI pre-start hook invoked"

    if ! prepare_workspace; then
        log "ERROR: Failed to prepare workspace"
        return 0
    fi

    print_runtime_info || log "WARNING: Failed to query PyTorch runtime"

    if ! start_comfyui; then
        log "WARNING: ComfyUI failed to start"
        log "Pod startup will continue so SSH remains available for debugging"
    fi

    log "ComfyUI pre-start hook finished"

    return 0
}

main

# Intentionally always succeed.
#
# RunPod executes /pre_start.sh from its own /start.sh. A ComfyUI failure
# must not terminate the Pod, otherwise SSH would become unavailable and
# prevent runtime debugging.
exit 0