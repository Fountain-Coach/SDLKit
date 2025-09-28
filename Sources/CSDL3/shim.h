#pragma once

// Minimal FFI surface for the functions we use, to avoid
// hard dependency on full header search in CI environments.
// If full headers are available, they can still be included
// before this shim to provide richer types.

#include <stdint.h>

#ifndef CSDL3_SHIM_TYPES
#define CSDL3_SHIM_TYPES
typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef struct SDL_FRect { float x; float y; float w; float h; } SDL_FRect;
#endif

// Core
extern const char *SDL_GetError(void);
extern int SDL_Init(uint32_t flags);

// Window
extern SDL_Window *SDL_CreateWindow(const char *title, int32_t width, int32_t height, uint32_t flags);
extern void SDL_DestroyWindow(SDL_Window *window);

// Renderer
extern SDL_Renderer *SDL_CreateRenderer(SDL_Window *window, const char *driver, uint32_t flags);
extern int SDL_SetRenderDrawColor(SDL_Renderer *renderer, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
extern int SDL_RenderFillRect(SDL_Renderer *renderer, const SDL_FRect *rect);
extern void SDL_RenderPresent(SDL_Renderer *renderer);
