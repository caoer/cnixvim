{
  description = "ZT's Neovim — upstream khanelivim + zt customizations";

  inputs = {
    # No nixpkgs input — use khanelivim's nixpkgs so intermediate plugin
    # derivation hashes match khanelivim.cachix.org.
    khanelivim.url = "github:khaneliman/khanelivim";
  };

  nixConfig = {
    extra-substituters = [
      # Public niks3 cache (R2 CDN) — CI pushes every build here (all platforms).
      "https://cache.0xtau.com"
      "https://khanelivim.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.0xtau.com-1:M4y9SWhqZED/M9nvrYvJuxAlEj0umdXnxRYMgoXZxfU="
      "khanelivim.cachix.org-1:Tb0jsMlhXSJDtI2ISiGPBrvL1XIzQrWap80AiJuBGI0="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    allow-import-from-derivation = false;
  };

  outputs =
    { khanelivim, ... }:
    let
      lib = khanelivim.inputs.nixpkgs.lib;
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          # Supported customization surface: evaluate an upstream profile via
          # khanelivim.lib.mkNixvimConfig, then extend it with zt modules.
          # zt-extras (keymaps/autocmds/clipboard/plugins) always applies
          # since cnixvim IS the zt build.
          mkNeovim =
            profile: modules:
            ((khanelivim.lib.mkNixvimConfig { inherit system profile; }).extendModules {
              modules = modules ++ [ ./modules/zt-extras.nix ];
            }).config.build.package;

          # Workstation build: upstream standard profile + zt trims.
          neovim = mkNeovim "standard" [ ./modules/zt-overrides.nix ];

          # Small-server build: upstream basic profile ("comfortable remote
          # editor") + zt trims of the toolchain-heavy LSP defaults. Same
          # zt-extras workflow, ~10x smaller closure.
          server = mkNeovim "basic" [ ./modules/zt-server.nix ];
        in
        {
          default = neovim;
          inherit neovim server;
        }
      );
    };
}
