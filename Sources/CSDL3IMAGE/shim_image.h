#pragma once

#if __has_include(<SDL3_image/SDL_image.h>)
  #include <SDL3_image/SDL_image.h>
  static inline SDL_Surface *SDLKit_IMG_Load(const char *path) { return IMG_Load(path); }
  static inline int SDLKit_IMG_SavePNG_RW(SDL_Surface *surface, SDL_RWops *dst, int freedst) {
    return IMG_SavePNG_RW(surface, dst, freedst);
  }
#else
  struct SDL_Surface;
  struct SDL_RWops;
  static inline struct SDL_Surface *SDLKit_IMG_Load(const char *path) { (void)path; return (struct SDL_Surface*)0; }
  static inline int SDLKit_IMG_SavePNG_RW(struct SDL_Surface *surface, struct SDL_RWops *dst, int freedst) {
    (void)surface; (void)dst; (void)freedst; return -1;
  }
#endif

