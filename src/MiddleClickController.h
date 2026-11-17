#import <Cocoa/Cocoa.h>

// Turns a three-finger trackpad click or tap in Chrome into a middle click
// (open link in a new tab / close the tab under the cursor). Owns its own
// mouse event tap, separate from the ⌘Tab keyboard tap. Call -start only once
// the process is Accessibility-trusted (see AppDelegate).
@interface MiddleClickController : NSObject
- (BOOL)start;
@end
