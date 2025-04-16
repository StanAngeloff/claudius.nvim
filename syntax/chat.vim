if exists("b:current_syntax")
  finish
endif

" Define the prefix matches
syntax match ClaudiusSystemPrefix '^@System:' contained
syntax match ClaudiusUserPrefix '^@You:' contained
syntax match ClaudiusAssistantPrefix '^@Assistant:' contained

" Define regions that contain both prefixes and markdown
syntax region ClaudiusSystem start='^@System:' end='\(^@\(You\|Assistant\):\)\@=\|\%$' contains=ClaudiusSystemPrefix,@Markdown
syntax region ClaudiusUser start='^@You:' end='\(^@\(System\|Assistant\):\)\@=\|\%$' contains=ClaudiusUserPrefix,@Markdown
syntax region ClaudiusAssistant start='^@Assistant:' end='\(^@\(System\|You\):\)\@=\|\%$' contains=ClaudiusAssistantPrefix,@Markdown

let b:current_syntax = "chat"
