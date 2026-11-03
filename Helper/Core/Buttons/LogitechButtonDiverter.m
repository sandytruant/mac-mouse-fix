// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// IOHIDLib worker, serial run-loop request transport and discovery adapted from
// lcandy2, PR #1995 (a874b40130ba0ab9bbea9e3eab57b5fa5de12f34).
// Framing/readback/ownership approach informed by PR #2094. Only Back/Forward.
#import "LogitechButtonDiverter.h"
#import "LogitechHIDPPState.h"
#import "Constants.h"
#import <AppKit/AppKit.h>
#import <IOKit/hid/IOHIDLib.h>
#include <assert.h>
#include <time.h>

@interface MFLogiTarget : NSObject
@property uint8_t index, feature, wireless, held;
@property uint64_t senderID;
@property NSMutableDictionary<NSNumber *, NSData *> *original;
@property NSMutableSet<NSNumber *> *confirmed;
@property NSMutableSet<NSNumber *> *foreign;
@end
@implementation MFLogiTarget
- (instancetype)init {
    if ((self = [super init])) {
        _original = [NSMutableDictionary dictionary];
        _confirmed = [NSMutableSet set]; _foreign = [NSMutableSet set];
    }
    return self;
}
@end
@interface MFLogiInterface : NSObject {
@public uint8_t buffer[64]; uint8_t reply[20];
}
@property IOHIDDeviceRef device;
@property BOOL open, receiver, waiting, answered, removed;
@property uint8_t pendingIndex, pendingFeature, command, software;
@property uint16_t pid;
@property size_t replyLength;
@property NSMutableArray<MFLogiTarget *> *targets;
@end
@implementation MFLogiInterface
- (instancetype)init { if ((self = [super init])) _targets = [NSMutableArray array]; return self; }
- (void)dealloc { if (_device) CFRelease(_device); }
@end
@interface LogitechButtonDiverter ()
@property NSMutableArray<MFLogiInterface *> *interfaces;
@property NSMutableArray<dispatch_block_t> *jobs;
@property NSThread *thread;
@property NSCondition *ready;
@property CFRunLoopRef loop;
@property IOHIDManagerRef manager;
@property BOOL draining, stopped, restoring;
@property (atomic) BOOL shutdown;
@end
static LogitechButtonDiverter *shared;
static BOOL exiting;
static const uint16_t sideCIDs[] = {0x53, 0x56};

@implementation LogitechButtonDiverter
+ (void)startWithEnabled:(BOOL)enabled {
    @synchronized(self) {
        if (!enabled || shared || exiting) return;
        shared = [self new];
        shared.interfaces = [NSMutableArray array]; shared.jobs = [NSMutableArray array];
        shared.ready = [NSCondition new];
        [shared.ready lock];
        shared.thread = [[NSThread alloc] initWithTarget:shared selector:@selector(threadMain) object:nil];
        shared.thread.name = @"com.nuebling.mac-mouse-fix.logitech-hidpp";
        [shared.thread start];
        while (!shared.loop) [shared.ready wait];
        [shared.ready unlock];
        [shared enqueue:^{ [shared setUpManager]; }];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidWakeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            [shared reverifySoon];
        }];
    }
}
+ (void)restoreNativeBehavior {
    LogitechButtonDiverter *s;
    @synchronized(self) { exiting = YES; s = shared; s.shutdown = YES; }
    if (!s) return;
    // Never run an overlapping sequence inside a request's nested run loop.
    NSCondition *done = [NSCondition new]; __block BOOL finished = NO;
    [done lock];
    [s enqueue:^{
        [s restoreAll];
        [done lock]; finished = YES; [done signal]; [done unlock];
    }];
    if (NSThread.currentThread != s.thread) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
        while (!finished && [done waitUntilDate:deadline]) {}
        if (!finished) NSLog(@"Logitech cleanup timed out; power-cycle mouse if needed");
    }
    [done unlock];
}
- (void)threadMain {
    @autoreleasepool {
        CFRunLoopSourceContext ctx = {0};
        CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &ctx);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes); CFRelease(source);
        CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(NULL, CFAbsoluteTimeGetCurrent()+30, 30, 0, 0, ^(CFRunLoopTimerRef t) {
            [self enqueue:^{ [self verifyAll]; }];
        });
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes); CFRelease(timer);
        [_ready lock]; _loop = CFRunLoopGetCurrent(); [_ready signal]; [_ready unlock];
    }
    while (true) { @autoreleasepool { CFRunLoopRun(); } }
}
// PR1995's queue guards against nested CFRunLoop request pumping reentrancy.
- (void)enqueue:(dispatch_block_t)job {
    @synchronized(_jobs) { [_jobs addObject:[job copy]]; }
    CFRunLoopPerformBlock(_loop, kCFRunLoopCommonModes, ^{ [self drain]; }); CFRunLoopWakeUp(_loop);
}
// A freshly (re)connected mouse may not answer yet. Retry shortly instead of waiting for the 30 s timer.
- (void)reverifySoon {
    [self enqueue:^{ [self verifyAll]; }];
    [self verifyAfter:1]; [self verifyAfter:3];
}
- (void)verifyAfter:(double)seconds {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self enqueue:^{ [self verifyAll]; }];
    });
}
- (void)drain {
    if (_draining) return;
    _draining = YES;
    while (true) {
        dispatch_block_t job;
        @synchronized(_jobs) { job = _jobs.firstObject; if (job) [_jobs removeObjectAtIndex:0]; }
        if (!job) break;
        @autoreleasepool { job(); }
    }
    _draining = NO;
}
// Receivers deliver mouse input through a sibling USB interface (same vendor/product/LocationID) with a
// mouse collection. Native events from the receiver resolve to that IOHIDDevice, so ours should too.
// 0 (-> StrangeDevice fallback) when missing or ambiguous. Candidates carry "MFRegistryID".
static uint64_t MFLogiMouseSibling(NSArray<NSDictionary *> *candidates, NSDictionary *vendor) {
    uint64_t found = 0;
    if (!vendor[@kIOHIDLocationIDKey]) return 0;
    for (NSDictionary *c in candidates) {
        BOOL same = YES;
        for (NSString *key in @[@kIOHIDVendorIDKey, @kIOHIDProductIDKey, @kIOHIDLocationIDKey]) same &= [c[key] isEqual:vendor[key]];
        BOOL mouse = NO;
        for (NSDictionary *pair in c[@kIOHIDDeviceUsagePairsKey])
            mouse |= [pair[@kIOHIDDeviceUsagePageKey] intValue] == 1 && [pair[@kIOHIDDeviceUsageKey] intValue] == 2;
        uint64_t rid = [c[@"MFRegistryID"] unsignedLongLongValue];
        if (!same || !mouse || !rid) continue;
        if (found && found != rid) return 0;
        found = rid;
    }
    return found;
}
static uint64_t receiverSenderID(IOHIDDeviceRef device) {
    NSArray *keys = @[@kIOHIDVendorIDKey, @kIOHIDProductIDKey, @kIOHIDLocationIDKey, @kIOHIDDeviceUsagePairsKey];
    NSMutableDictionary *vendor = [NSMutableDictionary dictionary];
    for (NSString *key in keys) [vendor setValue:(__bridge id)IOHIDDeviceGetProperty(device, (__bridge CFStringRef)key) forKey:key];
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(MACH_PORT_NULL, IOServiceMatching(kIOHIDDeviceKey), &it) != KERN_SUCCESS) return 0;
    NSMutableArray *candidates = [NSMutableArray array];
    for (io_service_t s; (s = IOIteratorNext(it)); IOObjectRelease(s)) {
        NSMutableDictionary *c = [NSMutableDictionary dictionary]; uint64_t rid = 0;
        for (NSString *key in keys) [c setValue:(__bridge_transfer id)IORegistryEntryCreateCFProperty(s, (__bridge CFStringRef)key, NULL, 0) forKey:key];
        if (IORegistryEntryGetRegistryEntryID(s, &rid) == KERN_SUCCESS) c[@"MFRegistryID"] = @(rid);
        [candidates addObject:c];
    }
    IOObjectRelease(it);
    return MFLogiMouseSibling(candidates, vendor);
}
static void matched(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    if (result) return;
    LogitechButtonDiverter *s = (__bridge id)context;
    CFRetain(device); [s enqueue:^{ [s addDevice:device]; CFRelease(device); }];
}
static void removed(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    LogitechButtonDiverter *s = (__bridge id)context;
    // Mark immediately so an in-flight activation cannot write to a disconnected device.
    for (MFLogiInterface *i in s.interfaces) if (i.device == device) {
        i.removed = YES;
        [s enqueue:^{
            for (MFLogiTarget *t in i.targets) [s releaseHeld:t mask:3];
            [s close:i]; [s.interfaces removeObjectIdenticalTo:i];
        }];
    }
}
- (void)setUpManager {
    if (_shutdown) return;
    _manager = IOHIDManagerCreate(NULL, kIOHIDManagerOptionNone);
    NSArray *match = @[
        @{@kIOHIDVendorIDKey:@0x046D, @kIOHIDDeviceUsagePageKey:@0xFF43, @kIOHIDDeviceUsageKey:@0x0202},
        @{@kIOHIDVendorIDKey:@0x046D, @kIOHIDDeviceUsagePageKey:@0xFF00, @kIOHIDDeviceUsageKey:@1},
        @{@kIOHIDVendorIDKey:@0x046D, @kIOHIDDeviceUsagePageKey:@0xFF00, @kIOHIDDeviceUsageKey:@2}];
    IOHIDManagerSetDeviceMatchingMultiple(_manager, (__bridge CFArrayRef)match);
    IOHIDManagerRegisterDeviceMatchingCallback(_manager, matched, (__bridge void *)self);
    IOHIDManagerRegisterDeviceRemovalCallback(_manager, removed, (__bridge void *)self);
    IOHIDManagerScheduleWithRunLoop(_manager, _loop, kCFRunLoopDefaultMode);
    IOReturn r = IOHIDManagerOpen(_manager, kIOHIDOptionsTypeNone);
    if (r) NSLog(@"Logitech HID++ manager open failed: %x", r);
}
static void input(void *context, IOReturn result, void *sender, IOHIDReportType type, uint32_t reportID, uint8_t *report, CFIndex length) {
    if (result || length < 0) return;
    MFLogiInterface *i = (__bridge id)context;
    uint8_t r[20]; size_t n = MFHIDPPNormalize(reportID, report, (size_t)length, r);
    if (!n || i.removed) return;
    if (i.waiting && MFHIDPPReply(r, n, i.pendingIndex, i.pendingFeature, i.command)) {
        memcpy(i->reply, r, 20); i.replyLength = n; i.answered = YES; return;
    }
    if (shared.shutdown || !i.open) return;
    for (MFLogiTarget *t in i.targets) if (t.index == r[1]) {
        if (i.receiver && r[2] == 0x41) {
            if (MFHIDPPReceiverLinkDown(r, n)) [shared enqueue:^{
                NSLog(@"Logitech receiver %04x slot %d disconnected", i.pid, t.index);
                [shared releaseHeld:t mask:3];
                // Slots can be reused. Never restore stale ownership onto a new mouse.
                [t.original removeAllObjects]; [t.confirmed removeAllObjects]; [t.foreign removeAllObjects];
                t.feature = 0; t.wireless = 0;
            }];
            else [shared reverifySoon];
        } else if (t.wireless && r[2] == t.wireless && !r[3]) {
            [shared reverifySoon];
        } else {
            uint8_t mask;
            if (MFHIDPPButtonSnapshot(r, n, t.index, t.feature, &mask)) [shared snapshot:mask target:t];
        }
    }
}
- (void)addDevice:(IOHIDDeviceRef)device {
    if (_shutdown) return;
    for (MFLogiInterface *i in _interfaces) if (i.device == device) return;
    MFLogiInterface *i = [MFLogiInterface new]; i.device = (IOHIDDeviceRef)CFRetain(device);
    uint16_t pid = [(__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey)) unsignedShortValue];
    i.pid = pid;
    i.receiver = pid == 0xC52B || pid == 0xC532 || pid == 0xC534 || pid == 0xC548 || pid == 0xC547;
    NSString *transport = (__bridge NSString *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDTransportKey));
    // Unknown USB receiver layouts (including C53F) are not treated as direct mice.
    if (!i.receiver && ![transport hasPrefix:@"Bluetooth"]) return;
    IOReturn opened = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
    if (opened) { NSLog(@"Logitech HID++ interface %04x (%@) open failed: %x", pid, transport, opened); return; }
    i.open = YES; [_interfaces addObject:i];
    IOHIDDeviceRegisterInputReportCallback(device, i->buffer, sizeof(i->buffer), input, (__bridge void *)i);
    IOHIDDeviceScheduleWithRunLoop(device, _loop, kCFRunLoopDefaultMode);
    uint64_t receiverSender = i.receiver ? receiverSenderID(device) : 0;
    for (int slot = 1; slot <= (i.receiver ? 6 : 1); slot++) {
        MFLogiTarget *t = [MFLogiTarget new]; t.index = i.receiver ? slot : 0xFF; t.senderID = receiverSender;
        // A receiver PID alone is NOT proof of the sender (see MFLogiMouseSibling for receivers).
        // Direct combined mouse collections alone have a known registry identity.
        NSArray *pairs = (__bridge NSArray *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDDeviceUsagePairsKey));
        if (!i.receiver) for (NSDictionary *pair in pairs) {
            if ([pair[@kIOHIDDeviceUsagePageKey] intValue] == 1 && [pair[@kIOHIDDeviceUsageKey] intValue] == 2) {
                uint64_t rid = 0; io_service_t service = IOHIDDeviceGetService(device);
                if (service && IORegistryEntryGetRegistryEntryID(service, &rid) == KERN_SUCCESS) t.senderID = rid;
            }
        }
        [i.targets addObject:t]; [self activate:t on:i];
    }
    // Reconnects (e.g. Bluetooth wake) re-add the interface before the mouse answers HID++.
    [self verifyAfter:1]; [self verifyAfter:3];
}
- (void)close:(MFLogiInterface *)i {
    if (!i.open) return;
    IOHIDDeviceRegisterInputReportCallback(i.device, i->buffer, sizeof(i->buffer), NULL, NULL);
    IOHIDDeviceUnscheduleFromRunLoop(i.device, _loop, kCFRunLoopDefaultMode);
    IOHIDDeviceClose(i.device, kIOHIDOptionsTypeNone); i.open = NO;
}
- (BOOL)request:(MFLogiInterface *)i target:(MFLogiTarget *)t feature:(uint8_t)feature function:(uint8_t)fn params:(const uint8_t *)p length:(size_t)n {
    assert(NSThread.currentThread == _thread);
    if (!i.open || i.removed || (_shutdown && !_restoring)) return NO;
    uint8_t packet[20] = {0x11, t.index, feature, 0};
    i.software = i.software % 15 + 1; i.command = (fn << 4) | i.software; packet[3] = i.command;
    if (n) memcpy(packet+4, p, MIN(n, 16));
    i.pendingIndex = t.index; i.pendingFeature = feature;
    i.waiting = YES; i.answered = NO; i.replyLength = 0;
    IOReturn err = IOHIDDeviceSetReport(i.device, kIOHIDReportTypeOutput, 0x11, packet, 20);
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent()+0.6;
    while (!err && !i.answered && !i.removed && (!_shutdown || _restoring) && CFAbsoluteTimeGetCurrent() < deadline)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.005, true);
    i.waiting = NO;
    return !err && i.answered && i->reply[2] != 0xFF;
}
- (uint8_t)feature:(uint16_t)fid target:(MFLogiTarget *)t on:(MFLogiInterface *)i {
    uint8_t p[] = {fid >> 8, fid & 255};
    return [self request:i target:t feature:0 function:0 params:p length:2] && i.replyLength >= 7 ? i->reply[4] : 0;
}
- (NSData *)reporting:(NSNumber *)cid target:(MFLogiTarget *)t on:(MFLogiInterface *)i {
    uint16_t c = cid.unsignedShortValue; uint8_t p[] = {c >> 8, c & 255};
    if (![self request:i target:t feature:t.feature function:2 params:p length:2] || !MFHIDPPReporting(i->reply, i.replyLength, c)) return nil;
    return [NSData dataWithBytes:i->reply+6 length:3];
}
- (BOOL)setDivert:(BOOL)divert cid:(NSNumber *)cid target:(MFLogiTarget *)t on:(MFLogiInterface *)i {
    uint16_t c = cid.unsignedShortValue;
    // remap=0 means unchanged; only temporary-diversion valid bit is set.
    uint8_t p[] = {c >> 8, c & 255, divert ? 3 : 2, 0, 0};
    BOOL ack = [self request:i target:t feature:t.feature function:3 params:p length:5] &&
        MFHIDPPReporting(i->reply, i.replyLength, c);
    NSData *now = [self reporting:cid target:t on:i];
    NSData *before = t.original[cid];
    return ack && before && now && MFHIDPPOwnership(before.bytes, now.bytes) == (divert ? 1 : 0);
}
- (void)activate:(MFLogiTarget *)t on:(MFLogiInterface *)i {
    if (_shutdown || !i.open || i.removed) return;
    if (!t.feature) {
        t.feature = [self feature:0x1B04 target:t on:i];
        if (!t.feature) return;
        t.wireless = [self feature:0x1D4B target:t on:i];
    }
    if (![self request:i target:t feature:t.feature function:0 params:NULL length:0] || i.replyLength < 7) return;
    int count = i->reply[4];
    for (int k = 0; k < count && !_shutdown; k++) {
        uint8_t p = k;
        if (![self request:i target:t feature:t.feature function:1 params:&p length:1] || i.replyLength < 9) continue;
        uint16_t c = i->reply[4] << 8 | i->reply[5]; NSNumber *cid = @(c);
        if (!MFHIDPPButtonBit(c) || !(i->reply[8] & 0x20) || t.original[cid] || [t.foreign containsObject:cid]) continue;
        NSData *now = [self reporting:cid target:t on:i];
        if (!now) continue;
        // A temporary diversion seen here is almost always our own leftover from a crash/SIGKILL; leaving it
        // would keep the button dead until a power cycle. Take it over and treat "not diverted" as original.
        // Persistent diversion (0x04) is untouched: our temporary bit overrides it and restore keeps it.
        uint8_t original[3]; memcpy(original, now.bytes, 3); original[0] &= ~1;
        // Record cleanup responsibility before the write, including lost-ACK cases.
        t.original[cid] = [NSData dataWithBytes:original length:3];
        if ([self setDivert:YES cid:cid target:t on:i]) {
            [t.confirmed addObject:cid];
            NSLog(@"Logitech acquired side CID %04x on %@ %04x index %02x", c, i.receiver ? @"receiver" : @"direct", i.pid, t.index);
        } else [self restore:cid target:t on:i];
    }
}
- (void)forget:(NSNumber *)cid target:(MFLogiTarget *)t {
    [self releaseHeld:t mask:MFHIDPPButtonBit(cid.unsignedShortValue)];
    [t.confirmed removeObject:cid]; [t.original removeObjectForKey:cid];
}
- (BOOL)restore:(NSNumber *)cid target:(MFLogiTarget *)t on:(MFLogiInterface *)i {
    NSData *before = t.original[cid], *now = [self reporting:cid target:t on:i];
    if (!before || !now) return NO;
    int state = MFHIDPPOwnership(before.bytes, now.bytes);
    if (state == 2) [t.foreign addObject:cid];
    else if (state == 1 && ![self setDivert:NO cid:cid target:t on:i]) return NO;
    [self forget:cid target:t]; return YES;
}
- (void)verifyAll {
    if (_shutdown) return;
    for (MFLogiInterface *i in [_interfaces copy]) if (i.receiver && !i.targets.firstObject.senderID) {
        // The receiver's mouse interface may have appeared after its HID++ interface.
        uint64_t sender = receiverSenderID(i.device);
        for (MFLogiTarget *t in i.targets) t.senderID = sender;
    }
    for (MFLogiInterface *i in [_interfaces copy]) for (MFLogiTarget *t in i.targets) {
        // Re-resolve after wake/reconnect; feature indexes need not survive a firmware reset.
        uint8_t feature = [self feature:0x1B04 target:t on:i];
        if (!feature) continue; // Sleeping/unsupported is not a button-up notification.
        t.feature = feature;
        t.wireless = [self feature:0x1D4B target:t on:i];
        for (NSNumber *cid in t.original.allKeys) {
            NSData *now = [self reporting:cid target:t on:i];
            if (!now) continue; // Unreachable is NOT evidence of release; preserve long holds.
            int state = MFHIDPPOwnership(t.original[cid].bytes, now.bytes);
            if (state == 2) { [t.foreign addObject:cid]; [self forget:cid target:t]; }
            else if (state == 0) {
                [self releaseHeld:t mask:MFHIDPPButtonBit(cid.unsignedShortValue)];
                [t.confirmed removeObject:cid];
                if ([self setDivert:YES cid:cid target:t on:i]) [t.confirmed addObject:cid];
            } else if (![t.confirmed containsObject:cid]) [self restore:cid target:t on:i];
        }
        // Retry absent/asleep devices and missing controls, without resetting held state.
        [self activate:t on:i];
    }
}
- (void)restoreAll {
    if (_stopped) return;
    _stopped = YES; _restoring = YES;
    // Release ALL held buttons before any potentially slow hardware cleanup.
    for (MFLogiInterface *i in _interfaces) for (MFLogiTarget *t in i.targets) [self releaseHeld:t mask:3];
    for (MFLogiInterface *i in _interfaces) {
        for (MFLogiTarget *t in i.targets) for (NSNumber *cid in t.original.allKeys)
            if (![self restore:cid target:t on:i]) NSLog(@"Logitech restoration unconfirmed CID %@; power-cycle mouse", cid);
        [self close:i];
    }
    [_interfaces removeAllObjects];
    if (_manager) {
        IOHIDManagerUnscheduleFromRunLoop(_manager, _loop, kCFRunLoopDefaultMode);
        IOHIDManagerClose(_manager, kIOHIDOptionsTypeNone); CFRelease(_manager); _manager = NULL;
    }
    _restoring = NO;
}
- (void)post:(uint16_t)cid down:(BOOL)down target:(MFLogiTarget *)t {
    CGEventRef location = CGEventCreate(NULL); if (!location) return;
    CGPoint point = CGEventGetLocation(location); CFRelease(location);
    CGEventRef e = CGEventCreateMouseEvent(NULL, down ? kCGEventOtherMouseDown : kCGEventOtherMouseUp, point, cid == 0x53 ? 3 : 4);
    if (!e) return;
    CGEventSetTimestamp(e, clock_gettime_nsec_np(CLOCK_UPTIME_RAW)); // ns, not Apple Silicon mach ticks
    CGEventSetIntegerValueField(e, kCGMouseEventPressure, down ? 1 : 0);
    CGEventSetIntegerValueField(e, kCGMouseEventClickState, 1);
    CGEventSetIntegerValueField(e, (CGEventField)kMFCGEventFieldSenderID, (int64_t)t.senderID);
    CGEventPost(kCGHIDEventTap, e); CFRelease(e);
}
- (void)snapshot:(uint8_t)mask target:(MFLogiTarget *)t {
    uint8_t owned = 0, held = t.held;
    for (NSNumber *cid in t.confirmed) owned |= MFHIDPPButtonBit(cid.unsignedShortValue);
    MFHIDPPEdges e = MFHIDPPTransition(&held, mask, owned); t.held = held;
    for (int k = 0; k < 2; k++) if (e.up & (1 << k)) [self post:sideCIDs[k] down:NO target:t];
    for (int k = 0; k < 2; k++) if (e.down & (1 << k)) [self post:sideCIDs[k] down:YES target:t];
}
- (void)releaseHeld:(MFLogiTarget *)t mask:(uint8_t)mask {
    uint8_t up = t.held & mask; t.held &= ~mask;
    for (int k = 0; k < 2; k++) if (up & (1 << k)) [self post:sideCIDs[k] down:NO target:t];
}
@end
