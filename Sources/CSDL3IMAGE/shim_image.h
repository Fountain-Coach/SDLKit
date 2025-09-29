#pragma once

#if __has_include(<SDL3_image/SDL_image.h>)
  #include <SDL3_image/SDL_image.h>
  static inline SDL_Surface *SDLKit_IMG_Load(const char *path) { return IMG_Load(path); }
#else
  struct SDL_Surface;
  static inline SDL_Surface *SDLKit_IMG_Load(const char *path) { (void)path; return (struct SDL_Surface*)0; }
#endif

