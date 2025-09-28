#pragma once

// Optional SDL3_ttf shim. If headers are present, include them.
// Otherwise, provide minimal stubs so the module compiles and autolink can be optional.

#if __has_include(<SDL3_ttf/SDL_ttf.h>)
  #include <SDL3_ttf/SDL_ttf.h>
#else
  // Minimal stubs so import succeeds without real headers.
  typedef void TTF_Font;
  static inline int TTF_Init(void) { return -1; }
  static inline TTF_Font *TTF_OpenFont(const char *path, int ptsize) { (void)path; (void)ptsize; return (TTF_Font*)0; }
  static inline void TTF_CloseFont(TTF_Font *font) { (void)font; }
#endif

