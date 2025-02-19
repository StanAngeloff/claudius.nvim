# Claudius 🤖

> **Note**: This entire plugin, including this README, was coded exclusively using [Aider](https://aider.chat). Exactly zero lines of code were written directly by a human!

A Neovim plugin providing a simple TUI for chatting with Claude, Anthropic's AI assistant. Claudius creates a natural chat-like interface right in your editor, with proper syntax highlighting and message folding.

<img src="assets/screenzy-1739995758256.png" alt="A screenshot of Claudius in action" />

## Requirements

Claudius requires:

- An Anthropic API key (set via ANTHROPIC_API_KEY environment variable)
- Tree-sitter for syntax highlighting

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
        system = "Special",    -- highlight group for system messages
        user = "Normal",       -- highlight group for user messages
        assistant = "Comment"  -- highlight group for Claude's responses
    },
    prefix_style = "bold,underline",  -- style applied to message prefixes
    ruler = {
        char = "─",           -- character used for the separator line
        style = "FoldColumn"  -- highlight group for the separator
    },
    model = "claude-3-sonnet-20240229",  -- Claude model to use
    keymaps = {
        normal = {
            send = "<C-]>",       -- Key to send message in normal mode
            cancel = "<C-c>",     -- Key to cancel ongoing request
            next_message = "]m",  -- Jump to next message
            prev_message = "[m",  -- Jump to previous message
        },
        insert = {
            send = "<C-]>"  -- Key to send message in insert mode
        },
        enable = true  -- Set to false to disable all keymaps
    }
})
```

## Usage

The plugin only works with files having the .chat extension. Create or open a .chat file and the plugin will automatically set up syntax highlighting and keybindings.

### Commands and Keybindings

The plugin provides several commands for interacting with Claude and managing chat content:

#### Core Commands

- `ClaudiusSend` - Send the current conversation to Claude
- `ClaudiusCancel` - Cancel an ongoing request
- `ClaudiusSendAndInsert` - Send to Claude and return to insert mode

#### Navigation Commands

- `ClaudiusNextMessage` - Jump to next message (`]m` by default)
- `ClaudiusPrevMessage` - Jump to previous message (`[m` by default)

#### Import Command

- `ClaudiusImport` - Convert a Claude Workbench API call into chat format

By default, the following keybindings are active in chat files:

- <kbd>Ctrl-]</kbd> - Send conversation (normal and insert mode)
- <kbd>Ctrl-C</kbd> - Cancel ongoing request
- <kbd>]m</kbd> - Jump to next message
- <kbd>[m</kbd> - Jump to previous message
- <kbd>im</kbd> - Text object for inside message content (customizable key)
- <kbd>am</kbd> - Text object for around message (customizable key)

You can disable the default keymaps by setting `keymaps.enable = false` and define your own:

```lua
-- Example custom keymaps
vim.keymap.set('n', '<Leader>cs', '<cmd>ClaudiusSend<cr>')
vim.keymap.set('n', '<Leader>cc', '<cmd>ClaudiusCancel<cr>')
vim.keymap.set('i', '<C-s>', '<cmd>ClaudiusSendAndInsert<cr>')
vim.keymap.set('n', '<Leader>cn', '<cmd>ClaudiusNextMessage<cr>')
vim.keymap.set('n', '<Leader>cp', '<cmd>ClaudiusPrevMessage<cr>')
vim.keymap.set('n', '<Leader>ci', '<cmd>ClaudiusSelectInMessage<cr>')
vim.keymap.set('n', '<Leader>ca', '<cmd>ClaudiusSelectMessage<cr>')
```

### Starting a New Chat

Start your conversation with a system message (optional):

```
@System: You are a helpful AI assistant.
```

Then add your first message:

```
@You: Hello Claude!
```

Messages are automatically folded for better overview. Press <kbd>za</kbd> to toggle folds.

### Importing from Claude Workbench

You can import conversations from the Claude Workbench (console.anthropic.com):

1. Open your saved prompt in the Workbench
2. Click the "Get Code" button
3. Change the language to TypeScript
4. Use the "Copy Code" button to copy the code snippet
5. Paste the code into a new buffer in Neovim
6. Run `:ClaudiusImport` to convert it to a .chat file

The command will parse the API call and convert it into Claudius's chat format.

## About

Claudius aims to provide a simple, native-feeling interface for having conversations with Claude directly in Neovim. The plugin focuses on being lightweight and following Vim/Neovim conventions.

---

_Keywords: claude tui, claude cli, claude terminal, claude vim, claude neovim, anthropic vim, anthropic neovim, ai vim, ai neovim, llm vim, llm neovim, chat vim, chat neovim_
