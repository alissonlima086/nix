-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.g.lazyvim_picker = "telescope"

-- Desativa: sem indentexpr de treesitter pra a maioria dos filetypes, o
-- smartindent (heurística estilo C) erra o indent do `}`/`]` quando o
-- mini.pairs quebra a linha no <CR>, jogando um tab a mais nele.
vim.opt.smartindent = false

-- Sincroniza a área de transferência do Neovim com o Wayland (Hyprland / wl-copy)
vim.opt.clipboard = "unnamedplus"
