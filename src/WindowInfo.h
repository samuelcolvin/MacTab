#import <Cocoa/Cocoa.h>

// A single switchable window, distilled from CGWindowListCopyWindowInfo().
@interface WindowInfo : NSObject

@property(nonatomic, assign) CGWindowID windowID;
@property(nonatomic, assign) pid_t ownerPID;
@property(nonatomic, copy) NSString *appName;      // e.g. "Safari"
@property(nonatomic, copy) NSString *windowTitle;  // e.g. "Inbox — samuel@…"
@property(nonatomic, strong) NSImage *icon;        // app icon, may be nil
@property(nonatomic, assign) CGRect bounds;

// Enumerate windows on the CURRENT Space, front-to-back (z-order == a good
// most-recently-used proxy), excluding our own process and non-window chrome.
+ (NSArray<WindowInfo *> *)currentSpaceWindowsExcludingPID:(pid_t)selfPID;

// Display string used in the overlay.
- (NSString *)displayTitle;

@end
