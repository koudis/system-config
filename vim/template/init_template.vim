lua << EOF
-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Configure lazy.nvim plugins
require("lazy").setup({
  -- Snippets
  {
    "SirVer/ultisnips",
    dependencies = { "honza/vim-snippets" },
    config = function()
      vim.g.UltiSnipsExpandTrigger = "<c-a>"
    end,
  },

  -- Commenter which works with visual mode etc.
  { "scrooloose/nerdcommenter" },

  -- File explorer options
  {
    "scrooloose/nerdtree",
    dependencies = { "jistr/vim-nerdtree-tabs" },
    config = function()
      -- Close all open buffers on entering a window if the only
      -- buffer that's left is the NERDTree buffer
      vim.api.nvim_create_autocmd("WinEnter", {
        callback = function()
          if vim.fn.exists("t:NERDTreeBufName") == 1 then
            if vim.fn.bufwinnr(vim.t.NERDTreeBufName) ~= -1 then
              if vim.fn.winnr("$") == 1 then
                vim.cmd("q")
              end
            end
          end
        end,
      })

      vim.g.nerdtree_tabs_autoclose = 1
      vim.g.nerdtree_tabs_open_on_console_startup = 1
    end,
  },

  -- Alternative: chadtree (commented out)
  -- {
  --   "ms-jpq/chadtree",
  --   branch = "chad",
  --   build = "python3 -m chadtree deps",
  -- },

  -- Neo-tree (modern file explorer)
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
  },

  -- Status line
  {
    "vim-airline/vim-airline",
    dependencies = { "vim-airline/vim-airline-themes" },
    config = function()
      vim.g.airline_theme = "dark"
      vim.g.airline_powerline_fonts = 1
    end,
  },

  -- Better icons (commented out)
  -- { "ryanoasis/vim-devicons" },

  -- Auto-completion
  {
    "Shougo/deoplete.nvim",
    build = ":UpdateRemotePlugins",
    config = function()
      vim.g["deoplete#enable_at_startup"] = 1
    end,
  },

  -- Fuzzy file finder
  {
    "junegunn/fzf",
    build = function()
      vim.fn["fzf#install"]()
    end,
  },
  {
    "junegunn/fzf.vim",
    dependencies = { "junegunn/fzf" },
    config = function()
      vim.g.fzf_action = {
        ["ctrl-t"] = "tab split",
        ["ctrl-x"] = "split",
        ["ctrl-v"] = "vsplit",
      }
    end,
  },

  -- Tabular support
  { "godlygeek/tabular" },

  -- Markdown support
  {
    "plasticboy/vim-markdown",
    dependencies = { "godlygeek/tabular" },
  },

  -- Treesitter for better syntax highlighting
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
  },

  -- Dev Container support
  {
    "https://codeberg.org/esensar/nvim-dev-container",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
  },

  -- AI assistants
  { "augmentcode/augment.vim" },
  { "daltonkyemiller/claude-code.nvim" },
}, {
  -- Lazy.nvim configuration options
  root = "___VIM_BASE_DIR___/plugin",
  install = {
    missing = true,
  },
})

-- General Vim settings
vim.opt.background = "dark"
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.fileformats = { "unix", "dos" }
vim.opt.fileencodings = { "UTF-8", "latin1" }
vim.opt.encoding = "UTF-8"
vim.opt.number = true
vim.opt.wrap = false
vim.opt.autowrite = true
vim.opt.mouse = "a"

EOF
