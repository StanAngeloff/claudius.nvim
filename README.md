# Claudius 🤖

A Neovim plugin providing a simple TUI for chatting with Claude, Anthropic's AI assistant. Claudius creates a natural chat-like interface right in your editor, with proper syntax highlighting and message folding.

# Requirements

Claudius requires an Anthropic API key to function. You'll need to set the ANTHROPIC_API_KEY environment variable with your key before using the plugin.

# Installation

Using your preferred package manager, for example with lazy.nvim:

```lua
{
    "StanAngeloff/claudius.nvim",
    config = function()
        require("claudius").setup()
    end
}
```

# Configuration

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
    model = "claude-3-sonnet-20240229" -- Claude model to use
})
```

# Usage

The plugin only works with files having the .chat extension. Create or open a .chat file and the plugin will automatically set up syntax highlighting and keybindings.

Start your conversation with a system message (optional):
```
@System: You are a helpful AI assistant.
```

Then add your first message:
```
@You: Hello Claude!
```

Press Ctrl-] to send the conversation to Claude. Use Ctrl-c to cancel an ongoing request.

Messages are automatically folded for better overview. Press za to toggle folds.

# About

Claudius aims to provide a simple, native-feeling interface for having conversations with Claude directly in Neovim. The plugin focuses on being lightweight and following Vim/Neovim conventions.

Keywords: claude tui, claude cli, claude terminal, claude vim, claude neovim, anthropic vim, anthropic neovim, ai vim, ai neovim, llm vim, llm neovim, chat vim, chat neovim
