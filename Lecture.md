# SDLKit Alpha Graphics Back‑End Lecture: Principles and Architecture

## 1 Overview of SDLKit

### 1.1 Purpose

SDLKit is a **Swift‑first wrapper** around the SDL3 C library that aims to make creating windows, handling events and rendering graphics approachable to both human developers and autonomous agents.  The repository targets Fountain‑Coach’s custom SDL3 fork and adds a modern **3D rendering and compute layer** with backends for **Metal**, **Direct3D 12** and **Vulkan**.  SDLKit exposes a JSON agent interface for opening/closing windows and drawing primitives and also includes a planned scene graph, shader build pipeline and GPU compute tools.  According to its README, SDLKit separates SDL interop from higher‑level modules so that the foundation can be reused across projects while exposing a predictable surface area for AI planners [README.md L318-L322](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L318-L322).

### 1.2 Current Status (Alpha)

As of the alpha release, SDLKit provides:

 - **Core window and renderer wrappers** that bind to SDL3, with support for a headless CI build where SDL is not linked [README.md L329-L333](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L329-L333).
 - A **JSON agent** that implements documented window controls, primitive drawing and input/screenshot tools [README.md L329-L337](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L329-L337).
 - A **cross‑platform 3D module** exposing Metal, Direct3D 12 and Vulkan backends, a scene graph for transform propagation and compute pipelines that share shader metadata [README.md L334-L336](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L334-L336).
 - A **shader build pipeline** using DXC and SPIRV‑Cross to generate SPIR‑V, DXIL and Metal binaries from a single HLSL source [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).

## 2 Principles of Graphics Back‑Ends

### 2.1 GPU architecture and memory hierarchy

Modern GPUs are designed for **massive parallelism**; they can run thousands of threads simultaneously, making them ideal for processing many vertices or pixels at once【5158873157052†L52-L59】.  GPUs have a complex memory hierarchy:

- **Global memory** for large, high‑latency data;
- **Shared memory** on the chip that is very fast and shared between threads in a work group;
- **Texture memory** optimized for 2D spatial locality; and
- **Constant memory** used for read‑only constants【5158873157052†L74-L83】.

Understanding this hierarchy is crucial when designing a back‑end because it influences how buffers and textures are allocated and accessed.

### 2.2 Graphics API fundamentals

Low‑level graphics APIs such as Vulkan, DirectX 12 and Metal act as a **bridge** between the CPU and the GPU.  A typical application cycle involves:

1. **Initialization** – create a context/device that encapsulates the state of the GPU【5158873157052†L95-L104】.  In SDLKit this corresponds to creating an `SDLWindow` and passing it to a concrete `RenderBackend`, which in turn creates platform‑specific devices (e.g., `MTLDevice` on macOS or `ID3D12Device` on Windows) [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).
2. **Resource management** – allocate buffers and textures on the GPU.  APIs expose functions to create textures and buffers; behind the scenes these calls allocate memory on the GPU【5158873157052†L108-L118】.  SDLKit’s `RenderBackend` exposes `createBuffer` and `createTexture` methods for this purpose [RenderBackend.swift L356-L363](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L356-L363).
3. **Define the rendering pipeline** – set up shaders and pipeline state.  Modern APIs treat the pipeline state as a monolithic object because all stages must be configured consistently【242488781808860†L318-L324】.  SDLKit uses `makePipeline` to create a graphics pipeline with a shader and vertex layout and `makeComputePipeline` for compute shaders [RenderBackend.swift L372-L380](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L372-L380).
4. **Issue draw calls** – record commands that bind resources and instruct the GPU to draw.  Draw calls depend on the state of the bound resources and shaders【65054574551388†L82-L103】.  SDLKit’s `draw(mesh:pipeline:bindings:transform:)` method encapsulates a draw call [RenderBackend.swift L366-L377](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L366-L377).
5. **Present the frame** – swap the back buffer to the screen.  This often uses a swap chain to manage multiple frame buffers【5158873157052†L141-L144】.
6. **Repeat** steps 2–5 until the application exits【838073614783006†L61-L79】.

After the application ends, resources are destroyed and the context is cleaned up.

### 2.3 Execution order and high‑level tasks

Across different graphics APIs the general **execution order** is consistent.  An application:

1. Initializes the API (creates device, contexts, swap chain).  In Diligent Engine, a **render device** creates all objects, while **device contexts** record immediate or deferred command lists【242488781808860†L272-L296】.  SDLKit uses a similar pattern: it exposes a `RenderBackend` protocol that initializes the GPU device and provides command recording functions [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).
2. Loads assets, including shaders and pipeline descriptions【838073614783006†L61-L70】.
3. Updates assets and performs application‑level logic such as simulation or UI【838073614783006†L71-L72】.
4. Presents the frame to the swap chain【838073614783006†L74-L75】.
5. Repeats steps 2–4 until termination【838073614783006†L64-L80】.
6. Destroys resources and waits for the GPU to finish【838073614783006†L79-L80】.

These steps provide a conceptual blueprint for designing a back‑end.

### 2.4 Modern rendering abstraction and design goals

Because GPUs and graphics APIs vary by platform, many engines implement a **rendering abstraction layer**.  Alex Tardif notes that a good abstraction should be **lightweight**, hide as many API‑specific concepts as possible and be easy to debug and maintain【859641878713924†L35-L49】.  He suggests defining only essential classes: a device that connects to a display, resource abstractions (buffers, textures) and a means of gathering and submitting command work in a multi‑core‑compatible way【859641878713924†L56-L70】.  High‑level code should not be polluted with API details; those live behind the abstraction.

## 3 SDLKit’s Graphics Architecture

### 3.1 RenderBackend protocol

SDLKit embodies the above principles through the **`RenderBackend` protocol**.  This protocol is the core contract between high‑level code (scene graph, agents) and the low‑level graphics back‑end.  Key responsibilities, as described in the implementation strategy document, include:

 - **Initialize a GPU device/context** for a given window [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).
- **Create buffers and textures** and optionally fill them with initial data [RenderBackend.swift L356-L363](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L356-L363).
- **Create samplers and pipeline state objects** (`makePipeline` and `makeComputePipeline`) [RenderBackend.swift L372-L380](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L372-L380).
- **Register meshes** by uploading vertex/index buffers and returning handles [RenderBackend.swift L366-L371](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L366-L371).
- **Issue draw calls** by binding a mesh, pipeline and resources and specifying a transform matrix [RenderBackend.swift L373-L377](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L373-L377).
- **Dispatch compute shaders** for non‑graphics workloads like physics or audio processing [RenderBackend.swift L379-L383](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L379-L383).
- **Begin and end frames, resize swap chains and wait for the GPU** [RenderBackend.swift L352-L357](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L352-L357).

Using handles and descriptors decouples client code from API‑specific objects.  For example, `BufferHandle` and `TextureHandle` are just integers under the hood [RenderBackend.swift L26-L38](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L26-L38), while `GraphicsPipelineDescriptor` collects the shader ID, vertex layout and render‑target formats [RenderBackend.swift L285-L303](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L285-L303).  The back‑end knows how to convert these into API objects (e.g., `MTLRenderPipelineState`, `VkPipeline` or `ID3D12PipelineState`).

### 3.2 Concrete back‑ends

SDLKit implements a separate class for each graphics API—**MetalRenderBackend**, **D3DRenderBackend** and **VulkanRenderBackend**—conforming to `RenderBackend`.  During runtime, SDLKit selects the appropriate back‑end based on the platform (Metal on macOS/iOS, D3D12 on Windows, Vulkan on Linux) [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).  Developers can override this choice for testing (e.g., forcing Vulkan on macOS via MoltenVK) [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).

When a window is created, the back‑end obtains **native handles** from SDL’s C API, such as the `CAMetalLayer` on macOS, the Win32 `HWND` on Windows or the `VkSurfaceKHR` on Linux [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).  A C shim function (e.g., `SDLKit_MetalLayerForWindow`) exposes these handles to Swift, after which the back‑end creates the platform device and swap chain [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).

### 3.3 Scene graph architecture

SDLKit plans to add a **scene graph** to organize 3D content.  The implementation strategy describes the following classes [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf):

- **Scene** – container for all objects and global settings.
- **SceneNode** – basic node storing a local transform (position, rotation, scale) and references to parent and children; world transforms are computed by combining ancestors [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).
- **Camera** – specialized node defining view and projection matrices [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).
- **Light** – node representing directional, point or spot lights with properties like color and intensity [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).
- **Mesh** – node containing geometry and associated with a material [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).
- **Material** – encapsulates shader programs and GPU resources, effectively representing a render pipeline configuration [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).
- **Renderable** – protocol/base class for nodes that can be drawn [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).

The scene graph will tag materials with pipeline types (opaque pass, shadow map pass) and remain platform‑agnostic—describing **what** to draw, while the back‑end describes **how** to draw it [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).

### 3.4 Shader toolchain

SDLKit uses a **single‑source shader pipeline**: developers write HLSL code, and the build process compiles it into SPIR‑V for Vulkan, DXIL for Direct3D 12 and MSL for Metal using DXC and SPIRV‑Cross [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).  This approach ensures feature parity across back‑ends and reduces maintenance.  The `ShaderLibrary` in `Sources/SDLKit/Graphics` loads precompiled shader binaries.  The `build‑shaders.py` script and the SwiftPM plugin regenerate these artifacts during development and CI [README.md L360-L363](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L360-L363).

### 3.5 GPU compute layer

Beyond graphics, SDLKit plans a **GPU compute layer** enabling general‑purpose computation.  According to the strategy document, compute tasks will use **compute shaders** compiled alongside graphics shaders (e.g., `fft_compute.hlsl` compiled to MSL and SPIR‑V) [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).  Each back‑end will create a **compute pipeline state** (e.g., `MTLComputePipelineState`, `VkPipeline` with a compute shader) [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).  The `RenderBackend` protocol may include methods such as `createComputePipeline` and `dispatchCompute` to run compute workloads on the GPU [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).  Compute and graphics will share buffers when appropriate, and synchronization primitives (pipeline barriers for Vulkan, command ordering for Metal) ensure correctness [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).  Use cases include audio DSP, physics simulations and machine‑learning inference [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).

### 3.6 Headless and testing modes

The README notes that SDLKit supports **headless CI mode**: by defining `-DHEADLESS_CI`, SDL interop and linking are compiled out and GUI calls return `sdlUnavailable` [README.md L401-L406](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L401-L406).  Smoke tests validate shader artifacts and image parity across back‑ends [README.md L364-L366](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L364-L366).  A golden‑image capture feature (supported via the `GoldenImageCapturable` protocol) allows back‑ends to save rendered frames and compare hashes [RenderBackend.swift L325-L333](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L325-L333).

## 4 General Architectural Design

### 4.1 Layered approach

SDLKit adopts a **layered architecture**:

1. **CSDL3 system library** – provides the C shim for SDL3 headers and exposes functions to Swift (e.g., retrieving native window handles).
2. **Core layer** – wraps SDL windows, events and the main loop (`SDLWindow.swift`, `SDLRenderer.swift`).  This layer abstracts away C pointers and event polling so that Swift code remains ergonomic.
3. **Graphics layer** – defines the `RenderBackend` protocol and implements back‑ends for Metal/D3D12/Vulkan.  It also contains resource descriptors, pipeline descriptors and golden‑image capture.
4. **SceneGraph layer** – organizes objects, cameras, lights and materials into a hierarchy; resolves transforms and dispatches draw calls.
5. **Shader and Compute layers** – compile and load shaders across platforms; provide compute pipelines and dispatch interfaces.
6. **Agent/JSON layer** – exposes the high‑level API to AI planners or external processes via JSON.  Methods such as `/agent/gui/window/open`, `/drawRectangle` and `/present` allow tools to drive SDLKit without linking Swift [README.md L522-L563](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L522-L563).

Separating these layers allows developers to **replace or extend** one part without affecting others.  For example, one could implement an OpenGL back‑end by conforming to `RenderBackend` without changing the scene graph.

### 4.2 Separation of interface and implementation

The architecture heavily uses **protocols** and **value types** (structs) to separate interfaces from platform‑specific implementations.  `RenderBackend` is a protocol; each back‑end implements it.  `BufferHandle`, `TextureHandle` and other resource handles are opaque wrappers around integers [RenderBackend.swift L26-L38](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L26-L38).  Higher‑level code treats them as tokens; only the back‑end knows how to map them to API resources.  This reduces coupling and makes the code easier to test and reason about.

### 4.3 Conditional compilation for platform code

Since Swift cannot import Metal/D3D/Vulkan on all platforms, SDLKit uses **conditional compilation** (`#if os(macOS)`, `#if os(Windows)` etc.) to include platform‑specific code only where it is valid [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).  The project structure organizes platform code into separate files (e.g., `MetalRenderBackend.swift`, `D3DRenderBackend.swift`), and the `Package.swift` file configures the correct linker settings [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).

## 5 Preparing for a Deep Code Dive

To effectively explore SDLKit’s code base, consider the following roadmap:

### 5.1 High‑level orientation

1. **Read `Package.swift`** to understand how targets are organized and what external dependencies (SDL3, DXC, SPIRV‑Cross) are linked.
2. **Explore `Sources/CSDL3`** to see how SDL3 headers are bridged to Swift.  The `shim.h` and `module.modulemap` define the C functions and link flags [README.md L341-L344](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L341-L344).
3. **Start with `Sources/SDLKit/Core`**.  Classes like `SDLWindow` encapsulate window creation and event handling.  Understand how they handle headless mode and how they expose native handles.

### 5.2 Graphics layer deep dive

1. **Study `RenderBackend.swift`**.  Familiarize yourself with the types (`BufferHandle`, `TextureDescriptor`, `GraphicsPipelineDescriptor`, etc.) and protocol methods [RenderBackend.swift L352-L383](https://github.com/Fountain-Coach/SDLKit/blob/main/Sources/SDLKit/Graphics/RenderBackend.swift#L352-L383).  These define the vocabulary used throughout SDLKit.
2. **Follow `RenderBackendFactory.swift`** (not shown here) to see how SDLKit selects a back‑end at runtime.
3. **Open `MetalRenderBackend.swift`, `D3DRenderBackend.swift` and `VulkanRenderBackend.swift`**.  Compare how each back‑end implements `init`, `createBuffer`, `makePipeline`, `draw` and `dispatchCompute`.  Notice how platform details (e.g., command buffers, descriptor heaps) are encapsulated.
4. **Review shader build scripts** in `Scripts/ShaderBuild` and the SwiftPM plugin in `Plugins/ShaderBuildPlugin`.  Observe how HLSL code is compiled to SPIR‑V, DXIL and MSL [README.md L360-L363](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L360-L363).

### 5.3 Scene and compute layers

1. **Inspect `SceneGraph.swift`** and related files.  Understand how scene nodes store transforms and how the scene is traversed.  Look at how materials reference shaders and pipeline states.
2. **Examine compute abstractions**.  If available, read `Compute.swift` or `ComputePipeline.swift` (planned in the strategy) to see how compute pipelines are created and dispatched [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).

### 5.4 JSON agent layer

1. **Read `AGENTS.md`** and `sdlkit.gui.v1.yaml` to understand the agent contract, error codes and event schema.  This layer turns JSON requests into `RenderBackend` actions, enabling remote control.
2. **Explore `SDLKitJSONAgent`** in `Sources/SDLKit/Core` to see how it routes JSON paths (e.g., `/agent/gui/drawRectangle`) to Swift method calls [README.md L523-L563](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L523-L563).

### 5.5 Testing and examples

1. **Run the tests** (`swift test`).  The `GoldenImageTests` and `SceneGraphComputeInteropTests` verify that graphics output matches reference images across back‑ends [README.md L364-L367](https://github.com/Fountain-Coach/SDLKit/blob/main/README.md#L364-L367).
2. **Build and run examples** in the `Examples` directory.  The scene graph demo demonstrates 3D rendering with different back‑ends.  Observe how it constructs the scene, compiles shaders and updates the scene per frame.

## 6 Conclusion and Next Steps

SDLKit’s alpha release lays the foundation for a modern, cross‑platform graphics and compute framework in Swift.  The **`RenderBackend` abstraction** encapsulates GPU operations and supports Metal, D3D12 and Vulkan.  A planned **scene graph** organizes 3D content with cameras, lights and materials [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).  The build system uses **single‑source HLSL shaders** cross‑compiled to SPIR‑V, DXIL and MSL [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf).  Upcoming features include a **compute layer** for GPGPU workloads [Implementation Strategy PDF](https://github.com/Fountain-Coach/SDLKit/blob/main/Implementation%20Strategy%20for%20Extending%20SDLKit%20with%203D%20Graphics,%20Multi-API%20Shaders,%20and%20GPU%20Compute.pdf) and enhanced agent tooling.

For a deep code dive, start by understanding high‑level concepts—how a GPU works, what a rendering pipeline looks like and why a rendering abstraction is useful.  Then follow the layered architecture of SDLKit, moving from the core SDL wrappers to the graphics back‑ends, scene graph, shader pipeline and JSON agent.  By approaching the project with this conceptual map, you’ll be well prepared to navigate the code and contribute to SDLKit’s evolution.
