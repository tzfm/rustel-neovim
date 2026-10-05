if exists('b:current_syntax')
  finish
endif

runtime! syntax/javascript.vim
unlet! b:current_syntax

syntax match rustelLabel /^\s*\zs\$\w*\s*:/
syntax match rustelFunction /\<[a-zA-Z_$][a-zA-Z0-9_$]*\ze\s*(/

" Mini notation applies only to the first string in these calls.
syntax match rustelFunction /\<\%(s\|sound\|n\|note\|mini\)\ze\_s*(/ nextgroup=rustelPatternOpen skipwhite skipnl
syntax match rustelPatternOpen /(/ contained nextgroup=rustelPatternDouble,rustelPatternSingle,rustelPatternTemplate skipwhite skipnl
syntax region rustelPatternDouble start=/"/ skip=/\\\\\|\\"/ end=/"\|$/ contained contains=rustelMiniOperator,rustelMiniRest,javaScriptSpecial
syntax region rustelPatternSingle start=/'/ skip=/\\\\\|\\'/ end=/'\|$/ contained contains=rustelMiniOperator,rustelMiniRest,javaScriptSpecial
syntax region rustelPatternTemplate start=/`/ skip=/\\\\\|\\`/ end=/`/ contained contains=rustelMiniOperator,rustelMiniRest,javaScriptSpecial,javaScriptEmbed
syntax match rustelMiniOperator +[][<>*/!?,@:%|]+ contained
syntax match rustelMiniRest /\~/ contained

highlight default link rustelLabel Label
highlight default link rustelFunction Function
highlight default link rustelPatternOpen Delimiter
highlight default link rustelPatternDouble String
highlight default link rustelPatternSingle String
highlight default link rustelPatternTemplate String
highlight default link rustelMiniOperator Operator
highlight default link rustelMiniRest Special

let b:current_syntax = 'rustel'
