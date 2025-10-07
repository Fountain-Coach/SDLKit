#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include "../CSDL3/shim.h"

// Minimal stub implementations that satisfy the shim symbol surface when SDL3
// headers/libraries are unavailable. All functions return failure defaults.

static const char *SDLKIT_STUB_ERROR_MESSAGE = "SDLKit SDL3 stub: SDL unavailable";
static int s_destroy_renderer_calls = 0;
static int s_quit_calls = 0;
static int s_ttf_quit_calls = 0;

const char *SDLKit_GetError(void) {
    return SDLKIT_STUB_ERROR_MESSAGE;
}

int SDLKit_Init(uint32_t flags) {
    (void)flags;
    return -1;
}

SDL_Window *SDLKit_CreateWindow(const char *title, int32_t width, int32_t height, uint32_t flags) {
    (void)title; (void)width; (void)height; (void)flags;
    return NULL;
}

void SDLKit_DestroyWindow(SDL_Window *window) {
    (void)window;
}

void SDLKit_DestroyRenderer(SDL_Renderer *renderer) {
    (void)renderer;
    s_destroy_renderer_calls++;
}

void SDLKit_ShowWindow(SDL_Window *window) {
    (void)window;
}

void SDLKit_HideWindow(SDL_Window *window) {
    (void)window;
}

void SDLKit_SetWindowTitle(SDL_Window *window, const char *title) {
    (void)window; (void)title;
}

const char *SDLKit_GetWindowTitle(SDL_Window *window) {
    (void)window;
    return "SDLKit Stub Window";
}

void SDLKit_SetWindowPosition(SDL_Window *window, int x, int y) {
    (void)window; (void)x; (void)y;
}

void SDLKit_GetWindowPosition(SDL_Window *window, int *x, int *y) {
    (void)window;
    if (x) { *x = 0; }
    if (y) { *y = 0; }
}

void SDLKit_SetWindowSize(SDL_Window *window, int w, int h) {
    (void)window; (void)w; (void)h;
}

void SDLKit_GetWindowSize(SDL_Window *window, int *w, int *h) {
    (void)window;
    if (w) { *w = 0; }
    if (h) { *h = 0; }
}

void SDLKit_MaximizeWindow(SDL_Window *window) {
    (void)window;
}

void SDLKit_MinimizeWindow(SDL_Window *window) {
    (void)window;
}

void SDLKit_RestoreWindow(SDL_Window *window) {
    (void)window;
}

int SDLKit_SetWindowFullscreen(SDL_Window *window, int enabled) {
    (void)window; (void)enabled;
    return -1;
}

int SDLKit_SetWindowOpacity(SDL_Window *window, float opacity) {
    (void)window; (void)opacity;
    return -1;
}

int SDLKit_SetWindowAlwaysOnTop(SDL_Window *window, int enabled) {
    (void)window; (void)enabled;
    return -1;
}

void SDLKit_CenterWindow(SDL_Window *window) {
    (void)window;
}

int SDLKit_SetClipboardText(const char *text) {
    (void)text;
    return -1;
}

char *SDLKit_GetClipboardText(void) {
    return NULL;
}

void SDLKit_free(void *p) {
    free(p);
}

void SDLKit_GetMouseState(int *x, int *y, unsigned int *buttons) {
    if (x) { *x = 0; }
    if (y) { *y = 0; }
    if (buttons) { *buttons = 0; }
}

int SDLKit_GetModMask(void) {
    return 0;
}

int SDLKit_GetNumVideoDisplays(void) {
    return 0;
}

const char *SDLKit_GetDisplayName(int index) {
    (void)index;
    return "SDLKit Stub Display";
}

int SDLKit_GetDisplayBounds(int index, int *x, int *y, int *w, int *h) {
    (void)index;
    if (x) { *x = 0; }
    if (y) { *y = 0; }
    if (w) { *w = 0; }
    if (h) { *h = 0; }
    return -1;
}

void *SDLKit_CreateRenderer(void *window, uint32_t flags) {
    (void)window; (void)flags;
    return NULL;
}

int SDLKit_SetRenderDrawColor(void *renderer, uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    (void)renderer; (void)r; (void)g; (void)b; (void)a;
    return -1;
}

int SDLKit_RenderClear(void *renderer) {
    (void)renderer;
    return -1;
}

int SDLKit_RenderFillRect(void *renderer, const struct SDL_FRect *rect) {
    (void)renderer; (void)rect;
    return -1;
}

int SDLKit_RenderFillRects(void *renderer, const struct SDL_FRect *rects, int count) {
    (void)renderer; (void)rects; (void)count;
    return -1;
}

int SDLKit_RenderRects(void *renderer, const struct SDL_FRect *rects, int count) {
    (void)renderer; (void)rects; (void)count;
    return -1;
}

int SDLKit_RenderPoints(void *renderer, const struct SDL_FPoint *points, int count) {
    (void)renderer; (void)points; (void)count;
    return -1;
}

int SDLKit_RenderLine(void *renderer, float x1, float y1, float x2, float y2) {
    (void)renderer; (void)x1; (void)y1; (void)x2; (void)y2;
    return -1;
}

void SDLKit_RenderPresent(void *renderer) {
    (void)renderer;
}

void SDLKit_GetRenderOutputSize(void *renderer, int *w, int *h) {
    (void)renderer;
    if (w) { *w = 0; }
    if (h) { *h = 0; }
}

void SDLKit_GetRenderScale(void *renderer, float *sx, float *sy) {
    (void)renderer;
    if (sx) { *sx = 1.0f; }
    if (sy) { *sy = 1.0f; }
}

int SDLKit_SetRenderScale(void *renderer, float sx, float sy) {
    (void)renderer; (void)sx; (void)sy;
    return -1;
}

void SDLKit_GetRenderDrawColor(void *renderer, uint8_t *r, uint8_t *g, uint8_t *b, uint8_t *a) {
    (void)renderer;
    if (r) { *r = 0; }
    if (g) { *g = 0; }
    if (b) { *b = 0; }
    if (a) { *a = 0; }
}

int SDLKit_SetRenderViewport(void *renderer, int x, int y, int w, int h) {
    (void)renderer; (void)x; (void)y; (void)w; (void)h;
    return -1;
}

void SDLKit_GetRenderViewport(void *renderer, int *x, int *y, int *w, int *h) {
    (void)renderer;
    if (x) { *x = 0; }
    if (y) { *y = 0; }
    if (w) { *w = 0; }
    if (h) { *h = 0; }
}

int SDLKit_SetRenderClipRect(void *renderer, int x, int y, int w, int h) {
    (void)renderer; (void)x; (void)y; (void)w; (void)h;
    return -1;
}

int SDLKit_DisableRenderClipRect(void *renderer) {
    (void)renderer;
    return -1;
}

void SDLKit_GetRenderClipRect(void *renderer, int *x, int *y, int *w, int *h) {
    (void)renderer;
    if (x) { *x = 0; }
    if (y) { *y = 0; }
    if (w) { *w = 0; }
    if (h) { *h = 0; }
}

int SDLKit_PollEvent(SDLKit_Event *out) {
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    return 0;
}

int SDLKit_WaitEventTimeout(SDLKit_Event *out, int timeout_ms) {
    (void)timeout_ms;
    if (out) {
        memset(out, 0, sizeof(*out));
    }
    return 0;
}

int SDLKit_TTF_Init(void) {
    return -1;
}

SDLKit_TTF_Font *SDLKit_TTF_OpenFont(const char *path, int ptsize) {
    (void)path; (void)ptsize;
    return NULL;
}

void SDLKit_TTF_CloseFont(SDLKit_TTF_Font *font) {
    (void)font;
}

struct SDL_Surface *SDLKit_TTF_RenderUTF8_Blended(SDLKit_TTF_Font *font, const char *text,
                                                  uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    (void)font; (void)text; (void)r; (void)g; (void)b; (void)a;
    return NULL;
}

void *SDLKit_CreateTextureFromSurface(void *renderer, struct SDL_Surface *surface) {
    (void)renderer; (void)surface;
    return NULL;
}

void SDLKit_DestroySurface(void *surface) {
    (void)surface;
}

void SDLKit_DestroyTexture(void *tex) {
    (void)tex;
}

void SDLKit_GetTextureSize(void *tex, int *w, int *h) {
    (void)tex;
    if (w) { *w = 0; }
    if (h) { *h = 0; }
}

int SDLKit_RenderTexture(void *renderer, void *tex, const struct SDL_FRect *src, const struct SDL_FRect *dst) {
    (void)renderer; (void)tex; (void)src; (void)dst;
    return -1;
}

int SDLKit_RenderTextureRotated(void *renderer, void *tex, const struct SDL_FRect *src, const struct SDL_FRect *dst, double angle, int hasCenter, float cx, float cy) {
    (void)renderer; (void)tex; (void)src; (void)dst; (void)angle; (void)hasCenter; (void)cx; (void)cy;
    return -1;
}

void *SDLKit_LoadBMP(const char *path) {
    (void)path;
    return NULL;
}

void *SDLKit_CreateSurfaceFrom(int width, int height, unsigned int format, void *pixels, int pitch) {
    (void)width; (void)height; (void)format; (void)pixels; (void)pitch;
    return NULL;
}

void *SDLKit_RWFromFile(const char *file, const char *mode) {
    (void)file; (void)mode;
    return NULL;
}

unsigned int SDLKit_PixelFormat_ABGR8888(void) {
    return 0;
}

int SDLKit_RenderReadPixels(void *renderer, int x, int y, int w, int h, void *pixels, int pitch) {
    (void)renderer; (void)x; (void)y; (void)w; (void)h; (void)pixels; (void)pitch;
    return -1;
}

void *SDLKit_MetalLayerForWindow(void *window) {
    (void)window;
    return NULL;
}

void *SDLKit_Win32HWND(void *window) {
    (void)window;
    return NULL;
}

bool SDLKit_CreateVulkanSurface(void *window, VkInstance instance, VkSurfaceKHR *surface) {
    (void)window; (void)instance;
    if (surface) {
        *surface = (VkSurfaceKHR)0;
    }
    return false;
}

void SDLKit_Quit(void) {
    s_quit_calls++;
}

// --- Audio (stubs) ---
unsigned int SDLKit_AudioFormat_F32(void) { return 0; }
unsigned int SDLKit_AudioFormat_S16(void) { return 0; }
void *SDLKit_OpenDefaultAudioRecordingStream(int sample_rate, unsigned int format, int channels) {
    (void)sample_rate; (void)format; (void)channels; return NULL;
}
void *SDLKit_OpenDefaultAudioPlaybackStream(int sample_rate, unsigned int format, int channels) {
    (void)sample_rate; (void)format; (void)channels; return NULL;
}
int SDLKit_GetAudioStreamAvailable(void *stream) { (void)stream; return 0; }
int SDLKit_GetAudioStreamData(void *stream, void *buf, int len) { (void)stream; (void)buf; (void)len; return -1; }
int SDLKit_PutAudioStreamData(void *stream, const void *buf, int len) { (void)stream; (void)buf; (void)len; return -1; }
int SDLKit_FlushAudioStream(void *stream) { (void)stream; return -1; }
void SDLKit_DestroyAudioStream(void *stream) { (void)stream; }
void *SDLKit_CreateAudioStreamConvert(int src_rate, unsigned int src_format, int src_channels,
                                                        int dst_rate, unsigned int dst_format, int dst_channels) {
    (void)src_rate; (void)src_format; (void)src_channels; (void)dst_rate; (void)dst_format; (void)dst_channels; return NULL;
}
int SDLKit_ClearAudioStream(void *stream) { (void)stream; return -1; }

int SDLKit_ListAudioPlaybackDevices(uint64_t *dst_ids, int dst_count) { (void)dst_ids; (void)dst_count; return -1; }
int SDLKit_ListAudioRecordingDevices(uint64_t *dst_ids, int dst_count) { (void)dst_ids; (void)dst_count; return -1; }
const char *SDLKit_GetAudioDeviceNameU64(uint64_t devid) { (void)devid; return NULL; }
int SDLKit_GetAudioDevicePreferredFormatU64(uint64_t devid, int *sample_rate, unsigned int *format, int *channels, int *sample_frames) {
    (void)devid; (void)sample_rate; (void)format; (void)channels; (void)sample_frames; return -1;
}
void *SDLKit_OpenAudioRecordingStreamU64(uint64_t devid, int sample_rate, unsigned int format, int channels) {
    (void)devid; (void)sample_rate; (void)format; (void)channels; return NULL;
}
void *SDLKit_OpenAudioPlaybackStreamU64(uint64_t devid, int sample_rate, unsigned int format, int channels) {
    (void)devid; (void)sample_rate; (void)format; (void)channels; return NULL;
}
int SDLKit_LoadWAV(const char *path, struct SDL_AudioSpec *out_spec, unsigned char **out_buf, unsigned int *out_len) {
    (void)path; (void)out_spec; (void)out_buf; (void)out_len; return -1;
}

void SDLKit_TTF_Quit(void) {
    s_ttf_quit_calls++;
}

int SDLKitStub_DestroyRendererCallCount(void) {
    return s_destroy_renderer_calls;
}

int SDLKitStub_QuitCallCount(void) {
    return s_quit_calls;
}

int SDLKitStub_TTFQuitCallCount(void) {
    return s_ttf_quit_calls;
}

void SDLKitStub_ResetCallCounts(void) {
    s_destroy_renderer_calls = 0;
    s_quit_calls = 0;
    s_ttf_quit_calls = 0;
}

int SDLKitStub_IsActive(void) {
    return 1;
}
