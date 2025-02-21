if exists("b:current_syntax")
  finish
endif

syntax region ClaudiusNotifyBold start="\*\*" end="\*\*" contains=NONE
highlight link ClaudiusNotifyBold Bold

let b:current_syntax = "claudius_notify"
