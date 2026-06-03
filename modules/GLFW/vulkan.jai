get_required_instance_extensions :: () -> count: u32, extensions: **u8 {
    count: u32;
    extensions := glfwGetRequiredInstanceExtensions(*count);

    return count, extensions;
}

// Returns VKResult
create_window_surface :: (
    instance:  *void, // VKInstance
    window:    *Window,
    allocator: *void, // VKAllocationCallbacks
    surface:   *void, // VKSurfaceKHR
) -> s32 #foreign GLFW "glfwCreateWindowSurface";



#scope_file

glfwGetRequiredInstanceExtensions :: (count: *u32) -> **u8 #foreign GLFW;
