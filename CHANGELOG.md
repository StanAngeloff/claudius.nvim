# Changelog

## v0.2 – 2025-04-16

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
