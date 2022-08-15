#include "coverage.h"

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "vt100_memory.h"

// Symbols are for the ROM, 0x0000 to 0x1fff
char *symtable[0x2000];

// Equates are symbols for the RAM, 0x2000 to 0x2fff
//
char *equtable[0x1000];
const uint16_t equoffset = 0x2000; // equtable[0] is for address 0x2000

int num_watch = 0;
const int max_watch = 1000;
uint16_t watch_addr[1000];
uint16_t watch_lastval[1000];
bool     watch_hadval[1000];
uint8_t  watch_interp[1000];

void watch_init() {
    num_watch = 0;
}

void watch_add(uint16_t addr, int interp) {
    if (num_watch < max_watch) {
        watch_addr[num_watch] = addr;
        watch_hadval[num_watch] = false;
        watch_lastval[num_watch] = 0;
        watch_interp[num_watch] = interp;
        ++num_watch;
    }
}

void watch_check()
{
    for (int w = 0; w < num_watch; ++w) {
        if (watch_interp[w] == 0) { // byte watch
            uint16_t newval = memory[watch_addr[w]];
            if (!watch_hadval[w] || newval != watch_lastval[w]) {
                char st[16];
                if (watch_addr[w] >= equoffset && equtable[watch_addr[w] - equoffset])
                    strncpy(st, equtable[watch_addr[w] - equoffset], 16);
                else
                    snprintf(st, 16, "%-11s%04x", "", watch_addr[w]);
                st[15] = 0;
                printf("\t\t\t\t%-15s  %02x -> %02x\n", st, watch_lastval[w], newval);
            }
            watch_lastval[w] = newval;
            watch_hadval[w] = true;
        }
        else if (watch_interp[w] == 1) { // word watch
            uint16_t newval = memory[watch_addr[w]] | (memory[watch_addr[w] + 1] << 8);
            if (!watch_hadval[w] || newval != watch_lastval[w]) {
                char st[16];
                char pt[30];
                // Symbol we're watching -- will be in RAM (equ table)
                if (watch_addr[w] >= equoffset && equtable[watch_addr[w] - equoffset])
                    strncpy(st, equtable[watch_addr[w] - equoffset], 16);
                else
                    snprintf(st, 16, "%-11s%04x", "", watch_addr[w]);
                st[15] = 0;
                // Pointer -- into ROM
                if (newval < 0x2000 && symtable[newval])
                    snprintf(pt, 30, "%04x  %s", newval, symtable[newval]);
                else
                    snprintf(pt, 30, "%04x", newval);
                pt[29] = 0;
                printf("\t\t\t\t%-15s  %04x -> %s\n", st, watch_lastval[w], pt);
            }
            watch_lastval[w] = newval;
            watch_hadval[w] = true;
        }
    }
}

