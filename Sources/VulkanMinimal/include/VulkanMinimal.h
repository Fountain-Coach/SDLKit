#ifndef SDLKIT_VULKAN_MINIMAL_H
#define SDLKIT_VULKAN_MINIMAL_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VkInstance_T *VkInstance;
typedef uint32_t VkFlags;
typedef VkFlags VkInstanceCreateFlags;
typedef int32_t VkResult;
typedef uint64_t VkSurfaceKHR;

typedef struct VulkanMinimalInstance {
    VkInstance handle;
} VulkanMinimalInstance;

typedef struct VkAllocationCallbacks VkAllocationCallbacks;

typedef enum VkStructureType {
    VK_STRUCTURE_TYPE_APPLICATION_INFO = 0,
    VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1
} VkStructureType;

typedef struct VkApplicationInfo {
    VkStructureType sType;
    const void *pNext;
    const char *pApplicationName;
    uint32_t applicationVersion;
    const char *pEngineName;
    uint32_t engineVersion;
    uint32_t apiVersion;
} VkApplicationInfo;

typedef struct VkInstanceCreateInfo {
    VkStructureType sType;
    const void *pNext;
    VkInstanceCreateFlags flags;
    const VkApplicationInfo *pApplicationInfo;
    uint32_t enabledLayerCount;
    const char *const *ppEnabledLayerNames;
    uint32_t enabledExtensionCount;
    const char *const *ppEnabledExtensionNames;
} VkInstanceCreateInfo;

static inline uint32_t VulkanMinimalMakeVersion(uint32_t major, uint32_t minor, uint32_t patch) {
    return (major << 22) | (minor << 12) | patch;
}

#define VK_SUCCESS 0
#define VK_ERROR_INITIALIZATION_FAILED -3
#define VK_API_VERSION_1_0 VulkanMinimalMakeVersion(1, 0, 0)

VkResult VulkanMinimalCreateInstance(VulkanMinimalInstance *instance);
void VulkanMinimalDestroyInstance(VulkanMinimalInstance *instance);

#ifdef __cplusplus
}
#endif

#endif // SDLKIT_VULKAN_MINIMAL_H
