return {
  -- C# is configured with Microsoft's Roslyn language server, rather than
  -- the OmniSharp-based LazyVim .NET extra.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        roslyn_ls = {},
        gopls = {
          -- Ativa o LSP apenas se 'go' estiver disponível no PATH (evita erro fora de flakes/devShells)
          enabled = vim.fn.executable("go") == 1,
          settings = {
            gopls = {
              usePlaceholders = true, -- preenche parâmetros da função ao aceitar o completion
              completeUnimported = true, -- sugere (e importa) pacotes que você ainda não importou
              staticcheck = true, -- lints extras, ajuda o completion a ser mais preciso
              gofumpt = true, -- formatação mais rígida que o gofmt padrão
              analyses = {
                unusedparams = true,
              },
            },
          },
        },
      },
    },
  },
  -- Autocomplete/settings extras pro Java (jdtls, vem do extra lang.java)
  {
    "mfussenegger/nvim-jdtls",
    -- Ativa o jdtls apenas se 'java' estiver disponível no PATH (evita erro fora de flakes/devShells)
    enabled = vim.fn.executable("java") == 1,
    opts = {
      settings = {
        java = {
          completion = {
            guessMethodArguments = true, -- preenche argumentos de método ao completar
            favoriteStaticMembers = {
              "org.junit.jupiter.api.Assertions.*",
              "java.util.Objects.requireNonNull",
            },
          },
          format = {
            enabled = true, -- deixa o jdtls formatar (indentação, chaves, etc.)
          },
        },
      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "roslyn-language-server",
      },
    },
  },

  -- The other requested languages are covered by LazyVim and its selected extras.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "c_sharp",
      },
    },
  },
}
