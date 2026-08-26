#!/usr/bin/env bash

set -euo pipefail

COMFYUI_HOME="${COMFYUI_HOME:-/opt/ComfyUI}"
WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"

configure_ssh()
{
    if [[ -z "${PUBLIC_KEY:-}" ]]; then
        echo "ERROR: PUBLIC_KEY is not configured." >&2
        echo "RunPod normally injects this environment variable." >&2
        exit 1
    fi

    install -d -m 0700 /root/.ssh

    printf '%s\n' "${PUBLIC_KEY}" \
        > /root/.ssh/authorized_keys

    chmod 0600 /root/.ssh/authorized_keys

    ssh-keygen -A
    /usr/sbin/sshd -t
    /usr/sbin/sshd
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
    cd "${COMFYUI_HOME}"

    exec python main.py \
        --listen 127.0.0.1 \
        --port "${COMFYUI_PORT}" \
        --extra-model-paths-config /etc/comfyui/extra_model_paths.yaml \
        --input-directory "${WORKSPACE}/input" \
        --output-directory "${WORKSPACE}/output" \
        --user-directory "${WORKSPACE}/user" \
        --disable-auto-launch
}

prepare_workspace
configure_ssh
start_comfyui