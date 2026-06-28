NASM      = nasm
NASMFLAGS = -f bin
SRC       = src/asm/dosfetch.asm
OUT       = dist/DOSFETCH.COM

.PHONY: all clean help

all: $(OUT)

$(OUT): $(SRC)
	mkdir -p dist
	$(NASM) $(NASMFLAGS) $(SRC) -o $(OUT)

clean:
	rm -f $(OUT)

help:
	@echo "make       - build dist/DOSFETCH.COM"
	@echo "make clean - remove build artifacts"
