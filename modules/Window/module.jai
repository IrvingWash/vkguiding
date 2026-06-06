Window    :: #type GLFW.Window;
Key       :: #type GLFW.Key;
Key_State :: #type GLFW.Key_State;

create_window :: (width: u32, height: u32, $$title: string) -> *Window {
    GLFW.init();

    GLFW.set_window_hint(.CLIENT_API, .NO_API);
    GLFW.set_window_hint(.RESIZABLE, true);

    window := GLFW.create_window(width, height, title, null, null);

    return window;
}

should_window_close :: inline (window: *Window) -> bool {
    return GLFW.should_window_close(window);
}

poll_window_events :: inline () {
    GLFW.poll_events();
}

destroy_window :: (window: *Window) {
    GLFW.destroy_window(window);

    GLFW.terminate();
}

get_window_required_instance_extensions :: () -> [..]*u8 {
    result: [..]*u8;

    count, names := GLFW.get_required_instance_extensions();

    for 0..(count - 1) {
        array_add(*result, names[it]);
    }

    return result;
}

create_window_surface :: (instance: VK.Instance, window: *Window) -> VK.Result, VK.Surface_KHR {
    surface: VK.Surface_KHR;

    result := GLFW.create_window_surface(instance, window, null, *surface);

    return cast(VK.Result, result), surface;
}

get_window_framebuffer_size :: (window: *Window) -> width: u32, height: u32 {
    width, height := GLFW.get_framebuffer_size(window);

    return width, height;
}

get_key :: inline (window: *Window, key: Key) -> Key_State {
    return GLFW.get_key(window, key);
}



#scope_file

#import "Basic";
GLFW :: #import "GLFW";
VK   :: #import "Jai_Vulkan";
