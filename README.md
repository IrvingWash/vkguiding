Learning Vulkan API using the [Vulkan Guide](https://vkguide.dev/)

Structure:
- `source`                        - """"Game logic"""".
- `modules/Renderer`              - A realtime renderer implementation using the VkGuide.
- `modules/Window`                - Thin GLFW wrapper to avoid coupling the Renderer with GLFW - a backend wrapper.
- `modules/GLFW`                  - Manually defined GLFW bindings. The purpose is to avoid the pain caused with interfacing with a 50 year old language. I took a lot of liberties here, so naming and API is differs quite a bit from the original C API.
- `modules/Jai_Vulkan`            - Manually defined Vulkan bindings. Principles:
    - No `VK`, `vk`, `Vk`, etc prefixes.
    - Identical naming, but converted to snake and Ada case.
    - Predefined `s_type`s for structures.
    - Structures have the same API (`xxx_count` and `p_xxxs` kept intact).
    - Procedures have "modern" api, returning multiple values instead of out parameters and expeding sliced instead of counts and pointers.
    - Maybe something else, it's not that formal, you know.
- `modules/Jai_Vulkan/VMA`        - Manually defined Vulkan Memory Allocator bidings. Has same principles as `Jai_Vulkan`. The binary can be build using `modules/Jai_Vulkan/generate.jai` (but be careful, because it also generates auto-bidings to both Vulkan and VMA).
- `tools` and `install_tools.jai` - Git hooks.
- `build.jai`                     - The build metaprogram.
