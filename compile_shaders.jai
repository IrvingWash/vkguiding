compile_shaders :: (output_path_root: string) -> error: string #compile_time {
    output_path := sprint("%/%", output_path_root, COMPILED_SHADERS_ROOT);

    ok := make_directory_if_it_does_not_exist(output_path, recursive = true);
    if !ok {
        return sprint("Failed to create directory at %", output_path);
    }

    for map: SHADER_PATH_MAPS {
        result, output, error := run_command(
            "glslc",
            map.source_path,
            "-o",
            sprint("%/%", output_path, map.destination_file_name),
            capture_and_return_output = true,
        );

        if result.exit_code != 0 return error;
    }

    return "";
}



#scope_file

Shader_Path_Map :: struct {
    source_path:           string;
    destination_file_name: string;
}

COMPILED_SHADERS_ROOT :: "shaders";

SHADER_PATH_MAPS :: Shader_Path_Map.[
    {
        source_path           = #run sprint("%/modules/Renderer/shaders/gradient.comp", #filepath),
        destination_file_name = "gradient.spv",
    },
    {
        source_path           = #run sprint("%/modules/Renderer/shaders/gradient_color.comp", #filepath),
        destination_file_name = "gradient_color.spv",
    },
];

#import "Basic";
#import "Process";
#import "File";
