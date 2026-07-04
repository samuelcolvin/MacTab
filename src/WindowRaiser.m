#import "WindowRaiser.h"
#import "PrivateAPI.h"

@implementation WindowRaiser

+ (void)raise:(WindowInfo *)window {
    if (!window) return;

    AXUIElementRef app = AXUIElementCreateApplication(window.ownerPID);
    if (!app) return;

    CFArrayRef axWindows = NULL;
    AXError err = AXUIElementCopyAttributeValue(
        app, kAXWindowsAttribute, (CFTypeRef *)&axWindows);

    AXUIElementRef target = NULL;
    if (err == kAXErrorSuccess && axWindows) {
        CFIndex n = CFArrayGetCount(axWindows);
        for (CFIndex i = 0; i < n; i++) {
            AXUIElementRef candidate =
                (AXUIElementRef)CFArrayGetValueAtIndex(axWindows, i);
            CGWindowID wid = kCGNullWindowID;
            if (_AXUIElementGetWindow(candidate, &wid) == kAXErrorSuccess &&
                wid == window.windowID) {
                target = candidate;
                CFRetain(target);
                break;
            }
        }
    }

    // Activate the owning app first, then raise the specific window so it
    // becomes key rather than just some other window of that app.
    NSRunningApplication *running =
        [NSRunningApplication runningApplicationWithProcessIdentifier:window.ownerPID];
    [running activateWithOptions:NSApplicationActivateIgnoringOtherApps];

    if (target) {
        AXUIElementPerformAction(target, kAXRaiseAction);
        AXUIElementSetAttributeValue(target, kAXMainAttribute, kCFBooleanTrue);
        CFRelease(target);
    }

    if (axWindows) CFRelease(axWindows);
    CFRelease(app);
}

@end
