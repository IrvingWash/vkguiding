#import "Basic";
#import "File";
#import "BuildCpp";
#import "Compiler";
#import "Bindings_Generator";

USE_VULKAN_BACKEND :: true;
USE_GLFW_BACKEND   :: true;

IMGUI_PATH  :: #run tprint("%imgui", #filepath);
#if USE_VULKAN_BACKEND {
    VULKAN_PATH :: #run tprint("%vulkan-1.4.350.0", #filepath);
}

#run {
    set_build_options_dc({ do_output = false });

    build();
    generate();
}

generate :: () {
    output_filename: string;
    options: Generate_Bindings_Options;
    {
        using options;

        #if OS == {
            case .LINUX;
            array_add(*library_search_paths, "linux");
            output_filename = "linux.jai";
            generate_library_declarations = true;
        }

        #if USE_VULKAN_BACKEND {
            array_add(
                *include_paths,
                tprint("%/include", VULKAN_PATH),
            );
        }

        array_add(*libraries,     .{filename="ImGui"});
        array_add(*include_paths, IMGUI_PATH);
        array_add(*source_files,
            tprint("%/imgui.h", IMGUI_PATH),
            tprint("%/backends/imgui_impl_glfw.h", IMGUI_PATH),
            tprint("%/backends/imgui_impl_vulkan.h", IMGUI_PATH),
        );
        array_add(*extra_clang_arguments, "-x", "c++", "-DWIN32_LEAN_AND_MEAN");
        array_add(*flatten_namespaces, "ImGui");
        array_add(*strip_prefixes, "ImGui");
        auto_detect_enum_prefixes = false;
        log_stripped_declarations = false;
        generate_compile_time_struct_checks = false;
    }

    ok := generate_bindings(options, output_filename);
    assert(ok, "Failed to generate bidings");
}

build :: () {
    imgui_sources: [..]string;

    array_add(
        *imgui_sources,
        tprint("%/imgui.cpp",                      IMGUI_PATH),
        tprint("%/imgui_widgets.cpp",              IMGUI_PATH),
        tprint("%/imgui_draw.cpp",                 IMGUI_PATH),
        tprint("%/imgui_tables.cpp",               IMGUI_PATH),
    );
    #if USE_VULKAN_BACKEND {
        array_add(
            *imgui_sources,
            tprint("%/backends/imgui_impl_vulkan.cpp", IMGUI_PATH),
        );
    }
    #if USE_GLFW_BACKEND {
        array_add(
            *imgui_sources,
            tprint("%/backends/imgui_impl_glfw.cpp",   IMGUI_PATH),
        );
    }

    success: bool;
    #if OS == {
        case .LINUX;
            make_directory_if_it_does_not_exist(tprint("%linux", #filepath));

            extra_flags: [..]string;
            array_add(
                *extra_flags,
                tprint("-I%", IMGUI_PATH),
            );

            linker_flags: [..]string;
            #if USE_VULKAN_BACKEND || USE_GLFW_BACKEND {
                array_add(
                    *extra_flags,
                    tprint("-I%/backends", IMGUI_PATH),
                );
            }
            #if USE_VULKAN_BACKEND {
                array_add(
                    *extra_flags,
                    tprint("-I%/include", VULKAN_PATH),
                );
            }
            #if USE_GLFW_BACKEND {
                array_add(
                    *extra_flags,
                    "-lglfw"
                );
            }

            success = build_cpp_dynamic_lib(
                "linux/ImGui",
                ..imgui_sources,
                extra = extra_flags,
            );
        case;
            print("Unsupported OS: '%'", OS, to_standard_error = true);
            exit(1);
    }

    if !success {
        print("Failed to build", to_standard_error = true);
        exit(1);
    }
}
