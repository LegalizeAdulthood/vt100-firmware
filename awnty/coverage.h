#ifndef COVERAGE_H
#define COVERAGE_H

#include <stdint.h>

#define COV_EXEC 1
#define COV_READ 2
#define COV_WRITE 4
#define COV_DATA 8
#define COV_SYMBOL 16
#define COV_UNREACH 32
#define COV_DMA 64

// Symbols are for the ROM, 0x0000 to 0x1fff
extern char *symtable[];

// Equates are symbols for the RAM, 0x2000 to 0x2fff
//
extern char *equtable[];
extern const uint16_t equoffset;// = 0x2000; // equtable[0] is for address 0x2000

void watch_init();
void watch_add(uint16_t addr, int interp);
void watch_check();

#endif
