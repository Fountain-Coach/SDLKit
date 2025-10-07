#pragma once
#include <stdint.h>

#if __has_include(<SDL3/SDL.h>)
#  include <SDL3/SDL.h>
#  if __has_include(<SDL3/SDL_properties.h>)
#    include <SDL3/SDL_properties.h>
#  endif
#  if __has_include(<SDL3/SDL_syswm.h>)
#    include <SDL3/SDL_syswm.h>
#  endif
#endif

#if __has_include(<SDL3_ttf/SDL_ttf.h>)
#  include <SDL3_ttf/SDL_ttf.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Returns HWND on Windows via SDL properties; NULL elsewhere.
void *SDLKit_Win32HWND_Compat(void *window);

// Render UTF-8 text via SDL3_ttf's TTF_RenderText_Blended (UTF-8 assumed).
struct SDL_Surface *SDLKit_TTF_RenderTextBlended_UTF8(void *font,
                                                      const char *text,
                                                      uint8_t r, uint8_t g, uint8_t b, uint8_t a);

#ifdef __cplusplus
}
#endif

