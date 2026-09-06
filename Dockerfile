FROM runpod/pytorch:1.0.3-cu1300-torch291-ubuntu2404

ARG COMFYUI_VERSION=v0.32.0

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    COMFYUI_HOME=/opt/ComfyUI \
    COMFYUI_WORKSPACE=/workspace/comfyui

# ---------------------------------------------------------------------------
# System dependencies
# ---------------------------------------------------------------------------

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        ffmpeg \
        git \
        libgl1 \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# ComfyUI
# ---------------------------------------------------------------------------

RUN git clone \
        --branch "${COMFYUI_VERSION}" \
        --depth 1 \
        https://github.com/Comfy-Org/ComfyUI.git \
        "${COMFYUI_HOME}"

# ---------------------------------------------------------------------------
# Python dependencies
#
# The RunPod base image already supplies:
#
#   PyTorch 2.9.1
#   CUDA 13.0
#   torchvision
#   torchaudio
#
# ComfyUI does not constrain the versions of these packages, so pip should
# keep the versions supplied by the base image.
# ---------------------------------------------------------------------------

RUN python -m pip install \
        --no-cache-dir \
        -r "${COMFYUI_HOME}/requirements.txt"

# ---------------------------------------------------------------------------
# Build-time validation
#
# Fail the image build if a future RunPod base image or dependency update
# accidentally leaves us with a non-CUDA or pre-CUDA-13 PyTorch installation.
# ---------------------------------------------------------------------------

RUN python - <<'PY'
import torch

print("PyTorch:", torch.__version__)
print("PyTorch CUDA runtime:", torch.version.cuda)

if torch.version.cuda is None:
    raise RuntimeError("PyTorch was installed without CUDA support")

cuda_version = tuple(
    int(component)
    for component in torch.version.cuda.split(".")[:2]
)

if cuda_version < (13, 0):
    raise RuntimeError(
        f"CUDA >= 13.0 required, found {torch.version.cuda}"
    )

print("CUDA >= 13.0 validation successful")
PY

# Verify that the ComfyUI Python package itself can be imported.
RUN cd "${COMFYUI_HOME}" \
    && python -c "import comfy; print('ComfyUI import successful')"

# ---------------------------------------------------------------------------
# ComfyUI configuration
#
# Models and mutable data are deliberately kept outside the image in
# /workspace/comfyui, which should be backed by persistent RunPod storage.
# ---------------------------------------------------------------------------

COPY docker/extra_model_paths.yaml \
    /etc/comfyui/extra_model_paths.yaml

# ---------------------------------------------------------------------------
# RunPod startup hook
#
# runpod/pytorch:1.0.3 uses /start.sh as its normal CMD. That script invokes
# /pre_start.sh before starting SSH and subsequently remains alive.
#
# pre_start.sh launches ComfyUI in the background.
#
# Do NOT add our own ENTRYPOINT or CMD here; inherit RunPod's startup logic.
# ---------------------------------------------------------------------------

COPY docker/pre_start.sh \
    /pre_start.sh

RUN chmod 0755 /pre_start.sh

WORKDIR ${COMFYUI_HOME}
