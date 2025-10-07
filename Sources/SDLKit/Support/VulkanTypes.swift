#if canImport(Vulkan)
@_exported import Vulkan
public typealias VkInstance = Vulkan.VkInstance
public typealias VkSurfaceKHR = Vulkan.VkSurfaceKHR
#elseif os(Linux) && canImport(CVulkan)
@_exported import CVulkan
public typealias VkInstance = CVulkan.VkInstance
public typealias VkSurfaceKHR = CVulkan.VkSurfaceKHR
#elseif canImport(CSDL3)
// Align Swift-side Vulkan handle types with CSDL3 module import
import CSDL3
public typealias VkInstance = CSDL3.VkInstance
public typealias VkSurfaceKHR = CSDL3.VkSurfaceKHR
#else
public typealias VkInstance = OpaquePointer?
public typealias VkSurfaceKHR = UInt64
#endif
