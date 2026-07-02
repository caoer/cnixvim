{
  description = "ZT's Neovim — upstream khanelivim + zt customizations";

  inputs = {
    # No nixpkgs input — use khanelivim's nixpkgs so intermediate plugin
    # derivation hashes match khanelivim.cachix.org.
    khanelivim.url = "github:khaneliman/khanelivim";
  };

  nixConfig = {
    extra-substituters = [
      # Public attic cache — CI pushes every build here (all platforms).
      "https://attic-yul2.0xdao.app/cnixvim"
      "https://khanelivim.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cnixvim:S0udLnYCWHR0iRCFYUe2LhDp3rIAYGKGflQ7Seeau3c="
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
          pkgs = import khanelivim.inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = lib.attrValues khanelivim.inputs.nixvim.overlays;
          };

          neovim = (khanelivim.inputs.nixvim.lib.evalNixvim {
            inherit system;

            extraSpecialArgs = {
              inputs = khanelivim.inputs;
              self = khanelivim;
              inherit system;
            };

            modules = [
              khanelivim.nixvimModules.default

              # Base: use standard profile from upstream
              {
                enableMan = lib.mkDefault (lib.hasAttr system khanelivim.inputs.nixvim.packages);
                nixpkgs.pkgs = lib.mkDefault pkgs;
                nixpkgs.config = lib.mkForce { };
                khanelivim.profile = "standard";
              }

              # ZT overrides on top of standard
              ./modules/zt-overrides.nix

              # ZT extras: keymaps, autocmds, clipboard, plugins
              ./modules/zt-extras.nix
            ];
          }).config.build.package;
        in
        {
          default = neovim;
          neovim = neovim;
        }
      );
    };
}
