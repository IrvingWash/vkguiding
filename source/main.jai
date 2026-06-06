#placeholder DEBUG;

#import "Basic"()(
    MEMORY_DEBUGGER                 = DEBUG,
    TEMP_ALLOCATOR_OVERWRITE_MEMORY = DEBUG,
    ENABLE_ASSERT                   = DEBUG,
);

Win :: #import "Window";

R :: #import "Renderer"()(
    Window_Type           = *Win.Window,
    USE_VALIDATION_LAYERS = DEBUG,
);

main :: () {
    setup_formatting();

    #if DEBUG {
        defer report_memory_leaks();
    }

    window := Win.create_window(800, 600, "VkGuiding");
    defer Win.destroy_window(window);

    R.init(
        window,
        Win.get_window_framebuffer_size,
        Win.create_window_surface,
        Win.get_window_required_instance_extensions,
    );
    defer R.deinit();

    while !Win.should_window_close(window) {
        Win.poll_window_events();

        if Win.get_key(window, .ONE) == .PRESS {
            R.set_background_effect("gradient");
        }
        if Win.get_key(window, .TWO) == .PRESS {
            R.set_background_effect("sky");
        }

        R.draw();

        reset_temporary_storage();
    }
}

setup_formatting :: () {
    print_style := *context.print_style;

    print_style.default_format_struct.draw_type_name = true;
    print_style.default_format_struct.use_long_form_if_more_than_this_many_members = 0;
    print_style.default_format_struct.use_newlines_if_long_form = true;
}
