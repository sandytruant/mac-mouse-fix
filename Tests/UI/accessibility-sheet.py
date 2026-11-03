#!/usr/bin/env python3
"""Exercise the production viewDidLoad method in an isolated AppKit sheet.

Shows a temporary blank window; does not start MMF, touch TCC, or open HID devices.
The rest of the controller (IPC, localization and HelperServices) is intentionally
not linked. This checks the macOS 26 window-metrics regression, not authorization.
"""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'App/UI/Accessibility/AuthorizeAccessibilityView.m').read_text()
start = source.index('- (void)viewDidLoad {')
end = source.index('\n- (IBAction)AuthorizeButton:', start)
method = source[start:end]
harness = r'''
#import <AppKit/AppKit.h>
#include <assert.h>
#define MFLocalizedString(key, comment) (key)
@interface AccessibilitySheetRegression : NSViewController
@property NSTextField *openSettingsLink;
@end
@implementation AccessibilitySheetRegression
- (void)loadView { self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 150)]; }
PRODUCTION_METHOD
@end
int main(void) { @autoreleasepool {
    if (@available(macOS 26.0, *)) {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        NSViewController *parent = [NSViewController new];
        parent.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 250)];
        parent.view.prefersCompactControlSizeMetrics = YES;
        NSWindow *window = [NSWindow windowWithContentViewController:parent];
        window.title = @"MMF accessibility sheet regression test";
        AccessibilitySheetRegression *sheet = [AccessibilitySheetRegression new];
        __block BOOL sawSheet = NO;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"_NSWindowDidBecomeVisible" object:nil queue:nil usingBlock:^(NSNotification *note) {
            NSWindow *visible = note.object;
            if (visible.contentView == sheet.view) {
                assert(visible.contentView.prefersCompactControlSizeMetrics == YES);
                sawSheet = YES;
            }
        }];
        [window makeKeyAndOrderFront:nil];
        [parent presentViewControllerAsSheet:sheet];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (!sawSheet && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        assert(sawSheet);
        assert(sheet.view.window.contentView.prefersCompactControlSizeMetrics == YES);
        [parent dismissViewController:sheet];
        [window orderOut:nil];
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        puts("PASS: production accessibility viewDidLoad sets compact metrics before sheet becomes visible");
    } else {
        puts("SKIP: compact-control metrics requires macOS 26+");
    }
} }
'''.replace('PRODUCTION_METHOD', method)
with tempfile.TemporaryDirectory(prefix='mmf-accessibility-sheet-') as temp:
    src = pathlib.Path(temp) / 'sheet.m'
    exe = pathlib.Path(temp) / 'sheet'
    src.write_text(harness)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'AppKit', str(src), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True, timeout=15)
