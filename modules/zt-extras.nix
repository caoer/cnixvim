# zt-extras.nix — ZT keymaps, autocmds, clipboard, extra plugins, spell.
#
# Ported from caoer/nixvim zt-extras.nix. Not gated on profile — always
# applied since cnixvim IS the zt build.
{
  lib,
  pkgs,
  cccMdformat,
  ...
}:
let
  videre-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "videre-nvim";
    version = "unstable-2025-04-03";
    src = pkgs.fetchFromGitHub {
      owner = "Owen-Dechow";
      repo = "videre.nvim";
      rev = "785ede15e3b280fbf5a6d36823eb74122cd85a83";
      hash = "sha256-GAbSWhaEB5XnH2DGYQAXgWJCm5zHhLJaQ6WTbbVTWJk=";
    };
    doCheck = false;
    meta.homepage = "https://github.com/Owen-Dechow/videre.nvim";
  };

  # nixpkgs' ts-comments (2025-10-28) reads vim.opt.comments._info.default to
  # detect the default 'comments' — _info was dropped from vim.opt option
  # objects in Nvim 0.12, so every gc died with "attempt to index field
  # '_info'". Upstream fix 426303d switches to nvim_get_option_info2. Both
  # profiles ship ts-comments, so pin here (shared). Drop once nixpkgs'
  # vimPlugins passes 2026-06-29.
  ts-comments-nvim = pkgs.vimPlugins.ts-comments-nvim.overrideAttrs (old: {
    version = "1.5.0-unstable-2026-06-29";
    src = pkgs.fetchFromGitHub {
      owner = "folke";
      repo = "ts-comments.nvim";
      rev = "426303d38d8c9168737b9b8763a97d84b692978f";
      hash = "sha256-fvu+NYY/aLbsXmPNiZYnAjFrgPqj1mOuuJQEyDXRtOI=";
    };
  });
in
{
  # ── Editor option overrides ────────────────────────────────────────────
  opts = {
    backup = false;
    hlsearch = false;
    scrolloff = 8;
    softtabstop = 2;
    spell = lib.mkForce false;
    spelloptions = "camel";
    updatetime = lib.mkForce 50;
  };

  # ── Custom filetype associations ───────────────────────────────────────
  filetype = {
    extension = {
      conf = "toml";
      dconf = "toml";
      har = "json";
    };
    filename = {
      "Cargo.lock" = "toml";
    };
    pattern = {
      "%.config/.*" = "toml";
      ".*surge%-config/providers/.*%.txt" = "dosini";
    };
  };

  # ── Plugin version pins ────────────────────────────────────────────────
  plugins.ts-comments.package = ts-comments-nvim;

  # ── Lint ───────────────────────────────────────────────────────────────
  # Markdown diagnostics are disabled buffer-wide (autocmd below), so the
  # upstream markdown linters (markdownlint-cli2 + codespell) run on every
  # InsertLeave/BufWritePost only to have their output discarded. Their sole
  # visible output is spawn-failure popups ("Error running markdownlint-cli2:
  # ENOENT") when uv_spawn hits a transiently dead cwd (agent tree rewrites
  # under an open buffer). Cut the filetype instead of guarding the spawn.
  plugins.lint.lintersByFt.markdown = lib.mkForce [ ];

  # yamllint's line-length rule fires "line too long (N > 80 characters)" on
  # every long YAML line — noise for config/secrets files with long values.
  # Disable just that rule via inline config data (-d), keeping the rest of
  # yamllint (indentation, trailing space, syntax errors). Only args are
  # overridden; nvim-lint's built-in yamllint cmd/parser/severities stay
  # intact (nixvim emits `__lint.linters.yamllint.args = ...`).
  plugins.lint.linters.yamllint.args = lib.mkForce [
    "--format"
    "parsable"
    "-d"
    "{extends: default, rules: {line-length: disable}}"
    "-"
  ];

  # ── Format-on-save (markdown → ccc-mdformat) ───────────────────────────
  # Markdown formats to lean, token-efficient output ON DISK: ccc-mdformat
  # is mdformat with the canonical flags (--wrap=no --compact-tables) and the
  # 4-plugin ship set baked in — compact tables, unwrapped prose, frontmatter
  # + GFM checkboxes preserved. Replaces upstream's deno_fmt for markdown.
  # File mode (stdin=false + $FILENAME) matches ccc-mdformat's tested in-place
  # `ccc-mdformat FILE` contract. Pretty is a display-only layer (markview
  # conceal, enabled by the standard profile) — never written to disk.
  # cccMdformat is injected via _module.args in flake.nix.
  plugins.conform-nvim.settings = {
    formatters_by_ft.markdown = lib.mkForce [ "ccc_mdformat" ];
    formatters.ccc_mdformat = {
      command = lib.getExe cccMdformat;
      args = [ "$FILENAME" ];
      stdin = false;
    };
  };

  # ── Autocmds ───────────────────────────────────────────────────────────
  autoCmd = [
    {
      event = [ "BufRead" "BufNewFile" ];
      pattern = [ "*.md" ];
      callback.__raw = "function() vim.diagnostic.enable(false, { bufnr = 0 }) end";
    }
    {
      # toml/yaml default to marker folds ({{{ / }}}); any buffer can flip
      # fold method with zT (see zt_toggle_foldmethod)
      event = [ "FileType" ];
      pattern = [ "toml" "yaml" ];
      callback.__raw = "function(args) vim.b[args.buf].zt_marker_folds = true end";
    }
    {
      # Upstream lsp.nix force-sets foldmethod=expr on BufWinEnter +
      # LspAttach (LSP attaches async, after modelines/FileType). For
      # buffers opted into marker folds, re-assert by scheduling AFTER
      # upstream's callback runs.
      event = [ "FileType" "BufWinEnter" "LspAttach" ];
      callback.__raw = ''
        function(args)
          local bufnr = args.buf
          if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then return end
          if not vim.b[bufnr].zt_marker_folds then return end
          local collapse = args.event == "FileType"
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then return end
            local win = vim.fn.bufwinid(bufnr)
            if win == -1 then return end
            vim.api.nvim_win_call(win, function()
              _G.zt_apply_marker_folds(collapse)
            end)
          end)
        end
      '';
    }
    {
      event = [ "FileType" ];
      pattern = [ "dosini" ];
      callback.__raw = ''
        function()
          vim.bo.commentstring = "# %s"
        end
      '';
    }
    {
      event = [ "FileType" ];
      pattern = [ "hurl" ];
      callback.__raw = ''
        function()
          local opts = function(desc) return { buffer = true, desc = desc, silent = true } end
          vim.keymap.set("n", "<leader>ha", "<cmd>HurlRunner<CR>", opts("Hurl: Run all requests"))
          vim.keymap.set("n", "<leader>he", "<cmd>HurlRunnerAt<CR>", opts("Hurl: Run at cursor"))
          vim.keymap.set("n", "<leader>hE", "<cmd>HurlRunnerToEnd<CR>", opts("Hurl: Run to end"))
          vim.keymap.set("n", "<leader>hv", "<cmd>HurlVerbose<CR>", opts("Hurl: Run verbose"))
          vim.keymap.set("n", "<leader>hm", "<cmd>HurlToggleMode<CR>", opts("Hurl: Toggle popup/split"))
          vim.keymap.set("v", "<leader>h",  ":HurlRunner<CR>", opts("Hurl: Run selection"))
        end
      '';
    }
  ];

  # ── Keymaps (simple string actions) ────────────────────────────────────
  keymaps = [
    { mode = "n"; key = "zT"; action.__raw = "function() _G.zt_toggle_foldmethod() end"; options = { desc = "Toggle fold method (marker/treesitter)"; silent = true; }; }
    {
      mode = "n"; key = "gv"; action = ":!code %<CR>";
      options = { desc = "Open in VS Code"; silent = true; };
    }
    { mode = "n"; key = "<leader>h"; action = "<C-w>h"; options = { desc = "Go to left window"; silent = true; }; }
    { mode = "n"; key = "<leader>j"; action = "<C-w>j"; options = { desc = "Go to below window"; silent = true; }; }
    { mode = "n"; key = "<leader>k"; action = "<C-w>k"; options = { desc = "Go to above window"; silent = true; }; }
    { mode = "n"; key = "<leader>l"; action = "<C-w>l"; options = { desc = "Go to right window"; silent = true; }; }
    { mode = "n"; key = "<Left>"; action = "<C-w>h"; options = { desc = "Go to left window"; silent = true; }; }
    { mode = "n"; key = "<Down>"; action = "<C-w>j"; options = { desc = "Go to below window"; silent = true; }; }
    { mode = "n"; key = "<Up>"; action = "<C-w>k"; options = { desc = "Go to above window"; silent = true; }; }
    { mode = "n"; key = "<Right>"; action = "<C-w>l"; options = { desc = "Go to right window"; silent = true; }; }
    { mode = "t"; key = "<S-Left>"; action = "<cmd>wincmd h<cr>"; options = { desc = "Go to left window"; silent = true; }; }
    { mode = "t"; key = "<S-Down>"; action = "<cmd>wincmd j<cr>"; options = { desc = "Go to below window"; silent = true; }; }
    { mode = "t"; key = "<S-Up>"; action = "<cmd>wincmd k<cr>"; options = { desc = "Go to above window"; silent = true; }; }
    { mode = "t"; key = "<S-Right>"; action = "<cmd>wincmd l<cr>"; options = { desc = "Go to right window"; silent = true; }; }
    { mode = "n"; key = "<S-Left>"; action = "<C-w>h"; options = { desc = "Go to left window"; silent = true; }; }
    { mode = "n"; key = "<S-Down>"; action = "<C-w>j"; options = { desc = "Go to below window"; silent = true; }; }
    { mode = "n"; key = "<S-Up>"; action = "<C-w>k"; options = { desc = "Go to above window"; silent = true; }; }
    { mode = "n"; key = "<S-Right>"; action = "<C-w>l"; options = { desc = "Go to right window"; silent = true; }; }
    { mode = "n"; key = "<leader>gd"; action = "<cmd>DiffviewOpen<cr>"; options = { desc = "Diffview: Open"; silent = true; }; }
    { mode = "n"; key = "<leader>gh"; action = "<cmd>DiffviewFileHistory %<cr>"; options = { desc = "Diffview: File history"; silent = true; }; }
    { mode = "n"; key = "<leader>gH"; action = "<cmd>DiffviewFileHistory<cr>"; options = { desc = "Diffview: Branch history"; silent = true; }; }
    { mode = "n"; key = "<leader>sz"; action = "<cmd>SopsDecrypt<cr>"; options = { desc = "Decrypt SOPS file"; silent = true; }; }
    { mode = "n"; key = "<leader>se"; action = "<cmd>SopsEncrypt<cr>"; options = { desc = "Encrypt SOPS file"; silent = true; }; }
    { mode = "n"; key = "<leader>jv"; action = "<cmd>Videre<cr>"; options = { desc = "JSON Graph Explorer"; silent = true; }; }
  ];

  # ── Extra plugins (lazy-loaded) ────────────────────────────────────────
  extraPlugins = [
    { plugin = pkgs.vimPlugins.hurl-nvim; optional = true; }
    { plugin = pkgs.vimPlugins.nvim-sops; optional = true; }
    { plugin = videre-nvim; optional = true; }
    { plugin = pkgs.vimPlugins.csvview-nvim; optional = true; }
  ];

  # ── Spell dictionary ───────────────────────────────────────────────────
  extraFiles."spell/en.utf-8.add".text = ''
    Backend
    backend
    frontend
    Frontend
    config
    configs
    Tailscale
    tailscale
    https
    API
    APIs
    async
    await
    boolean
    stylesheet
    kubernetes
    kubectl
    nginx
    postgres
    PostgreSQL
    redis
    Redis
    TypeScript
    JavaScript
    localhost
    enum
    enums
    namespace
    middleware
    middlewares
    auth
    OAuth
    JSON
    yaml
    YAML
    dockerfile
    Dockerfile
    websocket
    GraphQL
    terraform
    Terraform
    workflow
    workflows
    repo
    repos
    microservice
    microservices
    Homebrew
    Tmux
    WezTerm
    Cheatsheet
    frontmatter
    callouts
  '';

  # ── Nvim 0.13 deprecation shims ────────────────────────────────────────
  # Bundled plugins still call APIs deprecated in 0.13 (removal: 0.15) —
  # hardtime/bufferline: vim.F.if_nil; nvim-lightbulb: vim.F.npcall (plenary
  # and nvim-dap carry more call sites); typescript-tools:
  # vim.lsp.codelens.refresh (upstream khanelivim has a TODO for it). All are
  # unfixed at upstream HEAD, so a khanelivim bump can't clear them. Re-point
  # the old names at their official replacements: the vim.deprecate() warning
  # path never runs, and the plugins keep working after 0.15 deletes the
  # originals. Drop each line once upstreams adopt the new APIs.
  extraConfigLuaPre = ''
    if vim.nonnil and vim.F then vim.F.if_nil = vim.nonnil end
    if vim.npcall and vim.F then vim.F.npcall = vim.npcall end
    if vim.lsp.codelens.enable then
      vim.lsp.codelens.refresh = function(opts) vim.lsp.codelens.enable(true, opts) end
    end
  '';

  # ── Complex Lua config ─────────────────────────────────────────────────
  extraConfigLua = ''
    -- ====================================================================
    -- ZT Profile: Fold method toggle (zT) — marker {{{ }}} vs treesitter
    -- ====================================================================
    -- One buffer-sticky switch instead of merged fold systems. Upstream
    -- lsp.nix force-sets expr folding on BufWinEnter/LspAttach, so opted-in
    -- buffers get re-asserted by the folding autocmd (see autoCmd).
    function _G.zt_apply_marker_folds(collapse)
      vim.wo.foldmethod = "marker"
      vim.wo.foldtext = "foldtext()"
      if collapse then vim.wo.foldlevel = 0 end
    end

    function _G.zt_toggle_foldmethod()
      if vim.b.zt_marker_folds then
        vim.b.zt_marker_folds = nil
        vim.wo.foldmethod = "expr"
        vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
        vim.wo.foldlevel = 99
        vim.notify("folds: treesitter")
      else
        vim.b.zt_marker_folds = true
        _G.zt_apply_marker_folds(true)
        vim.notify("folds: marker {{{ }}}")
      end
    end

    -- ====================================================================
    -- ZT Profile: Editor option overrides (dynamic paths)
    -- ====================================================================
    vim.opt.undodir = os.getenv("HOME") .. "/.local/share/nvim/undo"

    -- Spell file in writable location
    local spelldir = vim.fn.expand("~/.local/share/nvim/spell")
    vim.fn.mkdir(spelldir, "p")
    local user_spellfile = spelldir .. "/en.utf-8.add"
    if vim.fn.filereadable(user_spellfile) == 0 then
      vim.fn.writefile({}, user_spellfile)
    end
    vim.opt.spellfile = {
      vim.fn.stdpath("config") .. "/spell/en.utf-8.add",
      user_spellfile,
    }

    -- ====================================================================
    -- ZT Profile: Clipboard (dual pbcopy/OSC52)
    -- ====================================================================
    local is_local_mac = vim.fn.has("mac") == 1 and vim.env.SSH_CONNECTION == nil

    local function zt_copy_fn(reg)
      if is_local_mac then
        return function(lines, regtype)
          local text = table.concat(lines, "\n")
          if regtype == "V" then text = text .. "\n" end
          vim.fn.system("pbcopy", text)
        end
      end
      local osc52_fn = require("vim.ui.clipboard.osc52").copy(reg)
      return function(lines, regtype)
        if regtype == "V" then
          local copy = { unpack(lines) }
          table.insert(copy, "")
          return osc52_fn(copy)
        end
        return osc52_fn(lines)
      end
    end

    local function zt_paste_fn()
      if is_local_mac then
        local h = io.popen("pbpaste")
        local content = h:read("*a")
        h:close()
        local lines = vim.split(content, "\n", { plain = true })
        if #lines > 1 and lines[#lines] == "" then
          table.remove(lines)
          return lines, "V"
        end
        return lines
      end
      local h = io.popen("tmux save-buffer - 2>/dev/null")
      if h then
        local content = h:read("*a")
        h:close()
        if content and content ~= "" then
          local lines = vim.split(content, "\n", { plain = true })
          if #lines > 1 and lines[#lines] == "" then
            table.remove(lines)
            return lines, "V"
          end
          return lines
        end
      end
      return {}
    end

    vim.g.clipboard = {
      name = is_local_mac and "pbcopy/pbpaste" or "OSC 52 + tmux",
      copy  = { ["+"] = zt_copy_fn("+"), ["*"] = zt_copy_fn("*") },
      paste = { ["+"] = zt_paste_fn,      ["*"] = zt_paste_fn },
    }

    -- ====================================================================
    -- ZT Profile: Yank module (file references, XML refs, outer-tmux OSC52)
    -- ====================================================================
    local zt_yank = {}

    function zt_yank.to_outer_tmux()
      local content = vim.fn.getreg('"')
      if content == "" then return end
      local tty = os.getenv("OUTER_TTY")
      if not tty or tty == "" then
        local env_output = vim.fn.system("tmux show-environment OUTER_TTY 2>/dev/null"):gsub("%s+$", "")
        tty = env_output:match("OUTER_TTY=(.+)")
      end
      if not tty or tty == "" then
        tty = vim.fn.system("tmux -L zt list-clients -F '#{client_tty}' 2>/dev/null | head -1"):gsub("%s+$", "")
      end
      if not tty or tty == "" then
        vim.notify("Could not find outer tmux TTY", vim.log.levels.WARN)
        return
      end
      local encoded = vim.fn.system("echo -n " .. vim.fn.shellescape(content) .. " | base64 -w0")
      local cmd = string.format("printf '\\033]52;c;%s\\007' > %s", encoded, tty)
      vim.fn.system(cmd)
    end

    local function zt_git_root()
      local root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
      if vim.v.shell_error == 0 and root and #root > 0 then return root end
      return nil
    end

    local function zt_relative_path()
      local abs = vim.fn.expand("%:p")
      local git_root = zt_git_root()
      if git_root then
        return abs:gsub("^" .. vim.pesc(git_root) .. "/", "")
      end
      return vim.fn.fnamemodify(abs, ":~:.")
    end

    local function zt_get_range(is_visual)
      if not is_visual then return nil, nil end
      local s = vim.fn.line("v")
      local e = vim.fn.line(".")
      if s > e then s, e = e, s end
      if s > 0 and e > 0 then return s, e end
      return nil, nil
    end

    function zt_yank.yank_ref(is_visual)
      local path = zt_relative_path()
      local s, e = zt_get_range(is_visual)
      local ref = s and string.format("@%s#L%d-%d", path, s, e) or ("@" .. path)
      vim.fn.setreg("+", ref)
      vim.notify(ref)
    end

    function zt_yank.yank_ref_abs(is_visual)
      local path = vim.fn.expand("%:p")
      local s, e = zt_get_range(is_visual)
      local ref = s and string.format("@%s#L%d-%d", path, s, e) or ("@" .. path)
      vim.fn.setreg("+", ref)
      vim.notify(ref)
    end

    function zt_yank.yank_xml_empty(is_visual)
      local filepath = vim.fn.expand("%:p")
      local s, e = zt_get_range(is_visual)
      if not s then s = vim.fn.line("."); e = s end
      local xml = string.format('<content filepath="@%s" lines="L%d-%d">\n  \n</content>', filepath, s, e)
      vim.fn.setreg("+", xml)
      vim.notify(string.format("Copied ref: @%s L%d-%d", filepath, s, e))
    end

    function zt_yank.yank_xml_full(is_visual)
      local filepath = vim.fn.expand("%:p")
      local s, e = zt_get_range(is_visual)
      local lines
      if s then
        lines = vim.fn.getline(s, e)
      else
        s = vim.fn.line("."); e = s
        lines = { vim.fn.getline(s) }
      end
      local content = table.concat(lines, "\n")
      local xml = string.format('<content filepath="%s" lines="L%d-%d">\n%s\n</content>', filepath, s, e, content)
      vim.fn.setreg("+", xml)
      vim.notify(string.format("Copied: %s L%d-%d", filepath, s, e))
    end

    -- Yank module keymaps
    vim.keymap.set("n", "<leader>yc", function() zt_yank.yank_ref(false) end, { desc = "Copy @file ref (relative)" })
    vim.keymap.set("v", "<leader>yc", function() zt_yank.yank_ref(true) end, { desc = "Copy @file ref (relative)" })
    vim.keymap.set("n", "<leader>yC", function() zt_yank.yank_ref_abs(false) end, { desc = "Copy @file ref (absolute)" })
    vim.keymap.set("v", "<leader>yC", function() zt_yank.yank_ref_abs(true) end, { desc = "Copy @file ref (absolute)" })
    vim.keymap.set("n", "<leader>yx", function() zt_yank.yank_xml_empty(false) end, { desc = "Copy XML ref (no content)" })
    vim.keymap.set("v", "<leader>yx", function() zt_yank.yank_xml_empty(true) end, { desc = "Copy XML ref (no content)" })
    vim.keymap.set("n", "<leader>yX", function() zt_yank.yank_xml_full(false) end, { desc = "Copy XML with content" })
    vim.keymap.set("v", "<leader>yX", function() zt_yank.yank_xml_full(true) end, { desc = "Copy XML with content" })

    -- ====================================================================
    -- ZT Profile: Custom keymaps (Lua functions)
    -- ====================================================================

    -- Save file with Snacks notification
    vim.keymap.set("n", "<leader>ww", function()
      vim.cmd("w")
      local ok, snacks = pcall(require, "snacks")
      if ok and snacks.notify then
        snacks.notify.info(vim.fn.expand("%"), { title = "Saved", style = "fancy" })
      else
        vim.notify("Saved: " .. vim.fn.expand("%"), vim.log.levels.INFO)
      end
    end, { desc = "Save file" })

    -- grug-far: search/replace scoped to current file
    vim.keymap.set({ "n", "v" }, "<leader>sf", function()
      local ok, grug = pcall(require, "grug-far")
      if not ok then vim.notify("grug-far not available", vim.log.levels.WARN); return end
      local opts = { prefills = { paths = vim.fn.expand("%") } }
      if vim.fn.mode() == "v" or vim.fn.mode() == "V" then
        grug.with_visual_selection(opts)
      else
        grug.open(opts)
      end
    end, { desc = "Search/replace in current file" })

    -- Quick substitute: visual selection → global replace in file
    vim.keymap.set("v", "<leader>ss", function()
      vim.cmd('noautocmd normal! "zy')
      local escaped = vim.fn.escape(vim.fn.getreg("z"), "/\\.*$^~[]")
      local cmd = string.format("%%s/%s/%s/g", escaped, escaped)
      vim.api.nvim_feedkeys(":", "n", false)
      vim.schedule(function()
        vim.fn.setcmdline(cmd, 5 + 2 * #escaped)
      end)
    end, { desc = "Substitute selected (cursor at end)" })

    -- Replace visual selection with random 16-char alphanumeric string
    vim.keymap.set("x", "<leader>xr", function()
      math.randomseed(os.clock() * 1e7 + os.time())
      local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      local t = {}
      for i = 1, 16 do
        local idx = math.random(#chars)
        t[i] = chars:sub(idx, idx)
      end
      local s = table.concat(t)
      local keys = vim.api.nvim_replace_termcodes('"_c' .. s .. "<Esc>", true, false, true)
      vim.api.nvim_feedkeys(keys, "x", false)
    end, { desc = "Replace selection with random string" })

    -- DuckDB CSV column projection
    vim.keymap.set("n", "<leader>tq", function()
      local cols = vim.fn.input("select cols (e.g. url,tranco_today): ")
      if cols == "" then return end
      local tmp = vim.fn.tempname() .. ".csv"
      vim.fn.system(string.format(
        "duckdb -c \"COPY (SELECT %s FROM read_csv_auto('%s')) TO '%s' (HEADER)\"",
        cols, vim.fn.expand("%:p"), tmp
      ))
      vim.cmd("edit " .. tmp)
    end, { desc = "CSV: project cols via DuckDB" })

    -- ====================================================================
    -- ZT Profile: Complex autocmds
    -- ====================================================================

    -- macOS Sequoia: codesign treesitter parser .so files
    if vim.fn.has("mac") == 1 then
      local function sign_treesitter_parsers()
        local parser_dir = vim.fn.stdpath("data") .. "/site/parser"
        local handle = io.popen('ls "' .. parser_dir .. '"/*.so 2>/dev/null | head -1')
        if handle then
          local first = handle:read("*l")
          handle:close()
          if first then
            vim.fn.jobstart(
              { "sh", "-c", 'for f in "' .. parser_dir .. '"/*.so; do codesign -f -s - "$f" 2>/dev/null; done' },
              { detach = true }
            )
          end
        end
      end

      vim.api.nvim_create_user_command("TSCodesign", function()
        sign_treesitter_parsers()
        vim.notify("Signing treesitter parsers...")
      end, { desc = "Codesign treesitter parser .so files (macOS)" })

      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
          vim.schedule(function()
            local parser_dir = vim.fn.stdpath("data") .. "/site/parser"
            local result = vim.fn.system("codesign --verify " .. parser_dir .. "/lua.so 2>&1")
            if vim.v.shell_error ~= 0 then
              sign_treesitter_parsers()
            end
          end)
        end,
      })
    end

    -- zt-browsers profiles.toml: auto-sort by namespace/name on save
    vim.api.nvim_create_autocmd("BufWritePre", {
      pattern = "*/zt-browsers/profiles.toml",
      callback = function()
        local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local profiles = {}
        local current = nil
        for _, line in ipairs(buf_lines) do
          local is_marker = line:match("^# .+ %(%d+%) {{{$") or line:match("^# }}}$")
          if not is_marker then
            if line:match("^%[%[profiles%]%]$") then
              if current then table.insert(profiles, current) end
              current = { lines = { line }, name = "", namespace = "" }
            elseif current then
              if line ~= "" then
                table.insert(current.lines, line)
                local ns = line:match('^namespace%s*=%s*"([^"]*)"')
                if ns then current.namespace = ns end
                local nm = line:match('^name%s*=%s*"([^"]*)"')
                if nm then current.name = nm end
              end
            end
          end
        end
        if current then table.insert(profiles, current) end
        if #profiles == 0 then return end

        local groups, ns_order = {}, {}
        for _, p in ipairs(profiles) do
          local ns = p.namespace
          if not groups[ns] then groups[ns] = {}; table.insert(ns_order, ns) end
          table.insert(groups[ns], p)
        end
        table.sort(ns_order, function(a, b)
          if a == "" then return false end
          if b == "" then return true end
          return a:lower() < b:lower()
        end)
        for _, ns in ipairs(ns_order) do
          table.sort(groups[ns], function(a, b) return a.name:lower() < b.name:lower() end)
        end

        local out = {}
        for _, ns in ipairs(ns_order) do
          local label = ns ~= "" and ns or "ungrouped"
          local entries = groups[ns]
          table.insert(out, "# " .. label .. " (" .. #entries .. ") {{{")
          table.insert(out, "")
          for _, p in ipairs(entries) do
            for _, l in ipairs(p.lines) do table.insert(out, l) end
            table.insert(out, "")
          end
          table.insert(out, "# }}}")
          table.insert(out, "")
        end
        while #out > 0 and out[#out] == "" do table.remove(out) end
        table.insert(out, "")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, out)
      end,
    })

    -- Lazy-load hurl.nvim on FileType hurl
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "hurl",
      once = true,
      callback = function()
        vim.cmd("packadd hurl-nvim")
        require("hurl").setup({
          mode = "split",
          show_notification = false,
          formatters = { json = { "jq" } },
        })
      end,
    })

    -- Lazy-load nvim-sops on *.sops.yaml / *.sops.json only
    vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
      pattern = { "*.sops.yaml", "*.sops.json" },
      callback = function()
        if vim.g._sops_loaded then return end
        vim.g._sops_loaded = true
        vim.cmd("packadd nvim-sops")
        require("sops").setup({
          auto_decrypt = true,
          auto_encrypt = true,
        })
        vim.cmd("doautocmd BufReadPost " .. vim.fn.fnameescape(vim.fn.expand("%")))
      end,
    })

    -- Lazy-load videre on :Videre command
    vim.api.nvim_create_user_command("Videre", function(opts)
      vim.cmd("packadd videre-nvim")
      vim.cmd("delcommand Videre")
      vim.cmd("Videre " .. (opts.args or ""))
    end, { nargs = "?", desc = "JSON Graph Explorer (lazy)" })

    -- Lazy-load csvview.nvim on csv/tsv, auto-enable aligned table view
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "csv", "tsv" },
      callback = function(args)
        if not vim.g._csvview_loaded then
          vim.g._csvview_loaded = true
          vim.cmd("packadd csvview.nvim")
          require("csvview").setup({ view = { display_mode = "border" } })
        end
        if not require("csvview").is_enabled(args.buf) then
          require("csvview").enable(args.buf)
        end
        vim.keymap.set("n", "<leader>tv", "<cmd>CsvViewToggle<cr>",
          { buffer = args.buf, desc = "CSV: toggle table view", silent = true })
      end,
    })
  '';
}
