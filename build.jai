#scope_file

#import "Basic";
#import "Compiler";
#import "Metaprogram_Plugins";
#import "String";
#import "File";
#import "File_Utilities";
#import "Process";

#load "compile_shaders.jai";

CONFIG_FLAGS :: struct {
    OPTIMIZED      :: "--optimized";
    DEBUG          :: "--debug";
    VERY_OPTIMIZED :: "--very-optimized";
    VERY_DEBUG     :: "--very-debug";
}

Config :: struct {
    optimization_type: Optimization_Type;
    plugins_to_create: [..]Plugin_To_Create;
    plugins_to_create.allocator = temp;
}

#run,stallable {
    defer reset_temporary_storage();

    set_build_options_dc({do_output = false});

    build_options_dc := get_build_options();

    error, config := create_config(build_options_dc.compile_time_command_line);
    if error {
        print("Failed to create config: %", error, to_standard_error = true);
        return;
    }

    output_path := make_output_path(config);

    #if !#exists(JAILS_DIAGNOSTICS_BUILD) {
        error = compile_shaders(output_path);
        if error {
            print("Failed to compile shaders: %", error, to_standard_error = true);
            return;
        }
    }

    error = build(build_options_dc, config, output_path);
    if error {
        print("Failed to build: %", error, to_standard_error = true);
        return;
    }
}

build :: (build_options_dc: Build_Options, config: Config, output_path: string) -> error: string {
    print("Building with % optimization\n", config.optimization_type);
    for plugin_to_create: config.plugins_to_create {
        print("% plugin enabled\n", plugin_to_create.name);
    }

    workspace := compiler_create_workspace("vkguiding");

    ENTRY_FILE_PATH :: #run tprint("%source/main.jai", #filepath);
    EXECUTABLE_NAME :: "target";

    build_options := get_build_options(workspace);
    {
        copy_commonly_propagated_fields(build_options_dc, *build_options);

        #if #exists(JAILS_DIAGNOSTICS_BUILD) {
            build_options.output_type = .NO_OUTPUT;
        } else {
            build_options.output_type = .EXECUTABLE;
        }

        build_options.output_executable_name = EXECUTABLE_NAME;
        build_options.output_path = output_path;
        build_options.intermediate_path = output_path;

        set_optimization(*build_options, config.optimization_type);

        set_build_options(build_options, workspace);
    }

    ok := make_directory_if_it_does_not_exist(output_path, recursive = true);
    if !ok {
        return "Failed to create build directory";
    }

    copy_ok := copy_dependencies(build_options.output_path);
    if !copy_ok {
        return "Failed to copy dependencies";
    }

    plugins: [..]*Metaprogram_Plugin;
    plugins.allocator = temp;
    ok = init_plugins(config.plugins_to_create, *plugins, workspace);
    if !ok {
        return "Failed to init some plugins";
    }

    intercept_flags: Intercept_Flags;

    for plugin: plugins {
        if plugin.before_intercept {
            plugin.before_intercept(plugin, *intercept_flags);
        }
    }

    compiler_begin_intercept(workspace, intercept_flags);

    for plugin: plugins {
        if plugin.add_source {
            plugin.add_source(plugin);
        }
    }

    add_build_file(ENTRY_FILE_PATH, workspace);

    handle_compiler_messages(plugins, config, workspace);

    compiler_end_intercept(workspace);

    for plugin: plugins {
        if plugin.finish {
            plugin.finish(plugin);
        }

        if plugin.shutdown {
            plugin.shutdown(plugin);
        }
    }

    return "";
}

handle_compiler_messages :: (
    plugins:   []*Metaprogram_Plugin,
    config:    Config,
    workspace: Workspace,
) {
    while true {
        message := compiler_wait_for_message();

        for plugin: plugins {
            if plugin.message {
                plugin.message(plugin, message);
            }
        }

        handle_debug_constant(message, config, workspace);

        if message.kind == {
            case .COMPLETE;
                break;
        }
    }
}

handle_debug_constant :: (
    message:   *Message,
    config:    Config,
    workspace: Workspace,
) {
    if message.kind == {
        case .FILE;
            file := cast(*Message_File, message);
            if ends_with(file.fully_pathed_filename, "main.jai") {
                add_build_string(
                    tprint(
                        "DEBUG: bool : %;",
                        config.optimization_type <= .VERY_DEBUG
                    ),
                    workspace,
                    file
                );
            }
    }
}

create_config :: (arguments: []string) -> error: string, Config {
    config: Config;

    unknown_arguments: [..]string;
    unknown_arguments.allocator = temp;

    for argument: arguments {
        if argument == {
            case CONFIG_FLAGS.DEBUG;
                config.optimization_type = .DEBUG;
            case CONFIG_FLAGS.VERY_DEBUG;
                config.optimization_type = .VERY_DEBUG;
            case CONFIG_FLAGS.OPTIMIZED;
                config.optimization_type = .OPTIMIZED;
            case CONFIG_FLAGS.VERY_OPTIMIZED;
                config.optimization_type = .VERY_OPTIMIZED;
            case;
                PLUGIN_ARGUMENT_PREFIX :: "+";

                if !starts_with(argument, PLUGIN_ARGUMENT_PREFIX) {
                    array_add(*unknown_arguments, argument);
                }
        }
    }

    if unknown_arguments.count > 0 {
        return tprint("Unknown arguments: %", unknown_arguments), config;
    }

    DEFAULT_PLUGINS_TO_CREATE :: Plugin_To_Create.[
        { name = "Check" },
    ];
    _, config.plugins_to_create = parse_plugin_arguments(arguments);
    array_add(*config.plugins_to_create, ..DEFAULT_PLUGINS_TO_CREATE);

    return "", config;
}

make_output_path :: (config: Config) -> string {
    OUTPUT_PATH :: #run tprint("%.build", #filepath);

    return tprint("%/%", OUTPUT_PATH, config.optimization_type);
}

copy_dependencies :: (output_path: string) -> bool {
    #if OS == {
        case .WINDOWS;
            // This is super janky stuff.
            // I don't know why we need to do this and, honestly, don't care that much.
            return copy_file(
                tprint("%modules/Jai_Vulkan/windows/libvma.dll", #filepath),
                tprint("%/libvma.dll", output_path),
        );
        case;
            return true;
    }

    return true;
}
