\ Variables example for sectorforth, a 512-byte, bootable x86 Forth.
\ Copyright (c) 2020 Cesar Blum
\ Distributed under the MIT license. See LICENSE for details.
\ Depends on definitions built in the "hello, world" example.

\ constant to check/set hidden flag
: 40h lit [ 1 2* 2* 2* 2* 2* 2* , ] ;

\ make words visible
: reveal latest @ 2 + dup @ 40h invert and swap ! ;

\ creates a word that pushes the address to its body at runtime
: create
    :               \ parse word and create dictionary entry
    ['] lit ,       \ compile lit
    here @ 4 + ,    \ compile address past new word's exit call
    ['] exit ,      \ compile exit
    reveal          \ make created word visible
    0 state !       \ switch back to interpretation state

\ cells are 2 bytes wide
: cells ( -- x ) lit [ 2 , ] ;

\ reserve bytes in dictionary
: allot ( x -- ) here @ + here ! ;

: variable create 1 cells allot ;

variable var
2 var !
var @ emit \ should print smiley face
