# Using sd-cpp-nix on a NixOS host

`sd-cpp-nix` packages a pinned
[stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)
CUDA build (the ggml-based diffusion engine that llama.cpp's author also
maintains, and the tool the Qwen-Image GGUF weights are converted with) and
a NixOS module that runs `sd-server` as a hardened, auto-restarting systemd
service. It is model-agnostic: any SD1.5/SDXL/SD3/Flux/Qwen-Image family
weights (GGUF or safetensors) work — the preset below pins
[Qwen-Image-2.1 Uncensored GGUF](https://huggingface.co/abenzerps/Qwen-Image-2.1-Uncensored-GGUF),
whose model card targets ComfyUI but which sd.cpp loads natively, so no
ComfyUI is required.

Requirements: an `x86_64-linux` or `aarch64-linux` NixOS host with a
CUDA-capable NVIDIA GPU managed by nixpkgs (`hardware.nvidia`, driver libs on
`/run/opengl-driver/lib`).

## Quick start (Qwen-Image-2.1 UC preset)

```nix
{
  inputs.sd-cpp-nix.url = "github:carlschader/sd-cpp-nix";

  outputs = { nixpkgs, sd-cpp-nix, ... }: {
    nixosConfigurations.box = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        sd-cpp-nix.nixosModules.sd-cpp
        sd-cpp-nix.nixosModules."qwen-image-2.1-uc"
        ({ pkgs, ... }: {
          nixpkgs.config.allowUnfree = true;

          services.sd-cpp = {
            enable = true;
            package = sd-cpp-nix.packages.${pkgs.system}.sdcpp;
            openFirewall = true;
          };
        })
      ];
    };
  };
}
```

The first `nixos-rebuild` fetches ~14.6 GB of SHA256-pinned weights into the
Nix store (4.6 GB `Q4_K_M` diffusion GGUF + 9.4 GB int8 Qwen3-VL-8B text
encoder + 0.7 GB bf16 VAE, per the model card's recommended memory layout:
diffusion in VRAM-speed weights, encoder offloaded to RAM once per prompt).
Everything the preset sets is `mkDefault`; override any of
`diffusionModel`/`vae`/`textEncoder` to point at other files (e.g. a
Q6_K/Q8_0 quantization, or a local copy).

The API serves on `0.0.0.0:1234` (the sd-server default).

## API

All of these are served on one port (default 1234):

| Family | Endpoints |
| --- | --- |
| OpenAI-compatible | `POST /v1/images/generations`, `POST /v1/images/edits`, `GET /v1/models` |
| Native (async jobs) | `POST /sdcpp/v1/img_gen` → job id, `GET /sdcpp/v1/jobs/<id>`, `POST /sdcpp/v1/jobs/<id>/cancel`, `GET /sdcpp/v1/capabilities` |
| Stable Diffusion WebUI style | `POST /sdapi/v1/txt2img`, `POST /sdapi/v1/img2img`, `GET /sdapi/v1/{samplers,schedulers,sd-models,options}` |

OpenAI example (verified):

```console
$ curl -s -X POST http://<host>:1234/v1/images/generations \
    -H 'Content-Type: application/json' \
    -d '{"model":"qwen-image-2.1","prompt":"a lighthouse on a cliff at dusk","
        "n":1,"size":"1024x1024"}' | jq -r '.data[0].b64_json' | base64 -d > img.png
```

Responses carry the image as `data[].b64_json` (PNG unless the request asks
for jpeg/webp). Generation defaults come from the CLI flags the module passes
(`--cfg-scale 6.0 --sampling-method euler` in the preset); requests can
override steps/seed/size/CFG per call. `POST /v1/images/edits` (multipart,
`image` + `prompt`) needs a vision projector: set
`services.sd-cpp.llmVision` to a Qwen3-VL `mmproj` GGUF (not included in the
preset; the base Qwen-Image-2.1 release doesn't ship one in this repo).

## Measured on an RTX 4090 (24 GB)

Preset weights, 20 steps (default), `--offload-to-cpu` + flash attention:

| Output | Wall time | Breakdown |
| --- | --- | --- |
| 512×512 | ~11 s | condition 3.4 s + sampling 6.6 s + VAE 0.7 s |
| 1024×1024 | ~30 s | condition 3.6 s + sampling 25.1 s + VAE 1.2 s |

Model weights total ~13.4 GB in system RAM (encoder ~8.3 GB, diffusion
~4.4 GB, VAE ~0.6 GB); the 4090 holds activations/flash-attention workspaces
in VRAM. A 16 GB host needs ~30 GB RAM for this quantization set; smaller
cards can drop `offloadToCpu` for a VRAM-resident encoder at the cost of
~9 GB VRAM.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `enable` | `false` | Enable the sd-cpp service. |
| `package` | — (required) | Package with `bin/sd-server`; use `sd-cpp-nix.packages.<system>.sdcpp`. |
| `host` / `port` | `"0.0.0.0"` / `1234` | API listen address. |
| `openFirewall` | `false` | Open the API port. |
| `diffusionModel` | — (required) | Diffusion/transformer weights (`.gguf`/`.safetensors`/`.ckpt`). |
| `vae` | — (required) | VAE decoder weights; must match the model family. |
| `textEncoder` | `null` | `--llm` text encoder (GGUF or safetensors; Qwen-Image-2.1 needs it). |
| `clip` | `null` | `--clip` CLIP encoder (SD1.5/SDXL-style models). |
| `llmVision` | `null` | `--llm_vision` vision projector; enables image editing. |
| `offloadToCpu` | `true` | `--offload-to-cpu`: keep weights in RAM, VRAM for activations. |
| `flashAttention` | `true` | `--diffusion-fa`. |
| `vaeTiling` | `false` | `--vae-tiling` (peak-VRAM relief at high resolutions). |
| `cfgScale` | `null` | default `--cfg-scale` (string). |
| `samplingMethod` | `null` | default `--sampling-method` (`euler`, `euler_a`, `dpmpp_2m`, ...). |
| `numThreads` | `null` | CPU thread count (`--threads`; default: physical core count). |
| `memoryMax` | `null` | systemd `MemoryMax=` (runaway offload guard). |
| `cudaToolkit` | `pkgs.cudaPackages_13.cudatoolkit` | toolkit lib dir for `LD_LIBRARY_PATH` (plus the nixpkgs driver). |
| `extraArgs` | `[]` | extra `sd-server` args (e.g. `--main-gpu`, `--seed`, `--vae-tiling`). |

The unit runs as the `sd-cpp` system user with GPU `DeviceAllow`,
`ProtectSystem=strict` and `Restart=always`; model files live in the Nix
store, so nothing is written at boot and restarts are fast.

## Updating the pin

Move `rev` in `nix/sd-cpp.nix` and refresh the tree hash (submodules
included):

```console
nix run nixpkgs#nix-prefetch-git -- --fetch-submodules \
  --url https://github.com/leejet/stable-diffusion.cpp --rev <sha>
```

Keep the ggml submodule pointer in lockstep (it is part of the pinned tree).
CUDA kernel architectures are baked in at build time
(`mkSdcpp "89-real;90-virtual;120a-real;121a-real"`); for other GPUs,
`packages.<system>.sdcpp` can be re-derived from the same source via
`overrideAttrs`, or the flake's `mkSdcpp` called with a different arch list
(null falls back to ggml's portable default).

## Troubleshooting

- CUDA not found / no GPU detected — the process cannot see the NVIDIA
  driver. Check `hardware.nvidia` is configured and `/run/opengl-driver/lib`
  exists; the unit's `LD_LIBRARY_PATH` already points there.
- First start is slow — the service loads multi-GB of weights into
  RAM/VRAM (`TimeoutStartSec` is 10 min for that reason); subsequent
  restarts reuse the Nix-store-resident files.
