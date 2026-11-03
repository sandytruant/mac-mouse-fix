//
// --------------------------------------------------------------------------
// UNIXSignals.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2024
// Licensed under Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

#import "UNIXSignals.h"
#import <signal.h>
#import "DeviceManager.h"

@implementation UNIXSignals

+ (void)load_Manual {
    
    static dispatch_source_t term, interrupt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Dispatch signal sources execute in normal context, NOT in a POSIX handler.
        // Current deconfigureDevices only waits on the independent HID++ worker.
        // If IOThread-owned driver cleanup is re-enabled there, marshal that part
        // asynchronously to IOThread (never make the worker wait for it).
        dispatch_queue_t queue = dispatch_queue_create("mmf.logitech.termination", DISPATCH_QUEUE_SERIAL);
        signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN);
        term = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, queue);
        interrupt = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, queue);
        dispatch_block_t cleanup = ^{
            [DeviceManager deconfigureDevices];
            exit(0);
        };
        dispatch_source_set_event_handler(term, cleanup);
        dispatch_source_set_event_handler(interrupt, cleanup);
        dispatch_resume(term); dispatch_resume(interrupt);
    });
}

@end
