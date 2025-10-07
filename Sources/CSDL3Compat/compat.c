#include "compat.h"
#include <string.h>

void *SDLKit_Win32HWND_Compat(void *window) {
#if defined(SDL_PROP_WINDOW_WIN32_HWND_POINTER)
    if (!window) return NULL;
    SDL_PropertiesID props = SDL_GetWindowProperties((SDL_Window *)window);
    if (!props) return NULL;
    return SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
#else
    (void)window;
    return NULL;
#endif
}

struct SDL_Surface *SDLKit_TTF_RenderTextBlended_UTF8(void *font,
                                                      const char *text,
                                                      uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
#if __has_include(<SDL3_ttf/SDL_ttf.h>)
    SDL_Color c = { r, g, b, a };
    size_t len = text ? strlen(text) : 0;
    return TTF_RenderText_Blended((TTF_Font *)font, text, len, c);
#else
    (void)font; (void)text; (void)r; (void)g; (void)b; (void)a;
    return (struct SDL_Surface *)0;
#endif
}

