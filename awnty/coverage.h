#ifndef COVERAGE_H
#define COVERAGE_H

#include "i8080.h"

// Coverage and watch functionality.

#include <stdint.h>
#include <SDL2/SDL.h>

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

void coverage_read_sym(const char *fname);
void coverage_read_equ(const char *fname);

// Prime the coverage array with details of data structures and presumed
// unreachable code, filled out during disassembly.
//
void coverage_load(const i8080 *c, const char *fname);

void coverage_rw(const i8080 *c, uint16_t area_start, uint16_t area_len);

void coverage_graphic_sdl(const i8080 *c, SDL_Renderer *rend);

#endif
