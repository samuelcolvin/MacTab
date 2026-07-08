#import "WindowInfo.h"
#import "PrivateAPI.h"

// Maps window bounds to the display the window is (mostly) on. kCGWindowBounds
// and CGDisplayBounds share the same global top-left-origin coordinate space,
// so no conversion is needed. Returns kCGNullDirectDisplay if nothing matches.
static CGDirectDisplayID DisplayForBounds(CGRect bounds) {
    CGDirectDisplayID display = kCGNullDirectDisplay;
    uint32_t count = 0;
    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    // The call succeeds even when the point lies on no display (count == 0,
    // display left untouched), so success alone isn't enough — require count == 1.
    if (CGGetDisplaysWithPoint(center, 1, &display, &count) == kCGErrorSuccess &&
        count == 1) {
        return display;
    }
    // Center off every display (window straddling an edge, partly dragged
    // off-screen, …) — settle for any display the window intersects.
    if (CGGetDisplaysWithRect(bounds, 1, &display, &count) == kCGErrorSuccess &&
        count == 1) {
        return display;
    }
    return kCGNullDirectDisplay;
}

// The display the mouse cursor is on. Needs no extra permissions:
// CGEventCreate(NULL) reads the cursor location in the same global
// top-left-origin coordinates as CGGetDisplaysWithPoint.
static CGDirectDisplayID DisplayUnderCursor(void) {
    CGEventRef e = CGEventCreate(NULL);
    if (!e) return kCGNullDirectDisplay;
    CGPoint cursor = CGEventGetLocation(e);
    CFRelease(e);
    CGDirectDisplayID display = kCGNullDirectDisplay;
    uint32_t count = 0;
    if (CGGetDisplaysWithPoint(cursor, 1, &display, &count) == kCGErrorSuccess &&
        count == 1) {
        return display;
    }
    return kCGNullDirectDisplay;
}

@implementation WindowInfo

+ (NSArray<WindowInfo *> *)currentSpaceWindowsExcludingPID:(pid_t)selfPID {
    // kCGWindowListOptionOnScreenOnly restricts results to the windows that are
    // currently on screen — i.e. the current Space. That is exactly the
    // "current Space only" semantics we want, and it needs no private APIs.
    // The array comes back in front-to-back z-order.
    CGWindowListOption opts = kCGWindowListOptionOnScreenOnly |
                              kCGWindowListExcludeDesktopElements;
    CFArrayRef raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID);
    if (!raw) return @[];

    NSMutableArray<WindowInfo *> *result = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSRunningApplication *> *appCache =
        [NSMutableDictionary dictionary];

    CFIndex count = CFArrayGetCount(raw);
    for (CFIndex i = 0; i < count; i++) {
        NSDictionary *info = (__bridge NSDictionary *)CFArrayGetValueAtIndex(raw, i);

        // Only real application windows live on layer 0. Menubar, dock,
        // wallpaper, shadows, tooltips etc. sit on other layers.
        NSNumber *layer = info[(__bridge NSString *)kCGWindowLayer];
        if (layer.intValue != 0) continue;

        // Skip fully transparent windows (helper/overlay surfaces).
        NSNumber *alpha = info[(__bridge NSString *)kCGWindowAlpha];
        if (alpha && alpha.doubleValue <= 0.01) continue;

        pid_t pid = (pid_t)[info[(__bridge NSString *)kCGWindowOwnerPID] intValue];
        if (pid == selfPID) continue;

        // Reject tiny windows (status-item popovers, 1px helpers, …).
        CGRect bounds = CGRectZero;
        CFDictionaryRef boundsDict =
            (__bridge CFDictionaryRef)info[(__bridge NSString *)kCGWindowBounds];
        if (boundsDict) CGRectMakeWithDictionaryRepresentation(boundsDict, &bounds);
        if (bounds.size.width < 60 || bounds.size.height < 60) continue;

        WindowInfo *w = [WindowInfo new];
        w.windowID = (CGWindowID)[info[(__bridge NSString *)kCGWindowNumber] unsignedIntValue];
        w.ownerPID = pid;
        w.appName = info[(__bridge NSString *)kCGWindowOwnerName] ?: @"";
        w.windowTitle = info[(__bridge NSString *)kCGWindowName] ?: @"";
        w.bounds = bounds;

        NSRunningApplication *app = appCache[@(pid)];
        if (!app) {
            app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            if (app) appCache[@(pid)] = app;
        }
        w.icon = app.icon;
        // Prefer the localized app name when available.
        if (app.localizedName.length) w.appName = app.localizedName;

        [result addObject:w];
    }

    CFRelease(raw);

    // Restrict to the current display, defined by the mouse cursor rather than
    // the focused window: when the cursor's display has no windows, focus lives
    // on another display and following it would surface that display's windows
    // here. If the cursor's display can't be determined, leave the list
    // unfiltered.
    if (result.count > 0) {
        CGDirectDisplayID active = DisplayUnderCursor();
        if (active != kCGNullDirectDisplay) {
            NSIndexSet *keep = [result
                indexesOfObjectsPassingTest:^BOOL(WindowInfo *w, NSUInteger idx,
                                                  BOOL *stop) {
                    return DisplayForBounds(w.bounds) == active;
                }];
            result = [[result objectsAtIndexes:keep] mutableCopy];
        }
    }
    return result;
}

+ (void)fillTitlesViaAccessibility:(NSArray<WindowInfo *> *)windows {
    // One AX app query per owning app, not per window.
    NSMutableDictionary<NSNumber *, NSMutableArray<WindowInfo *> *> *byPID =
        [NSMutableDictionary dictionary];
    for (WindowInfo *w in windows) {
        if (w.windowTitle.length) continue;  // CG already provided one
        NSMutableArray<WindowInfo *> *group = byPID[@(w.ownerPID)];
        if (!group) {
            group = [NSMutableArray array];
            byPID[@(w.ownerPID)] = group;
        }
        [group addObject:w];
    }

    for (NSNumber *pidNum in byPID) {
        AXUIElementRef app = AXUIElementCreateApplication(pidNum.intValue);
        if (!app) continue;
        // These calls are synchronous into the target app and we're on the main
        // thread (which also services the event tap) — a beachballed app must
        // fail fast, not stall keyboard input.
        AXUIElementSetMessagingTimeout(app, 0.1);

        CFArrayRef axWindows = NULL;
        if (AXUIElementCopyAttributeValue(app, kAXWindowsAttribute,
                                          (CFTypeRef *)&axWindows) == kAXErrorSuccess &&
            axWindows) {
            CFIndex n = CFArrayGetCount(axWindows);
            for (CFIndex i = 0; i < n; i++) {
                AXUIElementRef axWin =
                    (AXUIElementRef)CFArrayGetValueAtIndex(axWindows, i);
                CGWindowID wid = kCGNullWindowID;
                if (_AXUIElementGetWindow(axWin, &wid) != kAXErrorSuccess) continue;
                for (WindowInfo *w in byPID[pidNum]) {
                    if (w.windowID != wid) continue;
                    CFTypeRef title = NULL;
                    if (AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute,
                                                      &title) == kAXErrorSuccess &&
                        title) {
                        if (CFGetTypeID(title) == CFStringGetTypeID()) {
                            w.windowTitle = (__bridge NSString *)title;
                        }
                        CFRelease(title);
                    }
                    break;
                }
            }
        }
        if (axWindows) CFRelease(axWindows);
        CFRelease(app);
    }
}

- (NSString *)displayTitle {
    if (self.windowTitle.length && ![self.windowTitle isEqualToString:self.appName]) {
        return [NSString stringWithFormat:@"%@ — %@", self.appName, self.windowTitle];
    }
    return self.appName.length ? self.appName : @"Untitled";
}

@end
