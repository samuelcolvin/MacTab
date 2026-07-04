// Declarations for the one private Accessibility function we rely on.
//
// _AXUIElementGetWindow maps an AXUIElement (an app's AXWindow) to its
// CoreGraphics window id (CGWindowID). This is the reliable way to match a
// window we enumerated via CGWindowListCopyWindowInfo() to the AX element we
// need in order to raise it. It has been stable across macOS releases for
// years and is what AltTab, Rectangle, yabai, etc. all use.
#import <ApplicationServices/ApplicationServices.h>

extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *identifier);
