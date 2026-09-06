# RunPod ComfyUI Container

Reproducible Docker image for running [ComfyUI](https://github.com/Comfy-Org/ComfyUI) on a GPU-enabled RunPod instance.

The container is designed for private access through SSH port forwarding.

ComfyUI listens only on the container loopback interface:

```text
127.0.0.1:8188
```

Port `8188` must **not** be exposed by the RunPod template.

Only SSH is exposed externally:

```text
RunPod TCP port → container :22
```

The resulting connection path is:

```text
Local browser/application
        |
        | http://127.0.0.1:8188
        v
Local SSH client
        |
        | encrypted SSH port forward
        v
RunPod container :22
        |
        v
127.0.0.1:8188
        |
        v
ComfyUI
```

## Features

* Ubuntu 24.04
* NVIDIA CUDA runtime
* Python
* CUDA-enabled PyTorch
* pinned ComfyUI version
* OpenSSH server
* private ComfyUI interface
* persistent ComfyUI data under `/workspace/comfyui`
* automatic container builds with GitHub Actions
* container images published to GitHub Container Registry

## Repository layout

```text
.
├── .github/
│   └── workflows/
│       └── container.yml
├── docs/
│   └── storage-layout.md
├── docker/
│   ├── pre_start.sh
│   └── extra_model_paths.yaml
├── .dockerignore
├── Dockerfile
└── README.md
```

## Runtime layout

The Docker image contains software and dependencies only.

Large and mutable data is stored separately under `/workspace/comfyui`:

```text
/workspace/
└── comfyui/
    ├── models/
    │   ├── checkpoints/
    │   ├── loras/
    │   ├── vae/
    │   ├── controlnet/
    │   ├── text_encoders/
    │   ├── clip_vision/
    │   ├── diffusion_models/
    │   ├── embeddings/
    │   └── upscale_models/
    ├── input/
    ├── output/
    ├── runtime/
    │   ├── comfyui.log
    │   └── comfyui.pid
    └── user/
        └── comfyui.db
```

On RunPod, `/workspace` should be backed by persistent storage.

Models are deliberately not included in the Docker image.

The [storage-layout decision](docs/storage-layout.md) explains why shared data
and ComfyUI user state are separated and how to move an existing volume.

## Build locally

Build the image:

```bash
docker build \
    --tag runpod-comfyui:dev \
    .
```

Verify the bundled PyTorch installation:

```bash
docker run \
    --rm \
    --entrypoint python \
    runpod-comfyui:dev \
    -c 'import torch; print("PyTorch:", torch.__version__); print("CUDA:", torch.version.cuda)'
```

A CUDA-enabled PyTorch version should be reported.

## Test with an NVIDIA GPU

The NVIDIA Container Toolkit must be installed on the Docker host.

Create a temporary workspace:

```bash
mkdir -p workspace
```

Run the container:

```bash
docker run \
    --rm \
    --gpus all \
    --name comfyui-test \
    --env PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)" \
    --publish 127.0.0.1:2222:22 \
    --volume "$(pwd)/workspace:/workspace" \
    runpod-comfyui:dev
```

Only the SSH port is published.

In particular, do **not** add:

```text
-p 8188:8188
```

ComfyUI is intentionally unavailable directly from outside the container.

## Connect through SSH

Create the port forward:

```bash
ssh \
    -N \
    -p 2222 \
    -i ~/.ssh/id_ed25519 \
    -L 8188:127.0.0.1:8188 \
    root@127.0.0.1
```

Open:

```text
http://127.0.0.1:8188
```

The browser connects to local port `8188`. SSH forwards the connection to port `8188` on the loopback interface inside the container.

## Verify network isolation

Inside the running container:

```bash
docker exec comfyui-test ss -lntp
```

The relevant listeners should resemble:

```text
0.0.0.0:22
127.0.0.1:8188
```

ComfyUI must **not** listen on:

```text
0.0.0.0:8188
```

or:

```text
:::8188
```

The container entrypoint explicitly starts ComfyUI with:

```bash
--listen 127.0.0.1
```

Do not change this to `0.0.0.0` when the container is intended for SSH-only access.

## GPU verification

After connecting through SSH:

```bash
nvidia-smi
```

Verify PyTorch:

```bash
python - <<'PY'
import torch

print("PyTorch:", torch.__version__)
print("CUDA runtime:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())

if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))
    properties = torch.cuda.get_device_properties(0)
    print("VRAM:", round(properties.total_memory / 1024**3, 1), "GiB")
PY
```

Expected:

```text
CUDA available: True
GPU: NVIDIA ...
```

## Models

Put checkpoints in:

```text
/workspace/comfyui/models/checkpoints/
```

For example:

```text
/workspace/comfyui/models/checkpoints/RealVisXL_V5.0_fp16.safetensors
```

LoRAs go into:

```text
/workspace/comfyui/models/loras/
```

ControlNet models go into:

```text
/workspace/comfyui/models/controlnet/
```

The supplied `extra_model_paths.yaml` makes these persistent directories available to ComfyUI.

## GitHub Container Registry

GitHub Actions builds the image automatically.

### Push to `main`

A push to `main` publishes images such as:

```text
ghcr.io/<github-user>/runpod-comfyui:latest
ghcr.io/<github-user>/runpod-comfyui:main
ghcr.io/<github-user>/runpod-comfyui:sha-xxxxxxxx
```

### Create a release

Create a Git tag:

```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

The workflow publishes:

```text
ghcr.io/<github-user>/runpod-comfyui:0.1.0
ghcr.io/<github-user>/runpod-comfyui:0.1
```

Use the complete release version for deployment:

```text
ghcr.io/<github-user>/runpod-comfyui:0.1.0
```

Avoid deploying `latest` when reproducibility matters.

### Package visibility

GitHub Container Registry packages may initially be private even when the GitHub repository itself is public.

After the first image has been published:

```text
GitHub
→ Profile
→ Packages
→ runpod-comfyui
→ Package settings
→ Change visibility
→ Public
```

Verify anonymous access:

```bash
docker pull ghcr.io/<github-user>/runpod-comfyui:0.1.0
```

## RunPod configuration

Create a custom RunPod template using:

```text
Container image:
ghcr.io/<github-user>/runpod-comfyui:0.1.0

Container disk:
20–30 GB

Persistent volume:
30 GB or larger

Volume mount path:
/workspace

Exposed TCP ports:
22

Exposed HTTP ports:
none

Entrypoint override:
none

Command override:
none
```

RunPod's inherited startup script starts SSH and invokes this image's
`/pre_start.sh`, which starts ComfyUI.

### SSH key

Configure an SSH public key in your RunPod account before starting the pod.

The container expects the RunPod-provided `PUBLIC_KEY` environment variable and writes it to:

```text
/root/.ssh/authorized_keys
```

Password authentication is disabled.

## Connect to RunPod

In the RunPod UI, select:

```text
Pod
→ Connect
→ SSH over exposed TCP
```

RunPod displays a command similar to:

```bash
ssh root@203.0.113.10 \
    -p 25341 \
    -i ~/.ssh/runpod_comfyui
```

Test the connection first:

```bash
ssh root@203.0.113.10 \
    -p 25341 \
    -i ~/.ssh/runpod_comfyui
```

Then establish the ComfyUI tunnel:

```bash
ssh \
    -N \
    -L 8188:127.0.0.1:8188 \
    root@203.0.113.10 \
    -p 25341 \
    -i ~/.ssh/runpod_comfyui
```

Open:

```text
http://127.0.0.1:8188
```

## SSH client configuration

For repeated use, add an entry to `~/.ssh/config`:

```sshconfig
Host runpod-comfyui
    HostName 203.0.113.10
    Port 25341
    User root
    IdentityFile ~/.ssh/runpod_comfyui
    IdentitiesOnly yes

    LocalForward 8188 127.0.0.1:8188
    ExitOnForwardFailure yes

    ServerAliveInterval 30
    ServerAliveCountMax 4
```

The tunnel can then be established with:

```bash
ssh -N runpod-comfyui
```

The mapped RunPod SSH port or IP address may change when a pod is recreated. Update `~/.ssh/config` accordingly.

## Updating the container

Change the Docker configuration and commit it:

```bash
git add -- \
    Dockerfile \
    docker/pre_start.sh \
    docker/extra_model_paths.yaml \
    docs/storage-layout.md

git commit -m "Update ComfyUI runtime"
git push
```

GitHub Actions builds a new image.

After validation, create another release:

```bash
git tag -a v0.2.0 -m "Release v0.2.0"
git push origin v0.2.0
```

Then change the RunPod template from:

```text
ghcr.io/<github-user>/runpod-comfyui:0.1.0
```

to:

```text
ghcr.io/<github-user>/runpod-comfyui:0.2.0
```

The persistent `/workspace` volume does not need to change.

## Security properties

The intended deployment has the following properties:

* only the SSH service is reachable externally;
* ComfyUI binds exclusively to `127.0.0.1`;
* RunPod does not publish port `8188`;
* SSH password authentication is disabled;
* authentication uses an injected SSH public key;
* model files remain outside the immutable container image;
* ComfyUI access requires an authenticated SSH connection;
* local applications can use `http://127.0.0.1:8188` without being aware that inference runs remotely.

Do not expose port `8188` through the RunPod template unless a separate authentication and network-security layer is intentionally added.

## License

This repository is licensed under the [MIT License](LICENSE).

The licenses and usage conditions of ComfyUI, PyTorch, CUDA, and individual
image-generation models remain independent of this repository and must be
reviewed separately.
