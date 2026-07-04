#import <Cocoa/Cocoa.h>
#import "WindowInfo.h"

// Brings a specific window to the front and makes it key, without changing
// Spaces (the window is already on the current Space).
@interface WindowRaiser : NSObject
+ (void)raise:(WindowInfo *)window;
@end
