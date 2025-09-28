/*
 Minimal FFI surface for the functions we use, with a resilient strategy:
 - If real SDL3 headers are available, include them to provide full types.
 - Otherwise, fall back to lightweight typedefs so Swift can still compile
   (linking will require libSDL3 at runtime/CI where it exists).
 */

#pragma once
#include <stdint.h>

#if __has_include(<SDL3/SDL.h>)
  #include <SDL3/SDL.h>
#else
  // Fallback minimal declarations that match the ABI we use.
  // Define concrete (non-opaque) structs so Swift sees the names.
  typedef struct SDL_Window { int _unused_window; } SDL_Window;
  typedef struct SDL_Renderer { int _unused_renderer; } SDL_Renderer;
  typedef struct SDL_FRect { float x; float y; float w; float h; } SDL_FRect;

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
#endif
