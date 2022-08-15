#ifndef SDL_GD_H
#define SDL_GD_H

#include <gd.h>
#include <SDL2/SDL.h>

void sdl_gdImageString(SDL_Renderer *rend, gdFontPtr f, int x, int y, char *str, SDL_Color col);

#endif
