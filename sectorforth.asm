        ; sectorforth - a 512-byte, bootable x86 Forth.
        ; Copyright (c) 2020 Cesar Blum
        ; Distributed under the MIT license. See LICENSE for details.
        ;
        ; sectorforth is a 16-bit x86 Forth that fits entirely within a
        ; boot sector (512 bytes).
        ;
        ; It's a direct threaded Forth, with SI acting as the Forth
        ; instruction pointer. Words are executed using LODSW to advance
        ; SI and load the next word's address into AX, which is then
        ; jumped to.
        ;
        ; The SP register is used as the data stack pointer, and the BP
        ; register acts as the return stack pointer.
        ;
        ; The minimum CPU required to run sectorforth is the 386, to use
        ; the SETNZ instruction.
        bits 16
        cpu 386

        ; Set CS to a known value by performing a far jump. Memory up to
        ; 0x0500 is used by the BIOS. Setting the segment to 0x0500 gives
        ; sectorforth an entire free segment to work with.
        jmp 0x0050:start

        ; On x86, the boot sector is loaded at 0x7c00 on boot. In segment
        ; 0x0500, that's 0x7700 (0x0050 << 4 + 0x7700 == 0x7c00).
        org 0x7700

        ; Define constants for the memory map. Everything is organized
        ; within a single 64 KB segment. TIB is placed at 0x0000 to
        ; simplify input parsing (the Forth variable >IN ends up being
        ; also a pointer into TIB, so there's no need to add >IN to TIB
        ; to get a pointer to the parse area). TIB is 4 KB long.
TIB             equ 0x0000      ; terminal input buffer (TIB)
STATE           equ 0x1000      ; current state (0=interpret, 1=compile)
TOIN            equ 0x1002      ; current read offset into TIB (>IN)
RP0             equ 0x76fe      ; bottom of return stack
SP0             equ 0xfffe      ; bottom of data stack

        ; Each dictionary entry is laid out in memory as such:
        ;
        ; *--------------*--------------*--------------*--------------*
        ; | Link pointer | Flags+Length |    Name...   |    Code...   |
        ; *--------------*--------------*--------------*--------------*
        ;     2 bytes         1 byte      Length bytes     Variable
        ;
        ; Flags IMMEDIATE and HIDDEN are used in assembly code. Room is
        ; left for an additional, user-defined flag, so word names are
        ; limited to 32 characters.
F_IMMEDIATE     equ 0x80
F_HIDDEN        equ 0x40
LENMASK         equ 0x1f

        ; Each dictionary entry needs a link to the previous entry. The
        ; last entry links to zero, marking the end of the dictionary.
        ; As dictionary entries are defined, link will be redefined to
        ; point to the previous entry.
%define link 0

        ; defword lays out a dictionary entry where it is expanded.
%macro defword 3-4 0            ; name, length, label, flags
word_%3:
        dw link                 ; link to previous word
%define link word_%3
        db %4+%2                ; flags+length
        db %1                   ; name
%3:                             ; code starts here
%endmacro

        ; NEXT advances execution to the next word. The actual code is
        ; placed further ahead for strategic reasons. The macro has to be
        ; defined here, since it's used in the words defined ahead.
%define NEXT jmp next

        ; sectorforth has only eight primitive words, with which
        ; everything else can be built in Forth:
        ;
        ; @ ( addr -- x )       Fetch memory at addr
        ; ! ( x addr -- )       Store x at addr
        ; sp@ ( -- addr )       Get current data stack pointer
        ; rp@ ( -- addr )       Get current return stack pointer
        ; 0= ( x -- f )         -1 if top of stack is 0, 0 otherwise
        ; + ( x1 x2 -- n )      Add the two values at the top of the stack
        ; nand ( x1 x2 -- n )   NAND the two values at the top of the stack
        ; exit ( r:addr -- )    Resume execution at address at the top of
        ;                       the return stack
        defword "@",1,FETCH
        pop bx
        push word [bx]
        NEXT

        defword "!",1,STORE
        pop bx
        pop word [bx]
        NEXT

        defword "sp@",3,SPFETCH
        push sp
        NEXT

        defword "rp@",3,RPFETCH
        push bp
        NEXT

        defword "0=",2,ZEROEQUALS
        pop ax
        test ax,ax
        setnz al                ; AL=0 if ZF=1, else AL=1
        dec ax                  ; AL=ff if AL=0, else AL=0
        cbw                     ; AH=AL
        push ax
        NEXT

        defword "+",1,PLUS
        pop bx
        pop ax
        add ax,bx
        push ax
        NEXT

        defword "nand",4,NAND
        pop bx
        pop ax
        and ax,bx
        not ax
        push ax
        NEXT

        defword "exit",4,EXIT
        xchg sp,bp              ; swap SP and BP, SP controls return stack
        pop si                  ; pop address to next word
        xchg sp,bp              ; restore SP and BP
        NEXT

        ; Besides primitives, a few variables are exposed to Forth code:
        ; TIB, STATE, >IN, HERE, and LATEST. With sectorforth's >IN being
        ; both an offset and a pointer into TIB (as TIB starts at 0x0000),
        ; TIB could be left out. But it is exposed so that sectorforth
        ; code that accesses the parse area can be written in an idiomatic
        ; fashion (e.g. TIB >IN @ +).
        defword "tib",3,TIBVAR
        push word TIB
        NEXT

        defword "state",5,STATEVAR
        push word STATE
        NEXT

        defword ">in",3,TOINVAR
        push word TOIN
        NEXT

        ; Strategically define next here so most jumps to it are short,
        ; saving extra bytes that would be taken by near jumps.
next:
        lodsw                   ; load next word's address into AX
        jmp ax                  ; jump directly to it

        ; Words and data space for the HERE and LATEST variables.
        defword "here",4,HEREVAR
        push word HERE
        NEXT
HERE:   dw start_HERE

        defword "latest",6,LATESTVAR
        push word LATEST
        NEXT
LATEST: dw word_SEMICOLON       ; initialized to last word in dictionary

        ; Define a couple of I/O primitives to make things interactive.
        ; They can also be used to build a richer interpreter loop.
        ;
        ; KEY waits for a key press and pushes its scan code (AH) and
        ; ASCII character (AL) to the stack, both in a single cell.
        defword "key",3,KEY
        mov ah,0
        int 0x16
        push ax
        NEXT

        ; EMIT writes to the screen the ASCII character corresponding to
        ; the lowest 8 bits of the value at the top of the stack.
        defword "emit",4,EMIT
        pop ax
        call writechar
        NEXT

        ; The colon compiler reads a name from the terminal input buffer,
        ; creates a dictionary entry for it, writes machine code to jump
        ; to DOCOL, updates LATEST and HERE, and switches to compilation
        ; state.
        defword ":",1,COLON
        call token              ; parse word from input
        push si
        mov si,di               ; set parsed word as string copy source
        mov di,[HERE]           ; set current value of HERE as destination
        mov ax,[LATEST]         ; get pointer to latest defined word
        mov [LATEST],di         ; update LATEST to new word being defined
        stosw                   ; link pointer
        mov al,cl
        or al,F_HIDDEN          ; hide new word while it's being defined
        stosb                   ; word length
        rep movsb               ; word name
        mov ax,0x26ff
        stosw                   ; compile near jump, absolute indirect...
        mov ax,DOCOL.addr
        stosw                   ; ...to DOCOL
        mov [HERE],di           ; update HERE to next free position
        mov byte [STATE],1      ; switch to compilation state
        pop si
        NEXT

        ; DOCOL sets up and starts execution of a user-defined words.
        ; Those differ from words defined in machine code by being
        ; sequences of addresses to other words, so a bit of code is
        ; needed to save the current value of SI (this Forth's instruction
        ; pointer), and point it to the sequence of addresses that makes
        ; up a word's body.
        ;
        ; DOCOL advances AX 4 bytes, and then moves that value to SI. When
        ; DOCOL is jumped to, AX points to the code field of the word
        ; about to be executed. The 4 bytes being skipped are the actual
        ; jump instruction to DOCOL itself, inserted by the colon compiler
        ; when it creates a new entry in the dictionary.
DOCOL:
        xchg sp,bp              ; swap SP and BP, SP controls return stack
        push si                 ; push current "instruction pointer"
        xchg sp,bp              ; restore SP and BP
        add ax,4                ; skip word's code field
        mov si,ax               ; point "instruction pointer" to word body
        NEXT                    ; start executing the word

        ; The jump instruction inserted by the compiler is an indirect
        ; jump, so it needs to read the location to jump to from another
        ; memory location.
.addr:  dw DOCOL

        ; Semicolon is the only immediate primitive. It writes the address
        ; of EXIT to the end of a new word definition, makes the word
        ; visible in the dictionary, and switches back to interpretation
        ; state.
        defword ";",1,SEMICOLON,F_IMMEDIATE
        mov bx,[LATEST]
        and byte [bx+2],~F_HIDDEN       ; reveal new word
        mov byte [STATE],0      ; switch to interpretation state
        mov ax,EXIT             ; prepare to compile EXIT
compile:
        mov di,[HERE]
        stosw                   ; compile contents of AX to HERE
        mov [HERE],di           ; advance HERE to next cell
        NEXT

        ; Execution starts here.
start:
        cld                     ; clear direction flag

        ; Set up segment registers to point to the same segment as CS.
        push cs
        push cs
        push cs
        pop ds
        pop es
        pop ss

        ; Skip error signaling on initialization
        jmp init

        ; Display a red '!!' to let the user know an error happened and the
        ; interpreter is being reset
error:
        mov ax,0x0921           ; write '!'
        mov bx,0x0004           ; black background, red text
        mov cx,2                ; twice
        int 0x10

        ; Initialize stack pointers, state, and terminal input buffer.
init:
        mov bp,RP0              ; BP is the return stack pointer
        mov sp,SP0              ; SP is the data stack pointer

        ; Fill TIB with zeros, and set STATE and >IN to 0
        mov al,0
        mov cx,STATE+4
        mov di,TIB
        rep stosb

        ; Enter the interpreter loop.
        ;
        ; Words are read one at time and searched for in the dictionary.
        ; If a word is found in the dictionary, it is either interpreted
        ; (i.e. executed) or compiled, depending on the current state and
        ; the word's IMMEDIATE flag.
        ;
        ; When a word is not found, the state of the interpreter is reset:
        ; the data and return stacks are cleared as well as the terminal
        ; input buffer, and the interpreter goes into interpretation mode.
interpreter:
        call token              ; parse word from input
        mov bx,[LATEST]         ; start searching for it in the dictionary
.1:     test bx,bx              ; zero?
        jz error                ; not found, reset interpreter state
        mov si,bx
        lodsw                   ; skip link
        lodsb                   ; read flags+length
        mov dl,al               ; save those for later use
        test al,F_HIDDEN        ; entry hidden?
        jnz .2                  ; if so, skip it
        and al,LENMASK          ; mask out flags
        cmp al,cl               ; same length?
        jne .2                  ; if not, skip entry
        push cx
        push di
        repe cmpsb              ; compare strings
        pop di
        pop cx
        je .3                   ; if equal, search is over
.2:     mov bx,[bx]             ; skip to next entry
        jmp .1                  ; try again
.3:     mov ax,si               ; after comparison, SI points to code field
        mov si,.loop            ; set SI so NEXT loops back to interpreter
        ; Decide whether to interpret or compile the word. The IMMEDIATE
        ; flag is located in the most significant bit of the flags+length
        ; byte. STATE can only be 0 or 1. When ORing those two, these are
        ; the possibilities:
        ;
        ; IMMEDIATE     STATE         OR   ACTION
        ;   0000000   0000000   00000000   Interpret
        ;   0000000   0000001   00000001   Compile
        ;   1000000   0000000   10000000   Interpret
        ;   1000000   0000001   10000001   Interpret
        ;
        ; A word is only compiled when the result of that OR is 1.
        ; Decrementing that result sets the zero flag for a conditional
        ; jump.
        and dl,F_IMMEDIATE      ; isolate IMMEDIATE flag
        or dl,[STATE]           ; OR with state
        dec dl                  ; decrement
        jz compile              ; if result is zero, compile
        jmp ax                  ; otherwise, interpret (execute) the word
.loop:  dw interpreter

        ; Parse a word from the terminal input buffer and return its
        ; address and length in DI and CX, respectively.
        ;
        ; If after skipping spaces a 0 is found, more input is read from
        ; the keyboard into the terminal input buffer until return is
        ; pressed, at which point execution jumps back to the beginning of
        ; token so it can attempt to parse a word again.
        ;
        ; Before reading input from the keyboard, a CRLF is emitted so
        ; the user can enter input on a fresh, blank line on the screen.
token:
        mov di,[TOIN]           ; starting at the current position in TIB
        mov cx,-1               ; search "indefinitely"
        mov al,32               ; for a character that's not a space
        repe scasb
        dec di                  ; result is one byte past found character
        cmp byte [di],0         ; found a 0?
        je .readline            ; if so, read more input
        mov cx,-1               ; search "indefinitely" again
        repne scasb             ; this time, for a space
        dec di                  ; adjust DI again
        mov [TOIN],di           ; update current position in TIB
        not cx                  ; after ones' complement, CX=length+1
        dec cx                  ; adjust CX to correct length
        sub di,cx               ; point to start of parsed word
        ret
.readline:
        mov al,13
        call writechar          ; CR
        mov al,10
        call writechar          ; LF
        mov di,TIB              ; read into TIB
.1:     mov ah,0                ; wait until a key is pressed
        int 0x16
        cmp al,13               ; return pressed?
        je .3                   ; if so, finish reading
        cmp al,8                ; backspace pressed?
        je .2                   ; if so, erase character
        call writechar          ; otherwise, write character to screen
        stosb                   ; store character in TIB
        jmp .1                  ; keep reading
.2:     cmp di,TIB              ; start of TIB?
        je .1                   ; if so, there's nothing to erase
        dec di                  ; erase character in TIB
        call writechar          ; move cursor back one character
        mov ax,0x0a20           ; erase without moving cursor
        mov cx,1
        int 0x10                ; (BH already set to 0 by writechar)
        jmp .1                  ; keep reading
.3:     mov ax,0x0020
        stosw                   ; put final delimiter and 0 in TIB
        call writechar          ; write a space between user input and
                                ; execution output
        mov word [TOIN],0       ; point >IN to start of TIB
        jmp token               ; try parsing a word again

        ; writechar writes a character to the screen. It uses INT 10/AH=0e
        ; to perform teletype output, writing the character, updating the
        ; cursor, and scrolling the screen, all in one go. Writing
        ; backspace using the BIOS only moves the cursor backwards within
        ; a line, but does not move it back to the previous line.
        ; writechar addresses that.
writechar:
        push ax                 ; INT 10h/AH=03h clobbers AX in some BIOSes
        mov bh,0                ; video page 0 for all BIOS calls
        mov ah,3                ; get cursor position (DH=row, DL=column)
        int 0x10
        pop ax                  ; restore AX
        mov ah,0x0e             ; teletype output
        mov bl,0x7              ; black background, light grey text
        int 0x10
        cmp al,8                ; backspace?
        jne .1                  ; if not, nothing else to do
        test dl,dl              ; was cursor in first column?
        jnz .1                  ; if not, nothing else to do
        mov ah,2                ; move cursor
        mov dl,79               ; to last column
        dec dh                  ; of previous row
        int 0x10
.1:     ret

        times 510-($-$$) db 0
        db 0x55, 0xaa

        ; New dictionary entries will be written starting here.
start_HERE:
