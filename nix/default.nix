{flake-utils, ...} @ inputs:
flake-utils.lib.meld inputs [
  ./sd-cpp.nix
]
