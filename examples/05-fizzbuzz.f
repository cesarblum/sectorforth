\ FizzBuzz example for sectorforth, a 512-byte, bootable x86 Forth.
\ Copyright (c) 2020 Cesar Blum
\ Distributed under the MIT license. See LICENSE for details.
\ Depends on definitions built up to the stack debugging example.

\ get do...loop index
: i ( -- index ) rp@ 4 + @ ;

\ make more numbers
: 3 1 2 + ;
: 5 2 3 + ;

\ newline
: cr lit [ 4 6 3 + + , ] lit [ 4 6 + , ] emit emit ;

: fizzbuzz ( x -- )
    cr 1 + 1 do
        i 3 mod 0= dup if ." Fizz" then
        i 5 mod 0= dup if ." Buzz" then
        or invert if i . then
        cr
    loop ;
