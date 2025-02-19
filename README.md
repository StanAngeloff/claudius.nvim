# Claudius 🤖

> **Note**: This entire plugin, including this README, was coded exclusively using [Aider](https://aider.chat). Exactly zero lines of code were written directly by a human!

A Neovim plugin providing a simple TUI for chatting with Claude, Anthropic's AI assistant. Claudius creates a natural chat-like interface right in your editor, with proper syntax highlighting and message folding.

<img src="screenzy-1739995758256.png" alt="A screenshot of Claudius in action" />

## Requirements

Claudius requires an Anthropic API key to function. You'll need to set the ANTHROPIC_API_KEY environment variable with your key before using the plugin.

## Installation

Using your preferred package manager, for example with lazy.nvim:

```lua
{
    "StanAngeloff/claudius.nvim",
    config = function()
        require("claudius").setup()
    end
}
```

## Configuration

The plugin works out of the box with sensible defaults, but you can customize various aspects:

```lua
require("claudius").setup({
    highlights = {
        system = "Special",  -- highlight group for system messages
        user = "Normal",     -- highlight group for user messages
        assistant = "Comment" -- highlight group for Claude's responses
    },
    prefix_style = "bold,underline", -- style applied to message prefixes
    ruler = {
        char = "─",         -- character used for the separator line
        style = "FoldColumn" -- highlight group for the separator
    },
    model = "claude-3-sonnet-20240229", -- Claude model to use
    keymaps = {
        normal = {
            send = "<C-]>",    -- Key to send message in normal mode
            cancel = "<C-c>"   -- Key to cancel ongoing request
        },
        insert = {
            send = "<C-]>"     -- Key to send message in insert mode
        },
        enable = true          -- Set to false to disable all keymaps
    }
})
```

## Usage

The plugin only works with files having the .chat extension. Create or open a .chat file and the plugin will automatically set up syntax highlighting and keybindings.

Start your conversation with a system message (optional):
```
@System: You are a helpful AI assistant.
```

Then add your first message:
```
@You: Hello Claude!
```

By default, press <kbd>Ctrl-]</kbd> to send the conversation to Claude and <kbd>Ctrl-C</kbd> to cancel an ongoing request.

If you prefer to set up your own keymaps, you can disable the default ones by setting `keymaps.enable = false` and use these commands in your configuration:

```lua
-- Map to your preferred keys
vim.keymap.set('n', '<Leader>cs', '<cmd>ClaudiusSend<cr>')
vim.keymap.set('n', '<Leader>cc', '<cmd>ClaudiusCancel<cr>')
vim.keymap.set('i', '<C-s>', '<cmd>ClaudiusSendAndInsert<cr>')
```

Messages are automatically folded for better overview. Press <kbd>za</kbd> to toggle folds.

## About

Claudius aims to provide a simple, native-feeling interface for having conversations with Claude directly in Neovim. The plugin focuses on being lightweight and following Vim/Neovim conventions.

---

_Keywords: claude tui, claude cli, claude terminal, claude vim, claude neovim, anthropic vim, anthropic neovim, ai vim, ai neovim, llm vim, llm neovim, chat vim, chat neovim_
