{...}: {
  nixosModules = rec {
    sd-cpp = import ./sd-cpp.nix;
    default = sd-cpp;
    # Preset for sd-cpp: Qwen-Image-2.1 Uncensored GGUF
    # (abenzerps/Qwen-Image-2.1-Uncensored-GGUF), import alongside `sd-cpp`.
    "qwen-image-2.1-uc" = import ./qwen-image-2.1-uc.nix;
  };
}
