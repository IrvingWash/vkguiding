#scope_module

Allocated_Image :: struct {
    image:      VK.Image;
    view:       VK.Image_View;
    allocation: VMA.Allocation;
    extent:     VK.Extent_3D;
    format:     VK.Format;
}

destroy_allocated_image :: (allocated_image: Allocated_Image) {
    VK.destroy_image_view(renderer.device, allocated_image.view);

    VMA.destroy_image(renderer.allocator, allocated_image.image, allocated_image.allocation);
}



#scope_file

VK  :: #import "Jai_Vulkan";
VMA :: #import "Jai_Vulkan/VMA";
