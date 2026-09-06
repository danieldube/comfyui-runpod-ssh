# ComfyUI workspace layout

## Decision

All mutable ComfyUI files are stored below `/workspace/comfyui`. The image
sets `COMFYUI_WORKSPACE` to this path and the startup hook creates the
directories before launching ComfyUI.

```text
/workspace/comfyui/
├── models/
├── input/
├── output/
├── user/
└── runtime/
```

`models`, `input`, and `output` use ComfyUI's standard directory names.
`extra_model_paths.yaml` uses this root as its model base path, and the startup
hook passes the input and output directories directly to ComfyUI.

`user` is ComfyUI's `--user-directory`. It holds user-specific settings,
workflows, and the SQLite database.

`runtime` holds the ComfyUI log and PID file. Keeping it under the same root
ensures no ComfyUI-managed files are created directly under `/workspace`.

## Rationale

The former flat layout put unrelated ComfyUI data directly in `/workspace`.
Using a single application root prevents collisions with other tools on the
RunPod volume and makes the mount contents recognizable. A `persistent`
directory does not make a useful distinction: the entire RunPod volume is
persistent, and both `output` and `user` contain user data. The direct layout
is therefore easier to navigate and matches ComfyUI's command-line names.

## Migrating an existing persistent volume

Stop ComfyUI before moving files. For the former flat layout, move each legacy
directory only after checking that its destination does not already contain
data:

```bash
mkdir -p /workspace/comfyui/runtime
mv /workspace/models /workspace/comfyui/models
mv /workspace/input /workspace/comfyui/input
mv /workspace/output /workspace/comfyui/output
mv /workspace/user /workspace/comfyui/user
mv /workspace/comfyui.log /workspace/comfyui/runtime/comfyui.log
mv /workspace/comfyui.pid /workspace/comfyui/runtime/comfyui.pid
```

Skip a command when its source does not exist. If the target already exists,
merge its contents deliberately instead of overwriting either copy. The
container does not migrate automatically because an automatic directory merge
could overwrite models, outputs, or user settings.

If the previous `persistent` layout was already deployed, move its three
directories into the direct layout using the same no-overwrite rule:

```bash
mv /workspace/comfyui/persistent/models /workspace/comfyui/models
mv /workspace/comfyui/persistent/input /workspace/comfyui/input
mv /workspace/comfyui/persistent/output /workspace/comfyui/output
```
