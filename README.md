# sectorforth

sectorforth is a 16-bit x86 Forth that fits in a 512-byte boot sector.

Inspiration to write sectorforth came from a 1996
[Usenet thread](https://groups.google.com/g/comp.lang.forth/c/NS2icrCj1jQ)
(in particular, Bernd Paysan's first post on the thread).

## Batteries not included

sectorforth contains only the eight primitives outlined in the Usenet
post above, five variables for manipulating internal state, and two I/O
primitives.

With that minimal set of building blocks, words for branching, compiling,
manipulating the return stack, etc. can all be written in Forth itself
(check out the examples!).

The colon compiler (`:`) is available, so new words can be defined easily
(that means `;` is also there, of course).

Contrary to many Forth implementations, sectorforth does not attempt to
convert unknown words to numbers, since numbers can be produced using the
available primitives. The two included I/O primitives are sufficient to
write a more powerful interpreter that can parse numbers.

### Primitives

| Primitive | Stack effects | Description                                   |
| --------- | ------------- | --------------------------------------------- |
| `@`       | ( addr -- x ) | Fetch memory contents at addr                 |
| `!`       | ( x addr -- ) | Store x at addr                               |
| `sp@`     | ( -- sp )     | Get pointer to top of data stack              |
| `rp@`     | ( -- rp )     | Get pointer to top of return stack            |
| `0=`      | ( x -- flag ) | -1 if top of stack is 0, 0 otherwise          |
| `+`       | ( x y -- z )  | Sum the two numbers at the top of the stack   |
| `nand`    | ( x y -- z )  | NAND the two numbers at the top of the stack  |
| `exit`    | ( r:addr -- ) | Pop return stack and resume execution at addr |
| `key`     | ( -- x )      | Read key stroke as ASCII character)           |
| `emit`    | ( x -- )      | Print low byte of x as an ASCII character     |

### Variables

| Variable | Description                                                   |
| -------- | ------------------------------------------------------------- |
| `state`  | 0: execute words; 1: compile word addresses to the dictionary |
| `tib`    | Terminal input buffer, where input is parsed from             |
| `>in`    | Current parsing offset into terminal input buffer             |
| `here`   | Pointer to next free position in the dictionary               |
| `latest` | Pointer to most recent dictionary entry                       |

## Compiling

sectorforth was developed using NASM 2.15.01. Earlier versions of NASM
are probably capable of compiling it, but that hasn't been tested.

To compile sectorforth, just run `make`:

```
$ make
```

That will produce a compiled binary (`sectorforth.bin`) and a floppy disk
image (`sectorforth.img`) containing the binary in its boot sector.

## Running

The makefile contains two targets for running sectorforth in QEMU:

- `debug` starts QEMU in debug mode, with execution paused. That allows
you to set up a remote target in GDB (`target remote localhost:1234`) and
set any breakpoints you want before sectorforth starts running.
- `run` simply runs sectorforth in QEMU.

## Usage

Up to 4KB of input can be entered per line. After pressing return, the
interpreter parses one word at a time an interprets it (i.e. executes it
or compiles it, according to the current value of the `state` variable).

sectorforth does not print the ` ok` prompt familiar to Forth users.
However, if a word is not found in the dictionary, the error message `!!`
is printed in red, letting you know an error happened.

When a word is not found in the dictionary, the interpreter's state is
reset: the data and return stacks, as well as the terminal input buffer
are cleared, and the interpreter is placed in interpretation mode. Other
errors (e.g. compiling an invalid address in a word definition and
attempting to execute it) are not handled gracefully, and will crash the
interpreter.

## Code structure

Comments throughout the code assume familiarity with Forth and how it is
commonly implemented.

If you're not familiar with Forth, read Leo Brodie's
[Starting Forth](https://www.forth.com/starting-forth).

If you're not familiar with how Forth is implemented on x86, read the
assembly code for Richard W.M. Jones'
[jonesforth](http://git.annexia.org/?p=jonesforth.git;a=blob;f=jonesforth.S).

sectorforth draws a lot of inspiration from jonesforth, but the latter
does a much better job at explaining the basics in its comments.

For an excellent introduction to threaded code techniques, and to how to
implement Forth in different architectures, read Brad Rodriguez's
[Moving Forth](http://www.bradrodriguez.com/papers/moving1.htm).
