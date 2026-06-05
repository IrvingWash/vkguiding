#scope_module

Allocated_Image :: struct {
    image:      VK.Image;
    view:       VK.Image_View;
    allocation: VMA.Allocation;
    extent:     VK.Extent_3D;
    format:     VK.Format;
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
