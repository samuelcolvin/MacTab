#import "AppDelegate.h"
#import "SwitcherController.h"

@interface AppDelegate ()
@property(nonatomic, strong) SwitcherController *switcher;
@property(nonatomic, strong) NSStatusItem *statusItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self setupStatusItem];

    // Prompt for Accessibility permission if we don't already have it. Both the
    // event tap and window-raising require it.
    NSDictionary *opts = @{ (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES };
    BOOL trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);

    self.switcher = [SwitcherController new];
    if (![self.switcher start]) {
        if (!trusted) {
            [self showPermissionAlert];
        }
    }
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

- (void)showPermissionAlert {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Accessibility permission needed";
    alert.informativeText =
        @"Grant this app Accessibility access in System Settings › Privacy & "
        @"Security › Accessibility, then relaunch it.";
    [alert addButtonWithTitle:@"Open System Settings"];
    [alert addButtonWithTitle:@"Quit"];
    NSModalResponse r = [alert runModal];
    if (r == NSAlertFirstButtonReturn) {
        NSURL *url = [NSURL URLWithString:
            @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
    [NSApp terminate:nil];
}

@end
