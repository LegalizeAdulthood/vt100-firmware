#include "sdl_gd.h"

// More or less straight from libgl's gd.c
// to replace the original
// gdImageString(gdImagePtr im, gdFontPtr f, int x, int y, unsigned char *s, int color)
//
// So, with
//   #include <gd.h>
//   #include <gdfonts.h>
//
// You call like:
//   sdl_gdImageString(..., gdFontGetSmall(), ...);
//
void sdl_gdImageString(SDL_Renderer *rend, gdFontPtr f, int x, int y, char *str, SDL_Color col)
{
    SDL_SetRenderDrawColor(rend, col.r, col.g, col.b, col.a);
    for (size_t i = 0; i < strlen(str); ++i, x += f->w) {
        int c = str[i];
        if (c < f->offset || (c >= (f->offset + f->nchars)))
            continue;
        int fline = (c - f->offset) * f->h * f->w;
        for (int cy = 0; cy < f->h; ++cy) {
            for (int cx = 0; cx < f->w; ++cx) {
                if (f->data[fline + cy * f->w + cx])
                    SDL_RenderDrawPoint(rend, x + cx, y + cy);
            }
        }
    }
}
