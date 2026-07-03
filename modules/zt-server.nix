# zt-server.nix — delta from khanelivim's basic profile, for small servers.
#
# Basic is upstream's "comfortable remote editor" base: native core,
# treesitter, snacks picker, lualine, which-key, yazi, git basics. It already
# gates off the closure bombs standard carries (rustowl → nightly rustc-dev,
# conform/lint autoInstall → per-language formatter toolchains, DAP).
#
# What basic does NOT trim are the khanelivim.lsp option defaults that drag
# full toolchains into the runtime closure:
#   cpp    = "clangd"  → clang + llvm libs (~1.4 GB)
#   java   → JDK, csharp → dotnet SDK, rust → rustc, typescript → nodejs
# This module nulls those. claudecode stays as the only AI plugin (same as
# the workstation build).
{ lib, pkgs, ... }:
let
  ov = lib.mkOverride 900;
in
{
  # No ruby/python providers on servers (drops neovim-ruby-env ~40 MB and
  # nvim-host-python3-env ~150 MB; no basic-profile plugin uses them).
  withRuby = false;
  withPython3 = false;

  # zt-extras sets vim.g.clipboard (OSC52/tmux) — the wl-clipboard provider
  # (→ xdg-utils → perl, ~65 MB) is dead weight headless.
  clipboard.providers = lib.mkForce { };

  # gitsigns declares nixvim's git dependency, which installs full-fat git
  # (perl + python, ~250 MB closure tail) — gitMinimal keeps the plugin
  # self-contained without the interpreter tail.
  dependencies.git.package = lib.mkForce pkgs.gitMinimal;

  # snacks.image pulls imagemagick/ghostscript/typst/tectonic for inline
  # image/PDF/math rendering — meaningless on a headless box.
  plugins.snacks.settings.image.enabled = lib.mkForce false;

  khanelivim = {
    ai.plugins = ov [ "claudecode" ];

    lsp = {
      cpp = ov null;
      csharp = ov null;
      docker = ov [ ];
      java = ov null;
      # nixd drags llvm-lib (~570 MB); nil-ls is a small rust binary.
      nix = ov "nil-ls";
      # basedpyright is ~220 MB + python runtime; ruff (linters default)
      # stays for diagnostics/formatting.
      python.typeChecker = ov null;
      rust = ov null;
      typescript = ov null;
    };
  };

  # Upstream lsp.nix enables a large server roster unconditionally
  # (enable = true, priority 100) — profile-level overrides can't reach
  # these, so force off everything a small infra box doesn't need.
  # Kept: bashls, cssls/html/jsonls (one vscode-langservers package),
  # yamlls, taplo, statix, nil-ls, emmylua_ls, ruff, typos_lsp.
  lsp.servers = lib.genAttrs [
    "angularls" # web
    "biome" # web
    "cmake"
    "copilot" # enabled via !copilot-lua.enable when AI plugins are off
    "eslint" # web
    "fish_lsp"
    "fsautocomplete" # F# → dotnet-sdk (~600 MB)
    "gdscript" # godot
    "gopls"
    "harper_ls" # grammar checker (~120 MB)
    "helm_ls" # kubernetes helm (~60 MB)
    "hyprls" # hyprland
    "kulala_ls" # http files (~75 MB)
    "marksman" # markdown → dotnet-runtime (~80 MB)
    "nushell"
    "qmlls" # qt6 qtdeclarative (~270 MB)
    "sqls"
    "stylelint_lsp" # web; also fails eval (insecure pnpm-9.15.9 build dep)
    "tailwindcss" # web (~120 MB)
    "teal_ls"
  ] (_: { enable = lib.mkForce false; });
}
