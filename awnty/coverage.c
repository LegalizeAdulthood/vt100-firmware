#include "coverage.h"

#include "vt100_memory.h"
#include "sdl_gd.h"

#include <gd.h>
#include <gdfonts.h>
#include <gdfontt.h>

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

// Prime the coverage array with details of data structures and presumed
// unreachable code, filled out during disassembly.
//
void coverage_load(const i8080* c, const char *fname)
{
    FILE *covf = fopen(fname, "r");
    if (!covf) {
        fprintf(stderr, "Warning: missing coverage areas: %s\n", fname);
        return;
    }

    uint16_t addr_start, addr_end;
    char covctype;
    char *lineptr = NULL;
    size_t linesize;
    while (getline(&lineptr, &linesize, covf) >= 0) {
        if (sscanf(lineptr, "%c %04hx %04hx", &covctype, &addr_start, &addr_end) == 3) {
            int covitype = 0;
            if (covctype == 'd')
                covitype = COV_DATA;
            else if (covctype == 'u')
                covitype = COV_UNREACH;
            else {
                fprintf(stderr, "Ignoring unknown coverage type '%c' in file\n", covctype);
                continue;
            }
            //printf("Coverage '%c' from %04hx to %04hx\n", covctype, addr_start, addr_end);
            for (uint16_t addr = addr_start; addr <= addr_end; ++addr)
                c->coverage[addr] |= covitype;
        }
    }
    free(lineptr);
    fclose(covf);
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

void coverage_graphic_sdl(const i8080 *c, SDL_Renderer *rend)
{
    int isc = 7; // size of each dot + gap
    int xo = 20;
    int yo =  8;

    SDL_Color black =   {   0,   0,   0, 255 };
    SDL_Color green =   {   0, 255,   0, 255 };
    SDL_Color amber =   { 192, 160,   0, 255 };
    SDL_Color white =   { 255, 255, 255, 255 };
    SDL_Color yellow =  { 255, 255,   0, 255 };
    SDL_Color grey1 =   {  64,  64,  64, 255 };
    SDL_Color dullred = { 128,   0,   0, 255 };
    SDL_Color magenta = { 192,   0, 192, 255 };
    SDL_Color blue =    {   0,   0, 255, 255 };
    SDL_Color red    =  { 255,   0, 255, 255 };
    SDL_Color cyan =    {   0, 192, 192, 255 };

    SDL_SetRenderDrawColor(rend, 0, 0, 0, 255);
    SDL_RenderClear(rend);


    for (int addr = 0x08; addr < 0x80; addr += 0x08) {
        SDL_Color col = addr & 0x000f ? grey1 : white;
        SDL_SetRenderDrawColor(rend, col.r, col.g, col.b, col.a);
        SDL_RenderDrawLine(rend, xo + addr * isc - 1, yo + 0 * isc, xo + addr * isc - 1, yo + (0x3000 / 128 + 1) * isc);
    }
    for (int addr = 0x0000; addr < 0x3100; addr += 0x0100) {
        SDL_Color col = addr & 0x0100 ? grey1 : white;
        SDL_SetRenderDrawColor(rend, col.r, col.g, col.b, col.a);
        int y = yo + (addr / 128 + (addr >= 0x2000)) * isc - 1;
        SDL_RenderDrawLine(rend, xo, y, xo + 0x80 * isc - 1, y);
    }

    for (int addr = 0; addr < 0x3000; ++addr) {
        int x = addr % 128;
        int y = addr / 128 + (addr >= 0x2000);
        SDL_Color col = black;
        // For coverage colours, information discovered by running the program takes priority over
        // the assertions about symbols and unreachability. (Though if we mark a section as unreachable
        // based on static analysis and it gets executed, we should note that at the end.)
        //
        if ((c->coverage[addr] & 0xf) != 0) {
            switch (c->coverage[addr] & 0xf) {
                case COV_EXEC:              col = green; break;
                case COV_READ:              col = grey1; break;
                case COV_READ + COV_EXEC:   col = green; break;
                case COV_WRITE:             col = dullred; break;
                case COV_WRITE + COV_READ:  col = magenta; break;
                case COV_DATA:              col = amber; break;
                case COV_DATA + COV_READ:   col = yellow; break;
            }
        }
        else if (c->coverage[addr] & COV_UNREACH) { // trumps UNREACH + SYMBOL
            col = red;
        }
        else if (c->coverage[addr] == COV_SYMBOL) { // we have a symbol for here (applied after the run)
            col = blue;
        }
        SDL_Rect fillrect = { xo + x * isc, yo + y * isc, isc - 2, isc - 2 };
        SDL_SetRenderDrawColor(rend, col.r, col.g, col.b, col.a);
        SDL_RenderFillRect(rend, &fillrect);

        if (c->coverage[addr] & COV_DMA) {
            int brx = xo + (x + 1) * isc - 2;
            int bry = yo + (y + 1) * isc - 2;
            SDL_SetRenderDrawColor(rend, cyan.r, cyan.g, cyan.b, cyan.a);
            SDL_RenderDrawPoint(rend, brx, bry);
            SDL_RenderDrawPoint(rend, brx - 1, bry);
            SDL_RenderDrawPoint(rend, brx, bry - 1);
        }
    }

    for (int addr = 0; addr < 0x3000; addr += 0x200) {
        int x = addr % 128;
        int y = addr / 128 + (addr >= 0x2000);
        char adst[5];
        sprintf(adst, "%04x", addr);
        sdl_gdImageString(rend, gdFontGetTiny(), x, yo + (y + 1) * isc - 8, adst, white);
    }

    SDL_RenderPresent(rend);
}


