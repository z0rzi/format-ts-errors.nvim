local M = {}

M.config = {
  prettier_path = "prettier",
  mappings = {
    show_diagnostic = "L",
    goto_next = ";j",
    goto_prev = ";k",
  },
}

local function format_type(type)
  -- Replacing non-ts formations by "@ ... @".
  -- Otherwise, prettier will not be able to format the type.

  type = type:gsub('{ %.%.%.; }', '"@{ ...; }@"')
  type = type:gsub('%[%.%.%.%]', '"@[...]@"')
  type = type:gsub('%.%.%. %d+ more %.%.%.', '"@ ... @"')
  type = type:gsub('<%.%.%.>', '<"@...@">')

  local tmp_file = vim.fn.tempname()

  -- Putting the type in /tmp/diagnostic.ts
  vim.fn.writefile({'type A = ' .. type}, tmp_file, 'a')

  -- Running prettier on /tmp/diagnostic.ts
  local result = vim.fn.system(M.config.prettier_path .. ' --parser typescript --write ' .. tmp_file)

  -- Getting the result
  local formatted_type = vim.fn.readfile(tmp_file)

  local result = vim.fn.join(formatted_type, '\n')

  -- Stripping the prefix
  result = result:gsub('type A = ', '')

  -- Replacing back the non-ts formations
  result = result:gsub('"@', '')
  result = result:gsub('@"', '')
  
  return result
end

local function parse_diagnostic(diagnostic)
  -- Character by character
  local prev_char = diagnostic.message:sub(1, 1)
  local type_buffer = nil

  local message = prev_char

  for i = 2, diagnostic.message:len() do
    local char = diagnostic.message:sub(i, i)

    if type_buffer then
      -- We are in a type

      if char == "'" and (prev_char == '}' or prev_char == '}') then
        -- This is the end of the type... probably
        local formatted_type = format_type(type_buffer)
        message = message .. '\n```typescript\n' .. formatted_type .. '\n```\n' 
        type_buffer = nil
      else
        type_buffer = type_buffer .. char
      end
    else
      -- We are not in a type
      if prev_char == "'" and (char == '{' or char == '[') then
        -- This is the start of a type... probably
        type_buffer = char
        -- Removing the last char of message (the quote)
        message = message:sub(1, message:len() - 1)
      else
        message = message .. char
      end
    end

    prev_char = char
  end

  -- Replacing ' by `
  message = message:gsub("'", '`')
  
  return message
end

function M.show_diagnostic()
  local bufnr = vim.diagnostic.open_float({
    scope = 'cursor',
    header = '',
    severity_sort = true,
    format = parse_diagnostic
  })
  
  if bufnr == 0 or bufnr == nil then
    return
  end

  -- Changing filetype to markdown
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  -- Setting conceallevel to 3
  vim.api.nvim_buf_set_option(bufnr, 'conceallevel', 3)

  vim.cmd('hi link DiagnosticFloatingError None')
  vim.cmd('hi link DiagnosticFloatingHint None')
  vim.cmd('hi link DiagnosticFloatingInfo None')
  vim.cmd('hi link DiagnosticFloatingWarn None')
end

function M.goto_next()
  local diagnostics = vim.diagnostic.get()
  if #diagnostics == 0 then
    return
  end
  vim.diagnostic.goto_next({
    float = false
  })
  vim.defer_fn(function()
    M.show_diagnostic()
  end, 100)
end

function M.goto_prev()
  local diagnostics = vim.diagnostic.get()
  if #diagnostics == 0 then
    return
  end
  vim.diagnostic.goto_prev({
    float = false
  })
  vim.defer_fn(function()
    M.show_diagnostic()
  end, 100)
end

function M.setup_mappings()
  local opts = { noremap = true }

  vim.keymap.set("n", M.config.mappings.show_diagnostic, ":lua require('format-ts-errors').show_diagnostic()<CR>", opts)
  vim.keymap.set("n", M.config.mappings.goto_next, ":lua require('format-ts-errors').goto_next()<CR>", opts)
  vim.keymap.set("n", M.config.mappings.goto_prev, ":lua require('format-ts-errors').goto_prev()<CR>", opts)
end

function M.setup(user_opts)
  M.config = vim.tbl_extend("force", M.config, user_opts or {})

  M.setup_mappings()
end

return M
