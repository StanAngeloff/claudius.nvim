# Changelog

## v25.06-1 – 2025-06-02

### Added

- **`@file` References:**
  - Implemented robust support for `@./path/to/file` references in user messages across all providers (Claude, OpenAI, Vertex AI).
  - Files are read, their MIME types detected (requires the `file` command-line utility), and content is base64 encoded for inclusion in API requests.
  - **Claude Provider:** Supports images (JPEG, PNG, GIF, WebP) and PDFs as `image` and `document` source types respectively. Text files (`text/*`) are embedded as text blocks.
  - **OpenAI Provider:** Supports images (JPEG, PNG, WebP, GIF) as `image_url` parts. Text files (`text/*`) are embedded as text parts. PDF files are also included as base64 encoded data (note: direct PDF support in chat completion API might vary by model).
  - **Vertex AI Provider:** Supports generic binary files as `inlineData` parts. Text files (`text/*`) are now sent as distinct text parts rather than `inlineData`.
  - File paths can be URL-encoded (e.g., spaces as `%20`) and will be automatically decoded.
  - Trailing punctuation in file paths (e.g., from ending a sentence with `@./file.txt.`) is ignored for robustness.
  - Notifications are shown if a file is not found, not readable, or its MIME type is unsupported by the provider for direct inclusion; in such cases, the raw `@./path/to/file` reference is sent as text.
  - Extracted MIME type detection to a new utility module `lua/claudius/mime.lua`.
- **Vertex AI "Thinking":**
  - Added support for Vertex AI's "thinking" feature (experimental model capability).
  - New `thinking_budget` parameter under `parameters.vertex` in `setup()` allows specifying a token budget for model thinking.
    - `nil` or `0` disables thinking by not sending the `thinkingConfig` to the API.
    - Values `>= 1` enable thinking with the specified budget (integer part taken).
  - When enabled, "thinking" from the model are streamed and displayed in the chat buffer, wrapped in `<thinking>...</thinking>` tags.
  - These `<thinking>` blocks are automatically stripped from assistant messages when they are part of the history sent in subsequent requests.
  - Thinking token usage is tracked and included in request/session cost calculations and notifications.
- **Lualine Integration:**
  - Added a Lualine component to display the currently active Claudius AI model.
  - The component is available as `require('lualine.components.claudius')` or simply `"claudius"`.
  - The model display is active only for `*.chat` buffers.
  - The display automatically refreshes when switching models/providers via `:ClaudiusSwitch`.
- **Configurable Timeouts:**
  - Made cURL `connect_timeout` (default: 10s) and `timeout` (response timeout, default: 120s) configurable.
  - These can be set globally in `setup()` under `parameters` or overridden per call with `:ClaudiusSwitch ... connect_timeout=X timeout=Y`.
- **New Models Supported:**
  - **Vertex AI:**
    - Added support for `gemini-2.5-pro-preview-05-06` (now the default Vertex AI model).
    - Added support for `gemini-2.5-flash-preview-04-17`.
  - Pricing information for these new models has been added.
- **Logging:**
  - Added `M.warn()` function to the logging module.

### Changed

- **README Overhaul:**
  - Significantly restructured and updated the README for clarity and completeness.
  - Added a new screenshot.
  - Reorganized sections: Installation, Requirements, Configuration, Usage.
  - Clarified API key storage with a `<details>` block for Linux `secret-tool`.
  - Moved plugin defaults into a `<details>` block.
  - Reordered and improved Usage sub-sections (Starting a New Chat, Commands and Keybindings, Switching Providers, Lualine Integration, Templating, File References, Importing).
  - Updated Lualine example to show icon usage: `{{ "claudius", icon = "🧠" }}`.
  - Documented new configuration options (`timeout`, `connect_timeout`, `thinking_budget`) and updated `:ClaudiusSwitch` examples.
- **Default Model:**
  - **Vertex AI:** Default model changed to `gemini-2.5-pro-preview-05-06`.
- **Visuals & Styling:**
  - Default ruler character (`ruler.char`) changed from `─` to `━` (Box Drawings Heavy Horizontal).
  - Default user sign character (`signs.user.char`) changed from `nil` (which defaulted to `▌`) to `▏` (Box Drawings Light Vertical).
  - Token usage and cost display in notifications is now better aligned for readability.
  - "Thoughts" token count in usage notifications is prefixed with the subset symbol `⊂` (e.g., "Output: X tokens (⊂ Y thoughts)").
- **Token Usage Display:**
  - Output token count in usage notifications now correctly includes any "thoughts" tokens.
  - Cost calculation for output tokens now correctly includes the cost of "thoughts" tokens.

### Fixed

- **Error Handling:**
  - Prevented a new `@You:` prompt from being added if an API error occurred during a request, even if the cURL command itself exited successfully.
  - Improved handling of cURL errors:
    - Spinner (`Thinking...` message) is now reliably cleaned up on cURL errors.
    - User is notified of cURL errors with more specific messages for common issues:
      - Code 6 (`CURLE_COULDNT_RESOLVE_HOST`): "cURL could not resolve host..."
      - Code 7 (`CURLE_COULDNT_CONNECT`): "cURL could not connect to host..."
      - Code 28 (Timeout): Message now includes the configured timeout value.
    - New `@You:` prompt is not added if the cURL request itself failed.
  - Updated error message for when the `file` command-line utility (for `@file` MIME type detection) is not found.
- **Internal:**
  - Corrected debug log messages in the `:ClaudiusSwitch` function.
  - Standardized API key parameter access within provider modules.
  - Unified OpenAI `data: [DONE]` message handling.
  - Switched from `vim.fn.base64encode` to `vim.base64.encode`.
  - Quoted filenames in various log messages for clarity.

## v25.04-1 – 2025-04-16

This release marks a major transition for Claudius, evolving from a Claude-specific plugin to a multi-provider AI chat interface within Neovim.

### Breaking Changes 💥

This version introduces significant internal refactoring and configuration changes. Please review the following and update your configuration if necessary:

1.  **Configuration Option Renames:**

    - The `prefix_style` option within `setup({})` has been renamed to `role_style`.
      - **Migration:** Rename `prefix_style` to `role_style` in your `require("claudius").setup({...})` call.
    - The `ruler.style` option within `setup({})` has been renamed to `ruler.hl`.
      - **Migration:** Rename `ruler.style` to `ruler.hl` in your `setup({})` call.

2.  **Highlight Group Renames (Affects Manual Linking Only):**

    - Internal syntax highlight groups used by `syntax/chat.vim` have been renamed from `Chat*` to `Claudius*` (e.g., `ChatSystem` ⇒ `ClaudiusSystem`, `ChatSystemPrefix` ⇒ `ClaudiusRoleSystem`).
    - **Migration:** This **only** affects users who were manually linking these highlight groups in their Neovim configuration (e.g., using `vim.cmd("highlight link ChatSystem MyCustomGroup")`). If you were doing this, update the source group name (e.g., `vim.cmd("highlight link ClaudiusSystem MyCustomGroup")`).
    - **Users configuring highlights _only_ via the `highlights` table in `setup()` are _not_ affected by this change.**

3.  **Configuration Structure (`model`, `provider`, `parameters`):**

    - A new top-level `provider` option specifies the AI provider (`"claude"`, `"openai"`, `"vertex"`). It defaults to `"claude"` for backward compatibility.
    - The `model` option now defaults based on the selected `provider` if set to `nil`. If you specify a `model`, ensure it's valid for the selected provider.
    - Provider-specific parameters (currently only for Vertex AI) are now nested (e.g., `parameters = { vertex = { project_id = "..." } }`).
    - **Migration:**
      - If you want to continue using Claude (the previous default), no action is strictly needed, but explicitly setting `provider = "claude"` is recommended for clarity.
      - If you had a specific `model` configured, ensure it's compatible with the default `claude` provider or explicitly set the correct `provider`.
      - If switching to Vertex AI, configure necessary parameters under `parameters.vertex = { ... }`.

4.  **Internal Function Relocation (Advanced Users Only):**
    - The Lua functions `get_fold_level` and `get_fold_text` were moved from the main `claudius` module to `claudius.buffers`.
    - **Migration:** If you were calling these functions directly in your Neovim config (e.g., `require("claudius").get_fold_level(...)`), update the call to use `require("claudius.buffers")` instead. Most users will not be affected.

### Added

- **Multi-Provider Support:** Claudius now supports multiple AI providers:
  - **Anthropic Claude:** Original provider.
  - **OpenAI:** Added support for various GPT models (e.g., `gpt-4o`, `gpt-3.5-turbo`).
  - **Google Vertex AI:** Added support for Gemini models (e.g., `gemini-2.5-pro`, `gemini-1.5-pro`).
- **Provider Switching (`:ClaudiusSwitch`):**
  - New command `:ClaudiusSwitch` allows switching the active AI provider and model on the fly.
  - Supports interactive selection via `vim.ui.select` when called with no arguments.
  - Allows specifying provider, model, and provider-specific parameters (e.g., `project_id` for Vertex) via arguments.
  - Includes command-line completion for providers and models.
- **Provider Configuration:**
  - New top-level `provider` option in `setup()` to set the default provider (`claude`, `openai`, `vertex`). Defaults to `claude`.
  - New `parameters.vertex` section in `setup()` for Vertex AI specific settings (`project_id`, `location`).
  - Configuration defaults are now centralized and provider-aware (e.g., default `model` depends on the selected `provider`).
- **Authentication:**
  - Generalized API key handling across providers.
  - Added support for retrieving OpenAI API keys via `OPENAI_API_KEY` environment variable or Linux `secret-tool` (`service openai key api`).
  - Added support for Vertex AI authentication:
    - Via `VERTEX_AI_ACCESS_TOKEN` environment variable.
    - Via service account JSON stored in `VERTEX_SERVICE_ACCOUNT` environment variable.
    - Via service account JSON stored using Linux `secret-tool` (`service vertex key api project_id <your_project_id>`). Requires `gcloud` CLI for token generation.
  - Improved authentication error messages using new modal alerts (`claudius.notify.alert`).
- **Highlighting & Styling:**
  - Highlight groups (`highlights.*`, `ruler.hl`) now accept hex color codes (e.g., `"#80a0ff"`) in addition to highlight group names.
  - Sign configuration (`signs.*.hl`) also accepts hex codes or specific highlight group names.
- **Notifications:**
  - Added `claudius.notify.alert()` function for displaying modal error/information windows with Markdown support.
  - Usage notifications now display the model name and provider.
  - Added syntax highlighting for model names in usage notifications (`syntax/claudius_notify.vim`).
- **Pricing Data:** Added pricing information for numerous OpenAI and Vertex AI models in `lua/claudius/pricing.lua`.
- **Logging:** Introduced a dedicated logging module (`lua/claudius/logging.lua`) with improved `inspect` formatting and configuration options.
- **Developer Environment:**
  - Added Nix configuration (`python-packages.nix`, updated `shell.nix`) for Python dependencies required for Vertex AI development (via Aider).
  - Added Aider configuration file (`.aider.conf.yml`).
  - Added `.env.example` and `.envrc` for easier setup.

### Changed

- **Core Architecture:** Major internal refactoring to introduce a provider abstraction layer (`lua/claudius/provider/`). API interaction logic is now handled by specific provider modules (`claude.lua`, `openai.lua`, `vertex.lua`) inheriting from a base class (`base.lua`).
- **Configuration:**
  - Centralized default configuration values in `lua/claudius/config.lua`.
  - Renamed `prefix_style` configuration option to `role_style` (See Breaking Changes).
  - Renamed `ruler.style` configuration option to `ruler.hl` (See Breaking Changes).
  - Clarified that setting `model`, `max_tokens`, or `temperature` to `nil` in `setup()` uses the provider's default value.
- **README:** Significantly updated to reflect multi-provider support, new configuration options, authentication methods, the `:ClaudiusSwitch` command, and developer setup.
- **Highlight Groups:** Renamed internal syntax highlight groups from `Chat*` to `Claudius*` (See Breaking Changes).
- **UI Updates:** Rulers and signs are now updated on `CursorHold` and `CursorHoldI` events, debouncing updates and improving performance, especially in large chat files.
- **Folding Logic:** Moved folding functions (`get_fold_level`, `get_fold_text`) from `init.lua` to `buffers.lua` (See Breaking Changes).
- **Command Descriptions:** Updated descriptions for `ClaudiusSend`, `ClaudiusCancel` to reflect multi-provider support.
- **Internal Naming:** Renamed internal variables like `prefix` to `role_type` for clarity.
- **Dependencies:** Updated Nix flake inputs (`flake.lock`).
- **Developer Scripts:** Updated `claudius-dev` (Aider wrapper) and `claudius-fmt` scripts in `shell.nix`.

### Fixed

- **UI Performance:** Debounced ruler and sign updates should reduce potential flickering and improve performance when editing chat files.
  - **Note:** Users may still experience syntax highlighting flicker, particularly when a `.chat` buffer is open in multiple windows scrolled to different positions. This is related to an upstream Neovim issue ([neovim/neovim#32660](https://github.com/neovim/neovim/issues/32660)) affecting Treesitter's handling of injections in recent nightly builds (as of 2025-04-16). A temporary workaround is to force synchronous parsing by setting `vim.g._ts_force_sync_parsing = true`. While the debouncing in Claudius might mitigate some visual artifacts, the root cause lies within Neovim core.
- **Error Handling:** More specific error reporting for authentication failures using modal alerts. Vertex AI provider includes handling for specific non-SSE error formats.
- **Cancellation:** Cancellation logic is now delegated to the provider implementation for potentially cleaner termination.
