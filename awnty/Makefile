bin = awnty
src = i8080.c awnty.c er1400.c coverage.o vt100_memory.o
obj = $(src:.c=.o)
CC = gcc
CFLAGS = -g -Wall -Wextra -O2 -std=c2x -pedantic
LDFLAGS = -lSDL2 -lgd

.PHONY: all clean

all: $(bin)

$(bin): $(obj)
	$(CC) -o $@ $^ $(LDFLAGS)

clean:
	-rm -f $(bin) $(obj)
