\ Stack debugging example for sectorforth, a 512-byte, bootable x86 Forth.
\ Copyright (c) 2020 Cesar Blum
\ Distributed under the MIT license. See LICENSE for details.
\ Depends on definitions built up to the variables examples.

\ make a few more basic operators
: ?dup dup ?branch [ 4 , ] dup ;
: -rot ( x y z -- z x y ) rot rot ;
: xor ( x y -- x^y) 2dup and invert -rot or and ;
: 8000h lit [ 0 c, 80h c, ] ; \ little endian
: >= ( x y -- flag ) - 8000h and 0= ;
: < ( x y -- flag ) >= invert ;
: <= ( x y -- flag ) 2dup < -rot = or ;
: 0< ( x -- flag ) 0 < ;

\ divison and modulo
: /mod ( x y -- x%y x/y )
    over 0< -rot                \ remainder negative if dividend is negative
    2dup xor 0< -rot            \ quotient negative if operand signs differ
    dup 0< if negate then       \ make divisor positive if negative
    swap dup 0< if negate then  \ make dividend positive if negative
    0 >r begin                  \ hold quotient in return stack
        over 2dup >=            \ while divisor greater than dividend
    while
        -                       \ subtract divisor from dividend
        r> 1 + >r               \ increment quotient
    repeat
    drop nip                    \ leave sign flags and remainder on stack
    rot if negate then          \ set remainder sign
    r> rot                      \ get quotient from return stack
    if negate then ;            \ set quotient sign
: / /mod nip ;
: mod /mod drop ;

\ constants for decimal and hexadecimal 10 (i.e. 10 and 16)
: 10 lit [ 4 4 2 + + , ] ;
: 10h lit [ 4 4 4 4 + + + , ] ;

variable base
10 base !

\ switch to common bases
: hex 10h base ! ;
: decimal 10 base ! ;

\ convert number to ASCII digit
: digit ( x -- c )
    dup 10 < if [char] 0 + else 10 - [char] A + then ;

\ print space
: space bl emit ;

\ print number at the top of the stack in current base
: . ( x -- )
    -1 swap                                     \ put sentinel on stack
    dup 0< if negate -1 else 0 then             \ make positive if negative
    >r                                          \ save sign on return stack
    begin base @ /mod ?dup 0= until             \ convert to base 10 digits
    r> if [char] - emit then                    \ print sign
    begin digit emit dup -1 = until drop        \ print digits
    space ;                                     \ print space

\ base of data stack
: sp0 lit [ sp@ , ] ;

\ print backspace
: backspace lit [ 4 4 + , ] emit ;

\ print stack
: .s
    sp@ 0 swap begin
        dup sp0 <
    while
        2 +
        swap 1 + swap
    repeat swap
    [char] < emit dup . backspace [char] > emit space
    ?dup if
        0 do 2 - dup @ . loop
    then drop ;
