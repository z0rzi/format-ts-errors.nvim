# format-ts-errors.nvim

A very simple Neovim plugin to explain your errors using AI.

## Requirements

This plugin uses `curl` to call the Anthropic API.

You will also need an Anthropic API key.

## Installation

Using Lazy.nvim:
```lua
{
    'z0rzi/format-ts-errors.nvim',
    config = function()
        require('format-ts-errors').setup({
            mappings = {
                show_diagnostic = "L", -- Show the diagnostic under the cursor
                show_AI_diagnostic = ";h", -- Asks Claude to explain the diagnostic under the cursor
                goto_next = ";j", -- Go to the next diagnostic
                goto_prev = ";k", -- Go to the previous diagnostic
            },

            anthropic_api_key = nil, -- You can also define it as an environment variable (ANTHROPIC_API_KEY)
        })

        -- Optional, to enable highlighting of the types (requires treesitter)
        vim.g.markdown_fenced_languages = { 'typescript' }
    end,
},
```

## How it works

This plugin uses the Anthropic API to generate a comprehensive explanation of the error under the cursor.
If you hit the `show_AI_diagnostic` keymap, multiple times in a row, you can ask follow-up questions to the AI.
