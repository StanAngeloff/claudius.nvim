if exists("b:current_syntax")
  finish
endif

syntax region ClaudiusNotifyBold matchgroup=Conceal start="\*\*" end="\*\*" concealends contains=NONE
highlight ClaudiusNotifyBold term=bold cterm=bold gui=bold

let b:current_syntax = "claudius_notify"
