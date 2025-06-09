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

" Define regions
" System and Assistant regions contain role markers and markdown
syntax region ClaudiusSystem start='^@System:' end='\(^@\(You\|Assistant\):\)\@=\|\%$' contains=ClaudiusRoleSystem,@Markdown
" User region contains role markers, User Lua expressions, User file references, and markdown
syntax region ClaudiusUser start='^@You:' end='\(^@\(System\|Assistant\):\)\@=\|\%$' contains=ClaudiusRoleUser,ClaudiusUserLuaExpression,ClaudiusUserFileReference,@Markdown
syntax region ClaudiusAssistant start='^@Assistant:' end='\(^@\(System\|You\):\)\@=\|\%$' contains=ClaudiusRoleAssistant,@Markdown

let b:current_syntax = "chat"
