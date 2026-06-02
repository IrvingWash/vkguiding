#scope_file

#import "Basic";
#import "Compiler";
#import "File";
#import "Bindings_Generator";
#import "String";

VULKAN_INCLUDE_PATH:: #run get_absolute_path("./vulkan-1.4.350.0/include");

#run {
    set_build_options_dc({ do_output = false });

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
