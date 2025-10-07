#pragma once

#if __has_include(<SDL3_image/SDL_image.h>)
  #include <SDL3_image/SDL_image.h>
  static inline SDL_Surface *SDLKit_IMG_Load(const char *path) { return IMG_Load(path); }
  static inline int SDLKit_IMG_SavePNG_RW(void *surface, void *dst, int freedst) {
    // SDL3: IMG_SavePNG_IO returns bool success, and takes SDL_IOStream*
    // Map to 0 on success, -1 on failure. freedst non-zero means close stream.
    return IMG_SavePNG_IO((SDL_Surface *)surface, (SDL_IOStream *)dst, freedst != 0) ? 0 : -1;
  }
#else
  struct SDL_Surface;
  struct SDL_IOStream;
  static inline struct SDL_Surface *SDLKit_IMG_Load(const char *path) { (void)path; return (struct SDL_Surface*)0; }
  static inline int SDLKit_IMG_SavePNG_RW(struct SDL_Surface *surface, void *dst, int freedst) {
    (void)surface; (void)dst; (void)freedst; return -1;
  }
#endif
