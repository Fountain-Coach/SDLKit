#pragma once

// Try common SDL3 include layouts (brew/apt/fork variations)
#if __has_include(<SDL3/SDL.h>)
#  include <SDL3/SDL.h>
#elif __has_include(<SDL.h>)
#  include <SDL.h>
#else
#  error "SDL3 headers not found. Ensure SDL3 is installed and headers are on the include path (e.g., -I/usr/local/include)."
#endif
