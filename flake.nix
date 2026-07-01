{
  description = "ZT's Neovim — thin wrapper over caoer/nixvim (khanelivim fork) with zt profile";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # khanelivim fork with zt profile + zt-extras
    khanelivim = {
      url = "github:caoer/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://khanelivim.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "khanelivim.cachix.org-1:Tb0jsMlhXSJDtI2ISiGPBrvL1XIzQrWap80AiJuBGI0="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    allow-import-from-derivation = false;
  };

  outputs =
    {
      nixpkgs,
      khanelivim,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = nixpkgs.lib.attrValues khanelivim.inputs.nixvim.overlays;
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
              {
                enableMan = nixpkgs.lib.mkDefault (
                  nixpkgs.lib.hasAttr system khanelivim.inputs.nixvim.packages
                );
                nixpkgs.pkgs = nixpkgs.lib.mkDefault pkgs;
                nixpkgs.config = nixpkgs.lib.mkForce { };
                khanelivim.profile = "zt";
              }
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
