#import <Cocoa/Cocoa.h>
#import "WindowInfo.h"

// A borderless, non-activating floating panel that lists windows and
// highlights the current selection. It never becomes key, so it does not
// disturb the front app while ⌘ is held.
@interface SwitcherPanel : NSPanel

- (void)showWindows:(NSArray<WindowInfo *> *)windows selectedIndex:(NSInteger)index;
- (void)updateSelectedIndex:(NSInteger)index;
- (void)dismiss;

@end
