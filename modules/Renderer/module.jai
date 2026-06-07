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
    graphics_queue:    VK.Queue;
    swapchain:         VK.Swapchain_KHR;
    allocator:         VMA.Allocator;

    swapchain_info:        VK.Swapchain_Create_Info_KHR;
    swapchain_images:      [..]VK.Image;
    swapchain_image_views: [..]VK.Image_View;

    immediate_fence:          VK.Fence;
    immediate_command_buffer: VK.Command_Buffer;
    immediate_command_pool:   VK.Command_Pool;

    frame_data: [FRAME_OVERLAP]Frame_Data;

    draw_image: Allocated_Image;

    global_descriptor_pool: VK.Descriptor_Pool;

    draw_image_descriptor_set:        VK.Descriptor_Set;
    draw_image_descriptor_set_layout: VK.Descriptor_Set_Layout;

    background_effects:              [..]Compute_Effect;
    current_background_effect_index: int;

    triangle_pipeline:        VK.Pipeline;
    triangle_pipeline_layout: VK.Pipeline_Layout;

    mesh_pipeline:        VK.Pipeline;
    mesh_pipeline_layout: VK.Pipeline_Layout;

    default_rectangle_mesh: Gpu_Mesh_Buffers;

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
    
    renderer.graphics_queue = VK.get_device_queue(
        renderer.device,
        renderer.graphics_qf_index,
        0,
    );

    renderer.swapchain,
    renderer.swapchain_info,
    renderer.swapchain_images,
    renderer.swapchain_image_views = init_swapchain();

    init_commands();

    init_sync_structures();

    // VMA
    {
        allocator_info := VMA.Allocator_Create_Info.{
             flags           = VMA.Allocator_Create_Flags.BUFFER_DEVICE_ADDRESS,
             physical_device = renderer.physical_device,
             device          = renderer.device,
             instance        = renderer.instance,
        };

        result:, renderer.allocator = VMA.create_allocator(*allocator_info);
        assert_result("Failed to create allocator");
    }

    renderer.draw_image = init_draw_image();

    renderer.global_descriptor_pool,
    renderer.draw_image_descriptor_set_layout,
    renderer.draw_image_descriptor_set = init_descriptors();

    renderer.background_effects = init_background_pipelines();

    renderer.triangle_pipeline,
    renderer.triangle_pipeline_layout = init_triangle_pipeline();

    renderer.mesh_pipeline,
    renderer.mesh_pipeline_layout = init_mesh_pipeline();

    renderer.default_rectangle_mesh = init_default_data();
}

deinit :: () {
    VK.device_wait_idle(renderer.device);

    VMA.destroy_buffer(
        renderer.allocator,
        renderer.default_rectangle_mesh.vertex_buffer.buffer,
        renderer.default_rectangle_mesh.vertex_buffer.allocation,
    );
    VMA.destroy_buffer(
        renderer.allocator,
        renderer.default_rectangle_mesh.index_buffer.buffer,
        renderer.default_rectangle_mesh.index_buffer.allocation,
    );

    VK.destroy_pipeline_layout(renderer.device, renderer.mesh_pipeline_layout);
    VK.destroy_pipeline(renderer.device, renderer.mesh_pipeline);

    VK.destroy_pipeline_layout(renderer.device, renderer.triangle_pipeline_layout);
    VK.destroy_pipeline(renderer.device, renderer.triangle_pipeline);

    for be: renderer.background_effects {
        VK.destroy_pipeline_layout(renderer.device, be.layout);
        VK.destroy_pipeline(renderer.device, be.pipeline);
    }
    array_free(renderer.background_effects);

    VK.destroy_descriptor_pool(renderer.device, renderer.global_descriptor_pool);
    VK.destroy_descriptor_set_layout(renderer.device, renderer.draw_image_descriptor_set_layout);

    destroy_allocated_image(renderer.draw_image);

    VMA.destroy_allocator(renderer.allocator);

    VK.destroy_fence(renderer.device, renderer.immediate_fence);
    VK.destroy_command_pool(renderer.device, renderer.immediate_command_pool);

    for frame_datalet: renderer.frame_data {
        VK.destroy_semaphore(renderer.device, frame_datalet.swapchain_semaphore);
        VK.destroy_semaphore(renderer.device, frame_datalet.render_semaphore);
        VK.destroy_fence(renderer.device, frame_datalet.render_fence);
        VK.destroy_command_pool(renderer.device, frame_datalet.command_pool);
    }

    destroy_swapchain();

    VK.destroy_device(renderer.device);

    VK.destroy_surface_khr(renderer.instance, renderer.surface);

    VK.destroy_instance(renderer.instance);
}

set_background_effect :: (name: string) {
    for be: renderer.background_effects {
        if be.name == name {
            renderer.current_background_effect_index = it_index;
            return;
        }
    }

    assert(false, "Background effect '%' does not exist", name);
}

draw :: () {
    defer renderer.frame_number += 1;

    frame_datalet := get_current_frame_data();

    // Wait for fences and reset stuff
    {
        result := VK.wait_for_fence(
            renderer.device,
            frame_datalet.render_fence,
            SECOND_IN_NANO,
        );
        assert_result("Failed to wait for render fence");
        result = VK.reset_fence(
            renderer.device,
            frame_datalet.render_fence,
        );
        assert_result("Failed to reset render fence");
    }
    VK.reset_command_buffer(frame_datalet.command_buffer, 0);

    // Get next swapchain image index
    swapchain_image_index: u32 = ---;
    {
        result:, swapchain_image_index = VK.acquire_next_image_khr(
            renderer.device,
            renderer.swapchain,
            SECOND_IN_NANO,
            frame_datalet.swapchain_semaphore,
            null,
        );
    }

    // Begin command buffer
    {
        begin_info := VK.Command_Buffer_Begin_Info.{
            flags = VK.Command_Buffer_Usage_Flags.ONE_TIME_SUBMIT,
        };

        result := VK.begin_command_buffer(
            frame_datalet.command_buffer,
            *begin_info,
        );
        assert_result("Failed to begin command buffer");
    }

    // Transition draw image to be suitable for writing
    transition_image(
        frame_datalet.command_buffer,
        renderer.draw_image.image,
        VK.Image_Layout.UNDEFINED,
        VK.Image_Layout.GENERAL,
        VK.Image_Aspect_Flags.COLOR,
    );

    draw_background(frame_datalet.command_buffer);

    // Transition draw image to be suitable for graphics pipeline
    transition_image(
        frame_datalet.command_buffer,
        renderer.draw_image.image,
        VK.Image_Layout.GENERAL,
        VK.Image_Layout.COLOR_ATTACHMENT_OPTIMAL,
        VK.Image_Aspect_Flags.COLOR,
    );

    draw_geometry(frame_datalet.command_buffer);

    // Transition draw image and swapchain image to transfer layout
    transition_image(
        frame_datalet.command_buffer,
        renderer.draw_image.image,
        VK.Image_Layout.COLOR_ATTACHMENT_OPTIMAL,
        VK.Image_Layout.TRANSFER_SRC_OPTIMAL,
        VK.Image_Aspect_Flags.COLOR,
    );
    transition_image(
        frame_datalet.command_buffer,
        renderer.swapchain_images[swapchain_image_index],
        VK.Image_Layout.UNDEFINED,
        VK.Image_Layout.TRANSFER_DST_OPTIMAL,
        VK.Image_Aspect_Flags.COLOR,
    );

    // Copy from draw image to swapchain image
    copy_image_to_image(
        frame_datalet.command_buffer,
        renderer.draw_image.image,
        renderer.swapchain_images[swapchain_image_index],
        renderer.draw_image.extent._2D,
        renderer.swapchain_info.image_extent,
    );

    // Transition swapchain image to presentable layout
    transition_image(
        frame_datalet.command_buffer,
        renderer.swapchain_images[swapchain_image_index],
        VK.Image_Layout.TRANSFER_DST_OPTIMAL,
        VK.Image_Layout.PRESENT_SRC_KHR,
        VK.Image_Aspect_Flags.COLOR,
    );

    // End command buffer (it's unrecordable after this)
    {
        result := VK.end_command_buffer(frame_datalet.command_buffer);
        assert_result("Failed to end command buffer");
    }

    // Submitting
    {
        command_buffer_submit_info := VK.Command_Buffer_Submit_Info.{
            command_buffer = frame_datalet.command_buffer,
        };

        wait_submit_info := VK.Semaphore_Submit_Info.{
            semaphore  = frame_datalet.swapchain_semaphore,
            value      = 1,
            stage_mask = VK.Pipeline_Stage_Flags_2.COLOR_ATTACHMENT_OUTPUT_KHR,
        };
        signal_submit_info := VK.Semaphore_Submit_Info.{
            semaphore  = frame_datalet.render_semaphore,
            value      = 1,
            stage_mask = VK.Pipeline_Stage_Flags_2.ALL_GRAPHICS,
        };

        submit_info := VK.Submit_Info_2.{
            wait_semaphore_info_count   = 1,
            p_wait_semaphore_infos      = *wait_submit_info,
            command_buffer_info_count   = 1,
            p_command_buffer_infos      = *command_buffer_submit_info,
            signal_semaphore_info_count = 1,
            p_signal_semaphore_infos    = *signal_submit_info,
        };

        result := VK.queue_submit_2(
            renderer.graphics_queue,
            .[submit_info],
            frame_datalet.render_fence,
        );
        assert_result("Failed to submit queue");
    }

    // Presenting
    {
        present_info := VK.Present_Info_KHR.{
            wait_semaphore_count = 1,
            p_wait_semaphores    = *frame_datalet.render_semaphore,
            swapchain_count      = 1,
            p_swapchains         = *renderer.swapchain,
            p_image_indices      = *swapchain_image_index,
        };

        result := VK.queue_present_khr(renderer.graphics_queue, *present_info);
        assert_result("Failed to present queue");
    }
}



#scope_file

Compute_Effect :: struct {
    name: string;

    pipeline:    VK.Pipeline;
    layout: VK.Pipeline_Layout;

    data: Compute_Push_Constants;
}

Compute_Push_Constants :: struct {
    data_1: Vector4;
    data_2: Vector4;
    data_3: Vector4;
    data_4: Vector4;
}

Frame_Data :: struct {
    command_pool:   VK.Command_Pool;
    command_buffer: VK.Command_Buffer;

    // To be signaled by swapchain - to be waited by render queue
    swapchain_semaphore: VK.Semaphore;

    // To be signaled by render queue - to be waited by swapchain
    render_semaphore:    VK.Semaphore;

    render_fence:        VK.Fence;
}

SECOND_IN_NANO :: 1000000000;

FRAME_OVERLAP :: 3;

VALIDATION_LAYERS :: *u8.[
    "VK_LAYER_KHRONOS_validation",
];

DEVICE_EXTENSIONS :: *u8.[
    VK.KHR_SWAPCHAIN_EXTENSION_NAME,
];

init_default_data :: () -> Gpu_Mesh_Buffers {
    RECT_VERTICES :: Vertex.[
        {
            position = { 0.5, -0.5, 0 },
            color    = { 0, 0, 0, 1 },
        },
        {
            position = { 0.5, 0.5, 0 },
            color    = { 0.5, 0.5, 0.5, 1 },
        },
        {
            position = { -0.5, -0.5, 0 },
            color    = { 1, 0, 0, 1 },
        },
        {
            position = { -0.5, 0.5, 0 },
            color    = { 0, 1, 0, 1 },
        },
    ];

    RECT_INDICES :: u32.[
        0, 1, 2,
        2, 1, 3,
    ];

    return upload_mesh(
        renderer.device,
        renderer.allocator,
        renderer.immediate_command_buffer,
        renderer.immediate_fence,
        renderer.graphics_queue,
        RECT_INDICES,
        RECT_VERTICES,
    );
}

draw_geometry :: (command_buffer: VK.Command_Buffer) {
    color_attachment := VK.Rendering_Attachment_Info.{
        image_view   = renderer.draw_image.view,
        image_layout = VK.Image_Layout.COLOR_ATTACHMENT_OPTIMAL,
        load_op      = VK.Attachment_Load_Op.DONT_CARE,
        store_op     = VK.Attachment_Store_Op.STORE,
    };

    rendering_info := VK.Rendering_Info.{
        render_area = VK.Rect_2D.{
            offset = VK.Offset_2D.{},
            extent = renderer.draw_image.extent._2D,
        },
        layer_count = 1,
        color_attachment_count = 1,
        p_color_attachments    = *color_attachment,
    };

    VK.cmd_begin_rendering(command_buffer, *rendering_info);

    {
        VK.cmd_bind_pipeline(command_buffer, VK.Pipeline_Bind_Point.GRAPHICS, renderer.triangle_pipeline);

        VK.cmd_set_viewport(
            command_buffer,
            .[
                VK.Viewport.{
                    width     = cast(float, renderer.draw_image.extent.width),
                    height    = cast(float, renderer.draw_image.extent.height),
                    min_depth = 0,
                    max_depth = 1,
                },
            ],
        );

        VK.cmd_set_scissor(
            command_buffer,
            .[
                VK.Rect_2D.{
                    extent = renderer.draw_image.extent._2D,
                },
            ],
        );

        VK.cmd_draw(command_buffer, 3, 1, 0, 0);
    }

    {
        VK.cmd_bind_pipeline(command_buffer, VK.Pipeline_Bind_Point.GRAPHICS, renderer.mesh_pipeline);

        VK.cmd_set_viewport(
            command_buffer,
            .[
                VK.Viewport.{
                    width     = cast(float, renderer.draw_image.extent.width),
                    height    = cast(float, renderer.draw_image.extent.height),
                    min_depth = 0,
                    max_depth = 1,
                },
            ],
        );

        VK.cmd_set_scissor(
            command_buffer,
            .[
                VK.Rect_2D.{
                    extent = renderer.draw_image.extent._2D,
                },
            ],
        );

        push_constants: Gpu_Draw_Push_Constants = {
            world_matrix          = Matrix4_Identity,
            vertex_buffer_address = renderer.default_rectangle_mesh.vertex_buffer_address,
        };

        VK.cmd_push_constants(
            command_buffer,
            renderer.mesh_pipeline_layout,
            VK.Shader_Stage_Flags.VERTEX,
            0,
            size_of(Gpu_Draw_Push_Constants),
            *push_constants
        );

        VK.cmd_bind_index_buffer(
            command_buffer,
            renderer.default_rectangle_mesh.index_buffer.buffer,
            0,
            VK.Index_Type.UINT32,
        );

        VK.cmd_draw_indexed(command_buffer, 6, 1, 0, 0, 0);
    }

    VK.cmd_end_rendering(command_buffer);
}

init_mesh_pipeline :: () -> VK.Pipeline, VK.Pipeline_Layout {
    vertex_shader   := create_shader_module("colored_triangle_mesh.vert.spv");
    fragment_shader := create_shader_module("colored_triangle.frag.spv");
    defer VK.destroy_shader_module(renderer.device, vertex_shader);
    defer VK.destroy_shader_module(renderer.device, fragment_shader);

    pipeline_layout: VK.Pipeline_Layout;
    {
        push_constant_range: VK.Push_Constant_Range = {
            stage_flags = VK.Shader_Stage_Flags.VERTEX,
            size = size_of(Gpu_Draw_Push_Constants),
        };

        pipeline_layout_info: VK.Pipeline_Layout_Create_Info = {
            push_constant_range_count = 1,
            p_push_constant_ranges    = *push_constant_range,
        };

        result:, pipeline_layout = VK.create_pipeline_layout(
            renderer.device,
            *pipeline_layout_info,
        );
        assert_result("Failed to create pipeline layout");
    }

    builder: Pipeline_Builder = {
        pipeline_layout = pipeline_layout,
    };

    builder.set_shaders(*builder, vertex_shader, fragment_shader);
    builder.set_input_topology(*builder, VK.Primitive_Topology.TRIANGLE_LIST);
    builder.set_polygon_mode(*builder, VK.Polygon_Mode.FILL);
    builder.set_cull_mode(*builder, VK.Cull_Mode_Flags.NONE, VK.Front_Face.CLOCKWISE);
    builder.set_multisampling_none(*builder);
    builder.disable_blending(*builder);
    builder.disable_depth_test(*builder);
    builder.set_color_attachment_format(*builder, renderer.draw_image.format);
    builder.set_depth_format(*builder, VK.Format.UNDEFINED);
    pipeline := builder.build(*builder, renderer.device);

    return pipeline, pipeline_layout;
}

init_triangle_pipeline :: () -> VK.Pipeline, VK.Pipeline_Layout {
    vertex_shader   := create_shader_module("colored_triangle.vert.spv");
    fragment_shader := create_shader_module("colored_triangle.frag.spv");
    defer VK.destroy_shader_module(renderer.device, vertex_shader);
    defer VK.destroy_shader_module(renderer.device, fragment_shader);

    pipeline_layout: VK.Pipeline_Layout;
    {
        pipeline_layout_info: VK.Pipeline_Layout_Create_Info;
        result:, pipeline_layout = VK.create_pipeline_layout(
            renderer.device,
            *pipeline_layout_info,
        );
        assert_result("Failed to create pipeline layout");
    }

    builder: Pipeline_Builder = {
        pipeline_layout = pipeline_layout,
    };

    builder.set_shaders(*builder, vertex_shader, fragment_shader);
    builder.set_input_topology(*builder, VK.Primitive_Topology.TRIANGLE_LIST);
    builder.set_polygon_mode(*builder, VK.Polygon_Mode.FILL);
    builder.set_cull_mode(*builder, VK.Cull_Mode_Flags.NONE, VK.Front_Face.CLOCKWISE);
    builder.set_multisampling_none(*builder);
    builder.disable_blending(*builder);
    builder.disable_depth_test(*builder);
    builder.set_color_attachment_format(*builder, renderer.draw_image.format);
    builder.set_depth_format(*builder, VK.Format.UNDEFINED);
    pipeline := builder.build(*builder, renderer.device);

    return pipeline, pipeline_layout;
}

init_background_pipelines :: () -> [..]Compute_Effect {
    effects: [..]Compute_Effect;

    // Gradient
    {
        push_constant: VK.Push_Constant_Range = {
            stage_flags = VK.Shader_Stage_Flags.COMPUTE,
            offset      = 0,
            size        = size_of(Compute_Push_Constants),
        };

        layout_info: VK.Pipeline_Layout_Create_Info = {
            set_layout_count          = 1,
            p_set_layouts             = *renderer.draw_image_descriptor_set_layout,
            push_constant_range_count = 1,
            p_push_constant_ranges    = *push_constant,
        };

        result, layout := VK.create_pipeline_layout(
            renderer.device,
            *layout_info,
        );
        assert_result("Failed to create pipeline layout");

        gradient_shader := create_shader_module("gradient_color.spv");
        defer VK.destroy_shader_module(renderer.device, gradient_shader);

        shader_stage_info: VK.Pipeline_Shader_Stage_Create_Info = {
            stage  = VK.Shader_Stage_Flags.COMPUTE,
            module = gradient_shader,
            p_name = "main",
        };

        pipeline_info: VK.Compute_Pipeline_Create_Info = {
            layout = layout,
            stage  = shader_stage_info,
        };

        result =, pipeline := VK.create_compute_pipeline(
            renderer.device,
            null,
            *pipeline_info
        );
        assert_result("Failed to create pipeline");

        array_add(
            *effects,
            Compute_Effect.{
                name     = "gradient",
                pipeline = pipeline,
                layout   = layout,
                data     = Compute_Push_Constants.{
                    data_1 = { 1, 0, 0, 1 },
                    data_2 = { 0, 0, 1, 1 },
                },
            },
        );
    }

    // Sky
    {
        push_constant: VK.Push_Constant_Range = {
            stage_flags = VK.Shader_Stage_Flags.COMPUTE,
            offset      = 0,
            size        = size_of(Compute_Push_Constants),
        };

        layout_info: VK.Pipeline_Layout_Create_Info = {
            set_layout_count          = 1,
            p_set_layouts             = *renderer.draw_image_descriptor_set_layout,
            push_constant_range_count = 1,
            p_push_constant_ranges    = *push_constant,
        };

        result, layout := VK.create_pipeline_layout(
            renderer.device,
            *layout_info,
        );
        assert_result("Failed to create pipeline layout");

        sky_shader := create_shader_module("sky.spv");
        defer VK.destroy_shader_module(renderer.device, sky_shader);

        shader_stage_info: VK.Pipeline_Shader_Stage_Create_Info = {
            stage  = VK.Shader_Stage_Flags.COMPUTE,
            module = sky_shader,
            p_name = "main",
        };

        pipeline_info: VK.Compute_Pipeline_Create_Info = {
            layout = layout,
            stage  = shader_stage_info,
        };

        result =, pipeline := VK.create_compute_pipeline(
            renderer.device,
            null,
            *pipeline_info
        );
        assert_result("Failed to create pipeline");

        array_add(
            *effects,
            Compute_Effect.{
                name = "sky",
                pipeline = pipeline,
                layout = layout,
                data = {
                    data_1 = { 0.1, 0.2, 0.4, 0.97 },
                },
            },
        );
    }

    return effects;
};

create_shader_module :: (name: string) -> VK.Shader_Module {
    File   :: #import "File";
    System :: #import "System";
    String :: #import "String";

    path := tprint(
        "%/shaders/%",
        String.path_strip_filename(System.get_path_of_running_executable()),
        name,
    );

    content, ok := File.read_entire_file(path);
    assert(ok, "Failed to read shader at '%'", path);
    defer free(content);

    shader_module_info := VK.Shader_Module_Create_Info.{
        code_size = xx (content.count * size_of(u8)),
        p_code    = cast(*u32, content.data),
    };

    result, module := VK.create_shader_module(renderer.device, *shader_module_info);
    assert_result("Failed to create shader module");

    return module;
};

init_descriptors :: () -> VK.Descriptor_Pool,
    VK.Descriptor_Set_Layout,
    VK.Descriptor_Set
{
    global_pool := create_descriptor_pool(
        renderer.device,
        .[
            VK.Descriptor_Pool_Size.{
                type             = VK.Descriptor_Type.STORAGE_IMAGE,
                descriptor_count = 10,
            },
        ],
        max_sets = 10,
    );

    draw_image_descriptor_set_layout := create_descriptor_set_layout(
        renderer.device,
        .[
            VK.Descriptor_Set_Layout_Binding.{
                binding          = 0,
                descriptor_count = 1,
                descriptor_type  = VK.Descriptor_Type.STORAGE_IMAGE,
                stage_flags      = VK.Shader_Stage_Flags.COMPUTE,
            },
        ],
        0,
    );

    draw_image_descriptor_set := allocate_descriptor_set(
        renderer.device,
        global_pool,
        draw_image_descriptor_set_layout,
    );

    // Write data into the descriptor_set
    {
        descriptor_image_info := VK.Descriptor_Image_Info.{
            image_view   = renderer.draw_image.view,
            image_layout = VK.Image_Layout.GENERAL,
        };

        image_write := VK.Write_Descriptor_Set.{
            dst_set          = draw_image_descriptor_set,
            dst_binding      = 0,
            descriptor_count = 1,
            descriptor_type  = VK.Descriptor_Type.STORAGE_IMAGE,
            p_image_info     = *descriptor_image_info,
        };

        VK.update_descriptor_sets(
            renderer.device,
            .[image_write],
            .[],
        );
    }

    return global_pool,
        draw_image_descriptor_set_layout,
        draw_image_descriptor_set;
}

draw_background :: (command_buffer: VK.Command_Buffer) {
    // clear_color_value: VK.Clear_Color_Value;
    // clear_color_value._float32 = float.[0, 0, 0.1, 1];
    //
    // clear_range := VK.Image_Subresource_Range.{
    //     aspect_mask      = VK.Image_Aspect_Flags.COLOR,
    //     base_mip_level   = 0,
    //     level_count      = 1,
    //     base_array_layer = 0,
    //     layer_count      = 1,
    // };
    //
    // VK.cmd_clear_color_image(
    //     command_buffer,
    //     renderer.draw_image.image,
    //     VK.Image_Layout.GENERAL,
    //     *clear_color_value,
    //     .[clear_range],
    // );

    background_effect := renderer.background_effects[renderer.current_background_effect_index];

    VK.cmd_bind_pipeline(
        command_buffer,
        VK.Pipeline_Bind_Point.COMPUTE,
        background_effect.pipeline,
    );

    VK.cmd_bind_descriptor_sets(
        command_buffer,
        VK.Pipeline_Bind_Point.COMPUTE,
        background_effect.layout,
        0,
        .[renderer.draw_image_descriptor_set],
        .[],
    );

    VK.cmd_push_constants(
        command_buffer,
        background_effect.layout,
        VK.Shader_Stage_Flags.COMPUTE,
        0,
        size_of(type_of(background_effect.data)),
        *background_effect.data,
    );

    VK.cmd_dispatch(
        command_buffer,
        xx ceil(renderer.draw_image.extent.width / 16.0),
        xx ceil(renderer.draw_image.extent.height / 16.0),
        1,
    );
}

copy_image_to_image :: (
    command_buffer: VK.Command_Buffer,
    src_image:      VK.Image,
    dst_image:      VK.Image,
    src_size:       VK.Extent_2D,
    dst_size:       VK.Extent_2D,
) {
    blit_region := VK.Image_Blit_2.{
        src_subresource = VK.Image_Subresource_Layers.{
            aspect_mask      = VK.Image_Aspect_Flags.COLOR,
            mip_level        = 0,
            base_array_layer = 0,
            layer_count      = 1,
        },
        src_offsets[1] = VK.Offset_3D.{
            x = xx src_size.width,
            y = xx src_size.height,
            z = 1,
        },
        dst_subresource = VK.Image_Subresource_Layers.{
            aspect_mask      = VK.Image_Aspect_Flags.COLOR,
            mip_level        = 0,
            base_array_layer = 0,
            layer_count      = 1,
        },
        dst_offsets[1] = VK.Offset_3D.{
            x = xx dst_size.width,
            y = xx dst_size.height,
            z = 1,
        },
    };

    blit_info := VK.Blit_Image_Info_2.{
        src_image        = src_image,
        src_image_layout = VK.Image_Layout.TRANSFER_SRC_OPTIMAL,
        dst_image        = dst_image,
        dst_image_layout = VK.Image_Layout.TRANSFER_DST_OPTIMAL,
        region_count     = 1,
        p_regions        = *blit_region,
        filter           = VK.Filter.LINEAR,
    };

    VK.cmd_blit_image_2(command_buffer, *blit_info);
}

init_draw_image :: () -> Allocated_Image {
    allocated_image := Allocated_Image.{
        format = VK.Format.R16G16B16A16_SFLOAT,
        extent = VK.Extent_3D.{
            width  = renderer.swapchain_info.image_extent.width,
            height = renderer.swapchain_info.image_extent.height,
            depth  = 1,
        },
    };

    // Image and allocation
    {
        image_create_info := VK.Image_Create_Info.{
            image_type   = VK.Image_Type._2D,
            format       = allocated_image.format,
            extent       = allocated_image.extent,
            mip_levels   = 1,
            array_layers = 1,
            samples      = VK.Sample_Count_Flags._1,
            tiling       = VK.Image_Tiling.OPTIMAL,
            usage        = VK.Image_Usage_Flags.TRANSFER_SRC | .TRANSFER_DST | .STORAGE | .COLOR_ATTACHMENT,
        };

        image_allocation_create_info := VMA.Allocation_Create_Info.{
            usage          = VMA.Memory_Usage.GPU_ONLY,
            required_flags = VK.Memory_Property_Flags.DEVICE_LOCAL,
        };

        result:, allocated_image.image, allocated_image.allocation = VMA.create_image(
            renderer.allocator,
            *image_create_info,
            *image_allocation_create_info,
            null,
        );
        assert_result("Failed to create image");
    }

    // Image View
    {
        image_view_create_info := VK.Image_View_Create_Info.{
            view_type         = VK.Image_View_Type._2D,
            format            = allocated_image.format,
            image             = allocated_image.image,
            subresource_range = VK.Image_Subresource_Range.{
                aspect_mask      = VK.Image_Aspect_Flags.COLOR,
                base_mip_level   = 0,
                level_count      = 1,
                base_array_layer = 0,
                layer_count      = 1,
            },
        };

        result:, allocated_image.view = VK.create_image_view(renderer.device, *image_view_create_info);
        assert_result("Failed to create image view");
    }

    return allocated_image;
}

transition_image :: (
    cmd:            VK.Command_Buffer,
    image:          VK.Image,
    current_layout: VK.Image_Layout,
    new_layout:     VK.Image_Layout,
    aspect_mask:    VK.Image_Aspect_Flags,
) {
    barriers := VK.Image_Memory_Barrier_2.[
        {
            src_stage_mask    = VK.Pipeline_Stage_Flags_2.ALL_COMMANDS,
            src_access_mask   = VK.Access_Flags_2.MEMORY_WRITE,
            dst_stage_mask    = VK.Pipeline_Stage_Flags_2.ALL_COMMANDS,
            dst_access_mask   = VK.Access_Flags_2.MEMORY_WRITE
                | .MEMORY_READ,
            old_layout        = current_layout,
            new_layout        = new_layout,
            image             = image,
            subresource_range = VK.Image_Subresource_Range.{
                aspect_mask      = aspect_mask,
                base_mip_level   = 0,
                level_count      = 1,
                base_array_layer = 0,
                layer_count      = 1,
            },
        }
    ];

    dependency_info := VK.Dependency_Info.{
        image_memory_barrier_count = xx barriers.count,
        p_image_memory_barriers    = barriers.data,
    };

    VK.cmd_pipeline_barrier_2(cmd, *dependency_info);
}

get_current_frame_data :: () -> Frame_Data {
    return renderer.frame_data[renderer.frame_number % FRAME_OVERLAP];
}

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
        assert_result("Failed to create instance");
    }

    // =========================================================================
    // Surface
    // =========================================================================
    surface: VK.Surface_KHR = ---;
    {
        result:, surface = create_window_surface(instance, renderer.window);
        assert_result("Failed to create surface");
    }

    // =========================================================================
    // Physical device
    // =========================================================================
    physical_device:   VK.Physical_Device = ---;
    graphics_qf_index: u32                = ---;
    {
        result, all_physical_devices := VK.enumerate_physical_devices(instance);
        assert_result("Failed to enumerate phyisical devices");
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
                    assert_result("Failed to get physical device surface support");

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
        assert_result("Failed to create device");
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
        assert_result("Failed to get surface capabilities");

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
        assert_result("Failed to create swapchain");
    }

    result, images := VK.get_swapchain_images_khr(renderer.device, swapchain);
    assert_result("Failed to get swapchain images");

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
            assert_result("Failed to create image view");

            image_views[it_index] = image_view;
        }
    }

    return swapchain, swapchain_info, images, image_views;
}

init_commands :: () {
    command_pool_info := VK.Command_Pool_Create_Info.{
        flags              = VK.Command_Pool_Create_Flags.RESET_COMMAND_BUFFER,
        queue_family_index = renderer.graphics_qf_index,
    };

    command_buffer_info := VK.Command_Buffer_Allocate_Info.{
        level                = VK.Command_Buffer_Level.PRIMARY,
        command_buffer_count = 1,
    };

    // Main commands, per image
    for *frame_datalet: renderer.frame_data {
        result, command_pool := VK.create_command_pool(
            renderer.device,
            *command_pool_info,
        );
        assert_result("Failed to create command pool");

        command_buffer_info.command_pool = command_pool;

        result =, command_buffer := VK.allocate_command_buffer(
            renderer.device,
            *command_buffer_info,
        );
        assert_result("Failed to allocate command boofer");

        frame_datalet.command_pool   = command_pool;
        frame_datalet.command_buffer = command_buffer;
    }

    // Immediate commands
    result:, renderer.immediate_command_pool = VK.create_command_pool(renderer.device, *command_pool_info);
    assert_result("Failed to create immediate command pool");

    command_buffer_info.command_pool = renderer.immediate_command_pool;

    result, renderer.immediate_command_buffer = VK.allocate_command_buffer(renderer.device, *command_buffer_info);
    assert_result("Failed to create immediate command buffer");
}

init_sync_structures :: () {
    semaphore_info: VK.Semaphore_Create_Info;
    fence_info := VK.Fence_Create_Info.{
        flags = VK.Fence_Create_Flags.SIGNALED,
    };

    // Main fences and semaphores, per image
    for *frame_datalet: renderer.frame_data {
        result, render_fence := VK.create_fence(renderer.device, *fence_info);
        assert_result("Failed to create fence");

        result =, swapchain_semaphore := VK.create_semaphore(renderer.device, *semaphore_info);
        assert_result("Failed to create semaphore");
        result =, render_semaphore := VK.create_semaphore(renderer.device, *semaphore_info);
        assert_result("Failed to create semaphore");

        frame_datalet.render_fence        = render_fence;
        frame_datalet.render_semaphore    = render_semaphore;
        frame_datalet.swapchain_semaphore = swapchain_semaphore;
    }

    // Immediate fence
    result:, renderer.immediate_fence = VK.create_fence(renderer.device, *fence_info);
    assert_result("Failed to create immediate fence");
}

destroy_swapchain :: () {
    for image_view: renderer.swapchain_image_views {
        VK.destroy_image_view(renderer.device, image_view);
    }
    array_free(renderer.swapchain_image_views);

    array_free(renderer.swapchain_images);

    VK.destroy_swapchain_khr(renderer.device, renderer.swapchain);
}

#import "Basic";
#import "Math";
VK  :: #import "Jai_Vulkan";
VMA :: #import "Jai_Vulkan/VMA";

#load "utils.jai";
