\ Quine example for sectorforth, a 512-byte, bootable x86 Forth.
\ Copyright (c) 2020 Cesar Blum
\ Distributed under the MIT license. See LICENSE for details.
\ Depends on definitions built in the "hello, world" example.

: 0<> 0= invert ;

\ get address to input buffer and number of characters in it
: source ( -- addr n )
        tib dup
        begin dup c@ 0<> while 1 + repeat
        tib - ;

\ prints itself
source type
