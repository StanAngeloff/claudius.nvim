if exists("b:current_syntax")
  finish
endif

" Keywords
syntax keyword ClaudiusNotifyKeyword Request Session

" Numbers including decimals
syntax match ClaudiusNotifyNumber "\<\d\+\(\.\d\+\)\?\>"

" Highlight groups
highlight default link ClaudiusNotifyKeyword Type
highlight default link ClaudiusNotifyNumber Number

let b:current_syntax = "claudius_notify"
