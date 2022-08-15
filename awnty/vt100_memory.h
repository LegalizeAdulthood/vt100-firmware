#ifndef VT100_MEMORY_H
#define VT100_MEMORY_H

#include <stdbool.h>
#include <stdint.h>

#define MEMORY_SIZE 0x10000

extern uint8_t *memory;

// true if successful, else malloc failed :-(
bool memory_init();

#endif

