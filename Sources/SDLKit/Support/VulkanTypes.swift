#if canImport(Vulkan)
@_exported import Vulkan
#elseif os(Linux) && canImport(CVulkan)
@_exported import CVulkan
#else
public typealias VkInstance = OpaquePointer?
public typealias VkSurfaceKHR = UInt64
#endif
