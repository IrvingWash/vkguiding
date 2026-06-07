// =============================================================================
// Types
// =============================================================================

Allocator  :: *Allocator_T;
Allocation :: *Allocation_T;
Pool       :: *Pool_T;

PFN_Allocate_Device_Memory_Function :: #type (
    allocator:   Allocator,
    memory_type: u32,
    memory:      Device_Memory,
    size:        Device_Size,
    p_user_data: *void,
) -> void #c_call;


PFN_Free_Device_Memory_Function :: #type (
    allocator:   Allocator,
    memory_type: u32,
    memory:      Device_Memory,
    size:        Device_Size,
    p_user_data: *void,
) -> void #c_call;

// =============================================================================
// Structs
// =============================================================================

Allocation_Info :: struct {
    memory_type:   u32;
    device_memory: Device_Memory;
    offset:        Device_Size;
    size:          Device_Size;
    p_mapped_data: *void;
    p_user_data:   *void;
    p_name:        *u8;
}

Allocation_Create_Info :: struct {
    flags:            Allocation_Create_Flags;
    usage:            Memory_Usage;
    required_flags:   Memory_Property_Flags;
    preferred_flags:  Memory_Property_Flags;
    memory_type_bits: u32;
    pool:             Pool;
    p_user_data:      *void;
    priority:         float;
}

Device_Memory_Callbacks :: struct {
    pfn_allocate: PFN_Allocate_Device_Memory_Function;
    pfn_free:     PFN_Free_Device_Memory_Function;
    p_user_data:  *void;
}

Allocator_Create_Info :: struct {
    flags:                               Allocator_Create_Flags;
    physical_device:                     Physical_Device;
    device:                              Device;
    preferred_large_heap_block_size:     Device_Size;
    p_allocation_callbacks:              *Allocation_Callbacks;
    pDeviceMemoryCallbacks:              *Device_Memory_Callbacks;
    p_heap_size_limit:                   *Device_Size;
    p_vulkan_functions:                  *void; // @Todo: This is not an opaque struct. But it's huge and requires defining things not only here, but in Vulkan's bindings as well.
    instance:                            Instance;
    vulkan_api_version:                  u32;
    p_type_external_memory_handle_types: *External_Memory_Handle_Type_Flags_KHR;
}

// =============================================================================
// Enums
// =============================================================================

Memory_Usage :: enum u32 {
    UNKNOWN              :: 0;
    GPU_ONLY             :: 1;
    CPU_ONLY             :: 2;
    CPU_TO_GPU           :: 3;
    GPU_TO_CPU           :: 4;
    CPU_COPY             :: 5;
    GPU_LAZILY_ALLOCATED :: 6;
    AUTO                 :: 7;
    AUTO_PREFER_DEVICE   :: 8;
    AUTO_PREFER_HOST     :: 9;
    MAX_ENUM             :: 2147483647;
}

Allocation_Create_Flags :: enum_flags u32 {
    DEDICATED_MEMORY                   :: 1;
    NEVER_ALLOCATE                     :: 2;
    MAPPED                             :: 4;
    USER_DATA_COPY_STRING              :: 32;
    UPPER_ADDRESS                      :: 64;
    DONT_BIND                          :: 128;
    WITHIN_BUDGET                      :: 256;
    CAN_ALIAS                          :: 512;
    HOST_ACCESS_SEQUENTIAL_WRITE       :: 1024;
    HOST_ACCESS_RANDOM                 :: 2048;
    HOST_ACCESS_ALLOW_TRANSFER_INSTEAD :: 4096;
    STRATEGY_MIN_MEMORY                :: 65536;
    STRATEGY_MIN_TIME                  :: 131072;
    STRATEGY_MIN_OFFSET                :: 262144;
    STRATEGY_BEST_FIT                  :: 65536;
    STRATEGY_FIRST_FIT                 :: 131072;
    STRATEGY_MASK                      :: 458752;
    FLAG_BITS_MAX_ENUM                 :: 2147483647;
}

External_Memory_Handle_Type_Flags_KHR :: enum_flags u32 {
    OPAQUE_FD                       :: 1;
    OPAQUE_WIN32                    :: 2;
    OPAQUE_WIN32_KMT                :: 4;
    D3D11_TEXTURE                   :: 8;
    D3D11_TEXTURE_KMT               :: 16;
    D3D12_HEAP                      :: 32;
    D3D12_RESOURCE                  :: 64;
    DMA_BUF_EXT                     :: 512;
    ANDROID_HARDWARE_BUFFER_ANDROID :: 1024;
    HOST_ALLOCATION_EXT             :: 128;
    HOST_MAPPED_FOREIGN_MEMORY_EXT  :: 256;
    ZIRCON_VMO_FUCHSIA              :: 2048;
    RDMA_ADDRESS_NV                 :: 4096;
    OH_NATIVE_BUFFER_OHOS           :: 32768;
    SCREEN_BUFFER_QNX               :: 16384;
    MTLBUFFER_EXT                   :: 65536;
    MTLTEXTURE_EXT                  :: 131072;
    MTLHEAP_EXT                     :: 262144;
    OPAQUE_FD_KHR                   :: 1;
    OPAQUE_WIN32_KHR                :: 2;
    OPAQUE_WIN32_KMT_KHR            :: 4;
    D3D11_TEXTURE_KHR               :: 8;
    D3D11_TEXTURE_KMT_KHR           :: 16;
    D3D12_HEAP_KHR                  :: 32;
    D3D12_RESOURCE_KHR              :: 64;
    FLAG_BITS_MAX_ENUM              :: 2147483647;
}

Allocator_Create_Flags :: enum_flags u32 {
    EXTERNALLY_SYNCHRONIZED    :: 1;
    KHR_DEDICATED_ALLOCATION   :: 2;
    KHR_BIND_MEMORY2           :: 4;
    EXT_MEMORY_BUDGET          :: 8;
    AMD_DEVICE_COHERENT_MEMORY :: 16;
    BUFFER_DEVICE_ADDRESS      :: 32;
    EXT_MEMORY_PRIORITY        :: 64;
    KHR_MAINTENANCE4           :: 128;
    KHR_MAINTENANCE5           :: 256;
    KHR_EXTERNAL_MEMORY_WIN32  :: 512;
    FLAG_BITS_MAX_ENUM         :: 2147483647;
}

// =============================================================================
// Procedures
// =============================================================================

destroy_buffer :: (
    allocator:  Allocator,
    buffer:     Buffer,
    allocation: Allocation,
) -> void #foreign libvma "vmaDestroyBuffer";

create_buffer :: inline (
    allocator:                Allocator,
    p_buffer_create_info:     *Buffer_Create_Info,
    p_allocation_create_info: *Allocation_Create_Info,
) -> Result,
    Buffer,
    Allocation,
    Allocation_Info
{
    buffer:          Buffer;
    allocation:      Allocation;
    allocation_info: Allocation_Info;

    result := vmaCreateBuffer(
        allocator,
        p_buffer_create_info,
        p_allocation_create_info,
        *buffer,
        *allocation,
        *allocation_info,
    );

    return result, buffer, allocation, allocation_info;
}

destroy_image :: (
    allocator:  Allocator,
    image:      Image,
    allocation: Allocation,
) -> void #foreign libvma "vmaDestroyImage";

create_image :: inline (
    allocator:                Allocator,
    p_image_create_info:      *Image_Create_Info,
    p_allocation_create_info: *Allocation_Create_Info,
    p_allocation_info:        *Allocation_Info,
) -> Result, Image, Allocation {
    image:      Image      = ---;
    allocation: Allocation = ---;

    result := vmaCreateImage(
        allocator,
        p_image_create_info,
        p_allocation_create_info,
        *image,
        *allocation,
        p_allocation_info,
    );

    return result, image, allocation;
}

create_allocator :: inline (
    p_create_info: *Allocator_Create_Info,
) -> Result, Allocator {
    allocator: Allocator = ---;

    result := vmaCreateAllocator(p_create_info, *allocator);

    return result, allocator;
}

destroy_allocator :: (
    allocator: Allocator,
) -> void #foreign libvma "vmaDestroyAllocator";



#scope_file

#if OS == {
    case .LINUX;
        libvma :: #library "../linux/libvma";
    case;
        assert(false, "Unsupported OS: %", OS);
}

Allocator_T  :: struct {};
Allocation_T :: struct {};
Pool_T       :: struct {};

vmaCreateAllocator :: (
    p_create_info: *Allocator_Create_Info,
    p_allocator: *Allocator,
) -> Result #foreign libvma;

vmaCreateImage :: (
    allocator:                Allocator,
    p_image_create_info:      *Image_Create_Info,
    p_allocation_create_info: *Allocation_Create_Info,
    p_image:                  *Image,
    p_allocation:             *Allocation,
    p_allocation_info:        *Allocation_Info,
) -> Result #foreign libvma;

vmaCreateBuffer :: (
    allocator:                Allocator,
    p_buffer_create_info:     *Buffer_Create_Info,
    p_allocation_create_info: *Allocation_Create_Info,
    p_buffer:                 *Buffer,
    p_allocation:             *Allocation,
    p_allocation_info:        *Allocation_Info,
) -> Result #foreign libvma;

#import "Jai_Vulkan";
