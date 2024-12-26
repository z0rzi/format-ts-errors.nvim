local M = {
}

M.config = {
  mappings = {
    show_diagnostic = "<C-l>",
  },
}

function M.show_diagnostic()
  vim.diagnostic.open_float()
end

function M.setup_mappings()
  local opts = { noremap = true }

  vim.keymap.set("n", M.config.mappings.show_diagnostic, ":lua require('format-ts-errors').show_diagnostic()<CR>", opts)
end

function M.setup(user_opts)
  M.config = vim.tbl_extend("force", M.config, user_opts or {})

  M.setup_mappings()
end

return M
