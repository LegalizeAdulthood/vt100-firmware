#include "vt100_memory.h"

#include <stdlib.h>

uint8_t *memory;

bool memory_init() {
    memory = malloc(MEMORY_SIZE);
    return memory != NULL;
}
