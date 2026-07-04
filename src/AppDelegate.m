#import "AppDelegate.h"
#import "SwitcherController.h"

@interface AppDelegate ()
@property(nonatomic, strong) SwitcherController *switcher;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, assign) BOOL didPromptAccessibility;
@property(nonatomic, assign) BOOL didStart;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self setupStatusItem];
    self.switcher = [SwitcherController new];
    [self startWhenTrusted];
}

// We create the keyboard event tap only once the process is already trusted for
// Accessibility. An *active* tap made by an Accessibility-trusted process is
// authorized by Accessibility alone, so macOS does NOT additionally prompt for
// Input Monitoring — you get a single permission dialog instead of two.
- (void)startWhenTrusted {
    if (self.didStart) return;

    if (AXIsProcessTrusted()) {
        self.didStart = YES;
        [self.switcher start];
        return;
    }

    // Show the one Accessibility prompt (once), then poll until it's granted.
    // The app lives in the menu bar meanwhile; no relaunch is needed.
    if (!self.didPromptAccessibility) {
        self.didPromptAccessibility = YES;
        NSDictionary *opts = @{ (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES };
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
    }
    [self performSelector:@selector(startWhenTrusted) withObject:nil afterDelay:1.0];
}

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];

    NSImage *icon = [NSImage imageWithSystemSymbolName:@"rectangle.on.rectangle"
                             accessibilityDescription:@"MacTab"];
    icon.template = YES;  // adapts to light/dark menu bar
    self.statusItem.button.image = icon;
    self.statusItem.button.toolTip = @"MacTab — hold ⌘, tap Tab";

    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *hint = [[NSMenuItem alloc]
        initWithTitle:@"Hold ⌘, tap Tab to switch" action:nil keyEquivalent:@""];
    hint.enabled = NO;
    [menu addItem:hint];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *github = [[NSMenuItem alloc]
        initWithTitle:@"View at github.com/samuelcolvin/MacTab" action:@selector(openGitHub:) keyEquivalent:@""];
    github.target = self;
    [menu addItem:github];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit MacTab"
                    action:@selector(terminate:)
             keyEquivalent:@"q"];
    self.statusItem.menu = menu;
}

- (void)openGitHub:(id)sender {
    [[NSWorkspace sharedWorkspace]
        openURL:[NSURL URLWithString:@"https://github.com/samuelcolvin/MacTab"]];
}

@end
