#include "er1400.h"
#include <stdio.h>

int er1400_state = 0;
int er1400_addr = 0;
int er1400_count = 0;
uint16_t er1400_reg = 0;
uint16_t er1400_mem[100];
int er1400_data = 0;
char er1400_addr_string[21];
int er1400_last_clock = 0;
int er1400_is_faulty;

void er1400_init() {
    er1400_state = 0;
    er1400_addr = 0;
    er1400_count = 0;
    er1400_reg = 0;
    er1400_data = 0;
    er1400_last_clock = 0;
    er1400_is_faulty = 0;
}

// 3 bit command value, as presented to port, 1 bit data
void er1400_write(uint8_t command, uint8_t data) {
    command = command ^ 7; // negative logic, so invert command
    switch (command) {
    case 0: // STANDBY
        break;
    case 6: // ADDRESS
        // If we're switch to address for the first time, initialise counters
        if (er1400_state != 6) {
            er1400_count = 0;
            er1400_addr = 0;
            er1400_addr_string[20] = 0;
        }
        er1400_addr_string[er1400_count] = '0' + (data & 1);
        ++er1400_count;
        if ((data & 1) == 0) {
            if (er1400_count <= 10) {
                er1400_addr = 10 * (10 - er1400_count);
            }
            else if (er1400_count <= 20) {
                er1400_addr += 20 - er1400_count;
            }
            else {
                printf("addr count too high: %d\n", er1400_count);
            }
        }
        //if (er1400_count == 20) {
        //    int intended_address = 99 - (10 * (er1400_addr % 10) + er1400_addr / 10);
        //    printf("ER1400 address = %s  %02d (%02d)\n", er1400_addr_string, er1400_addr, intended_address);
        //}
        break;
    case 1: // READ
        // Simulate a buggy NVR (always incorrect checksum) with "bug nvr"
        er1400_reg = er1400_is_faulty ? 0 : er1400_mem[er1400_addr];
        //printf("NVR READ  %02d => %04x\n", er1400_addr, er1400_reg);
        break;
    case 5: // SHIFT DATA OUT
        break;
    case 2: // ERASE
        er1400_mem[er1400_addr] = 0;//x3fff;
        break;
    case 7: // ACCEPT DATA
        // Store data uninverted (as arrives at port)
        er1400_reg = (er1400_reg << 1) | (data ^ 1);
        break;
    case 3: // WRITE
        er1400_mem[er1400_addr] = er1400_reg & 0x3fff;
        //printf("NVR WRTE %02d => %04x\n", er1400_addr, er1400_reg);
        break;
    case 4: // NOT USED
        break;
    }
    er1400_state = command;
}

void er1400_erase() {
    for (int loc = 0; loc < 100; ++loc)
        er1400_mem[loc] = (uint16_t)0;//x3fff;
}

// Clocking only matters if we're shifting data out
void er1400_clock(int clock) {
    if (er1400_state == 5) { // shift data out
        if (!er1400_last_clock && clock) { // next bit on clock high
            er1400_data = (er1400_reg & 0x2000) != 0;
            er1400_reg <<= 1;
            //printf(" H %d\n", er1400_data);
        }
        er1400_last_clock = clock;
    }
}

// Data out goes through inverting comparator (E48) so back to positive logic
int er1400_read() {
    return er1400_data ^ 1;
}

void er1400_load(const char *fname) {
    FILE *nvri = fopen(fname, "r");
    if (nvri) {
        printf("READING NVR FROM er1400.bin\n");
        fread(er1400_mem, sizeof(uint16_t), 100, nvri);
        fclose(nvri);
    }
    else {
        printf("ERASING NVR\n");
        er1400_erase();
    }
}

void er1400_save() {
    FILE *nvr = fopen("er1400.bin", "w");
    fwrite(er1400_mem, sizeof(uint16_t), 100, nvr);
    fclose(nvr);
}

void er1400_bug(int buggy) {
    er1400_is_faulty = buggy;
}
