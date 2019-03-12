/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 */

#import "AppDelegate.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender;
@end

@implementation AppDelegate
-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	return YES;
}

- (IBAction)openURL:(NSMenuItem*)sender {
    NSString *url = [sender toolTip];
    if (url) {
         [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
    }
}

#if 0
- (IBAction)openPreferences:(id)sender {
    /* FIXME TextEdit isn't allowed to open opensc.conf */
    NSString *builtinPluginsPath = [[NSBundle mainBundle] builtInPlugInsPath];
    NSString * opensc_conf = [NSString stringWithFormat:@"%@/%@", builtinPluginsPath, @"OpenSCToken.appex/Contents/Resources/opensc.conf"];
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSURL *textEdit = [NSURL fileURLWithPath:[workspace fullPathForApplication:@"TextEdit"]];
    if (textEdit) {
        NSError *error = nil;
        NSArray *arguments = [NSArray arrayWithObjects:opensc_conf, nil];
        [workspace launchApplicationAtURL:textEdit options:0 configuration:[NSDictionary dictionaryWithObject:arguments forKey:NSWorkspaceLaunchConfigurationArguments] error:&error];
    }
}
#endif

@end
