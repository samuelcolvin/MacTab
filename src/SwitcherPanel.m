#import "SwitcherPanel.h"

static const CGFloat kRowHeight = 44.0;
static const CGFloat kIconSize = 32.0;
static const CGFloat kPadding = 12.0;
static const CGFloat kPanelWidth = 560.0;
static const CGFloat kCornerRadius = 16.0;

#pragma mark - Content view (custom drawn)

@interface SwitcherContentView : NSView
@property(nonatomic, strong) NSArray<WindowInfo *> *windows;
@property(nonatomic, assign) NSInteger selectedIndex;
@end

@implementation SwitcherContentView

- (BOOL)isFlipped { return YES; }  // rows drawn top-to-bottom

- (void)drawRect:(NSRect)dirtyRect {
    // Rounded translucent background.
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                       xRadius:kCornerRadius
                                                       yRadius:kCornerRadius];
    [[NSColor colorWithWhite:0.12 alpha:0.92] setFill];
    [bg fill];

    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.95 alpha:1.0],
    };
    NSDictionary *selAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };

    for (NSInteger i = 0; i < (NSInteger)self.windows.count; i++) {
        WindowInfo *w = self.windows[i];
        CGFloat y = kPadding + i * kRowHeight;
        NSRect row = NSMakeRect(kPadding, y, kPanelWidth - 2 * kPadding, kRowHeight);

        if (i == self.selectedIndex) {
            NSBezierPath *hl = [NSBezierPath bezierPathWithRoundedRect:row
                                                              xRadius:10 yRadius:10];
            [[NSColor colorWithRed:0.20 green:0.48 blue:0.98 alpha:0.90] setFill];
            [hl fill];
        }

        CGFloat iconY = y + (kRowHeight - kIconSize) / 2.0;
        NSRect iconRect = NSMakeRect(row.origin.x + 8, iconY, kIconSize, kIconSize);
        if (w.icon) {
            [w.icon drawInRect:iconRect
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1.0
                respectFlipped:YES
                         hints:nil];
        }

        NSRect textRect = NSMakeRect(iconRect.origin.x + kIconSize + 12,
                                     y, row.size.width - kIconSize - 40, kRowHeight);
        NSString *title = [w displayTitle];
        NSDictionary *attrs = (i == self.selectedIndex) ? selAttrs : titleAttrs;
        NSSize sz = [title sizeWithAttributes:attrs];
        NSPoint tp = NSMakePoint(textRect.origin.x,
                                 y + (kRowHeight - sz.height) / 2.0);
        // Truncate manually by clipping.
        [NSGraphicsContext saveGraphicsState];
        [NSBezierPath clipRect:textRect];
        [title drawAtPoint:tp withAttributes:attrs];
        [NSGraphicsContext restoreGraphicsState];
    }
}

@end

#pragma mark - Panel

@interface SwitcherPanel ()
@property(nonatomic, strong) SwitcherContentView *contentViewCustom;
@end

@implementation SwitcherPanel

- (instancetype)init {
    self = [super initWithContentRect:NSMakeRect(0, 0, kPanelWidth, 100)
                            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        self.floatingPanel = YES;
        self.level = NSPopUpMenuWindowLevel;
        self.opaque = NO;
        self.backgroundColor = [NSColor clearColor];
        self.hasShadow = YES;
        self.hidesOnDeactivate = NO;
        self.becomesKeyOnlyIfNeeded = YES;
        self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                  NSWindowCollectionBehaviorTransient |
                                  NSWindowCollectionBehaviorIgnoresCycle;

        _contentViewCustom = [[SwitcherContentView alloc] initWithFrame:self.contentView.bounds];
        _contentViewCustom.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.contentView addSubview:_contentViewCustom];
    }
    return self;
}

// Never steal key/main focus from the app being switched away from.
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }

- (void)showWindows:(NSArray<WindowInfo *> *)windows selectedIndex:(NSInteger)index {
    self.contentViewCustom.windows = windows;
    self.contentViewCustom.selectedIndex = index;

    CGFloat height = 2 * kPadding + windows.count * kRowHeight;
    NSRect frame = NSMakeRect(0, 0, kPanelWidth, height);

    NSScreen *screen = [NSScreen mainScreen];
    NSRect vis = screen.visibleFrame;
    frame.origin.x = vis.origin.x + (vis.size.width - kPanelWidth) / 2.0;
    frame.origin.y = vis.origin.y + (vis.size.height - height) / 2.0;

    [self setFrame:frame display:YES];
    [self.contentViewCustom setNeedsDisplay:YES];
    [self orderFrontRegardless];
}

- (void)updateSelectedIndex:(NSInteger)index {
    self.contentViewCustom.selectedIndex = index;
    [self.contentViewCustom setNeedsDisplay:YES];
}

- (void)dismiss {
    [self orderOut:nil];
}

@end
