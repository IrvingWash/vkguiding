#module_parameters()(
    Window_Type: Type,
    USE_VALIDATION_LAYERS := false
);

Create_Window_Surface_Proc     :: #type (instance: VK.Instance, window: Window_Type) -> VK.Result, VK.Surface_KHR;
Get_Instance_Window_Extensions :: #type () -> [..]*u8;
Get_Window_Framebuffer_Size    :: #type (window: Window_Type) -> width: u32, height: u32;

Renderer :: struct {
    frame_number: u64;

    window: Window_Type;

    instance:          VK.Instance;
    physical_device:   VK.Physical_Device;
    device:            VK.Device;
    surface:           VK.Surface_KHR;
    graphics_qf_index: u32;
    swapchain:         VK.Swapchain_KHR;

    swapchain_info:        VK.Swapchain_Create_Info_KHR;
    swapchain_images:      [..]VK.Image;
    swapchain_image_views: [..]VK.Image_View;

    get_window_framebuffer_size: Get_Window_Framebuffer_Size;
}

renderer: Renderer;

init :: (
    window:                         Window_Type,
    get_window_framebuffer_size:    Get_Window_Framebuffer_Size,
    create_window_surface:          Create_Window_Surface_Proc,
    get_instance_window_extensions: Get_Instance_Window_Extensions,
) {
    renderer.window = window;
    renderer.get_window_framebuffer_size = get_window_framebuffer_size;

    renderer.instance,
    renderer.surface,
    renderer.physical_device,
    renderer.device,
    renderer.graphics_qf_index = init_vulkan(
        create_window_surface,
        get_instance_window_extensions,
    );

    renderer.swapchain,
    renderer.swapchain_info,
    renderer.swapchain_images,
    renderer.swapchain_image_views = init_swapchain();

    init_commands();

    init_sync_structures();
}

deinit :: () {
    destroy_swapchain();

    VK.destroy_device(renderer.device);

    VK.destroy_surface_khr(renderer.instance, renderer.surface);

    VK.destroy_instance(renderer.instance);
}

draw :: () {}



#scope_file

VALIDATION_LAYERS :: *u8.[
    "VK_LAYER_KHRONOS_validation",
];

DEVICE_EXTENSIONS :: *u8.[
    VK.KHR_SWAPCHAIN_EXTENSION_NAME,
];

init_vulkan :: (
    create_window_surface: Create_Window_Surface_Proc,
    get_window_extensions: Get_Instance_Window_Extensions,
) -> VK.Instance,
    VK.Surface_KHR,
    VK.Physical_Device,
    VK.Device,
    graphics_qf_index: u32
{
    // =========================================================================
    // Instance
    // =========================================================================
    instance: VK.Instance = ---;
    {
        layers: [..]*u8;
        defer array_free(layers);
        {
            #if USE_VALIDATION_LAYERS {
                array_add(*layers, ..VALIDATION_LAYERS);
            }
        }

        extensions: [..]*u8;
        defer array_free(extensions);
        {
            window_extensions := get_window_extensions();
            defer array_free(window_extensions);
            array_add(*extensions, ..window_extensions);
        }

        applicatino_info := VK.Application_Info.{
            api_version = VK.make_version(1, 4, 0),
        };

        instance_info := VK.Instance_Create_Info.{
            p_application_info         = *applicatino_info,
            enabled_layer_count        = xx layers.count,
            pp_enabled_layer_names     = layers.data,
            enabled_extension_count    = xx extensions.count,
            pp_enabled_extension_names = extensions.data,
        };

        result:, instance = VK.create_instance(*instance_info);
        assert_result(result, "Failed to create instance");
    }

    // =========================================================================
    // Surface
    // =========================================================================
    surface: VK.Surface_KHR = ---;
    {
        result:, surface = create_window_surface(instance, renderer.window);
        assert_result(result, "Failed to create surface");
    }

    // =========================================================================
    // Physical device
    // =========================================================================
    physical_device:   VK.Physical_Device = ---;
    graphics_qf_index: u32                = ---;
    {
        result, all_physical_devices := VK.enumerate_physical_devices(instance);
        assert_result(result, "Failed to enumerate phyisical devices");
        defer array_free(all_physical_devices);

        found: bool;
        for contender: all_physical_devices {
            features_1_3: VK.Physical_Device_Vulkan_1_3_Features;
            features_1_2 := VK.Physical_Device_Vulkan_1_2_Features.{
                p_next = *features_1_3,
            };
            features := VK.Physical_Device_Features_2.{
                p_next = *features_1_2,
            };
            VK.get_physical_device_features_2(contender, *features);

            properties := VK.get_physical_device_properties(contender);

            is_graphics_supported: bool;
            {
                qfps := VK.get_physical_device_queue_family_properties(contender);
                defer array_free(qfps);
                for qfp: qfps {
                    result, is_surface_supported := VK.get_physical_device_surface_support_khr(
                        contender,
                        xx it_index,
                        surface,
                    );
                    assert_result(result, "Failed to get physical device surface support");

                    if (
                        (qfp.queue_flags & VK.Queue_Flags.GRAPHICS)
                        && is_surface_supported
                    ) {
                        is_graphics_supported = true;
                        graphics_qf_index     = xx it_index;
                        break;
                    }
                }
            }

            if (
                features_1_3.dynamic_rendering
                && features_1_3.synchronization2
                && features_1_2.buffer_device_address
                && features_1_2.descriptor_indexing
                && properties.device_type == VK.Physical_Device_Type.DISCRETE_GPU
                && properties.api_version >= VK.make_version(1, 4, 0)
                && is_graphics_supported
            ) {
                physical_device = contender;
                found = true;
                break;
            }
        }

        assert(found, "There's no suitable GPU");
    }

    // =========================================================================
    // Device
    // =========================================================================
    device: VK.Device = ---;
    {
        extensions: [..]*u8;
        defer array_free(extensions);
        {
            array_add(*extensions, ..DEVICE_EXTENSIONS);
        }

        features_1_3 := VK.Physical_Device_Vulkan_1_3_Features.{
            dynamic_rendering = VK.TRUE,
            synchronization2  = VK.TRUE,
        };
        features_1_2 := VK.Physical_Device_Vulkan_1_2_Features.{
            p_next                = *features_1_3,
            buffer_device_address = VK.TRUE,
            descriptor_indexing   = VK.TRUE,
        };
        features := VK.Physical_Device_Features_2.{
            p_next = *features_1_2,
        };

        queue_priorities := float.[0.5];
        device_queue_infos := VK.Device_Queue_Create_Info.[
            {
                queue_family_index = graphics_qf_index,
                queue_count        = xx queue_priorities.count,
                p_queue_priorities = queue_priorities.data,
            },
        ];

        device_info := VK.Device_Create_Info.{
            p_next                     = *features,
            queue_create_info_count    = xx device_queue_infos.count,
            p_queue_create_infos       = device_queue_infos.data,
            enabled_extension_count    = xx extensions.count,
            pp_enabled_extension_names = extensions.data,
        };

        result:, device = VK.create_device(physical_device, *device_info);
        assert_result(result, "Failed to create device");
    }

    return instance,
        surface,
        physical_device,
        device,
        graphics_qf_index;
}

init_swapchain :: () -> VK.Swapchain_KHR,
    VK.Swapchain_Create_Info_KHR,
    [..]VK.Image,
    [..]VK.Image_View
{
    swapchain:      VK.Swapchain_KHR             = ---;
    swapchain_info: VK.Swapchain_Create_Info_KHR = ---;
    {
        result, surface_capabilities := VK.get_physical_device_surface_capabilities_khr(
            renderer.physical_device,
            renderer.surface,
        );
        assert_result(result, "Failed to get surface capabilities");

        width, height := renderer.get_window_framebuffer_size(renderer.window);

        swapchain_info = VK.Swapchain_Create_Info_KHR.{
            surface         = renderer.surface,
            min_image_count = min(
                surface_capabilities.min_image_count + 1,
                surface_capabilities.max_image_count,
            ),
            image_format      = VK.Format.B8G8R8A8_SRGB,
            image_color_space = VK.Color_Space_KHR.SRGB_NONLINEAR_KHR,
            image_extent      = VK.Extent_2D.{
                width  = width,
                height = height,
            },
            image_array_layers = 1,
            image_usage        = VK.Image_Usage_Flags.COLOR_ATTACHMENT | .TRANSFER_DST,
            image_sharing_mode = VK.Sharing_Mode.EXCLUSIVE,
            pre_transform      = surface_capabilities.current_transform,
            composite_alpha    = VK.Composite_Alpha_Flags_KHR.OPAQUE_KHR,
            present_mode       = VK.Present_Mode_KHR.FIFO_KHR,
            clipped            = VK.TRUE,
            old_swapchain      = renderer.swapchain,
        };

        result =, swapchain = VK.create_swapchain_khr(
            renderer.device,
            *swapchain_info,
        );
        assert_result(result, "Failed to create swapchain");
    }

    result, images := VK.get_swapchain_images_khr(renderer.device, swapchain);
    assert_result(result, "Failed to get swapchain images");

    image_views: [..]VK.Image_View;
    {
        array_resize(*image_views, images.count);

        image_view_info := VK.Image_View_Create_Info.{
            view_type         = VK.Image_View_Type._2D,
            format            = swapchain_info.image_format,
            subresource_range = VK.Image_Subresource_Range.{
                aspect_mask      = VK.Image_Aspect_Flags.COLOR,
                base_mip_level   = 0,
                level_count      = 1,
                base_array_layer = 0,
                layer_count      = 1,
            },
        };

        for image: images {
            image_view_info.image = image;

            result, image_view := VK.create_image_view(
                renderer.device,
                *image_view_info,
            );
            assert_result(result, "Failed to create image view");

            image_views[it_index] = image_view;
        }
    }

    return swapchain, swapchain_info, images, image_views;
}

init_commands :: () {
    // @Todo
}

init_sync_structures :: () {
    // @Todo
}

destroy_swapchain :: () {
    for image_view: renderer.swapchain_image_views {
        VK.destroy_image_view(renderer.device, image_view);
    }
    array_free(renderer.swapchain_image_views);

    VK.destroy_swapchain_khr(renderer.device, renderer.swapchain);
}

assert_result :: (result: VK.Result, message: string) {
    assert(result == .SUCCESS, "%: %", message, result);
}

#import "Basic";
VK :: #import "Jai_Vulkan";
