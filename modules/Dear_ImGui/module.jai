#if OS == {
    case .LINUX;
        #load("./linux.jai");
    case;
        assert(false, "Unsupported OS '%'", OS);
}

#import "Math";
#import "Basic";
