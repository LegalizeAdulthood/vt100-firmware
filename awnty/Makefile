bin = awnty
src = i8080.c awnty.c er1400.c coverage.o vt100_memory.o sdl_gd.o
obj = $(src:.c=.o)
CC = gcc
CFLAGS = -g -Wall -Wextra -O2 -pedantic
LDFLAGS = -lSDL2 -lgd

.PHONY: all clean

all: $(bin)

$(bin): $(obj)
	$(CC) -o $@ $^ $(LDFLAGS)

clean:
	-rm -f $(bin) $(obj)
