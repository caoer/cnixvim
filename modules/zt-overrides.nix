# zt-overrides.nix — delta from khanelivim's standard profile.
#
# Standard profile is the base; this trims it for ZT's workflow:
# claudecode-only AI, no Java/C#/JJ/wakatime/copilot/firenvim/leetcode,
# git without octo, no screenshots, diffview instead of codediff.
{ lib, ... }:
let
  ov = lib.mkOverride 900;
in
{
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
  ];
}
