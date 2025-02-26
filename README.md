# Claudius 🤖

Transform Neovim into your AI conversation companion with a native interface to Claude. Key features:

🚀 **Instant Integration**

- Chat with Claude directly in your editor - no context switching
- Native Neovim feel with proper syntax highlighting and folding
- Automatic API key management via system keyring

⚡ **Power Features**

- Dynamic Lua templates in your prompts - embed code evaluation results
- Import/export compatibility with Claude Workbench
- Real-time token usage and cost tracking
- Message-based text objects and navigation

🛠️ **Developer Experience**

- Markdown rendering in responses
- Code block syntax highlighting
- Automatic buffer management
- Customizable keymaps and styling

<img src="assets/pretty_snap_2025_1_21_23_9.png" alt="A screenshot of Claudius in action" />

## Requirements

Claudius requires:

- An Anthropic API key (via ANTHROPIC_API_KEY environment variable, or manual input prompt)
- Neovim with Tree-sitter support (required for core functionality)
- Tree-sitter markdown parser (required for message formatting and syntax highlighting)

Optional Features:

- On Linux systems with libsecret installed, your API key can be stored and retrieved from the system keyring:
  ```bash
  secret-tool store --label="Anthropic API Key" service anthropic key api
  ```
  This will securely prompt for your API key and store it in the system keyring.

## Installation

Using your preferred package manager, for example with lazy.nvim:

```lua
{
    "StanAngeloff/claudius.nvim",
    opts = {},
}
```

## Configuration

The plugin works out of the box with sensible defaults, but you can customize various aspects:

```lua
require("claudius").setup({
    model = "claude-3-7-sonnet-20250219",  -- Claude model to use
    parameters = {
        max_tokens = 4000,  -- Maximum tokens in response
        temperature = 0.7,  -- Response creativity (0.0-1.0)
    },
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
    signs = {
        enabled = false,  -- enable sign column highlighting for roles (disabled by default)
        char = "▌",       -- default vertical bar character
        system = {
            char = nil,   -- use default char
            hl = true,    -- inherit from highlights.system, set false to disable
        },
        user = {
            char = nil,   -- use default char
            hl = true,    -- inherit from highlights.user, set false to disable
        },
        assistant = {
            char = nil,   -- use default char
            hl = true,    -- inherit from highlights.assistant, set false to disable
        }
    },
    editing = {
        disable_textwidth = true,  -- Whether to disable textwidth in chat buffers
        auto_write = false,        -- Whether to automatically write the buffer after changes
    },
    pricing = {
        enabled = true,  -- Whether to show pricing information in notifications
    },
    notify = {
        enabled = true,      -- Enable/disable notifications
        timeout = 8000,      -- How long notifications stay visible (ms)
        max_width = 60,      -- Maximum width of notification windows
        padding = 1,         -- Padding around notification text
        border = "rounded",  -- Border style (same as nvim_open_win)
        title = nil,         -- Default title (nil for none)
    },
    text_object = "m",  -- Default text object key, set to false to disable
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
        enabled = true  -- Set to false to disable all keymaps
    }
})
```

### Templating and Dynamic Content

Chat files support two powerful features for dynamic content:

1. Lua Frontmatter - Define variables and functions at the start of your chat file
2. Expression Templates - Use `{{expressions}}` inside messages to evaluate Lua code

#### Lua Frontmatter

Start your chat file with a Lua code block between ` ```lua ` and ` ``` ` markers:

````markdown
```lua
greeting = "Hello, World!"  -- Must be global (no local keyword)
count = 42
```

@You: The greeting is: {{greeting}}
@Assistant: The greeting mentioned is: "Hello, World!"

@You: The count is: {{count}}
@Assistant: The count is: 42
````

Variables defined in the frontmatter are available to all expression templates in the file. Note that variables must be global (do not use the `local` keyword).

#### Expression Templates

Use `{{expression}}` syntax inside any message to evaluate Lua code:

```markdown
@You: Convert this to uppercase: {{string.upper("hello")}}
@Assistant: The text "HELLO" is already in uppercase.

@You: Calculate: {{math.floor(3.14159 * 2)}}
@Assistant: You've provided the number 6
```

The expression environment is restricted to safe operations focused on string manipulation, basic math, and table operations. Available functions include:

- String operations (upper, lower, sub, gsub, etc)
- Table operations (concat, insert, remove, sort)
- Math functions (abs, ceil, floor, max, min, etc)
- UTF-8 support
- Essential functions (assert, error, ipairs, pairs, etc)

While you can define functions in the frontmatter, the focus is on simple templating rather than complex programming:

````markdown
```lua
function greet(name)
    return string.format("Hello, %s!", name)
end
```

@You: {{greet("Claude")}}
@Assistant: Hello! It's nice to meet you.
````

## Usage

The plugin only works with files having the .chat extension. Create or open a .chat file and the plugin will automatically set up syntax highlighting and keybindings.

### Commands and Keybindings

The plugin provides several commands for interacting with Claude and managing chat content:

#### Core Commands

- `ClaudiusSend` - Send the current conversation to Claude
- `ClaudiusCancel` - Cancel an ongoing request
- `ClaudiusSendAndInsert` - Send to Claude and return to insert mode
- `ClaudiusRecallNotification` - Recall the last notification (useful for reviewing usage statistics)

#### Navigation Commands

- `ClaudiusNextMessage` - Jump to next message (<kbd>]m</kbd> by default)
- `ClaudiusPrevMessage` - Jump to previous message (<kbd>[m</kbd> by default)

#### Import Command

- `ClaudiusImport` - Convert a Claude Workbench API call into chat format

#### Logging Commands

- `ClaudiusEnableLogging` - Enable logging of API requests and responses
- `ClaudiusDisableLogging` - Disable logging (default state)
- `ClaudiusOpenLog` - Open the log file in a new tab

Logging is disabled by default to prevent sensitive data from being written to disk. When troubleshooting issues:

1. Enable logging with `:ClaudiusEnableLogging`
2. Reproduce the problem
3. Check the log with `:ClaudiusOpenLog`
4. Disable logging with `:ClaudiusDisableLogging` when done

The log file is stored at `~/.cache/nvim/claudius.log` (or equivalent on your system) and contains:

- API request details
- Response data
- Error messages
- Timing information

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
```

### Starting a New Chat

Start your conversation with a system message (optional):

```markdown
@System: You are a helpful AI assistant.
```

Then add your first message:

```markdown
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

## Contributing

### Development Setup

The project uses Nix for development environment management. This ensures all contributors have access to the same tools and versions.

#### Prerequisites

1. Install [Nix](https://nixos.org/download.html)
2. Set up your Anthropic API key:
   ```bash
   export ANTHROPIC_API_KEY=your_key_here
   ```

#### Development Workflow

1. Enter the development environment:

   ```bash
   nix develop
   ```

2. Available development commands:
   - `claudius-dev`: Starts an Aider session with the correct files loaded
   - `claudius-fmt`: Reformats the codebase using:
     - nixfmt for .nix files
     - stylua for Lua files
     - prettier for Markdown

#### Quick Testing

You can test changes without installing the plugin by running:

```bash
nvim --cmd "set runtimepath+=`pwd`" -c 'lua require("claudius").setup({})' -c ':edit example.chat'
```

This command:

- Adds the current directory to Neovim's runtime path
- Loads and configures the plugin
- Opens a new chat file ready for testing

### Development Guidelines

This project represents a unique experiment in AI-driven development. From its inception to the present day, every single line of code has been written using [Aider](https://aider.chat), demonstrating the potential of AI-assisted development in creating quality software.

While I encourage contributors to explore AI-assisted development, particularly with Aider, I welcome all forms of quality contributions. The project's development guidelines are:

1. **Consider Using Aider**: I recommend trying [Aider](https://aider.chat) for making changes - it's how this entire project was built
2. **Document AI Interactions**: If using AI tools, keep chat logs of significant conversations
3. **Use Formatting Tools**: Run `claudius-fmt` before committing to maintain consistent style
4. **Test Changes**: Use the quick testing command above to verify functionality
5. **Keep Focus**: Make small, focused changes in each development session

> **Note**: This project started as an experiment in pure AI-driven development, and to this day, every line of code has been written exclusively through Aider. I continue to maintain this approach in my own development while welcoming contributions from all developers who share a commitment to quality.

The goal is to demonstrate how far we can push AI-assisted development while maintaining code quality. Whether you choose to work with AI or write code directly, focus on creating clear, maintainable solutions.

---

_Keywords: claude tui, claude cli, claude terminal, claude vim, claude neovim, anthropic vim, anthropic neovim, ai vim, ai neovim, llm vim, llm neovim, chat vim, chat neovim_
