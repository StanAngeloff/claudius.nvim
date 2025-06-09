if exists("b:current_syntax")
  finish
endif

" Define the role marker matches (e.g., @System:)
syntax match ClaudiusRoleSystem '^@System:' contained
syntax match ClaudiusRoleUser '^@You:' contained
syntax match ClaudiusRoleAssistant '^@Assistant:' contained

" Define the Lua expression match
syntax match ClaudiusLuaExpression "{{.\{-}}}" contained

" Define regions that contain role markers, Lua expressions, and markdown
syntax region ClaudiusSystem start='^@System:' end='\(^@\(You\|Assistant\):\)\@=\|\%$' contains=ClaudiusRoleSystem,ClaudiusLuaExpression,@Markdown
syntax region ClaudiusUser start='^@You:' end='\(^@\(System\|Assistant\):\)\@=\|\%$' contains=ClaudiusRoleUser,ClaudiusLuaExpression,@Markdown
syntax region ClaudiusAssistant start='^@Assistant:' end='\(^@\(System\|You\):\)\@=\|\%$' contains=ClaudiusRoleAssistant,ClaudiusLuaExpression,@Markdown

let b:current_syntax = "chat"
