# zt-overrides.nix — delta from khanelivim's standard profile.
#
# Standard profile is the base; this trims it for ZT's workflow:
# claudecode-only AI, no Java/C#/JJ/wakatime/copilot/firenvim/leetcode,
# git without octo, no screenshots, diffview instead of codediff.
{ lib, pkgs, ... }:
let
  ov = lib.mkOverride 900;
in
{
  # Mermaid rendering for snacks.image (upstream enables image but leaves
  # mermaid-cli commented out pending a nixpkgs chromium for darwin).
  # mmdc drives a browser via puppeteer; point it at the installed Chrome —
  # upstream's default expects a Homebrew Chromium.app that isn't here.
  extraPackages = [ pkgs.mermaid-cli ];
  env = lib.optionalAttrs pkgs.stdenv.isDarwin {
    PUPPETEER_EXECUTABLE_PATH = lib.mkForce "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  };

  # Treesitter out-of-bounds guard (upstream bug neovim/neovim#38303, root #37091).
  # The highlighter's decoration provider (and injection parse) can read a node's
  # byte range via nvim_buf_get_text *before* the tree re-parses after a buffer edit
  # (classically `dd` in a larger file); the stale range is out of bounds so
  # nvim_buf_get_text throws "Index out of bounds". Core catches it and self-corrects
  # next redraw, but spams:
  #   Error in decoration provider ... (ns=nvim.treesitter.highlighter): Index out of bounds
  # The bug exists on stable (0.11.x) and nightly alike, so there is no version to
  # move to. vim.treesitter.get_node_text is the single lua entry point that calls
  # nvim_buf_get_text for the highlighter and injection language resolution; internal
  # callers resolve it at call-time, so wrapping it here makes an out-of-bounds read
  # return "" (skip text for that one stale frame — the next redraw fixes it) instead
  # of throwing. Remove once upstream #38303 lands bounds checks.
  extraConfigLuaPre = ''
    -- tmux's global environment leaks DIRENV_* state from whatever shell last
    -- exported it (e.g. a locus .envrc). direnv.vim (bundled by khanelivim)
    -- runs `direnv export` shortly after startup; with that stale state and no
    -- .envrc in scope, direnv "unloads" — reverting PATH to the recorded
    -- baseline and wiping every nix-wrapper PATH entry (mmdc, LSP servers,
    -- formatters). Clear the inherited state so the wrapper environment is
    -- direnv's baseline; project .envrc loading still works on top of it.
    for _, k in ipairs({ "DIRENV_DIFF", "DIRENV_DIR", "DIRENV_FILE", "DIRENV_WATCHES" }) do
      vim.env[k] = nil
    end

    do
      local ts = vim.treesitter
      if ts and type(ts.get_node_text) == "function" and not ts.__bounds_guarded then
        local orig = ts.get_node_text
        vim.g.ts_bounds_guard_catches = 0
        ts.get_node_text = function(...)
          local ok, res = pcall(orig, ...)
          if ok then
            return res
          end
          vim.g.ts_bounds_guard_catches = (vim.g.ts_bounds_guard_catches or 0) + 1
          return ""
        end
        ts.__bounds_guarded = true
      end
    end
  '';

  khanelivim = {
    ai.plugins = ov [ "claudecode" ];

    integrations.accountBacked.timeTracking.enable = ov false;

    git = {
      diffViewer = ov "diffview";
      integrations = ov [
        "gitsigns"
        "git-conflict"
        "git-worktree"
        "hunk"
        "native-difftool"
        "snacks-gh"
        "snacks-gitbrowse"
        "snacks-lazygit"
      ];
    };

    jj.integrations = ov [ ];

    lsp = {
      java = ov null;
      csharp = ov null;
    };

    utilities.screenshots = ov [ ];
  };

  plugins = {
    # Ordinal-only tab numbers (upstream shows buffer-id·ordinal); paired
    # with <leader>1-9 jumps below.
    bufferline.settings.options.numbers = lib.mkForce "ordinal";

    easy-dotnet.enable = lib.mkForce false;
    firenvim.enable = lib.mkForce false;
    leetcode.enable = lib.mkForce false;
    showkeys.enable = lib.mkForce false;

    # Guard faster.nvim's noice disable/enable against noice not yet being
    # set up (BufReadPost fires before DeferredUIEnter, so noice.setup()
    # hasn't run and noice.options.notify is nil → crash).
    faster.settings.features.noice = {
      disable.__raw = lib.mkForce ''
        function()
          local ok, noice = pcall(require, "noice")
          if ok then
            local dok, err = pcall(noice.disable)
            if not dok then
              vim.notify("[faster.nvim] noice.disable() skipped: " .. tostring(err), vim.log.levels.DEBUG)
            end
          end
        end
      '';
      enable.__raw = lib.mkForce ''
        function()
          local ok, noice = pcall(require, "noice")
          if ok then
            local eok, err = pcall(noice.enable)
            if not eok then
              vim.notify("[faster.nvim] noice.enable() skipped: " .. tostring(err), vim.log.levels.DEBUG)
            end
          end
        end
      '';
      commands.__raw = lib.mkForce ''
        function()
          vim.api.nvim_create_user_command("FasterEnableNoice", function()
            local ok, noice = pcall(require, "noice")
            if ok then pcall(noice.enable) end
          end, {})
          vim.api.nvim_create_user_command("FasterDisableNoice", function()
            local ok, noice = pcall(require, "noice")
            if ok then pcall(noice.disable) end
          end, {})
        end
      '';
    };
  };

  # copilot: lsp.nix sets enable at priority 100; mkOverride 900 loses — use mkForce
  lsp.servers.copilot.enable = lib.mkForce false;
  lsp.servers.stylelint_lsp.enable = lib.mkForce false;

  # Crash protection: upstream disables swapfile (options.nix, priority 100).
  # A hard crash with an unsaved buffer is otherwise unrecoverable — undofile
  # only persists on :w. Swap syncs every 4s/200 chars; nvim -r recovers it.
  opts.swapfile = lib.mkForce true;

  # Window nav: <C-h/j/k/l> in normal + terminal mode
  keymaps = [
    { mode = "n"; key = "<C-h>"; action = "<C-w>h"; options = { desc = "Go to left window"; silent = true; }; }
    { mode = "n"; key = "<C-j>"; action = "<C-w>j"; options = { desc = "Go to below window"; silent = true; }; }
    { mode = "n"; key = "<C-k>"; action = "<C-w>k"; options = { desc = "Go to above window"; silent = true; }; }
    { mode = "n"; key = "<C-l>"; action = "<C-w>l"; options = { desc = "Go to right window"; silent = true; }; }
    { mode = "t"; key = "<C-h>"; action = "<cmd>wincmd h<cr>"; options = { desc = "Go to left window"; silent = true; }; }
    { mode = "t"; key = "<C-j>"; action = "<cmd>wincmd j<cr>"; options = { desc = "Go to below window"; silent = true; }; }
    { mode = "t"; key = "<C-k>"; action = "<cmd>wincmd k<cr>"; options = { desc = "Go to above window"; silent = true; }; }
    { mode = "t"; key = "<C-l>"; action = "<cmd>wincmd l<cr>"; options = { desc = "Go to right window"; silent = true; }; }
  ]
  # Buffer jumps by bufferline ordinal: <leader>1-9 → Nth visible tab
  ++ map (n: {
    mode = "n";
    key = "<leader>${toString n}";
    action = "<cmd>BufferLineGoToBuffer ${toString n}<cr>";
    options = { desc = "Go to buffer ${toString n}"; silent = true; };
  }) (lib.range 1 9);
}
