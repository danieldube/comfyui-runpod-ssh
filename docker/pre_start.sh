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
    mkdir -p \
        "${WORKSPACE}/models/checkpoints" \
        "${WORKSPACE}/models/loras" \
        "${WORKSPACE}/models/vae" \
        "${WORKSPACE}/models/controlnet" \
        "${WORKSPACE}/models/text_encoders" \
        "${WORKSPACE}/models/clip_vision" \
        "${WORKSPACE}/models/upscale_models" \
        "${WORKSPACE}/models/embeddings" \
        "${WORKSPACE}/input" \
        "${WORKSPACE}/output" \
        "${WORKSPACE}/user"
}

start_comfyui()
{
    local log_file="${WORKSPACE}/comfyui.log"
    local pid_file="${WORKSPACE}/comfyui.pid"

    log "Python: $(python --version 2>&1)"

    python - <<'PY'
import torch

print("[comfyui-start] PyTorch:", torch.__version__)
print("[comfyui-start] CUDA runtime:", torch.version.cuda)
print("[comfyui-start] CUDA available:", torch.cuda.is_available())

if torch.cuda.is_available():
    print("[comfyui-start] GPU:", torch.cuda.get_device_name(0))
PY

    log "Starting ComfyUI"
    log "Address: 127.0.0.1:${COMFYUI_PORT}"
    log "Log: ${log_file}"

    cd "${COMFYUI_HOME}"

    nohup python main.py \
        --listen 127.0.0.1 \
        --port "${COMFYUI_PORT}" \
        --extra-model-paths-config /etc/comfyui/extra_model_paths.yaml \
        --input-directory "${WORKSPACE}/input" \
        --output-directory "${WORKSPACE}/output" \
        --user-directory "${WORKSPACE}/user" \
        --disable-auto-launch \
        > "${log_file}" 2>&1 &

    local pid=$!

    printf '%s\n' "${pid}" > "${pid_file}"

    sleep 2

    if kill -0 "${pid}" 2>/dev/null; then
        log "ComfyUI started successfully with PID ${pid}"
    else
        log "WARNING: ComfyUI terminated during startup"
        log "Last log lines:"
        tail -n 100 "${log_file}" || true
    fi
}

log "ComfyUI pre-start hook invoked"

prepare_workspace
start_comfyui

# Deliberately always succeed.
#
# RunPod's /start.sh invokes this script under `set -e`.
# ComfyUI failure must therefore not terminate the Pod; SSH should remain
# available so the failure can be debugged.
exit 0