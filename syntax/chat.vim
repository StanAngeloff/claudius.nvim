if exists("b:current_syntax")
  finish
endif

" Define the role marker matches (e.g., @System:)
syntax match ClaudiusRoleSystem '^@System:' contained
syntax match ClaudiusRoleUser '^@You:' contained
syntax match ClaudiusRoleAssistant '^@Assistant:' contained

" Define regions that contain both role markers and markdown
syntax region ClaudiusSystem start='^@System:' end='\(^@\(You\|Assistant\):\)\@=\|\%$' contains=ClaudiusRoleSystem,@Markdown
syntax region ClaudiusUser start='^@You:' end='\(^@\(System\|Assistant\):\)\@=\|\%$' contains=ClaudiusRoleUser,@Markdown
syntax region ClaudiusAssistant start='^@Assistant:' end='\(^@\(System\|You\):\)\@=\|\%$' contains=ClaudiusRoleAssistant,@Markdown

let b:current_syntax = "chat"
