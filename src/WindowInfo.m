#import "WindowInfo.h"

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
    return result;
}

- (NSString *)displayTitle {
    if (self.windowTitle.length && ![self.windowTitle isEqualToString:self.appName]) {
        return [NSString stringWithFormat:@"%@ — %@", self.appName, self.windowTitle];
    }
    return self.appName.length ? self.appName : @"Untitled";
}

@end
