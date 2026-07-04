#import "SwitcherController.h"
#import "SwitcherPanel.h"
#import "WindowInfo.h"
#import "WindowRaiser.h"

#import <Carbon/Carbon.h>  // for kVK_Tab, kVK_Escape

// How long ⌘ must stay held before the picker appears. A quick ⌘Tab tap
// commits before this fires, so it switches instantly with no UI flash.
static const NSTimeInterval kShowDelay = 0.2;

@interface SwitcherController () {
    CFMachPortRef _tap;
    CFRunLoopSourceRef _runLoopSource;
}
@property(nonatomic, assign) BOOL switching;
@property(nonatomic, assign) NSInteger selectedIndex;
@property(nonatomic, strong) NSArray<WindowInfo *> *windows;
@property(nonatomic, strong) SwitcherPanel *panel;
@property(nonatomic, assign) pid_t selfPID;
@property(nonatomic, strong) NSTimer *showTimer;
@property(nonatomic, assign) BOOL panelVisible;
- (CGEventRef)handleEventOfType:(CGEventType)type event:(CGEventRef)event;
@end

static CGEventRef EventTapCallback(CGEventTapProxy proxy, CGEventType type,
                                   CGEventRef event, void *refcon) {
    SwitcherController *self = (__bridge SwitcherController *)refcon;
    return [self handleEventOfType:type event:event];
}

@implementation SwitcherController

- (BOOL)start {
    self.selfPID = getpid();
    self.panel = [[SwitcherPanel alloc] init];

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) |
                       CGEventMaskBit(kCGEventKeyUp) |
                       CGEventMaskBit(kCGEventFlagsChanged);

    _tap = CGEventTapCreate(kCGSessionEventTap,
                            kCGHeadInsertEventTap,
                            kCGEventTapOptionDefault,  // active: may consume
                            mask,
                            EventTapCallback,
                            (__bridge void *)self);
    if (!_tap) {
        NSLog(@"[Switcher] Failed to create event tap — is Accessibility permission granted?");
        return NO;
    }

    _runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(_tap, true);
    NSLog(@"[Switcher] Event tap installed. Hold ⌘ and tap Tab.");
    return YES;
}

- (CGEventRef)handleEventOfType:(CGEventType)type event:(CGEventRef)event {
    // The system disables the tap if a callback runs too long or on user input
    // events during a modal loop — re-enable it and move on.
    if (type == kCGEventTapDisabledByTimeout ||
        type == kCGEventTapDisabledByUserInput) {
        if (_tap) CGEventTapEnable(_tap, true);
        return event;
    }

    CGKeyCode keycode =
        (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    CGEventFlags flags = CGEventGetFlags(event);
    BOOL cmd = (flags & kCGEventFlagMaskCommand) != 0;
    BOOL shift = (flags & kCGEventFlagMaskShift) != 0;

    switch (type) {
        case kCGEventKeyDown:
            if (keycode == kVK_Tab && cmd) {
                if (!self.switching) {
                    if (![self beginSwitchingBackward:shift]) {
                        return event;  // <2 windows: fall back to native switcher
                    }
                } else {
                    [self advanceBackward:shift];
                }
                return NULL;  // swallow so macOS's ⌘Tab switcher never sees it
            }
            if (keycode == kVK_Escape && self.switching) {
                [self cancel];
                return NULL;
            }
            break;

        case kCGEventKeyUp:
            // Swallow the Tab key-up while switching so it doesn't leak.
            if (self.switching && keycode == kVK_Tab) return NULL;
            break;

        case kCGEventFlagsChanged:
            // ⌘ released → commit the current selection.
            if (self.switching && !cmd) {
                [self commit];
            }
            break;

        default:
            break;
    }
    return event;
}

#pragma mark - State machine

- (BOOL)beginSwitchingBackward:(BOOL)backward {
    self.windows = [WindowInfo currentSpaceWindowsExcludingPID:self.selfPID];
    // We always take over ⌘Tab so the native switcher never appears — even with
    // zero windows, where the picker just shows a "No windows" message.
    self.switching = YES;
    self.panelVisible = NO;
    NSInteger last = (NSInteger)self.windows.count - 1;
    self.selectedIndex = backward ? last : 1;
    if (self.selectedIndex > last) self.selectedIndex = last;  // clamp (single window)
    // Defer showing the picker: a quick tap commits before this fires and just
    // switches to the selected window with no UI. Hold ⌘ past kShowDelay to see
    // the picker.
    self.showTimer = [NSTimer scheduledTimerWithTimeInterval:kShowDelay
                                                     target:self
                                                   selector:@selector(showTimerFired:)
                                                   userInfo:nil
                                                    repeats:NO];
    return YES;
}

- (void)showTimerFired:(NSTimer *)timer {
    if (!self.switching) return;
    [self.panel showWindows:self.windows selectedIndex:self.selectedIndex];
    self.panelVisible = YES;
}

- (void)advanceBackward:(BOOL)backward {
    NSInteger n = (NSInteger)self.windows.count;
    if (n == 0) return;
    self.selectedIndex = ((self.selectedIndex + (backward ? -1 : 1)) % n + n) % n;
    // If the picker is already up, reflect the new selection; otherwise it will
    // show the current selection once the timer fires.
    if (self.panelVisible) [self.panel updateSelectedIndex:self.selectedIndex];
}

- (void)commit {
    WindowInfo *chosen = nil;
    if (self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)self.windows.count) {
        chosen = self.windows[self.selectedIndex];
    }
    [self endSwitching];
    if (chosen) [WindowRaiser raise:chosen];
}

- (void)cancel {
    [self endSwitching];
}

- (void)endSwitching {
    self.switching = NO;
    [self.showTimer invalidate];
    self.showTimer = nil;
    if (self.panelVisible) {
        [self.panel dismiss];
        self.panelVisible = NO;
    }
    self.windows = nil;
    self.selectedIndex = 0;
}

@end
