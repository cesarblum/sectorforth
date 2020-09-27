\ "hello, world" example for sectorforth, a 512-byte, bootable x86 Forth.
\ Copyright (c) 2020 Cesar Blum
\ Distributed under the MIT license. See LICENSE for details.

: dup ( x -- x x ) sp@ @ ;

\ make some numbers
: -1 ( x -- x -1 ) dup dup nand dup dup nand nand ;
: 0 -1 dup nand ;
: 1 -1 dup + dup nand ;
: 2 1 1 + ;
: 4 2 2 + ;
: 6 2 4 + ;

\ logic and arithmetic operators
: invert ( x -- !x ) dup nand ;
: and ( x y -- x&y ) nand invert ;
: negate ( x -- -x ) invert 1 + ;
: - ( x y -- x-y ) negate + ;

\ equality checks
: = ( x y -- flag ) - 0= ;
: <> ( x y -- flag ) = invert ;

\ stack manipulation words
: drop ( x y -- x ) dup - + ;
: over ( x y -- x y x ) sp@ 2 + @ ;
: swap ( x y -- y x ) over over sp@ 6 + ! sp@ 2 + ! ;
: nip ( x y -- y ) swap drop ;
: 2dup ( x y -- x y x y ) over over ;
: 2drop ( x y -- ) drop drop ;

\ more logic
: or ( x y -- x|y ) invert swap invert and invert ;

\ compile things
: , ( x -- ) here @ ! here @ 2 + here ! ;

\ left shift 1 bit
: 2* ( x -- 2x ) dup + ;

\ constant to check/set immediate flag
: 80h ( -- 80h ) 1 2* 2* 2* 2* 2* 2* 2* ;

\ make words immediate
: immediate latest @ 2 + dup @ 80h or swap ! ;

\ control interpreter state
: [ 0 state ! ; immediate
: ] 1 state ! ;

\ unconditional branch
: branch ( r:addr -- r:addr+offset ) rp@ @ dup @ + rp@ ! ;

\ conditional branch when top of stack is 0
: ?branch ( r:addr -- r:addr | r:addr+offset)
    0= rp@ @ @ 2 - and rp@ @ + 2 + rp@ ! ;

\ lit pushes the value on the next cell to the stack at runtime
\ e.g. lit [ 42 , ] pushes 42 to the stack
: lit ( -- x ) rp@ @ dup 2 + rp@ ! @ ;

\ ['] is identical to lit, the choice of either depends on context
\ don't write as : ['] lit ; as that will break lit's assumptions about
\ the return stack
: ['] ( -- addr ) rp@ @ dup 2 + rp@ ! @ ;

\ push/pop return stack
: >rexit ( addr r:addr0 -- r:addr )
    rp@ ! ;                 \ override return address with original return
                            \ address from >r
: >r ( x -- r:x)
    rp@ @                   \ get current return address
    swap rp@ !              \ replace top of return stack with value
    >rexit ;                \ push new address to return stack
: r> ( r:x -- x )
    rp@ 2 + @               \ get value stored in return stack with >r
    rp@ @ rp@ 2 + !         \ replace value with address to return from r>
    lit [ here @ 6 + , ]    \ get address to this word's exit call
    rp@ ! ;                 \ make code return to this word's exit call,
                            \ effectively calling exit twice to pop return
                            \ stack entry created by >r

\ rotate stack
: rot ( x y z -- y z x ) >r swap r> swap ;

\ if/then/else
: if
    ['] ?branch ,       \ compile ?branch to skip if's body when false
    here @              \ get address where offset will be written
    0 ,                 \ compile dummy offset
    ; immediate
: then
    dup                 \ duplicate offset address
    here @ swap -       \ calculate offset from if/else
    swap !              \ store calculated offset for ?branch/branch
    ; immediate
: else
    ['] branch ,        \ compile branch to skip else's body when true
    here @              \ get address where offset will be written
    0 ,                 \ compile dummy offset
    swap                \ bring if's ?branch offset address to top of stack
    dup here @ swap -   \ calculate offset from if
    swap !              \ store calculated offset for ?branch
    ; immediate

\ begin...while...repeat and begin...until loops
: begin
    here @              \ get location to branch back to
    ; immediate
: while
    ['] ?branch ,       \ compile ?branch to terminate loop when false
    here @              \ get address where offset will be written
    0 ,                 \ compile dummy offset
    ; immediate
: repeat
    swap                        \ offset will be negative
    ['] branch , here @ - ,     \ compile branch back to begin
    dup here @ swap - swap !    \ compile offset from while
    ; immediate
: until
    ['] ?branch , here @ - ,    \ compile ?branch back to begin
    ; immediate

\ do...loop loops
: do ( end index -- )
    here @                      \ get location to branch back to
    ['] >r , ['] >r ,           \ at runtime, push inputs to return stack
    ; immediate
: loop
    ['] r> , ['] r> ,           \ move current index and end to data stack
    ['] lit , 1 , ['] + ,       \ increment index
    ['] 2dup , ['] = ,          \ index equals end?
    ['] ?branch , here @ - ,    \ when false, branch back to do
    ['] 2drop ,                 \ discard index and end when loop terminates
    ; immediate

\ fetch/store bytes
: 0fh lit [ 4 4 4 4 + + + 1 - , ] ;
: ffh lit [ 0fh 2* 2* 2* 2* 0fh or , ] ;
: c@ ( -- c ) @ ffh and ;
: c! ( c addr -- )
    dup @           \ fetch memory contents at address
    ffh invert and  \ zero out low byte
    rot ffh and     \ zero out high byte of value being stored
    or swap !       \ overwrite low byte of existing contents
    ;

\ compile bytes
: c, ( x -- ) here @ c! here @ 1 + here ! ;

\ read literal string from word body
: litstring ( -- addr len )
    rp@ @ dup 2 + rp@ ! @   \ push length to stack
    rp@ @                   \ push string address to stack
    swap
    2dup + rp@ ! ;          \ move return address past string

\ print string
: type ( addr len -- ) 0 do dup c@ emit 1 + loop drop ;

\ read char from terminal input buffer, advance >in
: in> ( "c<input>" -- c ) tib >in @ + c@ >in dup @ 1 + swap ! ;

\ constant for space char
: bl ( -- spc ) lit [ 1 2* 2* 2* 2* 2* , ] ;

\ parse input with specified delimiter
: parse ( delim "input<delim>" -- addr len )
    in> drop                    \ skip space after parse
    tib >in @ +                 \ put address of parsed input on stack
    swap 0 begin                \ ( addr delim len )
        over in>                \ ( addr delim len delim char )
    <> while
        1 +                     \ ( addr delim len+1 )
    repeat swap                 \ ( addr len delim )
    bl = if
        >in dup @ 1 - swap !    \ move >in back 1 char if delimiter is bl,
                                \ otherwise the interpreter is left in a
                                \ bad state
    then ;

\ parse input with specified delimiter, skipping leading delimiters
: word ( delim "<delims>input<delim>" -- addr len )
    in> drop                    \ skip space after word
    begin dup in> <> until      \ skip leading delimiters
    >in @ 2 - >in !             \ "put back" last char read from tib,
                                \ and backtrack >in leading char that will
                                \ be skipped by parse
    parse ;

\ parse word, compile first char as literal
: [char] ( "<spcs>input<spc>" -- c )
    ['] lit , bl word drop c@ , ; immediate

: ." ( "input<quote>" -- )
    [char] " parse                      \ parse input up to "
    state @ if
        ['] litstring ,                 \ compile litstring
        dup ,                           \ compile length
        0 do dup c@ c, 1 + loop drop    \ compile string
        ['] type ,                      \ display string at runtime
    else
        type                            \ display string
    then ; immediate

." hello, world"
: hello ." hello, world" ;
hello
