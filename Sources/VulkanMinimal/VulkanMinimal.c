#include "VulkanMinimal.h"
#include <string.h>
#include <dlfcn.h>

typedef VkResult (*PFN_vkCreateInstance)(const VkInstanceCreateInfo *, const VkAllocationCallbacks *, VkInstance *);
typedef void (*PFN_vkDestroyInstance)(VkInstance, const VkAllocationCallbacks *);

static void *vulkanLibraryHandle = NULL;
static PFN_vkCreateInstance pfn_vkCreateInstance = NULL;
static PFN_vkDestroyInstance pfn_vkDestroyInstance = NULL;

static bool VulkanMinimalEnsureLoaded(void) {
    if (pfn_vkCreateInstance && pfn_vkDestroyInstance) {
        return true;
    }

    if (!vulkanLibraryHandle) {
        const char *candidates[] = { "libvulkan.so.1", "libvulkan.so", NULL };
        for (int i = 0; candidates[i] != NULL; ++i) {
            vulkanLibraryHandle = dlopen(candidates[i], RTLD_NOW | RTLD_LOCAL);
            if (vulkanLibraryHandle) {
                break;
            }
        }
    }

    if (!vulkanLibraryHandle) {
        return false;
    }

    pfn_vkCreateInstance = (PFN_vkCreateInstance)dlsym(vulkanLibraryHandle, "vkCreateInstance");
    pfn_vkDestroyInstance = (PFN_vkDestroyInstance)dlsym(vulkanLibraryHandle, "vkDestroyInstance");

    return (pfn_vkCreateInstance && pfn_vkDestroyInstance);
}

VkResult VulkanMinimalCreateInstance(VulkanMinimalInstance *instance) {
    if (!instance) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    memset(instance, 0, sizeof(*instance));

    if (!VulkanMinimalEnsureLoaded()) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    const char appName[] = "SDLKitDemo";
    const char engineName[] = "SDLKit";

    VkApplicationInfo appInfo;
    memset(&appInfo, 0, sizeof(appInfo));
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = appName;
    appInfo.applicationVersion = VulkanMinimalMakeVersion(1, 0, 0);
    appInfo.pEngineName = engineName;
    appInfo.engineVersion = VulkanMinimalMakeVersion(0, 1, 0);
    appInfo.apiVersion = VK_API_VERSION_1_0;

    VkInstanceCreateInfo createInfo;
    memset(&createInfo, 0, sizeof(createInfo));
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;

    VkResult result = pfn_vkCreateInstance(&createInfo, NULL, &instance->handle);
    if (result != VK_SUCCESS) {
        instance->handle = NULL;
    }
    return result;
}

void VulkanMinimalDestroyInstance(VulkanMinimalInstance *instance) {
    if (!instance || !instance->handle) {
        return;
    }
    if (VulkanMinimalEnsureLoaded()) {
        pfn_vkDestroyInstance(instance->handle, NULL);
    }
    instance->handle = NULL;
}

VkResult VulkanMinimalCreateInstanceWithExtensions(const char *const *extensions,
                                                  uint32_t extensionCount,
                                                  VulkanMinimalInstance *instance) {
    if (!instance) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    memset(instance, 0, sizeof(*instance));

    if (!VulkanMinimalEnsureLoaded()) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    const char appName[] = "SDLKitDemo";
    const char engineName[] = "SDLKit";

    VkApplicationInfo appInfo;
    memset(&appInfo, 0, sizeof(appInfo));
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = appName;
    appInfo.applicationVersion = VulkanMinimalMakeVersion(1, 0, 0);
    appInfo.pEngineName = engineName;
    appInfo.engineVersion = VulkanMinimalMakeVersion(0, 1, 0);
    appInfo.apiVersion = VK_API_VERSION_1_0;

    VkInstanceCreateInfo createInfo;
    memset(&createInfo, 0, sizeof(createInfo));
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = extensionCount;
    createInfo.ppEnabledExtensionNames = extensions;

    VkResult result = pfn_vkCreateInstance(&createInfo, NULL, &instance->handle);
    if (result != VK_SUCCESS) {
        instance->handle = NULL;
    }
    return result;
}
