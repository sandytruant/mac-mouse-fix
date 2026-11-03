// MMF License. Compile the production implementation with a fake transport.
// No manager/device is opened, no event is posted, no configuration is read.
#import <CoreGraphics/CoreGraphics.h>
#include <assert.h>
static CGEventRef captured;
static void capture(CGEventTapLocation tap, CGEventRef event) {
    assert(tap == kCGHIDEventTap);
    if (captured) CFRelease(captured);
    captured = CGEventCreateCopy(event);
}
#define CGEventPost capture
#import "../../Helper/Core/Buttons/LogitechButtonDiverter.m"
#undef CGEventPost
@interface Fake : LogitechButtonDiverter
@property NSMutableDictionary<NSNumber *, NSData *> *states;
@property NSMutableArray<NSString *> *edges;
@property BOOL asleep, lostAck, shortReply, wrongCID;
@property int writes;
@end
@implementation Fake
- (instancetype)init {
    if ((self=[super init])) { self.interfaces=[NSMutableArray array]; _states=[NSMutableDictionary dictionary]; _edges=[NSMutableArray array]; }
    return self;
}
- (BOOL)request:(MFLogiInterface *)i target:(MFLogiTarget *)t feature:(uint8_t)f function:(uint8_t)fn params:(const uint8_t *)p length:(size_t)n {
    if (_asleep) return NO;
    memset(i->reply,0,20); i.replyLength=20;
    if (!f) { i->reply[4]=p[0]==0x1B?9:10;return YES; }
    if (!fn) { i->reply[4]=3;return YES; }
    if (fn==1) { const uint16_t cids[]={0x53,0x56,0xC3}; i->reply[5]=cids[*p]; i->reply[8]=0x20;return YES; }
    NSNumber *cid=@(p[0]<<8|p[1]);
    uint8_t state[3]={0x10,0x12,0x34}; if(_states[cid]) memcpy(state,_states[cid].bytes,3);
    i->reply[4]=p[0]; i->reply[5]=p[1];
    if(fn==3) {
        assert(n==5 && (p[2]==2||p[2]==3) && !p[3]&&!p[4]);
        state[0]=(state[0]&~1)|(p[2]&1); _states[cid]=[NSData dataWithBytes:state length:3];_writes++;
        if(_lostAck && (p[2]&1)) return NO;
    }
    memcpy(i->reply+6,state,3);
    if(_shortReply) i.replyLength=7;
    if(_wrongCID) i->reply[5]^=1;
    return YES;
}
- (void)post:(uint16_t)cid down:(BOOL)down target:(MFLogiTarget *)t { [_edges addObject:[NSString stringWithFormat:@"%x:%d",cid,down]]; }
- (void)close:(MFLogiInterface *)i { i.open=NO; }
@end
static MFLogiTarget *setup(Fake *d, MFLogiInterface **out) {
    MFLogiInterface *i=[MFLogiInterface new];i.open=YES;
    MFLogiTarget *t=[MFLogiTarget new];t.index=0xFF;
    [i.targets addObject:t];[d.interfaces addObject:i];*out=i;return t;
}
static void change(Fake *d, NSNumber *cid, uint8_t flags) {
    uint8_t state[]={flags,0x12,0x34}; d.states[cid]=[NSData dataWithBytes:state length:3];
}
int main(void) { @autoreleasepool {
    MFLogiInterface *i; Fake *d=[Fake new];MFLogiTarget *t=setup(d,&i);
    [d activate:t on:i];assert(t.confirmed.count==2 && t.original.count==2 && d.writes==2 && !d.states[@0xC3]);
    [d snapshot:3 target:t];assert(t.held==3 && d.edges.count==2);
    for(int k=0;k<3;k++) [d verifyAll];assert(t.held==3 && d.edges.count==2 && d.writes==2);
    d.asleep=YES;[d verifyAll];assert(t.held==3 && d.edges.count==2);
    d.asleep=NO;change(d,@0x56,0x10);[d verifyAll];
    assert(t.held==1 && t.confirmed.count==2 && d.edges.count==3 && d.writes==3); // second control only
    [d snapshot:3 target:t];assert(t.held==3);
    change(d,@0x53,0x21);[d verifyAll];assert(t.held==2 && ![t.confirmed containsObject:@0x53]);
    int writes=d.writes;[d restoreAll];assert(!i.open && t.held==0 && d.writes==writes+1);
    [d restoreAll];assert(d.writes==writes+1);
    // Leftover temporary diversion (crash/SIGKILL) is taken over and cleared on exit; persistent bit is kept.
    d=[Fake new];t=setup(d,&i);change(d,@0x53,0x11);change(d,@0x56,0x15);[d activate:t on:i];
    assert(t.confirmed.count==2 && ((const uint8_t *)t.original[@0x53].bytes)[0]==0x10);[d restoreAll];
    assert(((const uint8_t *)d.states[@0x53].bytes)[0]==0x10 && ((const uint8_t *)d.states[@0x56].bytes)[0]==0x14);
    d=[Fake new];t=setup(d,&i);d.lostAck=YES;[d activate:t on:i];
    assert(!t.original.count && !t.confirmed.count && d.writes==4); // accepted writes rolled back
    d=[Fake new];t=setup(d,&i);d.shortReply=YES;[d activate:t on:i];assert(!d.writes);
    d=[Fake new];t=setup(d,&i);d.wrongCID=YES;[d activate:t on:i];assert(!d.writes);
    d=[Fake new];t=setup(d,&i);d.asleep=YES;[d activate:t on:i];assert(!t.feature);
    d.asleep=NO;[d verifyAll];assert(t.confirmed.count==2);
    [d snapshot:3 target:t];[d releaseHeld:t mask:3];assert(!t.held && d.edges.count==4);
    d.shutdown=YES;writes=d.writes;[d verifyAll];[d activate:t on:i];assert(d.writes==writes);
    // Receiver sender: sibling mouse interface of the same USB device (values from a real C548 + C53F setup).
    NSDictionary *(^hid)(int, int, int, NSArray *) = ^(int pid, int loc, int rid, NSArray *pairs) {
        NSMutableArray *p=[NSMutableArray array];
        for (NSArray *u in pairs) [p addObject:@{@kIOHIDDeviceUsagePageKey:u[0], @kIOHIDDeviceUsageKey:u[1]}];
        return @{@kIOHIDVendorIDKey:@0x46D, @kIOHIDProductIDKey:@(pid), @kIOHIDLocationIDKey:@(loc), @kIOHIDDeviceUsagePairsKey:p, @"MFRegistryID":@(rid)};
    };
    NSDictionary *bolt=hid(0xC548,18087936,0xefe,@[@[@0xFF00,@1],@[@0xFF00,@2]]);
    NSMutableArray *all=[@[bolt, hid(0xC548,18087936,0xf07,@[@[@1,@6]]),
        hid(0xC548,18087936,0xf03,@[@[@1,@2],@[@1,@1],@[@12,@1]]), hid(0xC548,18087936,0xef9,@[@[@13,@5]]),
        hid(0xC53F,18022400,0x1684,@[@[@1,@2]]), hid(0xC548,99,0x999,@[@[@1,@2]])] mutableCopy];
    assert(MFLogiMouseSibling(all,bolt)==0xf03);
    assert(!MFLogiMouseSibling(all,@{@kIOHIDVendorIDKey:@0x46D,@kIOHIDProductIDKey:@0xC548}));      // no LocationID
    [all addObject:hid(0xC548,18087936,0xf10,@[@[@1,@2]])];assert(!MFLogiMouseSibling(all,bolt)); // ambiguous
    LogitechButtonDiverter *real=[LogitechButtonDiverter new];t.senderID=1234;
    [real post:0x53 down:YES target:t];
    assert(CGEventGetIntegerValueField(captured,kCGMouseEventButtonNumber)==3);
    assert(CGEventGetIntegerValueField(captured,kCGMouseEventPressure)==1);
    assert(CGEventGetIntegerValueField(captured,(CGEventField)87)==1234);
    assert(CGEventGetTimestamp(captured)>0);
    [real post:0x56 down:NO target:t];
    assert(CGEventGetIntegerValueField(captured,kCGMouseEventButtonNumber)==4);
    assert(CGEventGetIntegerValueField(captured,kCGMouseEventPressure)==0);
    CFRelease(captured);
    // Exercise actual worker queue + bounded normal-context shutdown, without a HID manager.
    d=[Fake new];t=setup(d,&i);[d activate:t on:i];[d snapshot:3 target:t];
    d.jobs=[NSMutableArray array];d.ready=[NSCondition new];
    [d.ready lock];d.thread=[[NSThread alloc] initWithTarget:d selector:@selector(threadMain) object:nil];
    [d.thread start];while(!d.loop) [d.ready wait];[d.ready unlock];
    shared=d;
    [LogitechButtonDiverter restoreNativeBehavior];
    assert(d.stopped && !i.open && !t.held && d.edges.count==4);
    writes=d.writes;[LogitechButtonDiverter restoreNativeBehavior];assert(d.writes==writes);
    // Shutdown before deferred startup must not start new hardware work.
    [LogitechButtonDiverter startWithEnabled:YES];assert(shared==d);
    puts("PASS lifecycle: ownership, remap preservation, lost ACK rollback, both-control verification, long hold/timeouts, retry, foreign diversion, crash-leftover takeover, receiver sender mapping, cleanup, pressure/sender/timestamp");
} }
