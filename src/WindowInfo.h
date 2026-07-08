#import <Cocoa/Cocoa.h>

// A single switchable window, distilled from CGWindowListCopyWindowInfo().
@interface WindowInfo : NSObject

@property(nonatomic, assign) CGWindowID windowID;
@property(nonatomic, assign) pid_t ownerPID;
@property(nonatomic, copy) NSString *appName;      // e.g. "Safari"
@property(nonatomic, copy) NSString *windowTitle;  // e.g. "Inbox — samuel@…"
@property(nonatomic, strong) NSImage *icon;        // app icon, may be nil
@property(nonatomic, assign) CGRect bounds;

// Enumerate windows on the CURRENT Space and CURRENT display (the display
// under the mouse cursor), front-to-back (z-order == a good most-recently-used
// proxy), excluding our own process and non-window chrome.
+ (NSArray<WindowInfo *> *)currentSpaceWindowsExcludingPID:(pid_t)selfPID;

// Fill in empty windowTitles via the Accessibility API (kAXTitle).
// CGWindowListCopyWindowInfo only returns kCGWindowName to processes with
// Screen Recording permission, which we don't request — so titles must come
// from AX instead. Makes synchronous AX calls into each owning app (bounded by
// a short messaging timeout); call it only when the panel is about to show,
// never on the quick-tap path.
+ (void)fillTitlesViaAccessibility:(NSArray<WindowInfo *> *)windows;

// Display string used in the overlay.
- (NSString *)displayTitle;

@end
