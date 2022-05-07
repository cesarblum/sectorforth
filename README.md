# sectorforth XT

[Sectorforth](https://github.com/cesarblum/sectorforth) is not a useful
version of the programming language Forth, nor does it claim to be. It is
instead a demonstration of the language's philosophy: a simple set of
primitives which fit into the first sector of floppy disk
can be combined to build up a complete language.

Compared to similar projects like
[bootBASIC](https://github.com/nanochess/bootBASIC) or
[sectorlisp](https://github.com/jart/sectorlisp), sectorforth requires an
Intel i386 processor or later to run. There are good reasons for this.
There are several features of the original 8086 architecture that expand the
size of a program running on it.

## What the 386 does differently

### Pushing immediate values

Placing immediate values onto the stack is allowed on the 386.

```
push 12345
```

On the 8086, only registers can be pushed.

````
mov ax, 12345
push ax
````

Surprisingly, this is only a byte larger than the original version.
Sectorforth pushes immediates in five different places, so this does have
overhead.

### SETNZ

To test if a given number is zero in the word ``0=``, sectorforth uses this
easy to understand routine. Keep in mind that -1 or 0xFFFF is what Forth
uses as the truth value:

```
test ax,ax
setnz al ; AL=0 if ZF=1, else AL=1
dec ax   ; AL=ff if AL=0, else AL=0
cbw      ; AH=AL
```

The SETNZ instruction introduced with the 386 is an example of what a
CISC architecture design does best: provide instructions to make
common situations easier. A naive replacement for this instruction could be
longer.

## Solutions

There are several things that can be done to reduce the size of the program.
Some can be used generally in 8086 programming, while others are specific to
this program.

###Removal of constants

The constant TIB is used several places in the code. This is always 0, and
will never be changed. This allows for several well-known techniques to be
used:

```
; Old version:
mov ax, word TIB
push ax
; New:
xor ax, ax
push ax
```

A number exclusive-ORed by itself will always be zero. This is a common
x86 idiom that saves a single byte.

```
; Old version:
cmp di,TIB ; start of TIB?
je .1      ; if so, there's nothing to erase
; New version:
test di,di ; is di 0, the start of TIB?
jz .1      ; if so, there's nothing to erase
```
```

The TEST instruction ANDs the two operands together. Since they are identical
here, this sets the zero flag, allowing the jump to occur as normal. This saves
another byte.

These changes occur in a few other places throughout the code, reducing
much of the overhead the altered stack instructions added.

### Improved 0=

While the routine used above for ``0=`` was easy to follow, A Github user
who has since deleted their account proposed a different version
[here](https://github.com/cesarblum/sectorforth/issues/3):

```
cmp ax, 1
sbb ax, ax
```

It compares the value to one, and then subtracts the value by itself.
Understanding why this works requires an understanding of how comparisons
work on the 8086. A compare is just a subtraction that doesn't save its
results. If AX is 0 and it is subtracted by 1, it will end up being -1.
This activates the carry flag. SBB (Subtract with borrow) will decrement
the result of its subtraction of the carry flag is active. This sets
AX to -1 if it is 0, and *only* if it is zero. This saves two bytes, while
not requiring the 386!.

### End result

With these optimizations, the binary comes out to the same size as the
original while being able to run on the original PC hardware.

## Using sectorforth XT

Use the build instructions found in the original sectorforth README, then
load in the PC emulator of your choice. I prefer
[86Box](https://github.com/86Box/86Box).
