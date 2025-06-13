if exists("b:current_syntax")
  finish
endif

" Define the role marker matches (e.g., @System:)
syntax match ClaudiusRoleSystem '^@System:' contained
syntax match ClaudiusRoleUser '^@You:' contained
syntax match ClaudiusRoleAssistant '^@Assistant:' contained

" Define the Lua expression match for User messages
syntax match ClaudiusUserLuaExpression "{{.\{-}}}" contained

" Define the File Reference match for User messages: @./path or @../path, excluding trailing punctuation
" @\v(\.\.?\/)\S*[^[:punct:]\s]
" @                  - literal @
" \v                 - very magic
" (\.\.?\/)          - group: literal dot, optional literal dot, literal slash (./ or ../)
" \S*                - zero or more non-whitespace characters
" [^[:punct:]\s]     - a character that is NOT punctuation and NOT whitespace (ensures end is not punctuation)
syntax match ClaudiusUserFileReference "@\v(\.\.?\/)\S*[^[:punct:]\s]" contained

" Define Thinking Tags (for highlighting the tags themselves)
syntax match ClaudiusThinkingTag "^<thinking>$" contained
syntax match ClaudiusThinkingTag "^</thinking>$" contained

" Define Frontmatter Tags (for highlighting the delimiters themselves)
syntax match ClaudiusFrontmatterTag "^```lua$" contained
syntax match ClaudiusFrontmatterTag "^```$" contained

" Define regions
" Frontmatter Block Region (top-level)
" This region starts with ```lua on the first line of the file and ends with ```.
" It contains the tags themselves (ClaudiusFrontmatterTag) and Lua syntax for the content.
syntax region ClaudiusFrontmatterBlock start="\%1l^```lua$" end="^```$" keepend contains=ClaudiusFrontmatterTag,@Lua

" System region
syntax region ClaudiusSystem start='^@System:' end='\(^@\(You\|Assistant\):\)\@=\|\%$' contains=ClaudiusRoleSystem,@Markdown
" User region
syntax region ClaudiusUser start='^@You:' end='\(^@\(System\|Assistant\):\)\@=\|\%$' contains=ClaudiusRoleUser,ClaudiusUserLuaExpression,ClaudiusUserFileReference,@Markdown

" Thinking Block Region (nested inside Assistant)
" This region starts with <thinking> and ends with </thinking>.
" It contains the tags themselves (ClaudiusThinkingTag) and markdown for the content.
syntax region ClaudiusThinkingBlock start="^<thinking>$" end="^</thinking>$" keepend contains=ClaudiusThinkingTag,@Markdown

" Assistant region contains role markers, markdown, and thinking blocks
syntax region ClaudiusAssistant start='^@Assistant:' end='\(^@\(System\|You\):\)\@=\|\%$' contains=ClaudiusRoleAssistant,ClaudiusThinkingBlock,@Markdown

let b:current_syntax = "chat"
