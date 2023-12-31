// This file uses the 8080 emulator to run the test suite (roms in cpu_tests
// directory). It uses a simple array as memory.

// decl to get nanosleep()
#define _POSIX_C_SOURCE 200809L

#include <gd.h>
#include <gdfonts.h>
#include <gdfontt.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "i8080.h"

#include <ctype.h>
#include <time.h>

#include <SDL2/SDL.h>

#include "coverage.h"
#include "er1400.h"
#include "sdl_gd.h"
#include "vt100_memory.h"

uint8_t chargen[2048];
uint8_t alt_chargen[2048];

int opt_coverage = 1;

//FILE *logmem;

const char *c0_names[32] = {
    "NUL",  "SOH",  "STX",  "ETX",  "EOT",  "ENQ",  "ACK",  "BEL",
    "BS",   "HT",   "LF",   "VT",   "FF",   "CR",   "SO",   "SI",
    "DLE",  "XON",  "DC2",  "XOFF", "DC4",  "NAK",  "SYN",  "ETB",
    "CAN",  "EM",   "SUB",  "ESC",  "FS",   "GS",   "RS",   "US"
};

// Pending interrupts
bool kbdi = false;
bool reci = false;
bool vbi = false;

int skip_display = 0; // investigating "jump back" while smooth scrolling

unsigned long vbi_cycles = 46080; // 60 Hz
unsigned long next_vbi = 46080;
unsigned long next_reci = 0;
unsigned long next_kbdi = 0;
unsigned long next_cov = 10000;
// Absolute number of cycles when we last drew the screen. Used at the beginning of execution
// when we'd like to know about the keyboard LEDs, but there haven't been any video interrrupts
// yet.
unsigned long last_screen = 0;
unsigned long command_pause = 10000000;
// With plain text, autowrap and jump scrolling, rx_gap can be reduced to 3000 cycles (1ms)
// without ever exhausting the receive buffer (and causing the terminal to send XOFF).
unsigned long rx_gap = 30000;
unsigned long key_gap = 5000;
uint8_t keyboard_status;
int lba7 = 0;
unsigned long next_lba7 = 88;

uint8_t key_feed[4];
int key_times = 0;
int key_count = 0;
int key_index = 0;
int done_keys = 0;
int key_pause = 0;
int conf_pause = 10; // user-configured that becomes the pause for each key

bool need_command;
bool feeding_pause;
long unsigned int pause_cycles;

long unsigned int remaining_cycles = 0;

long unsigned int receive_count = 0;
long unsigned int receive_index = 0;
int receive_feed[1000];

int kbdi_count = 0;

bool pusart_mode = true; // if PUSART write addresses mode register
uint8_t pusart_command = 0; // latest command byte sent (don't store mode bytes)

uint8_t nvr_latch = 0; // last value written to NVR latch (for reading back SPDI)

uint8_t oldx[6];

static bool test_finished = 0;

/* Things this VT100 is fitted with */
static int have_avo = 1;
static int have_gpo = 1;
static int have_stp = 0;
static int have_loopback = 0;

/* Bugs we might want to invoke */
static int bug_ram = 0;
static int bug_pusart = 0; // provoke framing error

// DC011 video timing chip. The only interesting signal we want from here is 80/132 columns
bool dc011_132_columns = false;

// DC012 video control chip.
int dc012_reverse_field = 0;
int dc012_blink_ff = 0;
int dc012_scroll_latch = 0;
int dc012_scroll_latch_low = 0;
int dc012_basic_attribute_reverse = 0;

const uint16_t LOC_RX_HEAD = 0x20c0;
const uint16_t LOC_RX_TAIL = 0x20c1;
const uint16_t LOC_ABACK_BUFFER = 0x217b;
const uint16_t LOC_LOCAL_MODE = 0x21a5;
const uint16_t LOC_SETUP_B1 = 0x21a6;

const int SCREEN_LINES = 24;

SDL_Window *cov_window = NULL;
SDL_Renderer *cov_renderer = NULL;

SDL_Window *scr_window = NULL;
SDL_Renderer *scr_renderer = NULL;
SDL_Texture *scr_font1 = NULL;
SDL_Texture *scr_font2 = NULL;
SDL_Texture *scr_fontt = NULL;
SDL_Texture *scr_fontb = NULL;

static void sdl_screen(const i8080 *c, SDL_Renderer *rend);

static uint8_t rb(void *userdata __attribute__ ((unused)), uint16_t addr) {
    if (bug_ram && (addr == 0x2222 || addr == 0x3222))
        return 0x88;
    if (addr < 0x3000)
        return memory[addr];
    else if (have_avo)
        return memory[addr] & 0x0f; // AVO is 4 bits wide
    else
        return 0x0f;
}

static void wb(void* userdata __attribute__ ((unused)), uint16_t addr, uint8_t val) {
    //fprintf(logmem, "W %04x %02x\n", (unsigned int)addr, (unsigned int)val);
    memory[addr] = val;
}


static uint8_t int_acknowledge(void *userdata __attribute__ ((unused)) ) {
    //i8080* const c = (i8080*) userdata;

    uint8_t iop = 0xc7 + (vbi << 5) + (reci << 4) + (kbdi << 3);
    if (iop == 0xc7)
        iop = 0;


    //printf("iack %02x %s %s %s\n", iop, vbi ? "v" : " ", reci ? "r" : "", kbdi ? "k" : "");
    return iop;
}

static uint8_t port_in(void *userdata, uint8_t port) {
    const i8080 *c = (i8080 *) userdata;
    uint8_t val = 0;
    if (port == 0x00) {
        reci = false;
        val = 0;
        if (receive_index < receive_count) {
            val = receive_feed[receive_index];
            ++receive_index;
            if (receive_index < receive_count) {
                next_reci = c->cyc + rx_gap;
            }
            else {
                // This particularly applies to data loopback test, where we kick off the test,
                // head into a pause and feed transmitted characters back into the terminal for
                // the test, without wanting to read further commands. So the pause has to be
                // as long as we expect the test to last (very short)
                need_command = !feeding_pause;
                next_reci = 0;
            }
        }
        //printf("\tRX %02x\n", val);
    }
    else if (port == 0x01) {
        if (pusart_command & 0x02)
            val |= 0x80;
        if (bug_pusart)
            val |= 0x38; // mix-in some errors
        //printf("in pusart status (01) -> %02x\n", val);
    }
    else if (port == 0x42) {
        val = 0x81 | (lba7 << 6) | (er1400_read() << 5) | (have_stp << 3) | (!have_gpo << 2) | (!have_avo << 1);
        //printf("in flags -> %02x\n", val);
    }
    else if (port == 0x82) {
        kbdi = false;
        next_kbdi = 0;
        if (key_pause-- > 0) {
            //printf("k in pause %d\n", key_pause);
            val = 0x7f;
        }
        else if (key_count > 0) {
            //printf("index %d count %d times %d\n", key_index, key_count, key_times);
            if (key_index < key_count) {
                val = key_feed[key_index];
                ++key_index;
                next_kbdi = c->cyc + key_gap;
            }
            else {
                val = 0x7f; // terminate this scan
                if (++key_times < 2)
                    // need to go round again (when triggered)
                    key_index = 0;
                else {
                    key_count = 0;
                    need_command = true;//++done_keys;
                }
            }
        }
        else {
            val = 0x7f;
            //printf("keyboard scan %d\n", ++kbdi_count);
        }
        if (val != 0x7f) {
            // printf("KEYBOARD %02x\n", val);
        }
        //printf("in 0x82 clears kbdi\n");
    }
    else if (port == 0x22) {
        if (have_loopback) {
            if ((pusart_command & 0x20) == 0)
                val |= 0x90;
            if ((pusart_command & 0x02) == 0)
                val |= 0x20;
            if (nvr_latch & 0x20)
                val |= 0x40;
        }
        //printf("in modem buffer (22) -> %02x\n", val);
    }
    else {
        printf("in OTHER(%02x) -> %02x\n", port, val);
    }
    return val;
}

static void port_out(void *userdata, uint8_t port, uint8_t value) {
    const i8080 *c = (i8080 *) userdata;

    if (port == 0x62) {
        //if (value != nvr_latch)
        //    printf("out nvr_latch %02x BIT 5 %d\n", value, (value & 0x20) != 0);
        nvr_latch = value;
        //int command = ~(value >> 1) & 0x07;
        er1400_write((value >> 1) & 7, value & 1); // WAS inverted
    }
    else if (port == 0x42) {
        //printf("out brightness %02x\n", value);
    }
    else if (port == 0x82) {
        if ((value ^ keyboard_status) & 0x3f) { // have any LEDs changed?
            keyboard_status = value;
            char *ls[7] = { "ONLINE", "LOCAL", "KBDLOCKED", "L1", "L2", "L3", "L4" };
            int ledstat[7];
            ledstat[0] = (keyboard_status & 0x20) == 0;
            ledstat[1] = !ledstat[0];
            ledstat[2] = (keyboard_status & 0x10) != 0;
            ledstat[3] = (keyboard_status & 0x08) != 0;
            ledstat[4] = (keyboard_status & 0x04) != 0;
            ledstat[5] = (keyboard_status & 0x02) != 0;
            ledstat[6] = (keyboard_status & 0x01) != 0;

            printf("Keyboard LEDs:");
            for (int led = 0; led < 7; ++led) {
                printf(" %s", ledstat[led] ? ls[led] : "");
            }
            printf("\n");

        }
        // Initial keyboard test spams the keyboard port, so make
        // we don't indefinitely delay the response.
        keyboard_status = value;
        if (next_kbdi == 0 && (value & 0x40)) { // "scan"
            next_kbdi = c->cyc + key_gap;
            //printf("SCAN next kbd int at cycle %lu\n", next_kbdi);
        }
    }
    else if (port == 0x00) {
        if (value < 32) {
            if (value == 0x13) // XOFF
                printf("\t\t\033[41mTX %02x  %s\033[m\n", value, c0_names[value]);
            else if (value == 0x11) // XON
                printf("\t\t\033[42mTX %02x  %s\033[m\n", value, c0_names[value]);
            else
                printf("\t\tTX %02x  %s\n", value, c0_names[value]);
        }
        else
            printf("\t\tTX %02x  %c\n", value, value < 127 ? value : ' ');
        if (have_loopback) {
            receive_count = 1;
            receive_index = 0;
            receive_feed[0] = value;
            next_reci = c->cyc + rx_gap;
        }
    }
    else if (port == 0x02) {
        //printf("out baudrate %02x\n", value);
    }
    else if (port == 0xa2) {
        switch (value & 0x0f) { // only a 4-bit value is decoded
            case  0:
            case  1:
            case  2:
            case  3:
                // always loaded low-order first (TM §4.6.3.1), so don't show activation
                dc012_scroll_latch_low = value & 0x03;
                break;
            case  4:
            case  5:
            case  6:
            case  7:
                dc012_scroll_latch = dc012_scroll_latch_low | (value & 0x03) << 2;
                //printf("DC012 scroll latch = %d\n", dc012_scroll_latch);
                break;
            case  8:
                dc012_blink_ff = !dc012_blink_ff;
                //printf("DC012 toggled blink flip flop\n");
                break;
            case  9: 
                vbi = 0; // clear vertical blank interrupt
                sdl_screen(c, scr_renderer);
                break;
            case 10:
                dc012_reverse_field = 1;
                //printf("DC012 set to reverse field\n");
                break;
            case 11:
                dc012_reverse_field = 0;
                //printf("DC012 set to normal field\n");
                break;
            case 12:
                dc012_basic_attribute_reverse = 0;
                dc012_blink_ff = 0;
                //printf("DC012 basic attribute is underline (and clear blink)\n");
                break;
            case 13:
                dc012_basic_attribute_reverse = 1;
                dc012_blink_ff = 0;
                //printf("DC012 basic attribute is reverse (and clear blink)\n");
                break;
            default:
                dc012_blink_ff = 0;
                //printf("DC012 <- 0x%02x RESERVED\n", value);
                break;
        }
    }
    else if (port == 0xc2) {
        //printf("out DC011 %02x\n", value);
        if (value == 0)
            dc011_132_columns = false;
        else if (value == 0x10)
            dc011_132_columns = true;
    }
    else if (port == 0x01) {
        //printf("out pusart cmd %02x\n", value);
        if (!pusart_mode) {
            pusart_command = value;
            pusart_mode = (pusart_command & 0x40) != 0;
            if (!pusart_mode) {
            //    printf("\t\tRTS = %d  DTR = %d\n", (pusart_command & 0x20) != 0, (pusart_command & 0x02) != 0);
            }
        }
        else
            pusart_mode = false;
    }
    else {
        printf("out OTHER(%02x) %02x\n", port, value);
    }
}

static inline int load_file(const char *filename, uint16_t addr) {
  FILE *f = fopen(filename, "rb");
  if (f == NULL) {
    fprintf(stderr, "error: can't open file '%s'.\n", filename);
    return 1;
  }

  // file size check:
  fseek(f, 0, SEEK_END);
  size_t file_size = ftell(f);
  rewind(f);

  if (file_size + addr >= MEMORY_SIZE) {
    fprintf(stderr, "error: file %s can't fit in memory.\n", filename);
    return 1;
  }

  // copying the bytes in memory:
  size_t result = fread(&memory[addr], sizeof(uint8_t), file_size, f);
  if (result != file_size) {
    fprintf(stderr, "error: while reading file '%s'\n", filename);
    return 1;
  }

  fclose(f);
  return 0;
}

// Two helper routines for screen() so we get coverage information without the
// PC censoring that the main routines do.

static uint8_t dma_rb(const i8080 *c, uint16_t addr) {
    c->coverage[addr] |= COV_DMA;
    if (addr < 0x3000)
        return memory[addr];
    else if (have_avo)
        return memory[addr] & 0x0f; // AVO is 4 bits wide
    else
        return 0x0f;
}

// Big-endian, for DMA addresses
static uint16_t dma_rw(const i8080 *c, uint16_t addr) {
    c->coverage[addr] |= COV_DMA;
    c->coverage[addr + 1] |= COV_DMA;
    return (memory[addr] << 8) | memory[addr + 1];
}

// Produce a fairly accurate picture of the VT100 screen. This is more accurate than it needs
// to be for coverage purposes, but it perhaps makes it clearer why the serial FIFO can fill
// and terminal starts sending XOFFs when you think it's just displaying characters. There can
// also be a display before operations like clearing the screen too.
//
#define GL_ATTR_BLINK(c) (((c) & 1) == 0)
#define GL_ATTR_UNDERSCORE(c) (((c) & 2) == 0)
#define GL_ATTR_BOLD(c) (((c) & 4) == 0)
#define GL_ATTR_ALT(c) (((c) & 8) == 0)

#define GL_BASE_ATTR(c) (((c) & 0x80) != 0)

#define LINE_SCROLLS(l) (((l) & 0x08) != 0)

static void sdl_screen(const i8080 *c, SDL_Renderer *rend)
{
    const char lnat_size_mask = 0x06;
    const char lnat_size_bottom = 0x00;
    const char lnat_size_top    = 0x02;
    const char lnat_size_single = 0x06;

    const char line_terminator = 0x7f;

    int xo = 20; // room for symbols on left?
    int yo = 0;
    int margin = 6;
    SDL_Color black  =      {   0,   0,   0, 255 };
    SDL_Color dull_orange = {  57,  22,   5, 255 };
    SDL_Color grey50 =      { 128, 128, 128, 255 };
    SDL_Color grey75 =      { 192, 192, 192, 255 };
    SDL_Color white  =      { 255, 255, 255, 255 };
    SDL_Color orange =      { 226,  87,  20, 255 };

    SDL_Rect wholescr = { 0, 0, xo + 10 * 80 + 2 * margin, yo + SCREEN_LINES * 20 + 40 };
    SDL_SetRenderDrawColor(rend, black.r, black.g, black.b, black.a);
    SDL_RenderFillRect(rend, &wholescr);

    SDL_SetRenderDrawColor(rend, black.r, black.g, black.b, black.a);
    SDL_Rect statarea = { 0, yo + SCREEN_LINES * 20 + 2 * margin, xo + 10 * 80, 40 };
    // (still black)
    SDL_RenderFillRect(rend, &statarea);

    SDL_SetRenderDrawColor(rend, orange.r, orange.g, orange.b, orange.a);

    SDL_RenderDrawLine(rend, xo + margin, yo, xo + margin + 80 * 10, yo);
    SDL_RenderDrawLine(rend, xo + margin, yo + SCREEN_LINES * 20 + 2 * margin - 1, xo + margin + 80 * 10, yo + SCREEN_LINES * 20 + 2 * margin - 1);
    SDL_RenderDrawLine(rend, xo, yo + margin, xo, yo + margin + SCREEN_LINES * 20);
    SDL_RenderDrawLine(rend, xo + 2 * margin - 1 + 80 * 10, yo + margin, xo + 2 * margin - 1 + 80 * 10, yo + margin + SCREEN_LINES * 20);
    int xc = xo + margin;
    int yc = yo + margin;
    SDL_Point curve_tl[] = {{ xc - 6, yc - 1 }, { xc - 6, yc - 2 }, { xc - 5, yc - 3 }, { xc - 5, yc - 4 },
                            { xc - 4, yc - 5 }, { xc - 3, yc - 5 }, { xc - 2, yc - 6 }, { xc - 1, yc - 6 } };
    SDL_RenderDrawPoints(rend, curve_tl, 8);
    xc = xo + margin + 80 * 10 - 1;
    SDL_Point curve_tr[] = {{ xc + 6, yc - 1 }, { xc + 6, yc - 2 }, { xc + 5, yc - 3 }, { xc + 5, yc - 4 },
                            { xc + 4, yc - 5 }, { xc + 3, yc - 5 }, { xc + 2, yc - 6 }, { xc + 1, yc - 6 } };
    SDL_RenderDrawPoints(rend, curve_tr, 8);
    yc = yo + margin + SCREEN_LINES * 20 - 1;
    SDL_Point curve_br[] = {{ xc + 6, yc + 1 }, { xc + 6, yc + 2 }, { xc + 5, yc + 3 }, { xc + 5, yc + 4 },
                            { xc + 4, yc + 5 }, { xc + 3, yc + 5 }, { xc + 2, yc + 6 }, { xc + 1, yc + 6 } };
    SDL_RenderDrawPoints(rend, curve_br, 8);
    xc = xo + margin;
    SDL_Point curve_bl[] = {{ xc - 6, yc + 1 }, { xc - 6, yc + 2 }, { xc - 5, yc + 3 }, { xc - 5, yc + 4 },
                            { xc - 4, yc + 5 }, { xc - 3, yc + 5 }, { xc - 2, yc + 6 }, { xc - 1, yc + 6 } };
    SDL_RenderDrawPoints(rend, curve_bl, 8);
    
    uint8_t char_code[256];
    uint8_t char_attr[256];
    uint8_t line_attr = 0;
    uint8_t nchline = 0;

    int y = -20;
    int normal_scan_count = 0;
    int scan_count_in_use = 0;

    int dots_per_char = 10;
    int chars_per_line = 80;
    double column_scale = 1.0;

    // Perform rather crude scaling of x-axis for 132 columns
    if (dc011_132_columns) {
        dots_per_char = 9;
        chars_per_line = 132;
        column_scale = (10 * 80) / (9 * 132);
    }
        
    uint16_t addr = 0x2000; // Video RAM always starts here 
    uint16_t dmad = dma_rw(c, addr + 1);
    uint8_t next_line_attr = dmad >> 12;
    addr = 0x2000 | (dmad & 0xfff);

    // Order of processing for glyphs is:
    // 1. Retrieve bits
    // 2. Copy lowest bit twice more for 80 columns, once more for 132 columns
    // 3. Apply dot stretching. Photo evidence is that this is done before double-width expansion
    //    on the VT100, unlike VT220, where expansion took place before dot stretching and could
    //    therefore reveal more detail.
    // 4. Double up the 9 or 10 bits, if necessary.
    // 5. Apply to screen at given intensity, reversing as necessary and applying scan 9 underline
    //
    while (y < SCREEN_LINES * 20) {
        // Whenever the scan count comes back round to zero, we need to DMA a new line of data
        // from video RAM. If we are jump scrolling, this will always occur every ten scan lines,
        // but if we are leaving a scrolling region in the middle of a smooth scroll, there could
        // be fewer than ten scans remaining at the top.
        //
        if (scan_count_in_use == 0 || (!LINE_SCROLLS(next_line_attr) && normal_scan_count == 0)) {
            // Now determine if we are changing regions
            if (!LINE_SCROLLS(line_attr) && LINE_SCROLLS(next_line_attr)) {
                scan_count_in_use = dc012_scroll_latch;
            }
            else if (LINE_SCROLLS(line_attr) && !LINE_SCROLLS(next_line_attr)) {
                scan_count_in_use = normal_scan_count;
            }
            line_attr = next_line_attr;
            // We are expecting there to be a terminator before we reach 133 characters, but
            // the VT100's line buffer is 255 anyway. We will give up if we don't find a terminator.
            uint8_t ch;
            nchline = 0;
            while (nchline < 255 && (ch = dma_rb(c, addr)) != line_terminator) {
                char_code[nchline] = ch;
                char_attr[nchline] = dma_rb(c, addr + 0x1000);
                ++nchline;
                ++addr;
                addr = 0x2000 | (addr & 0xfff);
            }
            dmad = dma_rw(c, addr + 1);
            next_line_attr = dmad >> 12;
            addr = 0x2000 | (dmad & 0xfff);

            if (nchline == 255) {
                SDL_Rect raster = { xo + margin, yo + margin, 10 * 80, SCREEN_LINES * 20 };
                SDL_SetRenderDrawColor(rend, dull_orange.r, dull_orange.g, dull_orange.b, dull_orange.a);
                SDL_RenderFillRect(rend, &raster);
                break;
            }

            // FIXME give up if no terminator found
            // Annotate line attributes
            char width_ch[4] = { 'B', 'T', '2', '1' };
            char buf[3];
            snprintf(buf, 3, "%s%c", LINE_SCROLLS(line_attr) ? "S" : "-", width_ch[(line_attr >> 1) & 3]);
            if (y >= 0 && y < SCREEN_LINES * 20) // avoid the final terminator (extra line)
                sdl_gdImageString(rend, gdFontGetSmall(), 3, yo + y + margin + 3, buf, grey75);
        }

        // Now we've got a new line of characters, if necessary, get onto processing the next scan line
        int x = 0;
        uint8_t nbuf = 0; // offset into character buffer
        // Every glyph on this screen will produce the same number of pixels
        int numpix = dots_per_char;
        if ((line_attr & lnat_size_mask) != lnat_size_single)
            numpix = 2 * dots_per_char;
        // Clocked dots is now outside the loop because the TM says that the first dot of each character
        // comes from the previous character, so we prime the dots with a single zero and then only process
        // the first 9 dots (single width) or 19 dots (double width) from each subsequent character.
        uint32_t clocked_dots = 0;
        while (x < dots_per_char * chars_per_line) {
            uint8_t glyph_base = 0;
            uint8_t glyph_attr = 0xff;

            // Grab the code, attributes and dots for the appropriate glyph scan of this character
            if (nbuf < nchline) {
                glyph_base = char_code[nbuf];
                glyph_attr = char_attr[nbuf];
                ++nbuf;
            }
            uint8_t glyph_code = glyph_base & 0x7f; // don't want base attribute bit
            int glyph_scan = scan_count_in_use; // This is correct for single-height lines
            if ((line_attr & lnat_size_mask) == lnat_size_top)
                glyph_scan = glyph_scan / 2; // so we will fetch each of the first five scans twice
            else if ((line_attr & lnat_size_mask) == lnat_size_bottom)
                glyph_scan = glyph_scan / 2 + 5; // fetch each of the second five scans twice
            uint32_t glyph_dots = 0;
            if (GL_ATTR_ALT(glyph_attr))
                glyph_dots = alt_chargen[16 * glyph_code | ((glyph_scan - 1) & 0xf)];
            else
                glyph_dots = chargen[16 * glyph_code | ((glyph_scan - 1) & 0xf)];
            // TM says underscore is on scanline 9 (1-based), so 8 for us. Confirmed by screen shots, showing
            // underscore directly below baseline of characters.
            // Need to duplicate the right-hand dot for line-joining, twice
            glyph_dots = (glyph_dots << 1) | (glyph_dots & 1); //  9 bits
            if (!dc011_132_columns)
                glyph_dots = (glyph_dots << 1) | (glyph_dots & 1); // 10 bits

            // Dot stretching. The effect of this does not extend beyond the bits we already have.
            glyph_dots |= glyph_dots >> 1;

            if ((line_attr & lnat_size_mask) != lnat_size_single) {
                for (uint32_t glyph_mask = 1 << (dots_per_char - 1); glyph_mask != 0; glyph_mask >>= 1)
                    clocked_dots  = (clocked_dots << 2) | ((glyph_dots & glyph_mask) ? 3 : 0);
            }
            else {
                clocked_dots = (clocked_dots << numpix) | glyph_dots;
            }

            // Force underscore, if necessary. This overrides the last dot from previous character,
            // so that underscores are continuous. It also doesn't provide a last dot of one to the
            // next character, so that underscore does not trail beyond a reversed field.
            if (glyph_scan == 8 &&
                    ( GL_ATTR_UNDERSCORE(glyph_attr) || (!dc012_basic_attribute_reverse && GL_BASE_ATTR(glyph_base)) ))
                clocked_dots = 0x1ffffe;

            // Now send dots to screen with appropriate intensity, dot stretching and possible inversion
            // All the dots of a glyph will be sent with same intensity
            //
            // Only boldness and blinking affects intensity. Reverse and underscore attributes
            // only affect whether a dot is shown or not.
            SDL_Color intensity;
            // Non-bold blinking characters will go dimmer when blink flip flop is active
            if (!GL_ATTR_BOLD(glyph_attr) && GL_ATTR_BLINK(glyph_attr) && dc012_blink_ff)
                intensity = grey50;
            // 1. Normal characters are 75%
            // 2. Bold & blinking characters will go down to 75% when blink flip flop is active
            else if (!GL_ATTR_BOLD(glyph_attr) || (GL_ATTR_BOLD(glyph_attr) && GL_ATTR_BLINK(glyph_attr) && dc012_blink_ff))
                intensity = grey75;
            // Bold characters are 100%
            else
                intensity = white;
            SDL_SetRenderDrawColor(rend, intensity.r, intensity.g, intensity.b, intensity.a);
            int xoff = 0;
            // Multiple attributes are involved in reversing bits in this cell. Let's work them out:
            // 1. Reverse field (black on white characters)
            // 2. If the base attribute means reverse and the base attribute is set
            // 3. BUT - if (2) is true and the attribute is ALSO blink and the blink flip-flop is true, that reverses again.
            // As these are constant for a given character position, resolve them ahread of time, so we can XON with each
            // bit coming through:
            int reverse = dc012_reverse_field ^ // (1)
                    (dc012_basic_attribute_reverse && GL_BASE_ATTR(glyph_base)) ^ // (2)
                    ( (dc012_basic_attribute_reverse && GL_BASE_ATTR(glyph_base)) &&    // (3)
                        GL_ATTR_BLINK(glyph_attr) && dc012_blink_ff );                  // (3)
                    
            // Now draw all the bits except bit 0, which is reserved for the next character
            for (int bv = 1 << numpix; bv > 1; bv >>= 1) {
                int dot = ((clocked_dots & bv) != 0) ^ reverse;
                if (dot && y >= 0)
                    SDL_RenderDrawPoint(rend, xo + margin + column_scale * (x + xoff), yo + y + margin);
                ++xoff;
            }
            x += numpix;
        } // while x
        y += 2;
        normal_scan_count = (normal_scan_count + 1) % 10;
        scan_count_in_use = (scan_count_in_use + 1) % 10;
    }

    // Now extra terminal status information
    int ledstat[7];
    ledstat[0] = (keyboard_status & 0x20) == 0;
    ledstat[1] = !ledstat[0];
    ledstat[2] = (keyboard_status & 0x10) != 0;
    ledstat[3] = (keyboard_status & 0x08) != 0;
    ledstat[4] = (keyboard_status & 0x04) != 0;
    ledstat[5] = (keyboard_status & 0x02) != 0;
    ledstat[6] = (keyboard_status & 0x01) != 0;

    for (int led = 0; led < 7; ++led) {
        char *ls[7] = { "Online", "Local", "Kbd Lk", "L1", "L2", "L3", "L4" };
        sdl_gdImageString(rend, gdFontGetSmall(), xo + 20 + led * 40 - 3 * strlen(ls[led]), yo + 2 * margin + SCREEN_LINES * 20 + 6, ls[led], grey75);
        SDL_Rect rled = { xo + 20 + led * 40 - 8, yo + 2 * margin + SCREEN_LINES * 20 + 20, 16, 16 };
        if (ledstat[led])
            SDL_SetRenderDrawColor(rend, orange.r, orange.g, orange.b, orange.a);
        else
            SDL_SetRenderDrawColor(rend, grey50.r, grey50.g, grey50.b, grey50.a);
        SDL_RenderFillRect(rend, &rled);
    }

    char rx_space[20];
    int space = (int)memory[LOC_RX_TAIL] - (int)memory[LOC_RX_HEAD];
    if (space <= 0) space += 32;
    sprintf(rx_space, "Rx Space: %2d", space);
    sdl_gdImageString(rend, gdFontGetSmall(), xo + 20 + 10 * 60, yo + 2 * margin + SCREEN_LINES * 20 + 0, rx_space, grey75);

    uint8_t sb1 = memory[0x21a6];
    int swx= xo + 20 + 280;
    int swy= yo + 2 * margin + SCREEN_LINES * 20 + 18;
    SDL_Rect sb1r = { swx - 4, swy - 2, 30 * 4 + 3, 20 };
    SDL_SetRenderDrawColor(rend, grey50.r, grey50.g, grey50.b, grey50.a);
    SDL_RenderDrawRect(rend, &sb1r);

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "smoot", (sb1 & 0x80) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "jump ", (sb1 & 0x80) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "rep  ", (sb1 & 0x40) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "norep", (sb1 & 0x40) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "light", (sb1 & 0x20) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "dark ", (sb1 & 0x20) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "block", (sb1 & 0x10) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "under", (sb1 & 0x10) == 0 ? white : grey50);
    swx += 40;

    uint8_t sb2 = dma_rb(c, 0x21a7);
    SDL_Rect sb2r = { swx - 3, swy - 2, 30 * 4 + 3, 20 };
    SDL_SetRenderDrawColor(rend, grey50.r, grey50.g, grey50.b, grey50.a);
    SDL_RenderDrawRect(rend, &sb2r);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "m bel", (sb2 & 0x80) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "nobel", (sb2 & 0x80) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "k clk", (sb2 & 0x40) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "noclk", (sb2 & 0x40) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "ANSI ", (sb2 & 0x20) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "VT52 ", (sb2 & 0x20) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "a xon", (sb2 & 0x10) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "noxon", (sb2 & 0x10) == 0 ? white : grey50);
    swx += 40;

    uint8_t sb3 = dma_rb(c, 0x21a8);
    SDL_Rect sb3r = { swx - 3, swy - 2, 30 * 4 + 3, 20 };
    SDL_SetRenderDrawColor(rend, grey50.r, grey50.g, grey50.b, grey50.a);
    SDL_RenderDrawRect(rend, &sb3r);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "UK   ", (sb3 & 0x80) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "ASCII", (sb3 & 0x80) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "awrap", (sb3 & 0x40) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "-wrap", (sb3 & 0x40) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "newln", (sb3 & 0x20) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "no ln", (sb3 & 0x20) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "inter", (sb3 & 0x10) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "noint", (sb3 & 0x10) == 0 ? white : grey50);
    swx += 40;

    uint8_t sb4 = dma_rb(c, 0x21a9);
    SDL_Rect sb4r = { swx - 3, swy - 2, 30 * 4 + 3, 20 };
    SDL_SetRenderDrawColor(rend, grey50.r, grey50.g, grey50.b, grey50.a);
    SDL_RenderDrawRect(rend, &sb4r);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "even ", (sb4 & 0x80) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "odd  ", (sb4 & 0x80) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "par  ", (sb4 & 0x40) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "nopar", (sb4 & 0x40) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "8 bit", (sb4 & 0x20) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "7 bit", (sb4 & 0x20) == 0 ? white : grey50);
    swx += 30;

    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy,     "50 Hz", (sb4 & 0x10) != 0 ? white : grey50);
    sdl_gdImageString(rend, gdFontGetTiny(), swx, swy + 8, "60 Hz", (sb4 & 0x10) == 0 ? white : grey50);
    swx += 40;

    SDL_RenderPresent(rend);
}

static void dump_memory(uint16_t start_addr, int num_bytes) {
    int nb = 0;
    char ch[17];
    ch[16] = 0;
    for (uint16_t addr = start_addr; addr < start_addr + num_bytes; ++addr) {
        if ((nb % 16) == 0) printf("%04x: ", addr);
        printf(" %02x", memory[addr]);
        ch[nb % 16] = memory[addr] >= 32 && memory[addr] < 127 ? memory[addr] : '.';
        ch[(nb % 16) + 1] = 0;
        ++nb;
        if ((nb % 16) == 0) printf(" %s\n", ch);
    }
    if ((nb % 16) != 0) printf("%*s %s\n", 3 * (16 - (nb % 16)), "", ch);
}

static void dumpx() {
    char *locname[6] = { "why_xoff", "tx_xo_char", "tx_xo_flag", "received_xoff", "", "noscroll" };
    uint8_t newx[6];
    // Dump locations related to XON/XOFF processing
    for (uint16_t addr = 0; addr < 6; ++addr) {
        newx[addr] = memory[0x21bf + addr];
        if (newx[addr] != oldx[addr])
            printf("\t\t\t\t%-15s  %02x -> %02x\n", locname[addr], oldx[addr], newx[addr]);
        oldx[addr] = newx[addr];
    }
}

static void dump_switches() {
    uint8_t sb1 = memory[0x21a6];
    printf("SB1: %d%d%d%d  %s scroll, autorepeat %s, %s background, cursor %s\n",
        (sb1 >> 7) & 1, (sb1 >> 6) & 1, (sb1 >> 5) & 1, (sb1 >> 4) & 1,
        (sb1 & 0x80) ? "smooth" : "jump",
        (sb1 & 0x40) ? "on" : "off",
        (sb1 & 0x20) ? "light" : "dark",
        (sb1 & 0x10) ? "block" : "underline");
    uint8_t sb2 = memory[0x21a7];
    printf("SB2: %d%d%d%d  margin bell %s, keyclick %s, %s mode, Auto XON/XOFF %s\n",
        (sb2 >> 7) & 1, (sb2 >> 6) & 1, (sb2 >> 5) & 1, (sb2 >> 4) & 1,
        (sb2 & 0x80) ? "ON" : "OFF",
        (sb2 & 0x40) ? "ON" : "OFF",
        (sb2 & 0x20) ? "ANSI" : "VT52",
        (sb2 & 0x10) ? "ON" : "OFF");
}

int parse_dump(char *cmd, uint16_t *maddr, uint8_t *mlen) {
    int got_cmd = 0;
    if (strlen(cmd) > 5 && strncmp(cmd, "dump ", 5) == 0) {
        if (sscanf(&cmd[5], "%hx,%hhx", maddr, mlen) == 2)
            got_cmd = 1;
    }
    return got_cmd;
}

int parse_key(char *cmd, uint8_t *hex, uint8_t maxhex) {
    int nhex = 0;
    if (strlen(cmd) > 4 && strncmp(cmd, "key ", 4) == 0) {
        bool finished = false;
        int idx = 4;
        char strhex[3];
        while (!finished || nhex >= maxhex) {
            while (cmd[idx] == ' ' || cmd[idx] == ',')
                ++idx;
            if (isxdigit(cmd[idx]) && cmd[idx] != 0 && isxdigit(cmd[idx + 1])) {
                strhex[0] = cmd[idx];
                strhex[1] = cmd[idx + 1];
                strhex[2] = 0;
                hex[nhex] = strtol(strhex, NULL, 16);
                ++nhex;
                idx += 2;
            }
            else
                finished = true;
        }
    }
    else {
        //printf("not key\n");
    }
    return nhex;
}

int parse_serial(char *cmd, uint8_t *hex, int maxhex) {
    int nhex = 0;
    if (strlen(cmd) > 4 && strncmp(cmd, "serial ", 7) == 0) {
        bool finished = false;
        size_t idx = 7;
        char strhex[3];
        while (!finished || nhex >= maxhex) {
            while (cmd[idx] == ' ' || cmd[idx] == ',')
                ++idx;
            if (isxdigit(cmd[idx]) && cmd[idx] != 0 && isxdigit(cmd[idx + 1])) {
                strhex[0] = cmd[idx];
                strhex[1] = cmd[idx + 1];
                strhex[2] = 0;
                hex[nhex] = strtol(strhex, NULL, 16);
                ++nhex;
                idx += 2;
            }
            else if (cmd[idx] == '"') {
                while (++idx < strlen(cmd) && nhex < maxhex && cmd[idx] != '"') {
                    hex[nhex] = cmd[idx];
                    ++nhex;
                }
                ++idx;
                if (idx >= strlen(cmd))
                    finished = true;
            }
            else
                finished = true;
        }
    }
    else {
        //printf("not serial\n");
    }
    return nhex;
}

int parse_pause(char *cmd) {
    long pause = 0;
    if (strlen(cmd) > 6 && strncmp(cmd, "pause ", 6) == 0) {
        pause = strtol(&cmd[6], NULL, 10);
    }
    return pause;
}

void display_stack(const i8080 *c) {
    printf("Stack:\n");
    for (uint16_t addr = c->sp; addr < 0x204e; addr += 2) {
        uint16_t dest = memory[addr] | (memory[addr + 1] << 8);
        if (dest < 0x2000) {
            if (symtable[dest]) {
                printf("  %04hx  %s\n", dest, symtable[dest]);
            }
            else {
                int foundback = -1;
                for (int back = 0; back < 64; ++back) {
                    if (symtable[dest - back]) {
                        foundback = back;
                        break;
                    }
                }
                if (foundback >= 0)
                    printf("  %04hx  %s + %d\n", dest, symtable[dest - foundback], foundback);
                else
                    printf("  %04hx\n", dest);
            }
        }
        else {
            printf("  %04hx\n", dest);
        }
    }
}

// 8080 clock is main crystal 24.8832 MHz divided by 9, i.e. 2.7648 MHz
// 60 Hz vertical blank interrupt is therefore every 46080 cycles.
// LBA 7 changes state every 31.7778 µs, i.e. every 88 cycles (87.859)
//
static inline void run_test(i8080* const c, const char* filename, const char *testfile) {
    i8080_init(c);
    c->userdata = c;
    c->read_byte = rb;
    c->write_byte = wb;
    c->port_in = port_in;
    c->port_out = port_out;
    c->iack = int_acknowledge;
    memset(memory, 0, MEMORY_SIZE);
    bool started_command = false;
    need_command = false;
    feeding_pause = false;
    char lasttime[100];
    lasttime[0] = 0;

    er1400_init();

    if (load_file(filename, 0) != 0) {
        return;
    }
    printf("*** TEST: %s\n", filename);

    er1400_load("er1400.bin");

    printf("memory[0x17a2] = %02x\n", memory[0x17a2]);

    /* Seed coverage with data structures */
    coverage_load(c, "vt100-coverage.txt");

    c->pc = 0;

    FILE *cmdf = fopen(testfile, "r");
    if (!cmdf) {
        fprintf(stderr, "No command file\n");
        exit(1);
    }

    coverage_read_sym("vt100.sym");
    coverage_read_equ("vt100.equ");

    watch_init();

    test_finished = 0;

    sdl_screen(c, scr_renderer);

    while (!test_finished) {

        // uncomment following line to have a debug output of machine state
        // warning: will output multiple GB of data for the whole test suite
        if (c->pc == 0x0a14) { // about to pop stack
            printf("AT POP_TO_GROUND -- stack contains\n");
            display_stack(c);
            //dump_memory(c->sp, 2);
        }
        //if (c->pc >= 0x186d && c->pc <= 0x1889) {
        //    i8080_debug_output(c, false);
        //}

        if (c->pc == 0xca) {
            printf("NVR FAILED\n");
        }

        i8080_step(c);

        //dumpx();
        watch_check();

        if (c->pc == 0xea4) // in curkey_report
            printf("Popped curkey_queue -> %02x '%c'\n", c->b, (c->b & 0x7f) > 32 ? c->b & 0x7f : '.');
        if (c->pc == 0x0f18) { // send_key_byte
            printf("\n\n\nsend_key_byte: %02x '%c'\n", c->a, (c->a & 0x7f) > 32 ? c->a & 0x7f : '.');
        }

        if (c->cyc > next_vbi) {
            //sdl_screen(c, scr_renderer);
            vbi = true;
            next_vbi += vbi_cycles;
        }

        // Although screen is normally refreshed when the vertical blank interrupt
        // occurs (roughly), our window needs refreshing early on because we'd like
        // to update the keyboard LEDs. This delay is picked to be longer than the
        // normal VBI, so we only do this at (re)start.
        //
        if (c->cyc - last_screen > 100000) {
            sdl_screen(c, scr_renderer);
            last_screen = c->cyc;
        }

        if (next_reci != 0 && !reci && c->cyc > next_reci) {
            reci = true;
        }

        if (next_kbdi != 0 && c->cyc > next_kbdi) {
            kbdi = true;
        }

        if (c->cyc > next_lba7) {
            lba7 = !lba7;
            er1400_clock(lba7); // ER1400 is clocked by LBA7
            next_lba7 = c->cyc + 88;
        }

        // Level rather than edge!
        c->interrupt_pending = vbi || reci || kbdi;

        if (!started_command && c->cyc > command_pause) {
            started_command = need_command = true;
        }

        if (need_command) {
            char *lineptr = NULL;
            size_t linesize;
            uint16_t addr;

            if (getline(&lineptr, &linesize, cmdf) >= 0) {
                printf("Command: %s", lineptr); // lineptr has LF already
                uint8_t hex[100];
                uint8_t nhex;
                if (( nhex = parse_key(lineptr, hex, 100) )) {
                    need_command = false;
                    for (int i = 0; i < nhex; ++i)
                        key_feed[i] = hex[i] & 0x7f;
                    key_count = nhex;
                    key_times = 0;
                    key_index = 0;
                    key_pause = conf_pause;
                }
                else if ( strncmp(lineptr, "reset", 5) == 0) {
                    c->pc = 0;
                }
                else if ( strncmp(lineptr, "keygap ", 7) == 0) {
                    int gap;
                    if (sscanf(&lineptr[7], "%d", &gap) == 1) {
                        printf("Setting keygap to %d\n", gap);
                        conf_pause = gap;
                    }
                }
                else if (strncmp(lineptr, "rxgap ", 6) == 0) {
                    long gap;
                    gap = strtol(&lineptr[6], NULL, 10);
                    printf("Setting rxgap to %ld cycles\n", gap);
                    rx_gap = gap;
                }
                else if (( nhex = parse_serial(lineptr, hex, 100) )) {
                    need_command = false;
                    for (int i = 0; i < nhex; ++i)
                        receive_feed[i] = hex[i] & 0x7f;
                    receive_count = nhex;
                    receive_index = 0;
                    next_reci = c->cyc + rx_gap;
                }
                else if (( pause_cycles = parse_pause(lineptr) )) {
                    printf("Pause for %lu cycles\n", pause_cycles);
                    need_command = false;
                    feeding_pause = true;
                    pause_cycles = c->cyc + pause_cycles;
                }
                else if ( strncmp(lineptr, "local", 5) == 0 ) {
                    printf("Forcing local mode\n");
                    memory[LOC_LOCAL_MODE] = 0x20;
                }
                else if ( strncmp(lineptr, "online", 6) == 0 ) {
                    printf("Forcing online mode\n");
                    memory[LOC_LOCAL_MODE] = 0;
                }
                else if (parse_dump(lineptr, &addr, &nhex)) {
                    dump_memory(addr, nhex);
                }
                else if (strncmp(lineptr, "log ", 4) == 0) {
                    // already echoing commands - do something
                    // else if we don't echo commands by default
                }
                else if (strncmp(lineptr, "have ", 5) == 0) {
                    if (strncmp(&lineptr[5], "avo", 3) == 0)
                        have_avo = 1;
                    else if (strncmp(&lineptr[5], "gpo", 3) == 0)
                        have_gpo = 1;
                    else if (strncmp(&lineptr[5], "stp", 3) == 0)
                        have_stp = 1;
                    else if (strncmp(&lineptr[5], "loopback", 8) == 0) {
                        have_loopback = 1;
                        printf("FITTED loopback connector\n");
                    }
                }
                else if (strncmp(lineptr, "missing ", 8) == 0) {
                    if (strncmp(&lineptr[8], "avo", 3) == 0)
                        have_avo = 0;
                    else if (strncmp(&lineptr[8], "gpo", 3) == 0)
                        have_gpo = 0;
                    else if (strncmp(&lineptr[8], "stp", 3) == 0)
                        have_gpo = 0;
                    else if (strncmp(&lineptr[8], "loopback", 8) == 0) {
                        have_loopback = 0;
                        printf("REMOVED loopback connector\n");
                    }
                }
                else if (strncmp(lineptr, "bug ", 4) == 0) {
                    if (strncmp(&lineptr[4], "nvr", 3) == 0) {
                        er1400_bug(1); 
                    }
                    else if (strncmp(&lineptr[4], "ram", 3) == 0) {
                        bug_ram = 1;
                    }
                    else if (strncmp(&lineptr[4], "pusart", 6) == 0) {
                        bug_pusart = 1;
                    }
                }
                else if (strncmp(lineptr, "nobug ", 6) == 0) {
                    if (strncmp(&lineptr[6], "nvr", 3) == 0) {
                        er1400_bug(0);
                    }
                    else if (strncmp(&lineptr[6], "ram", 3) == 0) {
                        bug_ram = 0;
                    }
                    else if (strncmp(&lineptr[6], "pusart", 6) == 0) {
                        bug_pusart = 0;
                    }
                }
                else if (strncmp(lineptr, "poke ", 5) == 0) {
                    uint16_t loc;
                    uint8_t  val;
                    if (sscanf(&lineptr[5], "%4hx,%2hhx", &loc, &val) == 2) {
                        printf("POKE %04x <- %02x\n", loc, val);
                        memory[loc] = val;
                    }
                }
                else if (strncmp(lineptr, "dumpx", 5) == 0) {
                    dumpx();
                }
                else if (strncmp(lineptr, "switches", 8) == 0) {
                    dump_switches();
                }
                else if (strncmp(lineptr, "covrw ", 6) == 0) {
                    uint16_t loc, len;
                    if (sscanf(&lineptr[6], "%4hx,%4hx", &loc, &len) == 2) {
                        printf("COVERAGE\n");
                        coverage_rw(c, loc, len);
                    }
                    else {
                        fprintf(stderr, "Couldn't read <addr>,<len> from: %s", lineptr);
                    }
                }
                else if (strncmp(lineptr, "watch ", 6) == 0) {
                    uint16_t loc;
                    int interp = 0;
                    int params = sscanf(&lineptr[6], "%4hx,%d", &loc, &interp);
                    if (params >= 1) {
                        watch_add(loc, interp);
                    }
                    else {
                        fprintf(stderr, "Couldn't read <addr> from: %s", lineptr);
                    }
                }
                else if (strncmp(lineptr, "stack", 5) == 0) {
                    display_stack(c);
                }
            }
            else {
                free(lineptr);
                printf("Finished commands\n");
                remaining_cycles = c->cyc + 5000000;
                need_command = false;
            }
        }

        if (opt_coverage) {
            if (c->cyc > next_cov) {
               coverage_graphic_sdl(c, cov_renderer);
               next_cov += 1000000;
            }
        }

        if (feeding_pause && c->cyc > pause_cycles) {
            feeding_pause = false;
            need_command = true;
        }

        test_finished = remaining_cycles > 0 && c->cyc > remaining_cycles;

        char timestr[100];
        sprintf(timestr, "Time %.4f\n", c->cyc / 2764800.0);
        if (strcmp(timestr, lasttime) != 0) {
            //printf(timestr);
            strcpy(lasttime, timestr);
            struct timespec t;
            t.tv_sec = 0;
            t.tv_nsec = 100000;
            nanosleep(&t, NULL);
        }

    }

    int numexec = 0;
    int totsyms = 0;
    for (uint16_t symaddr = 0; symaddr < 0x2000; ++symaddr) {
        if (symtable[symaddr]) {
            ++totsyms;
            if (c->coverage[symaddr] & (COV_EXEC | COV_DATA)) {
                ++numexec;
            }
            else {
                // Don't count or print unexecuted symbols in unreachable sections!
                if (!(c->coverage[symaddr] & COV_UNREACH)) {
                    //printf("sym %04x %s\n", symaddr, symname);
                }
                else
                    --totsyms;
            }
            c->coverage[symaddr] |= COV_SYMBOL; // mark we have symbol
        }
    }
    printf("%4d/%4d reachable symbols executed\n", numexec, totsyms);

    // Unreachable and uncovered (ROM)
    if (opt_coverage) {
        int uncovered_bytes = 0;
        int start_uncovered = -1;
        for (int addr = 0x0000; addr < 0x2000; ++addr) {
            if (c->coverage[addr] == 0 || c->coverage[addr] == COV_SYMBOL) {
                if (start_uncovered < 0) // not currently in a section
                    start_uncovered = addr;
            }
            else {
                if (start_uncovered >= 0) {
                    int foundback = -1;
                    for (int back = 0; back < 32; ++back) {
                        if (symtable[start_uncovered - back]) {
                            foundback = back;
                            break;
                        }
                    }
                    if (foundback >= 0)
                        printf("uncovered %04x - %04x (%2d bytes) %s + %d\n", start_uncovered, addr - 1, addr - start_uncovered,
                                symtable[start_uncovered - foundback], foundback);
                    else
                        printf("uncovered %04x - %04x (%2d bytes)\n", start_uncovered, addr - 1, addr - start_uncovered);
                    uncovered_bytes += addr - start_uncovered;
                    start_uncovered = -1;
                }
            }
            if ( (c->coverage[addr] & COV_UNREACH) && (c->coverage[addr] & ~(COV_UNREACH | COV_SYMBOL)) ) {
                char also[100];
                also[0] = 0;
                if (c->coverage[addr] & COV_EXEC) strcat(also, " exec");
                if (c->coverage[addr] & COV_READ) strcat(also, " read");
                if (c->coverage[addr] & COV_WRITE) strcat(also, " write");
                if (c->coverage[addr] & COV_DATA) strcat(also, " data");
                //if (c->coverage[addr] & COV_SYMBOL) strcat(also, " symbol");
                printf("unreachable %04x also %s\n", addr, also);
            }
        }
        printf("Total uncovered bytes = %d\n", uncovered_bytes);

        coverage_rw(c, 0x2000, 0x1000);

        coverage_graphic_sdl(c, cov_renderer);
    }

    //er1400_save(); // don't want this saved automatically any more -- better to use "pristine" NVRAM load

    dump_memory(LOC_ABACK_BUFFER, 0x33);

    printf("Total cycles: %ld ~ %.1f seconds\n", c->cyc, c->cyc / 2768000.0);

}

int main(int argc, char *argv[]) {
    if (!memory_init()) {
        fputs("Couldn't allocate 64K memory\n", stderr);
        return 1;
    }

    //logmem = fopen("logmem.txt", "w");

    i8080 cpu;
    char testfile[255];
    if (argc > 1)
        strcpy(testfile, argv[1]);
    else
        strcpy(testfile, "t/vt100-tests.txt"); 
  
    FILE *charf = fopen("../bin/23-018E2.bin", "rb");
    if (charf) {
        fread(chargen, 1, 2048, charf);
        fclose(charf);
    }
    else {
        fputs("Missing chargen ROM ../bin/23-018E2.bin\n", stderr);
    }

    charf = fopen("alt-chargen.bin", "rb");
    if (charf) {
        fread(alt_chargen, 1, 2048, charf);
        fclose(charf);
    }
    else {
        fputs("Missing alt chargen ROM alt-chargen.bin\n", stderr);
        memset(alt_chargen, 0xff, 2048);
    }

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        fprintf(stderr, "Could not init: %s\n", SDL_GetError());
    }

    if (opt_coverage) {
        if (SDL_CreateWindowAndRenderer(129 * 7 - 1 + 20, 98 * 7 - 1 + 8, 0, &cov_window, &cov_renderer) < 0) {
            fprintf(stderr, "Could not create window: %s\n", SDL_GetError());
        }
        SDL_SetWindowTitle(cov_window, "Awnty Coverage");
    }

    int screen_scale = 1;
    if (SDL_CreateWindowAndRenderer(screen_scale * (20 + 10 * 80 + 2 * 6), screen_scale * (0 + SCREEN_LINES * 20 + 40 + 2 * 6), 0, &scr_window, &scr_renderer) < 0) {
        fprintf(stderr, "Could not create window: %s\n", SDL_GetError());
    }
    SDL_SetWindowTitle(scr_window, "Awnty Screen");
    SDL_RenderSetScale(scr_renderer, screen_scale, screen_scale);

    run_test(&cpu, "../bin/vt100.bin", testfile);

    free(memory);
    free(cpu.coverage);

    SDL_Quit();

    return 0;
}
