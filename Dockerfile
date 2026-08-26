FROM nvidia/cuda:13.0.2-cudnn-runtime-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive

ARG COMFYUI_VERSION=v0.32.0
ARG TORCH_VERSION=2.13.0
ARG TORCHVISION_VERSION=0.28.0

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:${PATH}" \
    COMFYUI_HOME=/opt/ComfyUI

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        ffmpeg \
        git \
        libgl1 \
        libglib2.0-0 \
        openssh-server \
        python3.12 \
        python3.12-venv \
        tini \
    && rm -rf /var/lib/apt/lists/*

RUN python3.12 -m venv "${VIRTUAL_ENV}" \
    && python -m pip install --upgrade \
        pip \
        setuptools \
        wheel

RUN git clone \
        --branch "${COMFYUI_VERSION}" \
        --depth 1 \
        https://github.com/Comfy-Org/ComfyUI.git \
        "${COMFYUI_HOME}"

RUN python -m pip install \
        "torch==${TORCH_VERSION}" \
        "torchvision==${TORCHVISION_VERSION}" \
        --index-url https://download.pytorch.org/whl/cu130

# This container is intentionally image-generation-only.
#
# ComfyUI currently lists torch, torchvision and torchaudio in requirements.txt.
# torch and torchvision are installed explicitly above.
# torchaudio is omitted because it is not required for this image-generation
# use case and has an independent release/version lifecycle.
RUN grep -Ev '^(torch|torchvision|torchaudio)([<>=~!].*)?$' \
        "${COMFYUI_HOME}/requirements.txt" \
        > /tmp/comfyui-requirements.txt \
    && python -m pip install -r /tmp/comfyui-requirements.txt \
    && python -m pip check \
    && rm /tmp/comfyui-requirements.txt

COPY docker/extra_model_paths.yaml /etc/comfyui/extra_model_paths.yaml
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
    && mkdir -p /run/sshd \
    && sed -ri \
        's/^#?PermitRootLogin .*/PermitRootLogin prohibit-password/' \
        /etc/ssh/sshd_config \
    && printf '\nPasswordAuthentication no\nPubkeyAuthentication yes\nPermitEmptyPasswords no\n' \
        >> /etc/ssh/sshd_config \
    && rm -f /etc/ssh/ssh_host_*

WORKDIR ${COMFYUI_HOME}

EXPOSE 22

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]