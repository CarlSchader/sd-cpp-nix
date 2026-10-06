# sd-cpp-nix

A pinned [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)
CUDA build (ggml, `sd-cli` + `sd-server`) plus a NixOS module that runs
`sd-server` as a hardened, auto-restarting systemd service. It serves the
OpenAI-compatible `/v1/images/generations` + `/v1/images/edits` API, a
ComfyUI-sdwebui-style API on `/sdapi/v1/...` and sd.cpp's native async API on
`/sdcpp/v1/...` — no ComfyUI needed.

Spun out of [sglang-nix](https://github.com/carlschader/sglang-nix); same
layout, different engine. Supports `x86_64-linux` and `aarch64-linux`
(DGX Spark).

```nix
imports = [
  sd-cpp-nix.nixosModules.sd-cpp
  sd-cpp-nix.nixosModules."qwen-image-2.1-uc"   # optional preset, see below
];

services.sd-cpp = {
  enable = true;
  package = sd-cpp-nix.packages.${pkgs.system}.sdcpp;
  openFirewall = true;
};
```

The `qwen-image-2.1-uc` preset pins the
[Qwen-Image-2.1 Uncensored GGUF](https://huggingface.co/abenzerps/Qwen-Image-2.1-Uncensored-GGUF)
weights (SHA256-pinned, ~14.6 GB total) — OpenAI-compatible
`POST /v1/images/generations` out of the box, measured ~30 s/image at 1024²
on an RTX 4090. The module itself is model-agnostic: any SD1.5/SDXL/Flux/
Qwen-Image family weights (GGUF or safetensors) work.

See [docs/usage.md](docs/usage.md) for the full option reference, the preset
details and numbers, the API reference, and the pin-update procedure.

## Flake outputs

- `packages.<system>.sdcpp` (also `default`) — pinned stable-diffusion.cpp CUDA build (`bin/sd-cli`, `bin/sd-server`)
- `nixosModules.sd-cpp` (also `default`) — the `services.sd-cpp` image-generation server module
- `nixosModules."qwen-image-2.1-uc"` — preset for sd-cpp: Qwen-Image-2.1 Uncensored GGUF (SHA256-pinned weights)
- `checks.<system>.{sdcppVersion,sdcppModuleEval}` — binary smoke test and pure-eval module check

## Development

```console
nix build .#sdcpp       # build the sd.cpp CUDA binaries
nix flake check         # version + module-eval checks
```
