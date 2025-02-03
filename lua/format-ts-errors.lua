local M = {}

M.config = {
  mappings = {
    show_diagnostic = "L",
    show_AI_diagnostic = ";h",
    goto_next = ";j",
    goto_prev = ";k",
  },

  anthropic_api_key = nil,
}

local function setup_move_listener()
  local function on_move()
    vim.g.diagnostic_ai_bufnr = nil
    vim.g.diagnostic_bufnr = nil
    vim.g.diagnostic_ai_question = nil
    print('Conversation accessible in g:diagnostic_ai_conversation')
  end

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    callback = on_move,
    group = vim.api.nvim_create_augroup("format-ts-errors-move-listener", {}),
    pattern = "*",
    once = true,
  })
end

local function make_request(api_key, prompt)
  -- Escape special characters in the prompt
  local escaped_prompt = prompt:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
  
  -- Prepare the request body
  local request_data = {
    model = "claude-3-sonnet-20240229",
    messages = {
      {
        role = "user",
        content = escaped_prompt
      }
    },
    max_tokens = 1000
  }
  
  -- Encode the request body
  local body = vim.json.encode(request_data)
  
  -- Make the request using curl with proper JSON escaping
  local cmd = string.format(
    'curl -s -X POST "https://api.anthropic.com/v1/messages" ' ..
    '-H "Content-Type: application/json" ' ..
    '-H "x-api-key: %s" ' ..
    '-H "anthropic-version: 2023-06-01" ' ..
    '--data %s',
    api_key,
    vim.fn.shellescape(body)
  )

  local response = vim.fn.system(cmd)
  local ok, decoded = pcall(vim.json.decode, response)
  
  if ok and decoded.content then
    return decoded.content[1].text
  else
    error(string.format("API request failed: %s", response))
  end
end

-- Function to ask Claude a question
function M.ask_claude(prompt)
  -- Get the API key from config or env variable
  local api_key = M.config.anthropic_api_key or os.getenv("ANTHROPIC_API_KEY")

  if not api_key then
    vim.notify("Anthropic API key not set. Please set it in the config or set the ANTHROPIC_API_KEY environment variable", vim.log.levels.ERROR)
    return nil
  end

  local ok, result = pcall(make_request, api_key, prompt)
  if ok then
    return result
  else
    vim.notify("Error making request: " .. result, vim.log.levels.ERROR)
    return nil
  end
end

local function parse_diagnostic_ai(diagnostic)
  -- Get context around the error
  local bufnr = vim.api.nvim_get_current_buf()
  local line = diagnostic.lnum + 1  -- Convert to 1-based line number
  local start_line = math.max(1, line - 50)
  local end_line = line + 50
  
  local context_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local context = table.concat(context_lines, '\n')



  local prompt = ([[
    You are a helpful programming assistant. Given the following TypeScript/JavaScript error and its context,
    provide a clear explanation that a developer can quickly understand.

    Format your response like this:
    - Start with the core issue on a single line (max 50 chars)
    - Add 1-2 lines explaining the cause
    - If applicable, show a quick fix in a code block
    - Use bullet points for multiple solutions

    Error message:
    ```
    ]] .. diagnostic.message .. [[
    ```

    Code context (error occurs at line ]] .. line .. [[):
    ```
    ]] .. context .. [[
    ```
  ]])

  local response = M.ask_claude(prompt)

  vim.g.diagnostic_ai_conversation = prompt .. "\n\nAI response:\n" .. response

  return response
end

local function parse_diagnostic_and_question_ai(diagnostic)
    -- Create a new prompt with the conversation history
    local prompt = string.format([[
Previous conversation about this error:
%s

Follow-up question: %s

Please provide a clear, concise answer focusing on the specific question while maintaining context of the error.
]], vim.g.diagnostic_ai_conversation, vim.g.diagnostic_ai_question)

    -- print(prompt)

    -- Get Claude's response
    local response = M.ask_claude(prompt)

    vim.g.diagnostic_ai_conversation = vim.g.diagnostic_ai_conversation .. "\n\nUser question:\n" .. vim.g.diagnostic_ai_question .. '\n\nAI response:\n' .. response

    return response
end

local function parse_diagnostic(diagnostic)
  -- Character by character
  local message = diagnostic.message

  -- Replacing ' by `
  message = message:gsub("'", '`')
  
  return message
end

function M.show_ai_diagnostic()
  if vim.g.diagnostic_bufnr then
    vim.api.nvim_buf_delete(vim.g.diagnostic_bufnr, {})
    vim.g.diagnostic_bufnr = nil
  end

  local bufnr = nil
  if vim.g.diagnostic_ai_bufnr then
    -- Get user's follow-up question
    local question = vim.fn.input("Ask for more details: ")
    if question == "" then
      return
    end

    vim.api.nvim_buf_delete(vim.g.diagnostic_ai_bufnr, {})
    vim.g.diagnostic_ai_bufnr = nil

    vim.g.diagnostic_ai_question = question

    bufnr = vim.diagnostic.open_float({
      scope = 'cursor',
      header = '',
      severity_sort = true,
      format = parse_diagnostic_and_question_ai
    })
  else
    bufnr = vim.diagnostic.open_float({
      scope = 'cursor',
      header = '',
      severity_sort = true,
      format = parse_diagnostic_ai
    })
  end

  vim.g.diagnostic_ai_bufnr = bufnr
  
  if bufnr == 0 or bufnr == nil then
    return
  end

  -- Changing filetype to markdown
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  -- Setting conceallevel to 3
  vim.api.nvim_buf_set_option(bufnr, 'conceallevel', 3)

  setup_move_listener()
end

function M.show_diagnostic()
  local diagnostics = vim.diagnostic.get()
  if #diagnostics == 0 then
    return
  end

  local bufnr = vim.diagnostic.open_float({
    scope = 'cursor',
    header = '',
    severity_sort = true,
    format = parse_diagnostic
  })
  vim.g.diagnostic_bufnr = bufnr
  
  if bufnr == 0 or bufnr == nil then
    return
  end

  -- Changing filetype to markdown
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  -- Setting conceallevel to 3
  vim.api.nvim_buf_set_option(bufnr, 'conceallevel', 3)

  setup_move_listener()
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

  vim.keymap.set("n", M.config.mappings.show_AI_diagnostic, ":lua require('format-ts-errors').show_ai_diagnostic()<CR>", opts)
  vim.keymap.set("n", M.config.mappings.show_diagnostic, ":lua require('format-ts-errors').show_diagnostic()<CR>", opts)
  vim.keymap.set("n", M.config.mappings.goto_next, ":lua require('format-ts-errors').goto_next()<CR>", opts)
  vim.keymap.set("n", M.config.mappings.goto_prev, ":lua require('format-ts-errors').goto_prev()<CR>", opts)

  vim.cmd('hi link DiagnosticFloatingError None')
  vim.cmd('hi link DiagnosticFloatingHint None')
  vim.cmd('hi link DiagnosticFloatingInfo None')
  vim.cmd('hi link DiagnosticFloatingWarn None')
end

function M.setup(user_opts)
  M.config = vim.tbl_extend("force", M.config, user_opts or {})

  M.setup_mappings()
end

return M
