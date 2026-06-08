# RAGE1 cpc-banked disk-loader PoC (Stage B7 step 8a, risk R-DL1).
#
# Builds a bootable single-file .dsk that validates firmware file I/O into a
# paged expansion bank.  Plain +cpc (firmware stays alive); DEFAULT org (0x1200,
# page A) so the program is NOT in the 0x4000 paging window — do NOT add
# -zorg=0x4000 here (that was the cpc-poc firmware-font workaround).
#
# Run:  ../cap32-shot.sh poc.dsk POC   ->  shot.png shows BANKLOAD-PASS / -FAIL

NAME    = poc
CC      = zcc
TARGET  = +cpc
CFLAGS  = -compiler=sdcc -SO2 --max-allocs-per-node200000
CSRC    = main.c

.PHONY: all clean

all: $(NAME).dsk

$(NAME).dsk: $(CSRC)
	$(CC) $(TARGET) $(CFLAGS) -create-app -subtype=dsk -o $(NAME) $(CSRC)

clean:
	rm -f $(NAME) $(NAME).* *.o
