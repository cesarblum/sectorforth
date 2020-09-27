name = sectorforth

all: $(name).bin $(name).img

%.bin: %.asm
	nasm -f bin -o $@ -l $(^:.asm=.lst) $^

%.img: %.bin
	dd if=$^ of=boot.img bs=512
	dd if=/dev/zero of=zero.img bs=512 count=2879
	cat boot.img zero.img > $@
	rm -f boot.img zero.img

.PHONY: debug
gdb: $(name).bin
	qemu-system-i386 -hda $^ -monitor stdio -s -S

.PHONY: run
run: $(name).bin
	qemu-system-i386 -hda $^

.PHONY: clean
clean:
	rm -rf *.{bin,lst,img}
