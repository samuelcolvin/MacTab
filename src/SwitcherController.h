#import <Cocoa/Cocoa.h>

// Owns the global event tap and the ⌘-held / Tab-tapped switching state
// machine. Returns YES from -start if the tap was installed (requires
// Accessibility permission).
@interface SwitcherController : NSObject
- (BOOL)start;
@end
