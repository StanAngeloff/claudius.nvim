if exists("b:current_syntax")
  finish
endif

" Keywords
syntax keyword ClaudiusNotifyKeyword Request Session

" Numbers including decimals (with optional $ prefix)
syntax match ClaudiusNotifyNumber "\$\?\<\d\+\(\.\d\+\)\?\>"

" Model names (between backticks)
syntax region ClaudiusNotifyModel matchgroup=Conceal start=/`/ end=/`/ concealends

" Highlight groups
highlight default link ClaudiusNotifyKeyword Type
highlight default ClaudiusNotifyNumber gui=bold
highlight default link ClaudiusNotifyModel Special

let b:current_syntax = "claudius_notify"
