return {
  {
    "folke/snacks.nvim",
    opts = {
      explorer = { enabled = false }, -- desativado: usando neo-tree no lugar
    },
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    keys = {
      -- Sobrescreve o padrão do LazyVim (dir = LazyVim.root()): quando o root
      -- detectado (LSP/.git/lua) erra, o neo-tree acaba vigiando/escaneando
      -- a árvore inteira a partir dali. Usar cwd é sempre o diretório onde
      -- o nvim foi aberto, sem esse risco.
      {
        "<leader>e",
        function()
          require("neo-tree.command").execute({ toggle = true, dir = vim.uv.cwd(), reveal = true })
        end,
        desc = "Explorer NeoTree (cwd)",
      },
    },
  },
}
