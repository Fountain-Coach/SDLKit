// Resilient FFI surface that stays stable across SDL3 changes.
// Expose SDLKit_* wrapper functions that call into the real SDL3 API when
// headers are available; otherwise, provide lightweight types for headless CI.

#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

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
  #if __has_include(<SDL3/SDL_audio.h>)
    #include <SDL3/SDL_audio.h>
  #endif
  #if __has_include(<SDL3/SDL_properties.h>)
    #include <SDL3/SDL_properties.h>
  #endif
  #if __has_include(<SDL3/SDL_syswm.h>)
    #include <SDL3/SDL_syswm.h>
  #endif
  #if __has_include(<SDL3/SDL_metal.h>)
    #include <SDL3/SDL_metal.h>
  #endif
  #if __has_include(<SDL3/SDL_vulkan.h>)
    #include <SDL3/SDL_vulkan.h>
  #endif
  // Ensure opaque struct typedefs are visible to Swift importer
  typedef struct SDL_Window SDL_Window;
  typedef struct SDL_Renderer SDL_Renderer;
  typedef struct SDL_Surface SDL_Surface;
  typedef struct SDL_Texture SDL_Texture;
  typedef struct SDL_AudioStream SDL_AudioStream;
  static inline const char *SDLKit_GetError(void) { return SDL_GetError(); }
  // Normalize to 0 on success, -1 on failure to match other wrapper conventions.
  static inline int SDLKit_Init(uint32_t flags) { return SDL_Init(flags) ? 0 : -1; }
  static inline void *SDLKit_CreateWindow(const char *title, int32_t width, int32_t height, uint32_t flags) {
    return (void *)SDL_CreateWindow(title, width, height, flags);
  }
  static inline void SDLKit_DestroyWindow(void *window) { SDL_DestroyWindow((SDL_Window *)window); }
  static inline void SDLKit_DestroyRenderer(void *renderer) { SDL_DestroyRenderer((SDL_Renderer *)renderer); }
  static inline void SDLKit_ShowWindow(void *window) { SDL_ShowWindow((SDL_Window *)window); }
  static inline void SDLKit_HideWindow(void *window) { SDL_HideWindow((SDL_Window *)window); }
  static inline void SDLKit_RaiseWindow(void *window) { SDL_RaiseWindow((SDL_Window *)window); }
  static inline void SDLKit_SetWindowTitle(void *window, const char *title) { SDL_SetWindowTitle((SDL_Window *)window, title); }
  static inline const char *SDLKit_GetWindowTitle(void *window) { return SDL_GetWindowTitle((SDL_Window *)window); }
  static inline void SDLKit_SetWindowPosition(void *window, int x, int y) { SDL_SetWindowPosition((SDL_Window *)window, x, y); }
  static inline void SDLKit_GetWindowPosition(void *window, int *x, int *y) { SDL_GetWindowPosition((SDL_Window *)window, x, y); }
  static inline void SDLKit_SetWindowSize(void *window, int w, int h) { SDL_SetWindowSize((SDL_Window *)window, w, h); }
  static inline void SDLKit_GetWindowSize(void *window, int *w, int *h) { SDL_GetWindowSize((SDL_Window *)window, w, h); }
  static inline void SDLKit_MaximizeWindow(void *window) { SDL_MaximizeWindow((SDL_Window *)window); }
  static inline void SDLKit_MinimizeWindow(void *window) { SDL_MinimizeWindow((SDL_Window *)window); }
  static inline void SDLKit_RestoreWindow(void *window) { SDL_RestoreWindow((SDL_Window *)window); }
  static inline int SDLKit_SetWindowFullscreen(void *window, int enabled) { return SDL_SetWindowFullscreen((SDL_Window *)window, enabled != 0) ? 0 : -1; }
  static inline int SDLKit_SetWindowOpacity(void *window, float opacity) { return SDL_SetWindowOpacity((SDL_Window *)window, opacity) ? 0 : -1; }
  static inline int SDLKit_SetWindowAlwaysOnTop(void *window, int enabled) { return SDL_SetWindowAlwaysOnTop((SDL_Window *)window, enabled != 0) ? 0 : -1; }
  static inline void SDLKit_CenterWindow(void *window) { SDL_SetWindowPosition((SDL_Window *)window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED); }

  // Clipboard
  static inline int SDLKit_SetClipboardText(const char *text) { return SDL_SetClipboardText(text); }
  static inline char *SDLKit_GetClipboardText(void) { return SDL_GetClipboardText(); }
  static inline void SDLKit_free(void *p) { SDL_free(p); }

  // Input state
  static inline void SDLKit_GetMouseState(int *x, int *y, unsigned int *buttons) {
    float fx = 0.0f, fy = 0.0f;
    Uint32 b = SDL_GetMouseState(&fx, &fy);
    if (x) *x = (int)fx;
    if (y) *y = (int)fy;
    if (buttons) *buttons = (unsigned int)b;
  }
  static inline int SDLKit_GetModMask(void) {
    return (int)SDL_GetModState();
  }

  // Displays (best-effort wrappers; API may evolve across SDL3 releases)
  static inline int SDLKit_GetNumVideoDisplays(void) {
    int count = 0;
    SDL_DisplayID *ids = SDL_GetDisplays(&count);
    if (ids) { SDL_free(ids); }
    return count;
  }
  static inline const char *SDLKit_GetDisplayName(int index) {
    int count = 0;
    SDL_DisplayID *ids = SDL_GetDisplays(&count);
    if (!ids || index < 0 || index >= count) { if (ids) SDL_free(ids); return NULL; }
    SDL_DisplayID id = ids[index];
    const char *name = SDL_GetDisplayName(id);
    SDL_free(ids);
    return name;
  }
  static inline int SDLKit_GetDisplayBounds(int index, int *x, int *y, int *w, int *h) {
    int count = 0;
    SDL_DisplayID *ids = SDL_GetDisplays(&count);
    if (!ids || index < 0 || index >= count) { if (ids) SDL_free(ids); return -1; }
    SDL_DisplayID id = ids[index];
    SDL_Rect r; int rc = SDL_GetDisplayBounds(id, &r) ? 0 : -1;
    if (rc == 0) { if (x) *x = r.x; if (y) *y = r.y; if (w) *w = r.w; if (h) *h = r.h; }
    SDL_free(ids);
    return rc;
  }
  // Renderer creation API evolves; accept a flags arg but ignore when not needed.
  static inline void *SDLKit_CreateRenderer(void *window, uint32_t flags) {
    (void)flags;
    // Prefer default renderer (NULL name) on SDL3
    return (void *)SDL_CreateRenderer((SDL_Window *)window, NULL);
  }
  static inline int SDLKit_SetRenderDrawColor(void *renderer, uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    return SDL_SetRenderDrawColor((SDL_Renderer *)renderer, r, g, b, a) ? 0 : -1;
  }
  static inline int SDLKit_RenderClear(void *renderer) { return SDL_RenderClear((SDL_Renderer *)renderer) ? 0 : -1; }
  static inline int SDLKit_RenderFillRect(void *renderer, const struct SDL_FRect *rect) {
    return SDL_RenderFillRect((SDL_Renderer *)renderer, rect) ? 0 : -1;
  }
  static inline int SDLKit_RenderFillRects(void *renderer, const struct SDL_FRect *rects, int count) {
    return SDL_RenderFillRects((SDL_Renderer *)renderer, rects, count) ? 0 : -1;
  }
  static inline int SDLKit_RenderRects(void *renderer, const struct SDL_FRect *rects, int count) {
    return SDL_RenderRects((SDL_Renderer *)renderer, rects, count) ? 0 : -1;
  }
  static inline int SDLKit_RenderPoints(void *renderer, const struct SDL_FPoint *points, int count) {
    return SDL_RenderPoints((SDL_Renderer *)renderer, points, count) ? 0 : -1;
  }
  static inline int SDLKit_RenderLine(void *renderer, float x1, float y1, float x2, float y2) {
    return SDL_RenderLine((SDL_Renderer *)renderer, x1, y1, x2, y2) ? 0 : -1;
  }
  static inline void SDLKit_RenderPresent(void *renderer) { SDL_RenderPresent((SDL_Renderer *)renderer); }
  // Render state helpers
  static inline void SDLKit_GetRenderOutputSize(void *renderer, int *w, int *h) { SDL_GetRenderOutputSize((SDL_Renderer *)renderer, w, h); }
  static inline void SDLKit_GetRenderScale(void *renderer, float *sx, float *sy) { SDL_GetRenderScale((SDL_Renderer *)renderer, sx, sy); }
  static inline int SDLKit_SetRenderScale(void *renderer, float sx, float sy) { return SDL_SetRenderScale((SDL_Renderer *)renderer, sx, sy) ? 0 : -1; }
  static inline void SDLKit_GetRenderDrawColor(void *renderer, uint8_t *r, uint8_t *g, uint8_t *b, uint8_t *a) { SDL_GetRenderDrawColor((SDL_Renderer *)renderer, r, g, b, a); }
  static inline int SDLKit_SetRenderViewport(void *renderer, int x, int y, int w, int h) { SDL_Rect r = { x, y, w, h }; return SDL_SetRenderViewport((SDL_Renderer *)renderer, &r) ? 0 : -1; }
  static inline void SDLKit_GetRenderViewport(void *renderer, int *x, int *y, int *w, int *h) { SDL_Rect r; SDL_GetRenderViewport((SDL_Renderer *)renderer, &r); if (x) *x = r.x; if (y) *y = r.y; if (w) *w = r.w; if (h) *h = r.h; }
  static inline int SDLKit_SetRenderClipRect(void *renderer, int x, int y, int w, int h) { SDL_Rect r = { x, y, w, h }; return SDL_SetRenderClipRect((SDL_Renderer *)renderer, &r) ? 0 : -1; }
  static inline int SDLKit_DisableRenderClipRect(void *renderer) { return SDL_SetRenderClipRect((SDL_Renderer *)renderer, NULL) ? 0 : -1; }
  static inline void SDLKit_GetRenderClipRect(void *renderer, int *x, int *y, int *w, int *h) { SDL_Rect r; SDL_GetRenderClipRect((SDL_Renderer *)renderer, &r); if (x) *x = r.x; if (y) *y = r.y; if (w) *w = r.w; if (h) *h = r.h; }

  static inline void *SDLKit_MetalLayerForWindow(void *window) {
    #if __has_include(<SDL3/SDL_metal.h>)
      if (!window) return NULL;
      // SDL3 Metal API expects a Metal view; create one for the window and
      // return its CAMetalLayer. Callers do not own the layer.
      SDL_MetalView view = SDL_Metal_CreateView((SDL_Window *)window);
      if (!view) return NULL;
      return (void *)SDL_Metal_GetLayer(view);
    #else
      (void)window;
      return NULL;
    #endif
  }

  static inline void *SDLKit_Win32HWND(void *window) {
    (void)window;
    #if defined(SDL_PROP_WINDOW_WIN32_HWND_POINTER)
      if (!window) return NULL;
      SDL_PropertiesID props = SDL_GetWindowProperties((SDL_Window *)window);
      if (!props) return NULL;
      return SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
    #else
      return NULL;
    #endif
  }

  static inline void *SDLKit_CocoaWindow(void *window) {
    (void)window;
    #if defined(SDL_PROP_WINDOW_COCOA_WINDOW_POINTER)
      if (!window) return NULL;
      SDL_PropertiesID props = SDL_GetWindowProperties((SDL_Window *)window);
      if (!props) return NULL;
      return SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    #else
      return NULL;
    #endif
  }

  static inline bool SDLKit_CreateVulkanSurface(void *window, VkInstance instance, VkSurfaceKHR *surface) {
    #if __has_include(<SDL3/SDL_vulkan.h>)
      if (!window || !surface) {
        if (surface) { *surface = (VkSurfaceKHR)0; }
        return false;
      }
      return SDL_Vulkan_CreateSurface((SDL_Window *)window, instance, NULL, surface);
    #else
      (void)instance; (void)surface;
      return false;
    #endif
  }

  // Query required Vulkan instance extensions for the window.
  // On success, returns 1 and sets *pCount to the number of required extensions and
  // *names to an array of const char* owned by SDL. Callers should not free or modify.
  static inline int SDLKit_Vulkan_GetInstanceExtensions(void *window, unsigned int *pCount, const char *const **names) {
    #if __has_include(<SDL3/SDL_vulkan.h>)
      (void)window;
      Uint32 cnt = 0;
      const char * const *exts = SDL_Vulkan_GetInstanceExtensions(&cnt);
      if (pCount) { *pCount = (unsigned int)cnt; }
      if (names) { *names = exts; }
      return exts != NULL ? 1 : 0;
    #else
      if (pCount) { *pCount = 0; }
      if (names) { *names = NULL; }
      return 0;
    #endif
  }

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
        out->keycode = (int32_t)ev->key.key; break;
      case SDL_EVENT_KEY_UP:
        out->type = SDLKIT_EVENT_KEY_UP;
        out->keycode = (int32_t)ev->key.key; break;
      case SDL_EVENT_MOUSE_MOTION:
        out->type = SDLKIT_EVENT_MOUSE_MOVE;
        out->x = (int32_t)ev->motion.x;
        out->y = (int32_t)ev->motion.y; break;
      case SDL_EVENT_MOUSE_BUTTON_DOWN:
        out->type = SDLKIT_EVENT_MOUSE_DOWN;
        {
          float fx = 0.0f, fy = 0.0f; SDL_GetMouseState(&fx, &fy);
          out->x = (int32_t)fx; out->y = (int32_t)fy;
          out->button = (int32_t)ev->button.button; break;
        }
      case SDL_EVENT_MOUSE_BUTTON_UP:
        out->type = SDLKIT_EVENT_MOUSE_UP;
        {
          float fx = 0.0f, fy = 0.0f; SDL_GetMouseState(&fx, &fy);
          out->x = (int32_t)fx; out->y = (int32_t)fy;
          out->button = (int32_t)ev->button.button; break;
        }
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
    static inline void *SDLKit_TTF_OpenFont(const char *path, int ptsize) { return (void *)TTF_OpenFont(path, ptsize); }
    static inline void SDLKit_TTF_CloseFont(void *font) { if (font) TTF_CloseFont((TTF_Font *)font); }
    static inline void SDLKit_TTF_Quit(void) { TTF_Quit(); }
    static inline SDL_Surface *SDLKit_TTF_RenderUTF8_Blended(void *font, const char *text,
                                                             uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
      SDL_Color c = { r, g, b, a };
      size_t len = text ? strlen(text) : 0;
      return TTF_RenderText_Blended((TTF_Font *)font, text, len, c);
    }
  static inline void *SDLKit_CreateTextureFromSurface(void *renderer, void *surface) {
      return (void *)SDL_CreateTextureFromSurface((SDL_Renderer *)renderer, (SDL_Surface *)surface);
    }
    static inline void SDLKit_DestroySurface(void *surface) { SDL_DestroySurface((SDL_Surface *)surface); }
    static inline void SDLKit_DestroyTexture(void *tex) { SDL_DestroyTexture((SDL_Texture *)tex); }
    static inline void SDLKit_GetTextureSize(void *tex, int *w, int *h) {
      float fw = 0.0f, fh = 0.0f; SDL_GetTextureSize((SDL_Texture *)tex, &fw, &fh); if (w) *w = (int)fw; if (h) *h = (int)fh;
    }
  static inline int SDLKit_RenderTexture(void *renderer, void *tex, const SDL_FRect *src, const SDL_FRect *dst) {
    return SDL_RenderTexture((SDL_Renderer *)renderer, (SDL_Texture *)tex, src, dst) ? 0 : -1;
  }
  static inline int SDLKit_RenderTextureRotated(void *renderer, void *tex, const SDL_FRect *src, const SDL_FRect *dst, double angle, int hasCenter, float cx, float cy) {
    SDL_FPoint center = { cx, cy };
    return SDL_RenderTextureRotated((SDL_Renderer *)renderer, (SDL_Texture *)tex, src, dst, angle, hasCenter ? &center : NULL, SDL_FLIP_NONE) ? 0 : -1;
  }
  static inline void *SDLKit_LoadBMP(const char *path) { return (void *)SDL_LoadBMP(path); }
  static inline void *SDLKit_CreateSurfaceFrom(int width, int height, unsigned int format, void *pixels, int pitch) {
    return (void *)SDL_CreateSurfaceFrom(width, height, format, pixels, pitch);
  }
  static inline void *SDLKit_RWFromFile(const char *file, const char *mode) { return (void *)SDL_IOFromFile(file, mode); }
  static inline unsigned int SDLKit_PixelFormat_ABGR8888(void) { return SDL_PIXELFORMAT_ABGR8888; }
  static inline int SDLKit_RenderReadPixels(void *renderer, int x, int y, int w, int h, void *pixels, int pitch) {
    SDL_Rect r = { x, y, w, h };
    SDL_Surface *surf = SDL_RenderReadPixels((SDL_Renderer *)renderer, &r);
    if (!surf) { return -1; }
    SDL_Surface *conv = NULL;
    if (surf->format != SDL_PIXELFORMAT_ABGR8888) {
      conv = SDL_ConvertSurface(surf, SDL_PIXELFORMAT_ABGR8888);
      if (!conv) { SDL_DestroySurface(surf); return -1; }
    }
    SDL_Surface *src = conv ? conv : surf;
    // Copy row-by-row into destination buffer
    const int src_pitch = src->pitch;
    const unsigned char *src_pixels = (const unsigned char *)src->pixels;
    unsigned char *dst = (unsigned char *)pixels;
    for (int row = 0; row < h; ++row) {
      const unsigned char *srow = src_pixels + row * src_pitch;
      unsigned char *drow = dst + row * pitch;
      memcpy(drow, srow, (size_t)(w * 4));
    }
    if (conv) SDL_DestroySurface(conv);
    SDL_DestroySurface(surf);
    return 0;
  }
  #else
    // SDL_ttf headers not available: provide no-op wrappers so Swift can compile,
    // and report unavailable at runtime.
    static inline int SDLKit_TTF_Available(void) { return 0; }
    static inline int SDLKit_TTF_Init(void) { return -1; }
    static inline void *SDLKit_TTF_OpenFont(const char *path, int ptsize) { (void)path; (void)ptsize; return NULL; }
    static inline void SDLKit_TTF_CloseFont(void *font) { (void)font; }
    static inline void SDLKit_TTF_Quit(void) { }
    static inline SDL_Surface *SDLKit_TTF_RenderUTF8_Blended(void *font, const char *text,
                                                             uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
      (void)font; (void)text; (void)r; (void)g; (void)b; (void)a; return NULL;
    }
  #endif
  static inline void SDLKit_Quit(void) { SDL_Quit(); }
  // --- Audio (SDL3) ---
  // Minimal wrappers to expose SDL3 audio streams for capture and playback.
  // These use the simplified device+stream API and resume the device.
  static inline unsigned int SDLKit_AudioFormat_F32(void) { return (unsigned int)SDL_AUDIO_F32; }
  static inline unsigned int SDLKit_AudioFormat_S16(void) { return (unsigned int)SDL_AUDIO_S16; }

  static inline void *SDLKit_OpenDefaultAudioRecordingStream(int sample_rate,
                                                                        unsigned int format,
                                                                        int channels) {
    SDL_AudioSpec spec; spec.freq = sample_rate; spec.format = (SDL_AudioFormat)format; spec.channels = channels;
    SDL_AudioStream *stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_RECORDING, &spec, NULL, NULL);
    if (!stream) { return NULL; }
    SDL_AudioDeviceID dev = SDL_GetAudioStreamDevice(stream);
    (void)SDL_ResumeAudioDevice(dev);
    return (void *)stream;
  }

  static inline void *SDLKit_OpenDefaultAudioPlaybackStream(int sample_rate,
                                                                       unsigned int format,
                                                                       int channels) {
    SDL_AudioSpec spec; spec.freq = sample_rate; spec.format = (SDL_AudioFormat)format; spec.channels = channels;
    SDL_AudioStream *stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, NULL, NULL);
    if (!stream) { return NULL; }
    SDL_AudioDeviceID dev = SDL_GetAudioStreamDevice(stream);
    (void)SDL_ResumeAudioDevice(dev);
    return (void *)stream;
  }

  static inline int SDLKit_GetAudioStreamAvailable(void *stream) {
    return SDL_GetAudioStreamAvailable((SDL_AudioStream *)stream);
  }
  static inline int SDLKit_GetAudioStreamData(void *stream, void *buf, int len) {
    return SDL_GetAudioStreamData((SDL_AudioStream *)stream, buf, len);
  }
  static inline int SDLKit_PutAudioStreamData(void *stream, const void *buf, int len) {
    return SDL_PutAudioStreamData((SDL_AudioStream *)stream, buf, len) ? 0 : -1;
  }
  static inline int SDLKit_FlushAudioStream(void *stream) {
    return SDL_FlushAudioStream((SDL_AudioStream *)stream) ? 0 : -1;
  }
  static inline void SDLKit_DestroyAudioStream(void *stream) {
    SDL_DestroyAudioStream((SDL_AudioStream *)stream);
  }
  static inline void *SDLKit_CreateAudioStreamConvert(int src_rate, unsigned int src_format, int src_channels,
                                                                 int dst_rate, unsigned int dst_format, int dst_channels) {
    SDL_AudioSpec src; src.freq = src_rate; src.format = (SDL_AudioFormat)src_format; src.channels = src_channels;
    SDL_AudioSpec dst; dst.freq = dst_rate; dst.format = (SDL_AudioFormat)dst_format; dst.channels = dst_channels;
    return (void *)SDL_CreateAudioStream(&src, &dst);
  }
  static inline int SDLKit_ClearAudioStream(void *stream) {
    return SDL_ClearAudioStream((SDL_AudioStream *)stream) ? 0 : -1;
  }

  // WAV loading helpers
  static inline int SDLKit_LoadWAV(const char *path, SDL_AudioSpec *out_spec, unsigned char **out_buf, unsigned int *out_len) {
    Uint8 *buf = NULL; Uint32 len = 0; SDL_AudioSpec spec;
    if (!SDL_LoadWAV(path, &spec, &buf, &len)) { return -1; }
    if (out_spec) { *out_spec = spec; }
    if (out_buf) { *out_buf = (unsigned char*)buf; }
    if (out_len) { *out_len = (unsigned int)len; }
    return 0;
  }

  // --- Audio device enumeration ---
  static inline int SDLKit_ListAudioPlaybackDevices(uint64_t *dst_ids, int dst_count) {
    int count = 0;
    SDL_AudioDeviceID *ids = SDL_GetAudioPlaybackDevices(&count);
    if (!ids) { return -1; }
    int n = (count < dst_count) ? count : dst_count;
    for (int i = 0; i < n; ++i) { dst_ids[i] = (uint64_t)ids[i]; }
    SDL_free(ids);
    return n;
  }
  static inline int SDLKit_ListAudioRecordingDevices(uint64_t *dst_ids, int dst_count) {
    int count = 0;
    SDL_AudioDeviceID *ids = SDL_GetAudioRecordingDevices(&count);
    if (!ids) { return -1; }
    int n = (count < dst_count) ? count : dst_count;
    for (int i = 0; i < n; ++i) { dst_ids[i] = (uint64_t)ids[i]; }
    SDL_free(ids);
    return n;
  }
  static inline const char *SDLKit_GetAudioDeviceNameU64(uint64_t devid) {
    return SDL_GetAudioDeviceName((SDL_AudioDeviceID)devid);
  }
  static inline int SDLKit_GetAudioDevicePreferredFormatU64(uint64_t devid, int *sample_rate, unsigned int *format, int *channels, int *sample_frames) {
    SDL_AudioSpec spec;
    int frames = 0;
    if (!SDL_GetAudioDeviceFormat((SDL_AudioDeviceID)devid, &spec, &frames)) { return -1; }
    if (sample_rate) { *sample_rate = spec.freq; }
    if (format) { *format = (unsigned int)spec.format; }
    if (channels) { *channels = spec.channels; }
    if (sample_frames) { *sample_frames = frames; }
    return 0;
  }
  static inline void *SDLKit_OpenAudioRecordingStreamU64(uint64_t devid, int sample_rate, unsigned int format, int channels) {
    SDL_AudioSpec spec; spec.freq = sample_rate; spec.format = (SDL_AudioFormat)format; spec.channels = channels;
    SDL_AudioStream *stream = SDL_OpenAudioDeviceStream((SDL_AudioDeviceID)devid, &spec, NULL, NULL);
    if (!stream) { return NULL; }
    SDL_AudioDeviceID dev = SDL_GetAudioStreamDevice(stream);
    (void)SDL_ResumeAudioDevice(dev);
    return (void *)stream;
  }
  static inline void *SDLKit_OpenAudioPlaybackStreamU64(uint64_t devid, int sample_rate, unsigned int format, int channels) {
    SDL_AudioSpec spec; spec.freq = sample_rate; spec.format = (SDL_AudioFormat)format; spec.channels = channels;
    SDL_AudioStream *stream = SDL_OpenAudioDeviceStream((SDL_AudioDeviceID)devid, &spec, NULL, NULL);
    if (!stream) { return NULL; }
    SDL_AudioDeviceID dev = SDL_GetAudioStreamDevice(stream);
    (void)SDL_ResumeAudioDevice(dev);
    return (void *)stream;
  }
#else
  // Headless CI or no headers: provide minimal types so Swift can compile,
  // but no symbol definitions (and Swift code compiles them out in HEADLESS_CI).
  typedef struct SDL_Window { int _unused_window; } SDL_Window;
  typedef struct SDL_Renderer { int _unused_renderer; } SDL_Renderer;
  typedef struct SDL_Surface { int _unused_surface; } SDL_Surface;
  typedef struct SDL_Texture { int _unused_texture; } SDL_Texture;
  typedef struct SDL_FRect { float x; float y; float w; float h; } SDL_FRect;
  typedef struct SDL_FPoint { float x; float y; } SDL_FPoint;
  typedef struct SDLKit_TTF_Font { int _unused_font; } SDLKit_TTF_Font;
  #if __has_include(<vulkan/vulkan.h>)
    #include <vulkan/vulkan.h>
  #else
    typedef struct VkInstance_T *VkInstance;
    typedef uint64_t VkSurfaceKHR;
  #endif
  const char *SDLKit_GetError(void);
  int SDLKit_Init(uint32_t flags);
  SDL_Window *SDLKit_CreateWindow(const char *title, int32_t width, int32_t height, uint32_t flags);
  void SDLKit_DestroyWindow(SDL_Window *window);
  void SDLKit_ShowWindow(SDL_Window *window);
  void SDLKit_DestroyRenderer(SDL_Renderer *renderer);
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
  void *SDLKit_CreateRenderer(void *window, uint32_t flags);
  int SDLKit_SetRenderDrawColor(void *renderer, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
  int SDLKit_RenderClear(void *renderer);
  int SDLKit_RenderFillRect(void *renderer, const struct SDL_FRect *rect);
  int SDLKit_RenderFillRects(void *renderer, const struct SDL_FRect *rects, int count);
  int SDLKit_RenderRects(void *renderer, const struct SDL_FRect *rects, int count);
  int SDLKit_RenderPoints(void *renderer, const struct SDL_FPoint *points, int count);
  int SDLKit_RenderLine(void *renderer, float x1, float y1, float x2, float y2);
  void SDLKit_RenderPresent(void *renderer);
  void SDLKit_GetRenderOutputSize(void *renderer, int *w, int *h);
  void SDLKit_GetRenderScale(void *renderer, float *sx, float *sy);
  int SDLKit_SetRenderScale(void *renderer, float sx, float sy);
  void SDLKit_GetRenderDrawColor(void *renderer, uint8_t *r, uint8_t *g, uint8_t *b, uint8_t *a);
  int SDLKit_SetRenderViewport(void *renderer, int x, int y, int w, int h);
  void SDLKit_GetRenderViewport(void *renderer, int *x, int *y, int *w, int *h);
  int SDLKit_SetRenderClipRect(void *renderer, int x, int y, int w, int h);
  int SDLKit_DisableRenderClipRect(void *renderer);
  void SDLKit_GetRenderClipRect(void *renderer, int *x, int *y, int *w, int *h);
  int SDLKit_PollEvent(SDLKit_Event *out);
  int SDLKit_WaitEventTimeout(SDLKit_Event *out, int timeout_ms);
  static inline int SDLKit_TTF_Available(void) { return 0; }
  int SDLKit_TTF_Init(void);
  SDLKit_TTF_Font *SDLKit_TTF_OpenFont(const char *path, int ptsize);
  void SDLKit_TTF_CloseFont(SDLKit_TTF_Font *font);
  void SDLKit_TTF_Quit(void);
  struct SDL_Surface;
  struct SDL_Texture;
  struct SDL_Surface *SDLKit_TTF_RenderUTF8_Blended(SDLKit_TTF_Font *font, const char *text,
                                             uint8_t r, uint8_t g, uint8_t b, uint8_t a);
  void *SDLKit_CreateTextureFromSurface(void *renderer, void *surface);
  void SDLKit_DestroySurface(void *surface);
  void SDLKit_DestroyTexture(void *tex);
  void SDLKit_GetTextureSize(void *tex, int *w, int *h);
  int SDLKit_RenderTexture(void *renderer, void *tex, const struct SDL_FRect *src, const struct SDL_FRect *dst);
  int SDLKit_RenderTextureRotated(void *renderer, void *tex, const struct SDL_FRect *src, const struct SDL_FRect *dst, double angle, int hasCenter, float cx, float cy);
  void *SDLKit_LoadBMP(const char *path);
  void *SDLKit_CreateSurfaceFrom(int width, int height, unsigned int format, void *pixels, int pitch);
  void *SDLKit_RWFromFile(const char *file, const char *mode);
  unsigned int SDLKit_PixelFormat_ABGR8888(void);
  int SDLKit_RenderReadPixels(void *renderer, int x, int y, int w, int h, void *pixels, int pitch);
  void *SDLKit_MetalLayerForWindow(void *window);
  void *SDLKit_Win32HWND(void *window);
  bool SDLKit_CreateVulkanSurface(void *window, VkInstance instance, VkSurfaceKHR *surface);
  void SDLKit_Quit(void);

  // --- Audio (stubs) ---
  unsigned int SDLKit_AudioFormat_F32(void);
  unsigned int SDLKit_AudioFormat_S16(void);
  void *SDLKit_OpenDefaultAudioRecordingStream(int sample_rate, unsigned int format, int channels);
  void *SDLKit_OpenDefaultAudioPlaybackStream(int sample_rate, unsigned int format, int channels);
  int SDLKit_GetAudioStreamAvailable(void *stream);
  int SDLKit_GetAudioStreamData(void *stream, void *buf, int len);
  int SDLKit_PutAudioStreamData(void *stream, const void *buf, int len);
  int SDLKit_FlushAudioStream(void *stream);
  void SDLKit_DestroyAudioStream(void *stream);
  void *SDLKit_CreateAudioStreamConvert(int src_rate, unsigned int src_format, int src_channels,
                                                          int dst_rate, unsigned int dst_format, int dst_channels);
  int SDLKit_ClearAudioStream(void *stream);
  int SDLKit_ListAudioPlaybackDevices(uint64_t *dst_ids, int dst_count);
  int SDLKit_ListAudioRecordingDevices(uint64_t *dst_ids, int dst_count);
  const char *SDLKit_GetAudioDeviceNameU64(uint64_t devid);
  int SDLKit_GetAudioDevicePreferredFormatU64(uint64_t devid, int *sample_rate, unsigned int *format, int *channels, int *sample_frames);
  void *SDLKit_OpenAudioRecordingStreamU64(uint64_t devid, int sample_rate, unsigned int format, int channels);
  void *SDLKit_OpenAudioPlaybackStreamU64(uint64_t devid, int sample_rate, unsigned int format, int channels);

  int SDLKitStub_DestroyRendererCallCount(void);
  int SDLKitStub_QuitCallCount(void);
  int SDLKitStub_TTFQuitCallCount(void);
  void SDLKitStub_ResetCallCounts(void);
  int SDLKitStub_IsActive(void);
#endif

#if __has_include(<SDL3/SDL.h>)
  static inline int SDLKitStub_DestroyRendererCallCount(void) { return -1; }
  static inline int SDLKitStub_QuitCallCount(void) { return -1; }
  static inline int SDLKitStub_TTFQuitCallCount(void) { return -1; }
  static inline void SDLKitStub_ResetCallCounts(void) { }
  static inline int SDLKitStub_IsActive(void) { return 0; }
#endif

#ifdef __cplusplus
} // extern "C"
#endif
