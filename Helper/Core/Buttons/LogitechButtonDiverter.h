// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// IOHIDLib worker/transport derived from lcandy2's PR #1995.
#import <Foundation/Foundation.h>
@interface LogitechButtonDiverter : NSObject
// Caller reads the (default-on) setting once on IOThread after Config is ready. No config access here.
+ (void)startWithEnabled:(BOOL)enabled;
// Normal application context only, NOT signal-safe. Bounded wait; no IOThread/main callouts.
+ (void)restoreNativeBehavior;
@end
