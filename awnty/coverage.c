#include "coverage.h"

#include "vt100_memory.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

void coverage_read_sym(const char *fname) {
    FILE *symf = fopen(fname, "r");
    if (symf) {
        uint16_t symaddr;
        char symname[50];
        for (int i = 0; i < 0x2000; ++i)
            symtable[i] = 0;
        while (fscanf(symf, "%4hx %s\n", &symaddr, symname) == 2) {
            if (symaddr < 0x3000) {
                symtable[symaddr] = (char *)malloc(strlen(symname) + 1);
                if (symtable[symaddr])
                    strcpy(symtable[symaddr], symname);
            }
        }
        fclose(symf);
    }
    else {
        fprintf(stderr, "Warning: missing coverage symbols: %s\n", fname);
    }
}

// Read the symbol table of equates
void coverage_read_equ(const char *fname) {
    FILE *equf = fopen(fname, "r");
    if (equf) {
        uint16_t symaddr;
        char symname[50];
        for (int i = 0; i < 0x1000; ++i)
            equtable[i] = 0;
        while (fscanf(equf, "%4hx %s\n", &symaddr, symname) == 2) {
            if (symaddr >= equoffset && symaddr < equoffset + 0x1000) {
                symaddr -= equoffset; // table offset
                equtable[symaddr] = malloc(strlen(symname) + 1);
                if (equtable[symaddr])
                    strcpy(equtable[symaddr], symname);
            }
        }
        fclose(equf);
    }
    else {
        fprintf(stderr, "Warning: missing coverage equates: %s\n", fname);
    }
}

// One or both of the report_* booleans may be true. If they are both true,
// it is the caller's reponsibility to ensure that the addresses apply to
// both reports.
//
static void cov_report(bool report_unread, bool report_unwritten, uint16_t first_addr, uint16_t last_addr)
{
    char *st = "(unknown)";
    if (first_addr < equoffset && symtable[first_addr])
        st = symtable[first_addr];
    else if (first_addr >= equoffset && equtable[first_addr - equoffset])
        st = equtable[first_addr - equoffset];
    printf("%s %04x - %04x (%2d bytes) %s\n",
        report_unread ? (report_unwritten ? "unused" : "unread") : (report_unwritten ? "unwritten" : "BUG!" ),
        first_addr, last_addr, last_addr - first_addr + 1, st);
}


// Provide textural summary of read/write coverage of a particular area of ROM or RAM.
// ROM coverage will be useful if we expect a certain test to read a data structure,
// and RAM coverage will be used over the whole area at the end of concatenated tests.
//
void coverage_rw(const i8080 *c, uint16_t area_start, uint16_t area_len) {
    // Unread and unwritten (RAM)
    bool in_unread = false;
    bool in_unwritten = false;
    bool report_unread = false;
    bool report_unwritten = false;
    uint16_t unread_start = 0;
    uint16_t unwritten_start = 0;
    printf("Coverage Report: Read/Write from %04hx to %04hx\n", area_start, area_start + area_len - 1);
    for (uint16_t addr = area_start; addr < area_start + area_len; ++addr) {
        bool this_unread = (c->coverage[addr] & (COV_READ | COV_DMA)) == 0;
        bool this_unwritten = (c->coverage[addr] & COV_WRITE) == 0;

        //printf("%04hx %-6s %-9s [state: %-9s %-12s]\n", addr, this_unread ? "unread" : "", this_unwritten ? "unwritten": "",
        //    in_unread ? "in unread" : "", in_unwritten ? "in unwritten" : "");

        if (this_unread) {
            if (!in_unread) {
                in_unread = true;
                unread_start = addr;
            }
        }
        else if (in_unread) {
            report_unread = true;
        }

        if (this_unwritten) {
            if (!in_unwritten) {
                in_unwritten = true;
                unwritten_start = addr;
            }
        }
        else if (in_unwritten) {
            report_unwritten = true;
        }

        if (report_unread && report_unwritten && unread_start == unwritten_start) {
            // Matching areas makes this an UNUSED report
            //char *st = "(unknown)";
            //if (equtable[unread_start - equoffset])
            //    st = equtable[unread_start - equoffset];
            //printf("unused %04x - %04x (%2d bytes) %s\n", unread_start, addr - 1, addr - unread_start, st);
            cov_report(report_unread, report_unwritten, unread_start, addr - 1);
            in_unread = report_unread = false;
            in_unwritten = report_unwritten = false;
        }
        if (report_unread) {
            // As this section doesn't exactly match unread section, dump a pending unread recport
            //char *st = "(unknown)";
            //if (equtable[unread_start - equoffset])
            //    st = equtable[unread_start - equoffset];
            //printf("unread %04x - %04x (%2d bytes) %s\n", unread_start, addr - 1, addr - unread_start, st);
            cov_report(report_unread, report_unwritten, unread_start, addr - 1);
            in_unread = report_unread = false;
        }
        if (report_unwritten) {
            //char *st = "(unknown)";
            //if (equtable[unwritten_start - equoffset])
            //    st = equtable[unwritten_start - equoffset];
            //printf("unwritten %04x - %04x (%2d bytes) %s\n", unwritten_start, addr - 1, addr - unwritten_start, st);
            cov_report(report_unread, report_unwritten, unread_start, addr - 1);
            in_unwritten = report_unwritten = false;
        }
    }
    if (in_unread && in_unwritten && unread_start == unwritten_start) {
        cov_report(in_unread, in_unwritten, unread_start, area_start + area_len - 1);
        in_unread = in_unwritten = false;
    }
    if (in_unread) {
        cov_report(in_unread, in_unwritten, unread_start, area_start + area_len - 1);
        in_unread = false;
    }
    if (in_unwritten)
        cov_report(in_unread, in_unwritten, unwritten_start, area_start + area_len - 1);
}

