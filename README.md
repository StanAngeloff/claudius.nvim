# Claudius 🤖

Transform Neovim into your AI conversation companion with a native interface to multiple AI providers. Key features:

| 🚀 Instant Integration                                         | ⚡ Power Features                                                     | 🛠️ Developer Experience          |
| -------------------------------------------------------------- | --------------------------------------------------------------------- | -------------------------------- |
| Chat with multiple AI providers directly in your editor        | Dynamic Lua templates in your prompts - embed code evaluation results | Markdown rendering in responses  |
| Support for Claude, OpenAI, and Google Vertex AI models        | Import/export compatibility with Claude Workbench                     | Code block syntax highlighting   |
| Native Neovim feel with proper syntax highlighting and folding | Real-time token usage and cost tracking                               | Automatic buffer management      |
| Automatic API key management via system keyring                | Message-based text objects and navigation                             | Customizable keymaps and styling |
| `@file` references for embedding images, PDFs, and text        | Lualine component for model display                                   |                                  |

<img src="assets/pretty_snap_2025_1_21_23_9.png" alt="A screenshot of Claudius in action" />

## Requirements

Claudius requires:

- An API key for your chosen provider:
  - Anthropic API key (via ANTHROPIC_API_KEY environment variable)
  - OpenAI API key (via OPENAI_API_KEY environment variable)
  - Google Vertex AI access token (via VERTEX_AI_ACCESS_TOKEN environment variable) or service account credentials
- Neovim with Tree-sitter support (required for core functionality)
- Tree-sitter markdown parser (required for message formatting and syntax highlighting)
- The `file` command-line utility (for MIME type detection used by `@file` references)

Optional Features:

- On Linux systems with libsecret installed, your API key can be stored and retrieved from the system keyring:

  For Anthropic:

  ```bash
  secret-tool store --label="Anthropic API Key" service anthropic key api
  ```

  For OpenAI:

  ```bash
  secret-tool store --label="OpenAI API Key" service openai key api
  ```

  For Google Vertex AI (store service account JSON):

  ```bash
  secret-tool store --label="Vertex AI Service Account" service vertex key api project_id your_project_id
  ```

  This will securely prompt for your API key and store it in the system keyring.

- For Google Vertex AI, the Google Cloud CLI (`gcloud`) is required if using service account authentication.

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
    provider = "claude",  -- AI provider: "claude", "openai", or "vertex"
    model = nil,  -- Uses provider defaults if nil (see below)
    -- Claude default: "claude-3-7-sonnet-20250219"
    -- OpenAI default: "gpt-4o"
    -- Vertex default: "gemini-2.5-pro-preview-05-06"
    parameters = {
        max_tokens = nil,  -- Set to nil to use default (4000)
        temperature = nil,  -- Set to nil to use default (0.7)
        vertex = {
            project_id = nil,  -- Google Cloud project ID (required for Vertex AI)
            location = "us-central1",  -- Google Cloud region
        },
    },
    highlights = {
        system = "Special",    -- highlight group or hex color (e.g., "#80a0ff") for system messages
        user = "Normal",       -- highlight group or hex color for user messages
        assistant = "Comment"  -- highlight group or hex color for assistant messages
    },
    role_style = "bold,underline",  -- style applied to role markers like @You:
    ruler = {
        char = "━",           -- character used for the separator line
        hl = "NonText"        -- highlight group or hex color for the separator
    },
    signs = {
        enabled = false,  -- enable sign column highlighting for roles (disabled by default)
        char = "▌",       -- default vertical bar character
        system = {
            char = nil,   -- use default char
            hl = true,    -- inherit from highlights.system, set false to disable, or provide specific group/hex color
        },
        user = {
            char = "▏",   -- use default char
            hl = true,    -- inherit from highlights.user, set false to disable, or provide specific group/hex color
        },
        assistant = {
            char = nil,   -- use default char
            hl = true,    -- inherit from highlights.assistant, set false to disable, or provide specific group/hex color
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

### File References with `@file`

You can embed content from local files directly into your messages using the `@./path/to/file` syntax. This feature requires the `file` command-line utility to be installed for MIME type detection.

**Syntax:**

-   File paths must start with `./` (current directory) or `../` (parent directory).
-   Example: `@./images/diagram.png` or `@../documents/report.pdf`
-   File paths can be URL-encoded (e.g., spaces as `%20`) and will be automatically decoded.
-   Trailing punctuation in file paths (e.g., from ending a sentence with `@./file.txt.`) is ignored.

**Provider Support:**

-   **Claude & OpenAI:**
    -   Images: JPEG, PNG, GIF, WebP
    -   Documents: PDF
    -   Text: Plain text files (e.g., `.txt`, `.md`, `.lua`) are embedded as text.
-   **Vertex AI:**
    -   Supports generic binary files (sent as `inlineData` with detected MIME type).
    -   Text files (MIME type `text/*`) are embedded as text parts.

If a file is not found, not readable, or its MIME type is unsupported by the provider for direct inclusion, the raw `@./path/to/file` reference will be sent as text, and a notification will be shown.

Example:

```markdown
@You: Please analyze this image: @./screenshots/error.png and this document: @./specs/project%20brief.pdf
```

## Usage

The plugin only works with files having the .chat extension. Create or open a .chat file and the plugin will automatically set up syntax highlighting and keybindings.

### Commands and Keybindings

The plugin provides several commands for interacting with AI providers and managing chat content:

#### Core Commands

- `ClaudiusSend` - Send the current conversation to the configured AI provider
- `ClaudiusCancel` - Cancel an ongoing request
- `ClaudiusSendAndInsert` - Send to AI and return to insert mode
- `ClaudiusSwitch` - Switch between providers (e.g., `:ClaudiusSwitch openai gpt-4o`). If called with no arguments, it provides an interactive selection menu.
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

### Switching Providers

You can switch between AI providers at any time using the `:ClaudiusSwitch` command:

```
:ClaudiusSwitch	# Interactive provider/model selection
:ClaudiusSwitch claude	# Switch to Claude with default model
:ClaudiusSwitch openai gpt-4o	# Switch to OpenAI with specific model
:ClaudiusSwitch vertex gemini-2.5-pro-preview-05-06 project_id=my-project	# Switch to Vertex AI with project ID
:ClaudiusSwitch claude claude-3-7-sonnet-20250219 temperature=0.2 max_tokens=1000	# Multiple parameters
```

This allows you to compare responses from different AI models without restarting Neovim.

### Importing from Claude Workbench

You can import conversations from the Claude Workbench (console.anthropic.com):

1. Open your saved prompt in the Workbench
2. Click the "Get Code" button
3. Change the language to TypeScript
4. Use the "Copy Code" button to copy the code snippet
5. Paste the code into a new buffer in Neovim
6. Run `:ClaudiusImport` to convert it to a .chat file

The command will parse the API call and convert it into Claudius's chat format.

### Lualine Integration

Claudius includes a component to display the currently active AI model in your Lualine status bar. To use it, add the component to your Lualine configuration:

```lua
-- Example Lualine setup
require('lualine').setup {
  options = {
    -- ... your other options
  },
  sections = {
    lualine_a = {'mode'},
    -- ... other sections
    lualine_x = {require('lualine.components.claudius'), 'encoding', 'filetype'}, -- Add Claudius model component
    -- ... other sections
  },
  -- ...
}
```
The model display is active only for `*.chat` buffers.

## About

Claudius aims to provide a simple, native-feeling interface for having conversations with AI models directly in Neovim. Originally built for Claude (hence the name), it now supports multiple AI providers including OpenAI and Google Vertex AI. The plugin focuses on being lightweight and following Vim/Neovim conventions.

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

_Keywords: claude tui, claude cli, claude terminal, claude vim, claude neovim, anthropic vim, anthropic neovim, ai vim, ai neovim, llm vim, llm neovim, chat vim, chat neovim, openai vim, openai neovim, gpt vim, gpt neovim, vertex ai vim, vertex ai neovim, gemini vim, gemini neovim_
