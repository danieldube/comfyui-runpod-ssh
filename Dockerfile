FROM runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404

ARG COMFYUI_VERSION=v0.32.0

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    COMFYUI_HOME=/opt/ComfyUI

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        ffmpeg \
        libgl1 \
        libglib2.0-0 \
        curl \
    && rm -rf /var/lib/apt/lists/*

RUN git clone \
        --branch "${COMFYUI_VERSION}" \
        --depth 1 \
        https://github.com/Comfy-Org/ComfyUI.git \
        "${COMFYUI_HOME}"

# Keep the PyTorch installation supplied by RunPod.
RUN grep -Ev '^(torch|torchvision|torchaudio)([<>=~!].*)?$' \
        "${COMFYUI_HOME}/requirements.txt" \
        > /tmp/comfyui-requirements.txt \
    && python -m pip install \
        --no-cache-dir \
        -r /tmp/comfyui-requirements.txt \
    && python -m pip check \
    && rm /tmp/comfyui-requirements.txt

COPY docker/extra_model_paths.yaml \
    /etc/comfyui/extra_model_paths.yaml

COPY docker/pre_start.sh \
    /pre_start.sh

RUN chmod 0755 /pre_start.sh

WORKDIR ${COMFYUI_HOME}