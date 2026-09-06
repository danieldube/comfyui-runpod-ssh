#!/usr/bin/env bash

set -u

COMFYUI_HOME="${COMFYUI_HOME:-/opt/ComfyUI}"
COMFYUI_WORKSPACE="${COMFYUI_WORKSPACE:-/workspace/comfyui}"
COMFYUI_USER_DIR="${COMFYUI_WORKSPACE}/user"
COMFYUI_RUNTIME_DIR="${COMFYUI_WORKSPACE}/runtime"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"

log()
{
    printf '[comfyui-start] %s\n' "$*"
}

prepare_comfyui_workspace()
{
    log "Preparing ComfyUI workspace at ${COMFYUI_WORKSPACE}"

    mkdir -p \
        "${COMFYUI_WORKSPACE}/models/checkpoints" \
        "${COMFYUI_WORKSPACE}/models/loras" \
        "${COMFYUI_WORKSPACE}/models/vae" \
        "${COMFYUI_WORKSPACE}/models/controlnet" \
        "${COMFYUI_WORKSPACE}/models/t2i_adapter" \
        "${COMFYUI_WORKSPACE}/models/text_encoders" \
        "${COMFYUI_WORKSPACE}/models/clip" \
        "${COMFYUI_WORKSPACE}/models/clip_vision" \
        "${COMFYUI_WORKSPACE}/models/diffusion_models" \
        "${COMFYUI_WORKSPACE}/models/unet" \
        "${COMFYUI_WORKSPACE}/models/upscale_models" \
        "${COMFYUI_WORKSPACE}/models/embeddings" \
        "${COMFYUI_WORKSPACE}/input" \
        "${COMFYUI_WORKSPACE}/output" \
        "${COMFYUI_USER_DIR}" \
        "${COMFYUI_RUNTIME_DIR}"

    log "ComfyUI workspace ready"
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
    local log_file="${COMFYUI_RUNTIME_DIR}/comfyui.log"
    local pid_file="${COMFYUI_RUNTIME_DIR}/comfyui.pid"
    local database_file="${COMFYUI_USER_DIR}/comfyui.db"

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
        --input-directory "${COMFYUI_WORKSPACE}/input" \
        --output-directory "${COMFYUI_WORKSPACE}/output" \
        --user-directory "${COMFYUI_USER_DIR}" \
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

    if ! prepare_comfyui_workspace; then
        log "ERROR: Failed to prepare ComfyUI workspace"
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
