#import "MiddleClickController.h"

#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <math.h>
#import <os/lock.h>
#import <stdatomic.h>

// Two inputs are combined:
// - the private MultitouchSupport framework (loaded with dlopen) reports how
//   many fingers are on the trackpad, on a background thread;
// - a mouse event tap sees each left click. If exactly three fingers are down
//   and Chrome is frontmost, the click is rewritten in place as a middle click.
// With tap-to-click on, a three-finger *tap* generates no click event at all,
// so taps are detected from the touch data and a middle click is posted.

// Bundle identifiers of the apps where the remapping applies.
static NSArray<NSString *> *TargetApps(void) {
    return @[ @"com.google.Chrome", @"com.google.Chrome.beta",
              @"com.google.Chrome.dev", @"com.google.Chrome.canary" ];
}

static const int kFingers = 3;
// A tap must lift within this many seconds of the first touch...
static const double kTapMaxSecs = 0.3;
// ...and the fingers' centroid must move less than this (fraction of the pad).
static const float kTapMaxMove = 0.04f;

// ---- MultitouchSupport (private) ------------------------------------------

typedef CFTypeRef MTDeviceRef;
typedef int (*MTContactCallback)(MTDeviceRef device, const void *touches,
                                 int numTouches, double timestamp, int frame);

// One touch. The layout is undocumented; this is the one used by MiddleClick
// and other long-lived tools. Only the normalized position (0..1) is read.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint pos, vel; } MTVector;
typedef struct {
    int frame;
    double timestamp;
    int identifier, state, fingerId, handId;
    MTVector normalized;
    float size;
    int zero1;
    float angle, majorAxis, minorAxis;
    MTVector mm;
    int zero2[2];
    float unk2;
} MTTouch;
_Static_assert(sizeof(MTTouch) == 96, "unexpected MTTouch layout");

static CFArrayRef (*MTDeviceCreateList)(void);
static void (*MTRegisterContactFrameCallback)(MTDeviceRef, MTContactCallback);
static void (*MTUnregisterContactFrameCallback)(MTDeviceRef, MTContactCallback);
static void (*MTDeviceStart)(MTDeviceRef, int);
static void (*MTDeviceStop)(MTDeviceRef);

static BOOL LoadMultitouch(void) {
    static BOOL loaded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/"
                         "MultitouchSupport", RTLD_LAZY);
        if (!h) return;
        MTDeviceCreateList = dlsym(h, "MTDeviceCreateList");
        MTRegisterContactFrameCallback = dlsym(h, "MTRegisterContactFrameCallback");
        MTUnregisterContactFrameCallback = dlsym(h, "MTUnregisterContactFrameCallback");
        MTDeviceStart = dlsym(h, "MTDeviceStart");
        MTDeviceStop = dlsym(h, "MTDeviceStop");
        loaded = MTDeviceCreateList && MTRegisterContactFrameCallback &&
                 MTUnregisterContactFrameCallback && MTDeviceStart && MTDeviceStop;
    });
    return loaded;
}

static BOOL DebugEnabled(void) {
    static BOOL enabled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ enabled = getenv("MACTAB_DEBUG") != NULL; });
    return enabled;
}

// ---- touch state (written on the multitouch thread) -----------------------

// Fingers currently on the trackpad.
static atomic_int gFingersDown;
// Set by any real left click, so a three-finger *click* (already remapped by
// the event tap) isn't also reported as a tap.
static atomic_bool gClicked;

// The current touch sequence (first finger down to last finger up).
static os_unfair_lock gGestureLock = OS_UNFAIR_LOCK_INIT;
static struct {
    BOOL active, hasOrigin, moved;
    double start;
    int peak;
    float ox, oy;
} gGesture;

static __weak MiddleClickController *gController;

@interface MiddleClickController () {
    CFMachPortRef _tap;
    CFArrayRef _devices;
    IONotificationPortRef _ioPort;
    io_iterator_t _ioIterator;
}
@property(nonatomic, assign) BOOL remapping;
- (CGEventRef)handleEventOfType:(CGEventType)type event:(CGEventRef)event;
- (void)tapDetected;
- (void)devicesChanged;
@end

static int ContactFrame(MTDeviceRef device, const void *touches, int n,
                        double timestamp, int frame) {
    int prev = atomic_exchange(&gFingersDown, n);
    if (prev != n && DebugEnabled()) NSLog(@"[MiddleClick] fingers %d -> %d", prev, n);

    BOOL isTap = NO;
    os_unfair_lock_lock(&gGestureLock);
    if (n > 0 && !gGesture.active) {
        gGesture.active = YES;
        gGesture.start = timestamp;
        gGesture.peak = 0;
        gGesture.hasOrigin = NO;
        gGesture.moved = NO;
        atomic_store(&gClicked, false);
    }
    if (n > gGesture.peak) gGesture.peak = n;

    if (n == kFingers && touches) {
        const MTTouch *t = touches;
        float cx = 0, cy = 0;
        for (int i = 0; i < n; i++) {
            cx += t[i].normalized.pos.x;
            cy += t[i].normalized.pos.y;
        }
        cx /= n;
        cy /= n;
        if (!gGesture.hasOrigin) {
            gGesture.hasOrigin = YES;
            gGesture.ox = cx;
            gGesture.oy = cy;
        } else if (hypotf(cx - gGesture.ox, cy - gGesture.oy) > kTapMaxMove) {
            gGesture.moved = YES;
        }
    }

    if (n == 0 && gGesture.active) {
        gGesture.active = NO;
        double secs = timestamp - gGesture.start;
        isTap = gGesture.peak == kFingers && gGesture.hasOrigin && !gGesture.moved &&
                secs <= kTapMaxSecs;
        if (DebugEnabled() && gGesture.peak == kFingers) {
            NSLog(@"[MiddleClick] %d-finger touch ended: %.0fms moved=%d -> tap=%d",
                  kFingers, secs * 1000, gGesture.moved, isTap);
        }
    }
    os_unfair_lock_unlock(&gGestureLock);

    if (isTap) {
        // Give the event tap a moment to see any real click from the same
        // touch, then decide on the main thread.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{ [gController tapDetected]; });
    }
    return 0;
}

static CGEventRef MouseTapCallback(CGEventTapProxy proxy, CGEventType type,
                                   CGEventRef event, void *refcon) {
    MiddleClickController *self = (__bridge MiddleClickController *)refcon;
    return [self handleEventOfType:type event:event];
}

static void DevicesMatched(void *refcon, io_iterator_t it) {
    BOOL any = NO;
    io_object_t o;
    while ((o = IOIteratorNext(it))) {
        IOObjectRelease(o);
        any = YES;
    }
    if (any) [(__bridge MiddleClickController *)refcon devicesChanged];
}

@implementation MiddleClickController

- (BOOL)start {
    gController = self;
    [self startMultitouch];
    [self watchDevices];

    CGEventMask mask = CGEventMaskBit(kCGEventLeftMouseDown) |
                       CGEventMaskBit(kCGEventLeftMouseUp) |
                       CGEventMaskBit(kCGEventLeftMouseDragged);
    _tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                            kCGEventTapOptionDefault, mask, MouseTapCallback,
                            (__bridge void *)self);
    if (!_tap) {
        NSLog(@"[MiddleClick] Failed to create mouse event tap");
        return NO;
    }
    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    CGEventTapEnable(_tap, true);
    NSLog(@"[MiddleClick] Mouse event tap installed. Three-finger click/tap in Chrome = middle click.");
    return YES;
}

// (Re)register the contact callback on every multitouch device.
- (void)startMultitouch {
    if (!LoadMultitouch()) {
        NSLog(@"[MiddleClick] Couldn't load MultitouchSupport.framework");
        return;
    }
    if (_devices) {
        for (CFIndex i = 0; i < CFArrayGetCount(_devices); i++) {
            MTDeviceRef dev = CFArrayGetValueAtIndex(_devices, i);
            MTUnregisterContactFrameCallback(dev, ContactFrame);
            MTDeviceStop(dev);
        }
        CFRelease(_devices);
        _devices = NULL;
    }
    atomic_store(&gFingersDown, 0);

    _devices = MTDeviceCreateList();
    if (!_devices) {
        NSLog(@"[MiddleClick] No multitouch devices found");
        return;
    }
    CFIndex n = CFArrayGetCount(_devices);
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef dev = CFArrayGetValueAtIndex(_devices, i);
        MTRegisterContactFrameCallback(dev, ContactFrame);
        MTDeviceStart(dev, 0);
    }
    NSLog(@"[MiddleClick] Listening on %ld multitouch device(s)", (long)n);
}

// Multitouch device handles go stale across sleep and when a Magic Trackpad
// connects, so re-register on either event.
- (void)watchDevices {
    [[NSWorkspace sharedWorkspace].notificationCenter
        addObserver:self
           selector:@selector(devicesChanged)
               name:NSWorkspaceDidWakeNotification
             object:nil];

    _ioPort = IONotificationPortCreate(MACH_PORT_NULL);
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(_ioPort),
                       kCFRunLoopCommonModes);
    if (IOServiceAddMatchingNotification(_ioPort, kIOFirstMatchNotification,
                                         IOServiceMatching("AppleMultitouchDevice"),
                                         DevicesMatched, (__bridge void *)self,
                                         &_ioIterator) == KERN_SUCCESS) {
        // Drain the devices present at launch; this arms the notification.
        io_object_t o;
        while ((o = IOIteratorNext(_ioIterator))) IOObjectRelease(o);
    }
}

// Debounced: wake and device arrival tend to come in bursts.
- (void)devicesChanged {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(startMultitouch)
                                               object:nil];
    [self performSelector:@selector(startMultitouch) withObject:nil afterDelay:1.0];
}

- (BOOL)targetAppFrontmost {
    NSString *bid = [NSWorkspace sharedWorkspace].frontmostApplication.bundleIdentifier;
    return bid && [TargetApps() containsObject:bid];
}

static CGEventRef ToMiddle(CGEventRef event, CGEventType type) {
    CGEventSetType(event, type);
    CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, kCGMouseButtonCenter);
    return event;
}

// Runs on the main thread (the tap source is on the main run loop).
- (CGEventRef)handleEventOfType:(CGEventType)type event:(CGEventRef)event {
    switch (type) {
        case kCGEventTapDisabledByTimeout:
        case kCGEventTapDisabledByUserInput:
            if (_tap) CGEventTapEnable(_tap, true);
            return event;
        case kCGEventLeftMouseDown: {
            atomic_store(&gClicked, true);
            int fingers = atomic_load(&gFingersDown);
            if (DebugEnabled()) {
                NSLog(@"[MiddleClick] left down, fingers=%d target_app=%d", fingers,
                      [self targetAppFrontmost]);
            }
            if (fingers == kFingers && [self targetAppFrontmost]) {
                self.remapping = YES;
                return ToMiddle(event, kCGEventOtherMouseDown);
            }
            return event;
        }
        case kCGEventLeftMouseDragged:
            // Keep remapping until mouse-up even if a finger lifts mid-click.
            return self.remapping ? ToMiddle(event, kCGEventOtherMouseDragged) : event;
        case kCGEventLeftMouseUp:
            if (self.remapping) {
                self.remapping = NO;
                return ToMiddle(event, kCGEventOtherMouseUp);
            }
            return event;
        default:
            return event;
    }
}

// Main thread: a three-finger tap finished. Post a middle click at the cursor.
- (void)tapDetected {
    if (atomic_load(&gClicked) || ![self targetAppFrontmost]) return;
    if (DebugEnabled()) NSLog(@"[MiddleClick] posting middle click for tap");

    CGEventRef here = CGEventCreate(NULL);
    if (!here) return;
    CGPoint pos = CGEventGetLocation(here);
    CFRelease(here);
    for (int i = 0; i < 2; i++) {
        CGEventType type = i == 0 ? kCGEventOtherMouseDown : kCGEventOtherMouseUp;
        CGEventRef ev = CGEventCreateMouseEvent(NULL, type, pos, kCGMouseButtonCenter);
        if (!ev) return;
        CGEventSetIntegerValueField(ev, kCGMouseEventClickState, 1);
        CGEventPost(kCGHIDEventTap, ev);
        CFRelease(ev);
    }
}

@end
