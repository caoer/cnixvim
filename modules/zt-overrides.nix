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
