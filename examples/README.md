# A note on return stack manipulation

In these examples, some defintions like `branch` and `lit` do a fair
bit of return stack manipulation that may not be immediately intuitive
to grasp.

The key to understanding how those definitions work is in how Forth's
[threaded code](https://en.wikipedia.org/wiki/Threaded_code) is executed.

A word's body is comprised of a sequence of addresses to other words it
calls. One of the processor's registers (`SI`, in the case of sectorforth)
works as Forth's "instruction pointer", which is distinct from the
processor's instruction pointer.

Consider the following word definition:

```forth
: w4 w1 w2 w3 ;
```

Its body is laid out in memory like this:

```
address               addr1           addr2           addr3
                *---------------*---------------*---------------*
contents        | address of w1 | address of w2 | address of w3 |
                *---------------*---------------*---------------*
size                 2 bytes         2 bytes         2 bytes
```

When `w4` is about to be executed, `SI` points to its first cell:

```
address               addr1           addr2           addr3
                *---------------*---------------*---------------*
contents        | address of w1 | address of w2 | address of w3 |
                *---------------*---------------*---------------*
size                 2 bytes         2 bytes         2 bytes
                        ^
                        |
                        *--- SI
```

When `w4` starts executing and calls `w1`, two things happen:

- `SI` is advanced to the next cell (i.e. `SI = SI + 2`)
- `SI` is pushed to the return stack

Which means that if `w1` were to fetch the contents of the return stack
(`rp@ @`), it would get `addr2` as a result.

Now, when a word finishes executing, it calls `exit`, which pops the
return stack, and sets `SI` to the popped address so that execution
resumes there. In the example above, the execution of `w4` would
resume right past the point where it called `w1`, calling `w2` next.

What if `w1` were to do the following though:

```forth
... rp@ @ 2 + rp@ ! ...
```

`rp@ @ 2 +` would fetch the top of the return stack, yielding `addr2`,
then it would add 2 to it, resulting in `addr3`. `rp@ !` would then
replace the value at the top of the return stack with `addr3`.

In that situation, when `w1` calls `exit`, the top of the return stack
is popped, yielding `addr3` this time, and execution resumes there,
skipping the call to `w2` in the body of `w4` and going straight to `w3`.

That's how `branch`, `lit`, and other definitions that manipulate the
return stack work. `branch` reads an offset from the top of the return
stack (`rp@ @ @` reads the contents of the address at the top of the
return stack) and adds that offset to the address at the top of the return
stack itself (`rp@ @ + rp@ !`), so execution skips a number of words
corresponding to the offset (it actually skips bytes, so offsets always
have to be multiples of 2 to skip words). Like `branch`, `lit` reads a
value from the address at the top of the return stack, but always adds 2
to that same address so execution skips the literal (since attemping to
execute the literal value itself would not make sense).

The most involved definitions in terms of manipulating the return stack
are `>r` and `r>`, which push and pop arbitrary values to and from the
return stack itself:

```forth
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
```

`>r` uses an auxiliary word, `>rexit`, to push a new
address to the return stack (remember, an address is pushed every time a
word is called, so calling `>rexit` will do just that), then replaces it
with the return address that was pushed when `>r` was called. *That*
original address can thus be replaced with whatever value was on the data
stack when `>r` was called. When `>r` exits, the value left at the top of
the return stack is the argument to `>r`.

`r>` is a bit more complicated. In addition to reading a value placed on
the return stack by `>r` earlier, `r>` needs to pop that off. Evidently,
it cannot do so via an auxiliary word like `>r` does, since that would
only _push_ yet another address on the return stack. Instead, it obtains
the address to its `exit` call (located where `;` is), and replaces the
value pushed by `>r` with it. When `r>` calls `exit` the first time,
execution goes back _to that same exit call_ one more time, popping off
the return stack space created by `>r`; the second call to `exit` then
pops the address to return to wherever `r>` was called.
