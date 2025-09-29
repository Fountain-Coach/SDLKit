// Resilient FFI surface that stays stable across SDL3 changes.
// Expose SDLKit_* wrapper functions that call into the real SDL3 API when
// headers are available; otherwise, provide lightweight types for headless CI.

#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Normalized event kinds for Swift side (independent of SDL numeric codes)
enum {
  SDLKIT_EVENT_NONE = 0,
  SDLKIT_EVENT_KEY_DOWN = 1,
  SDLKIT_EVENT_KEY_UP = 2,
  SDLKIT_EVENT_MOUSE_DOWN = 3,
  SDLKIT_EVENT_MOUSE_UP = 4,
  SDLKIT_EVENT_MOUSE_MOVE = 5,
  SDLKIT_EVENT_QUIT = 6,
  SDLKIT_EVENT_WINDOW_CLOSED = 7
};

typedef struct SDLKit_Event {
  uint32_t type;   // one of SDLKIT_EVENT_*
  int32_t x;       // mouse position if applicable
  int32_t y;       // mouse position if applicable
  int32_t keycode; // platform keycode if applicable
  int32_t button;  // mouse button if applicable
} SDLKit_Event;

#if __has_include(<SDL3/SDL.h>)
  #include <SDL3/SDL.h>
  static inline const char *SDLKit_GetError(void) { return SDL_GetError(); }
  static inline int SDLKit_Init(uint32_t flags) { return SDL_Init(flags); }
  static inline SDL_Window *SDLKit_CreateWindow(const char *title, int32_t width, int32_t height, uint32_t flags) {
    return SDL_CreateWindow(title, width, height, flags);
  }
  static inline void SDLKit_DestroyWindow(SDL_Window *window) { SDL_DestroyWindow(window); }
  static inline void SDLKit_ShowWindow(SDL_Window *window) { SDL_ShowWindow(window); }
  static inline void SDLKit_HideWindow(SDL_Window *window) { SDL_HideWindow(window); }
  static inline void SDLKit_SetWindowTitle(SDL_Window *window, const char *title) { SDL_SetWindowTitle(window, title); }
  static inline const char *SDLKit_GetWindowTitle(SDL_Window *window) { return SDL_GetWindowTitle(window); }
  static inline void SDLKit_SetWindowPosition(SDL_Window *window, int x, int y) { SDL_SetWindowPosition(window, x, y); }
  static inline void SDLKit_GetWindowPosition(SDL_Window *window, int *x, int *y) { SDL_GetWindowPosition(window, x, y); }
  static inline void SDLKit_SetWindowSize(SDL_Window *window, int w, int h) { SDL_SetWindowSize(window, w, h); }
  static inline void SDLKit_GetWindowSize(SDL_Window *window, int *w, int *h) { SDL_GetWindowSize(window, w, h); }
  static inline void SDLKit_MaximizeWindow(SDL_Window *window) { SDL_MaximizeWindow(window); }
  static inline void SDLKit_MinimizeWindow(SDL_Window *window) { SDL_MinimizeWindow(window); }
  static inline void SDLKit_RestoreWindow(SDL_Window *window) { SDL_RestoreWindow(window); }
  static inline int SDLKit_SetWindowFullscreen(SDL_Window *window, int enabled) { return SDL_SetWindowFullscreen(window, enabled != 0); }
  static inline int SDLKit_SetWindowOpacity(SDL_Window *window, float opacity) { return SDL_SetWindowOpacity(window, opacity); }
  static inline int SDLKit_SetWindowAlwaysOnTop(SDL_Window *window, int enabled) { return SDL_SetWindowAlwaysOnTop(window, enabled != 0); }
  static inline void SDLKit_CenterWindow(SDL_Window *window) { SDL_SetWindowPosition(window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED); }

  // Clipboard
  static inline int SDLKit_SetClipboardText(const char *text) { return SDL_SetClipboardText(text); }
  static inline char *SDLKit_GetClipboardText(void) { return SDL_GetClipboardText(); }
  static inline void SDLKit_free(void *p) { SDL_free(p); }

  // Input state
  static inline void SDLKit_GetMouseState(int *x, int *y, unsigned int *buttons) {
    Uint32 b = SDL_GetMouseState(x, y);
    if (buttons) *buttons = (unsigned int)b;
  }
  static inline int SDLKit_GetModMask(void) {
    return (int)SDL_GetModState();
  }

  // Displays (best-effort wrappers; API may evolve across SDL3 releases)
  static inline int SDLKit_GetNumVideoDisplays(void) { return SDL_GetNumVideoDisplays(); }
  static inline const char *SDLKit_GetDisplayName(int index) { return SDL_GetDisplayName(index); }
  static inline int SDLKit_GetDisplayBounds(int index, int *x, int *y, int *w, int *h) {
    SDL_Rect r; if (SDL_GetDisplayBounds(index, &r) != 0) return -1; if (x) *x = r.x; if (y) *y = r.y; if (w) *w = r.w; if (h) *h = r.h; return 0;
  }
  // Renderer creation API evolves; accept a flags arg but ignore when not needed.
  static inline SDL_Renderer *SDLKit_CreateRenderer(SDL_Window *window, uint32_t flags) {
    (void)flags;
    // Prefer default renderer (NULL name) on SDL3
    return SDL_CreateRenderer(window, NULL);
  }
  static inline int SDLKit_SetRenderDrawColor(SDL_Renderer *renderer, uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    return SDL_SetRenderDrawColor(renderer, r, g, b, a);
  }
  static inline int SDLKit_RenderClear(SDL_Renderer *renderer) { return SDL_RenderClear(renderer); }
  static inline int SDLKit_RenderFillRect(SDL_Renderer *renderer, const struct SDL_FRect *rect) {
    return SDL_RenderFillRect(renderer, rect);
  }
  static inline int SDLKit_RenderFillRects(SDL_Renderer *renderer, const struct SDL_FRect *rects, int count) {
    return SDL_RenderFillRects(renderer, rects, count);
  }
  static inline int SDLKit_RenderRects(SDL_Renderer *renderer, const struct SDL_FRect *rects, int count) {
    return SDL_RenderRects(renderer, rects, count);
  }
  static inline int SDLKit_RenderPoints(SDL_Renderer *renderer, const struct SDL_FPoint *points, int count) {
    return SDL_RenderPoints(renderer, points, count);
  }
  static inline int SDLKit_RenderLine(SDL_Renderer *renderer, float x1, float y1, float x2, float y2) {
    return SDL_RenderLine(renderer, x1, y1, x2, y2);
  }
  static inline void SDLKit_RenderPresent(SDL_Renderer *renderer) { SDL_RenderPresent(renderer); }
  // Render state helpers
  static inline void SDLKit_GetRenderOutputSize(SDL_Renderer *renderer, int *w, int *h) { SDL_GetRenderOutputSize(renderer, w, h); }
  static inline void SDLKit_GetRenderScale(SDL_Renderer *renderer, float *sx, float *sy) { SDL_GetRenderScale(renderer, sx, sy); }
  static inline int SDLKit_SetRenderScale(SDL_Renderer *renderer, float sx, float sy) { return SDL_SetRenderScale(renderer, sx, sy); }
  static inline void SDLKit_GetRenderDrawColor(SDL_Renderer *renderer, uint8_t *r, uint8_t *g, uint8_t *b, uint8_t *a) { SDL_GetRenderDrawColor(renderer, r, g, b, a); }
  static inline int SDLKit_SetRenderViewport(SDL_Renderer *renderer, int x, int y, int w, int h) { SDL_Rect r = { x, y, w, h }; return SDL_SetRenderViewport(renderer, &r); }
  static inline void SDLKit_GetRenderViewport(SDL_Renderer *renderer, int *x, int *y, int *w, int *h) { SDL_Rect r; SDL_GetRenderViewport(renderer, &r); if (x) *x = r.x; if (y) *y = r.y; if (w) *w = r.w; if (h) *h = r.h; }
  static inline int SDLKit_SetRenderClipRect(SDL_Renderer *renderer, int x, int y, int w, int h) { SDL_Rect r = { x, y, w, h }; return SDL_SetRenderClipRect(renderer, &r); }
  static inline int SDLKit_DisableRenderClipRect(SDL_Renderer *renderer) { return SDL_SetRenderClipRect(renderer, NULL); }
  static inline void SDLKit_GetRenderClipRect(SDL_Renderer *renderer, int *x, int *y, int *w, int *h) { SDL_Rect r; SDL_GetRenderClipRect(renderer, &r); if (x) *x = r.x; if (y) *y = r.y; if (w) *w = r.w; if (h) *h = r.h; }

  static inline void SDLKit__FillEvent(SDLKit_Event *out, const SDL_Event *ev) {
    out->type = SDLKIT_EVENT_NONE;
    out->x = out->y = 0;
    out->keycode = out->button = 0;
    switch (ev->type) {
      case SDL_EVENT_QUIT:
        out->type = SDLKIT_EVENT_QUIT; break;
      case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
        out->type = SDLKIT_EVENT_WINDOW_CLOSED; break;
      case SDL_EVENT_KEY_DOWN:
        out->type = SDLKIT_EVENT_KEY_DOWN;
        out->keycode = (int32_t)ev->key.keysym.sym; break;
      case SDL_EVENT_KEY_UP:
        out->type = SDLKIT_EVENT_KEY_UP;
        out->keycode = (int32_t)ev->key.keysym.sym; break;
      case SDL_EVENT_MOUSE_MOTION:
        out->type = SDLKIT_EVENT_MOUSE_MOVE;
        out->x = (int32_t)ev->motion.x;
        out->y = (int32_t)ev->motion.y; break;
      case SDL_EVENT_MOUSE_BUTTON_DOWN:
        out->type = SDLKIT_EVENT_MOUSE_DOWN;
        out->x = (int32_t)ev->button.x;
        out->y = (int32_t)ev->button.y;
        out->button = (int32_t)ev->button.button; break;
      case SDL_EVENT_MOUSE_BUTTON_UP:
        out->type = SDLKIT_EVENT_MOUSE_UP;
        out->x = (int32_t)ev->button.x;
        out->y = (int32_t)ev->button.y;
        out->button = (int32_t)ev->button.button; break;
      default:
        break;
    }
  }

  static inline int SDLKit_PollEvent(SDLKit_Event *out) {
    SDL_Event ev; if (!SDL_PollEvent(&ev)) return 0; SDLKit__FillEvent(out, &ev); return 1;
  }
  static inline int SDLKit_WaitEventTimeout(SDLKit_Event *out, int timeout_ms) {
    SDL_Event ev; if (!SDL_WaitEventTimeout(&ev, timeout_ms)) return 0; SDLKit__FillEvent(out, &ev); return 1;
  }

  // Optional: SDL_ttf availability probe
  #if __has_include(<SDL3_ttf/SDL_ttf.h>)
    #include <SDL3_ttf/SDL_ttf.h>
    static inline int SDLKit_TTF_Available(void) { return 1; }
    static inline int SDLKit_TTF_Init(void) { return TTF_Init(); }
    typedef TTF_Font SDLKit_TTF_Font;
    static inline SDLKit_TTF_Font *SDLKit_TTF_OpenFont(const char *path, int ptsize) { return TTF_OpenFont(path, ptsize); }
    static inline void SDLKit_TTF_CloseFont(SDLKit_TTF_Font *font) { if (font) TTF_CloseFont(font); }
    static inline SDL_Surface *SDLKit_TTF_RenderUTF8_Blended(SDLKit_TTF_Font *font, const char *text,
                                                             uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
      SDL_Color c = { r, g, b, a };
      return TTF_RenderUTF8_Blended(font, text, c);
    }
    static inline SDL_Texture *SDLKit_CreateTextureFromSurface(SDL_Renderer *renderer, SDL_Surface *surface) {
      return SDL_CreateTextureFromSurface(renderer, surface);
    }
    static inline void SDLKit_DestroySurface(SDL_Surface *surface) { SDL_DestroySurface(surface); }
    static inline void SDLKit_DestroyTexture(SDL_Texture *tex) { SDL_DestroyTexture(tex); }
    static inline void SDLKit_GetTextureSize(SDL_Texture *tex, int *w, int *h) { SDL_GetTextureSize(tex, w, h); }
  static inline int SDLKit_RenderTexture(SDL_Renderer *renderer, SDL_Texture *tex, const SDL_FRect *src, const SDL_FRect *dst) {
    return SDL_RenderTexture(renderer, tex, src, dst);
  }
  static inline int SDLKit_RenderTextureRotated(SDL_Renderer *renderer, SDL_Texture *tex, const SDL_FRect *src, const SDL_FRect *dst, double angle, int hasCenter, float cx, float cy) {
    SDL_FPoint center = { cx, cy };
    return SDL_RenderTextureRotated(renderer, tex, src, dst, angle, hasCenter ? &center : NULL);
  }
  static inline SDL_Surface *SDLKit_LoadBMP(const char *path) { return SDL_LoadBMP(path); }
  static inline unsigned int SDLKit_PixelFormat_ABGR8888(void) { return SDL_PIXELFORMAT_ABGR8888; }
  static inline int SDLKit_RenderReadPixels(SDL_Renderer *renderer, int x, int y, int w, int h, void *pixels, int pitch) {
    SDL_Rect r = { x, y, w, h };
    return SDL_RenderReadPixels(renderer, &r, SDL_PIXELFORMAT_ABGR8888, pixels, pitch);
  }
  #else
    static inline int SDLKit_TTF_Available(void) { return 0; }
    typedef void SDLKit_TTF_Font;
  #endif
#else
  // Headless CI or no headers: provide minimal types so Swift can compile,
  // but no symbol definitions (and Swift code compiles them out in HEADLESS_CI).
  typedef struct SDL_Window { int _unused_window; } SDL_Window;
  typedef struct SDL_Renderer { int _unused_renderer; } SDL_Renderer;
  typedef struct SDL_FRect { float x; float y; float w; float h; } SDL_FRect;
  const char *SDLKit_GetError(void);
  int SDLKit_Init(uint32_t flags);
  SDL_Window *SDLKit_CreateWindow(const char *title, int32_t width, int32_t height, uint32_t flags);
  void SDLKit_DestroyWindow(SDL_Window *window);
  void SDLKit_ShowWindow(SDL_Window *window);
  void SDLKit_HideWindow(SDL_Window *window);
  void SDLKit_SetWindowTitle(SDL_Window *window, const char *title);
  const char *SDLKit_GetWindowTitle(SDL_Window *window);
  void SDLKit_SetWindowPosition(SDL_Window *window, int x, int y);
  void SDLKit_GetWindowPosition(SDL_Window *window, int *x, int *y);
  void SDLKit_SetWindowSize(SDL_Window *window, int w, int h);
  void SDLKit_GetWindowSize(SDL_Window *window, int *w, int *h);
  void SDLKit_MaximizeWindow(SDL_Window *window);
  void SDLKit_MinimizeWindow(SDL_Window *window);
  void SDLKit_RestoreWindow(SDL_Window *window);
  int SDLKit_SetWindowFullscreen(SDL_Window *window, int enabled);
  int SDLKit_SetWindowOpacity(SDL_Window *window, float opacity);
  int SDLKit_SetWindowAlwaysOnTop(SDL_Window *window, int enabled);
  void SDLKit_CenterWindow(SDL_Window *window);
  // Clipboard
  int SDLKit_SetClipboardText(const char *text);
  char *SDLKit_GetClipboardText(void);
  void SDLKit_free(void *p);
  // Input state
  void SDLKit_GetMouseState(int *x, int *y, unsigned int *buttons);
  int SDLKit_GetModMask(void);
  // Displays
  int SDLKit_GetNumVideoDisplays(void);
  const char *SDLKit_GetDisplayName(int index);
  int SDLKit_GetDisplayBounds(int index, int *x, int *y, int *w, int *h);
  SDL_Renderer *SDLKit_CreateRenderer(SDL_Window *window, uint32_t flags);
  int SDLKit_SetRenderDrawColor(SDL_Renderer *renderer, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
  int SDLKit_RenderClear(SDL_Renderer *renderer);
  int SDLKit_RenderFillRect(SDL_Renderer *renderer, const struct SDL_FRect *rect);
  int SDLKit_RenderFillRects(struct SDL_Renderer *renderer, const struct SDL_FRect *rects, int count);
  int SDLKit_RenderRects(struct SDL_Renderer *renderer, const struct SDL_FRect *rects, int count);
  int SDLKit_RenderPoints(struct SDL_Renderer *renderer, const struct SDL_FPoint *points, int count);
  int SDLKit_RenderLine(struct SDL_Renderer *renderer, float x1, float y1, float x2, float y2);
  void SDLKit_RenderPresent(SDL_Renderer *renderer);
  void SDLKit_GetRenderOutputSize(struct SDL_Renderer *renderer, int *w, int *h);
  void SDLKit_GetRenderScale(struct SDL_Renderer *renderer, float *sx, float *sy);
  int SDLKit_SetRenderScale(struct SDL_Renderer *renderer, float sx, float sy);
  void SDLKit_GetRenderDrawColor(struct SDL_Renderer *renderer, uint8_t *r, uint8_t *g, uint8_t *b, uint8_t *a);
  int SDLKit_SetRenderViewport(struct SDL_Renderer *renderer, int x, int y, int w, int h);
  void SDLKit_GetRenderViewport(struct SDL_Renderer *renderer, int *x, int *y, int *w, int *h);
  int SDLKit_SetRenderClipRect(struct SDL_Renderer *renderer, int x, int y, int w, int h);
  int SDLKit_DisableRenderClipRect(struct SDL_Renderer *renderer);
  void SDLKit_GetRenderClipRect(struct SDL_Renderer *renderer, int *x, int *y, int *w, int *h);
  int SDLKit_PollEvent(SDLKit_Event *out);
  int SDLKit_WaitEventTimeout(SDLKit_Event *out, int timeout_ms);
  static inline int SDLKit_TTF_Available(void) { return 0; }
  typedef void SDLKit_TTF_Font;
  int SDLKit_TTF_Init(void);
  SDLKit_TTF_Font *SDLKit_TTF_OpenFont(const char *path, int ptsize);
  void SDLKit_TTF_CloseFont(SDLKit_TTF_Font *font);
  struct SDL_Surface;
  struct SDL_Texture;
  SDL_Surface *SDLKit_TTF_RenderUTF8_Blended(SDLKit_TTF_Font *font, const char *text,
                                             uint8_t r, uint8_t g, uint8_t b, uint8_t a);
  struct SDL_Renderer;
  SDL_Texture *SDLKit_CreateTextureFromSurface(struct SDL_Renderer *renderer, struct SDL_Surface *surface);
  void SDLKit_DestroySurface(struct SDL_Surface *surface);
  void SDLKit_DestroyTexture(struct SDL_Texture *tex);
  void SDLKit_GetTextureSize(struct SDL_Texture *tex, int *w, int *h);
  int SDLKit_RenderTexture(struct SDL_Renderer *renderer, struct SDL_Texture *tex, const struct SDL_FRect *src, const struct SDL_FRect *dst);
  int SDLKit_RenderTextureRotated(struct SDL_Renderer *renderer, struct SDL_Texture *tex, const struct SDL_FRect *src, const struct SDL_FRect *dst, double angle, int hasCenter, float cx, float cy);
  struct SDL_Surface *SDLKit_LoadBMP(const char *path);
  unsigned int SDLKit_PixelFormat_ABGR8888(void);
  int SDLKit_RenderReadPixels(struct SDL_Renderer *renderer, int x, int y, int w, int h, void *pixels, int pitch);
#endif

#ifdef __cplusplus
} // extern "C"
#endif
