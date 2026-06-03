#scope_file

#import "Basic";
#import "Compiler";
#import "File";
#import "Bindings_Generator";
#import "String";
#import "BuildCpp";

VULKAN_INCLUDE_PATH :: #run get_absolute_path("./vulkan-1.4.350.0/include");
VMA_PATH            :: #run get_absolute_path("./vulkan-1.4.350.0/include/vma/vk_mem_alloc.h");

#run {
    set_build_options_dc({ do_output = false });

    ok := build_vma();
    if !ok {
        print("Failed to build vma", to_standard_error = true);

        compiler_set_workspace_status(.FAILED);
    }

    error := generate();
    if error {
        print(
            "Failed to generate bidings: %\n",
            error,
            to_standard_error = true,
        );

        compiler_set_workspace_status(.FAILED);
    }
}

build_vma :: () -> bool {
    make_directory_if_it_does_not_exist("./linux");

    return build_cpp_dynamic_lib(
        "linux/libvma",
        VMA_PATH,
        extra = .[
            "-I",
            VULKAN_INCLUDE_PATH,
            "-DVMA_IMPLEMENTATION",
            "-x",
            "c++",
            "-std=c++17",
            "-lstdc++",
            "-L./linux",
            "-lvulkan",
            "-fno-exceptions",
            "-fno-rtti",
        ],
    );
}

generate :: () -> error: string {
    options: Generate_Bindings_Options;
    output_filename: string;
    {
        #if OS == {
            case .LINUX;
                array_add(
                    *options.libraries,
                    {
                        filename   = "./linux/libvulkan.so",
                        identifier = "libvulkan",
                    },
                    {
                        filename   = "./linux/libvma.so",
                        identifier = "libvma",
                    },
                );

                output_filename = "linux.jai";
            case .WINDOWS;
                array_add(
                    *options.libraries,
                    {
                        filename   = "./windows/vulkan-1.dll",
                        identifier = "libvulkan",
                    },
                );

                output_filename = "windows.jai";
            case;
                return "Unsupported OS";
        }

        array_add(
            *options.source_files,
            tprint("%/%", VULKAN_INCLUDE_PATH, "vulkan/vulkan.h"),
            tprint("%/%", VULKAN_INCLUDE_PATH, "vma/vk_mem_alloc.h"),
        );


        array_add(
            *options.include_paths,
            VULKAN_INCLUDE_PATH,
        );

        options.generate_library_declarations = true;

        options.visitor = visit;

        options.generate_compile_time_struct_checks = false;
    }

    ok := generate_bindings(options, output_filename);

    return ifx ok
        then ""
        else "Generation failed. Hopefully there is more information up above";
}

visit :: (declaration: *Declaration, parent_declaration: *Declaration) -> Declaration_Visit_Result {
    // Omit header definitions (ex: VULKAN_H_)
    if declaration.kind == .MACRO_DEFINITION && ends_with(declaration.name, "_H_") {
        declaration.decl_flags |= .OMIT_FROM_OUTPUT;
        return .STOP;
    }

    return .RECURSE;
}
