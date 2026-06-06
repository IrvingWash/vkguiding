#scope_module

Allocated_Image :: struct {
    image:      VK.Image;
    view:       VK.Image_View;
    allocation: VMA.Allocation;
    extent:     VK.Extent_3D;
    format:     VK.Format;
}

Pipeline_Builder :: struct {
    shader_stages:          [..]VK.Pipeline_Shader_Stage_Create_Info;
    input_assembly:         VK.Pipeline_Input_Assembly_State_Create_Info;
    rasterizer:             VK.Pipeline_Rasterization_State_Create_Info;
    color_blend_attachment: VK.Pipeline_Color_Blend_Attachment_State;
    multisampling:          VK.Pipeline_Multisample_State_Create_Info;
    depth_stencil:          VK.Pipeline_Depth_Stencil_State_Create_Info;
    rendering_info:         VK.Pipeline_Rendering_Create_Info;

    color_attachment_format: VK.Format;

    pipeline_layout: VK.Pipeline_Layout;

    build :: (builder: *Pipeline_Builder, device: VK.Device) -> VK.Pipeline {
        viewport_state: VK.Pipeline_Viewport_State_Create_Info = {
            viewport_count = 1,
            scissor_count  = 1,
        };

        color_blend_state: VK.Pipeline_Color_Blend_State_Create_Info = {
            logic_op_enable  = VK.FALSE,
            logic_op         = VK.Logic_Op.COPY,
            attachment_count = 1,
            p_attachments    = *builder.color_blend_attachment,
        };

        vertex_input_state_info: VK.Pipeline_Vertex_Input_State_Create_Info;

        dynamic_states := VK.Dynamic_State.[
            VK.Dynamic_State.VIEWPORT,
            VK.Dynamic_State.SCISSOR,
        ];
        dynamic_state_info: VK.Pipeline_Dynamic_State_Create_Info = {
            dynamic_state_count = dynamic_states.count,
            p_dynamic_states    = dynamic_states.data,
        };

        pipeline_info: VK.Graphics_Pipeline_Create_Info = {
            p_next                 = *builder.rendering_info,
            stage_count            = xx builder.shader_stages.count,
            p_stages               = builder.shader_stages.data,
            p_vertex_input_state   = *vertex_input_state_info,
            p_input_assembly_state = *builder.input_assembly,
            p_viewport_state       = *viewport_state,
            p_rasterization_state  = *builder.rasterizer,
            p_multisample_state    = *builder.multisampling,
            p_color_blend_state    = *color_blend_state,
            p_depth_stencil_state  = *builder.depth_stencil,
            p_dynamic_state        = *dynamic_state_info,
            layout                 = builder.pipeline_layout,
        };

        result, pipeline := VK.create_graphics_pipeline(
            device,
            null,
            *pipeline_info
        );
        assert_result(result, "Failed to create graphics pipeline");

        builder.destroy(builder);

        return pipeline;
    }

    disable_blending :: (builder: *Pipeline_Builder) -> *Pipeline_Builder {
        builder.color_blend_attachment.color_write_mask = VK.Color_Component_Flags.R
            | .G
            | .B
            | .A;

        builder.color_blend_attachment.blend_enable = VK.FALSE;

        return builder;
    }

    set_color_attachment_format :: (
        builder: *Pipeline_Builder,
        format: VK.Format,
    ) -> *Pipeline_Builder {
        builder.color_attachment_format                   = format;
        builder.rendering_info.color_attachment_count     = 1;
        builder.rendering_info.p_color_attachment_formats = *builder.color_attachment_format;

        return builder;
    }

    set_depth_format :: (
        builder: *Pipeline_Builder,
        format:  VK.Format,
    ) -> *Pipeline_Builder {
        builder.rendering_info.depth_attachment_format = format;

        return builder;
    }
    
    disable_depth_test :: (
        builder: *Pipeline_Builder,
    ) -> *Pipeline_Builder {
        builder.depth_stencil = VK.Pipeline_Depth_Stencil_State_Create_Info.{
            depth_test_enable        = VK.FALSE,
            depth_write_enable       = VK.FALSE,
            depth_compare_op         = VK.Compare_Op.NEVER,
            depth_bounds_test_enable = VK.FALSE,
            stencil_test_enable      = VK.FALSE,
            min_depth_bounds         = 0,
            max_depth_bounds         = 1,
        };

        return builder;
    }

    set_input_topology :: (
        builder: *Pipeline_Builder,
        topology: VK.Primitive_Topology,
    ) -> *Pipeline_Builder {
        builder.input_assembly.topology                 = topology;
        builder.input_assembly.primitive_restart_enable = VK.FALSE;

        return builder;
    }

    set_polygon_mode :: (
        builder: *Pipeline_Builder,
        mode: VK.Polygon_Mode,
    ) -> *Pipeline_Builder {
        builder.rasterizer.polygon_mode = mode;
        builder.rasterizer.line_width   = 1;

        return builder;
    }

    set_cull_mode :: (
        builder: *Pipeline_Builder,
        cull_mode: VK.Cull_Mode_Flags,
        front_face: VK.Front_Face,
    ) -> *Pipeline_Builder {
        builder.rasterizer.cull_mode  = cull_mode;
        builder.rasterizer.front_face = front_face;

        return builder;
    }

    set_multisampling_none :: (builder: *Pipeline_Builder) -> *Pipeline_Builder {
        builder.multisampling = VK.Pipeline_Multisample_State_Create_Info.{
            rasterization_samples = VK.Sample_Count_Flags._1,
        };

        return builder;
    }

    set_shaders :: (
        builder: *Pipeline_Builder,
        vertex_shader: VK.Shader_Module,
        fragment_shader: VK.Shader_Module,
    ) -> *Pipeline_Builder {
        array_add(
            *builder.shader_stages,
            VK.Pipeline_Shader_Stage_Create_Info.{
                stage = VK.Shader_Stage_Flags.VERTEX,
                module = vertex_shader,
                p_name = "main",
            },
            VK.Pipeline_Shader_Stage_Create_Info.{
                stage = VK.Shader_Stage_Flags.FRAGMENT,
                module = fragment_shader,
                p_name = "main",
            }
        );

        return builder;
    }

    destroy :: (builder: *Pipeline_Builder) {
        array_free(builder.shader_stages);
        builder.* = .{};
    }
}

assert_result :: (result: VK.Result, message: string) {
    assert(result == .SUCCESS, "%: %", message, result);
}

create_descriptor_set_layout :: (
    device:      VK.Device,
    bindings:    []VK.Descriptor_Set_Layout_Binding,
    flags:       VK.Descriptor_Set_Layout_Create_Flags,
) -> VK.Descriptor_Set_Layout {
    create_info := VK.Descriptor_Set_Layout_Create_Info.{
        flags         = flags,
        binding_count = xx bindings.count,
        p_bindings    = bindings.data,
    };

    result, set_layout := VK.create_descriptor_set_layout(device, *create_info);
    assert_result(result, "Failed to create descriptor_set_layout");

    return set_layout;
}

allocate_descriptor_set :: (
    device: VK.Device,
    pool:   VK.Descriptor_Pool,
    layout: VK.Descriptor_Set_Layout,
) -> VK.Descriptor_Set {
    allocate_info := VK.Descriptor_Set_Allocate_Info.{
        descriptor_pool      = pool,
        descriptor_set_count = 1,
        p_set_layouts        = *layout,
    };

    result, set := VK.allocate_descriptor_set(device, *allocate_info);
    assert_result(result, "Failed to allocate descriptor set");

    return set;
}

destroy_allocated_image :: (allocated_image: Allocated_Image) {
    VK.destroy_image_view(renderer.device, allocated_image.view);

    VMA.destroy_image(
        renderer.allocator,
        allocated_image.image,
        allocated_image.allocation,
    );
}

create_descriptor_pool :: (
    device:     VK.Device,
    pool_sizes: []VK.Descriptor_Pool_Size,
    max_sets:   u32,
) -> VK.Descriptor_Pool {
    create_info := VK.Descriptor_Pool_Create_Info.{
        max_sets        = max_sets,
        pool_size_count = xx pool_sizes.count,
        p_pool_sizes    = pool_sizes.data,
    };

    result, pool := VK.create_descriptor_pool(device, *create_info);
    assert_result(result, "Failed to create descriptor pool");

    return pool;
}



#scope_file

VK  :: #import "Jai_Vulkan";
VMA :: #import "Jai_Vulkan/VMA";
