if exists("b:current_syntax")
  finish
endif

" Define the prefix matches
syntax match ChatSystemPrefix '^@System:' contained
syntax match ChatUserPrefix '^@You:' contained
syntax match ChatAssistantPrefix '^@Assistant:' contained

" Define regions that contain both prefixes and markdown
syntax region ChatSystem start='^@System:' end='\(^@\(You\|Assistant\):\)\@=\|\%$' contains=ChatSystemPrefix,@Markdown
syntax region ChatUser start='^@You:' end='\(^@\(System\|Assistant\):\)\@=\|\%$' contains=ChatUserPrefix,@Markdown
syntax region ChatAssistant start='^@Assistant:' end='\(^@\(System\|You\):\)\@=\|\%$' contains=ChatAssistantPrefix,@Markdown

let b:current_syntax = "chat"
