#placeholder DEBUG;

#import "Basic"()(
    MEMORY_DEBUGGER = DEBUG,
);

main :: () {
    defer report_memory_leaks();

    print("Hello, Sailor!");
}
