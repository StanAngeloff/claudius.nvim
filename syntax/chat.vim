if exists("b:current_syntax")
  finish
endif

" Define the role marker matches (e.g., @System:)
syntax match ClaudiusRoleSystem '^@System:' contained
syntax match ClaudiusRoleUser '^@You:' contained
syntax match ClaudiusRoleAssistant '^@Assistant:' contained

" Define the Lua expression match
syntax match ClaudiusLuaExpression "{{.\{-}}}" contained

" Define the File Reference match: @./path or @../path, excluding trailing punctuation
" @\v(\.\.?\/)\S*[^[:punct:]\s]
" @                  - literal @
" \v                 - very magic
" (\.\.?\/)          - group: literal dot, optional literal dot, literal slash (./ or ../)
" \S*                - zero or more non-whitespace characters
" [^[:punct:]\s]     - a character that is NOT punctuation and NOT whitespace (ensures end is not punctuation)
syntax match ClaudiusFileReference "@\v(\.\.?\/)\S*[^[:punct:]\s]" contained

" Define regions that contain role markers, Lua expressions, file references, and markdown
syntax region ClaudiusSystem start='^@System:' end='\(^@\(You\|Assistant\):\)\@=\|\%$' contains=ClaudiusRoleSystem,ClaudiusLuaExpression,ClaudiusFileReference,@Markdown
syntax region ClaudiusUser start='^@You:' end='\(^@\(System\|Assistant\):\)\@=\|\%$' contains=ClaudiusRoleUser,ClaudiusLuaExpression,ClaudiusFileReference,@Markdown
syntax region ClaudiusAssistant start='^@Assistant:' end='\(^@\(System\|You\):\)\@=\|\%$' contains=ClaudiusRoleAssistant,ClaudiusLuaExpression,ClaudiusFileReference,@Markdown

let b:current_syntax = "chat"
