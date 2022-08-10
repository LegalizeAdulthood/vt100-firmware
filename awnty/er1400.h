#ifndef ER1400_H
#define ER1400_H 1

#include <stdint.h>

void er1400_init();
void er1400_write(uint8_t command, uint8_t data);
void er1400_erase();
void er1400_clock(int clock);
int er1400_read();
void er1400_bug(int buggy);

void er1400_load(const char *fname);
void er1400_save();

#endif
