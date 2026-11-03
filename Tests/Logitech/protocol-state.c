// MMF License. Pure protocol/state regression tests; no hardware access.
#include "../../Helper/Core/Buttons/LogitechHIDPPState.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    uint8_t r[20] = {0x11, 0xFF, 9, 0, 0, 0x53, 0, 0x56}, out[20], mask;
    assert(MFHIDPPNormalize(0x11,r,20,out) == 20 && !memcmp(r,out,20));
    assert(MFHIDPPNormalize(0x11,r+1,19,out) == 20 && !memcmp(r,out,20));
    for (size_t n=0;n<19;n++) assert(!MFHIDPPNormalize(0x11,r,n,out));
    assert(!MFHIDPPNormalize(0x11,r,21,out));
    assert(!MFHIDPPNormalize(0x10,r,20,out));
    assert(MFHIDPPButtonSnapshot(r,20,0xFF,9,&mask) && mask==3);
    assert(!MFHIDPPButtonSnapshot(r,7,0xFF,9,&mask));
    assert(!MFHIDPPButtonSnapshot(r,20,1,9,&mask));
    r[1]=1; assert(MFHIDPPButtonSnapshot(r,20,1,9,&mask) && mask==3);
    r[5]=0xC3;r[7]=0xED; assert(MFHIDPPButtonSnapshot(r,20,1,9,&mask) && mask==0);
    r[5]=0x53;r[7]=0x53;assert(MFHIDPPButtonSnapshot(r,20,1,9,&mask) && mask==1);
    r[4]=1;r[6]=1;assert(MFHIDPPButtonSnapshot(r,20,1,9,&mask) && mask==0);
    uint8_t reply[20]={0x11,1,9,0x3C,0,0x53};
    assert(MFHIDPPReply(reply,20,1,9,0x3C));
    assert(!MFHIDPPReply(reply,20,2,9,0x3C));
    assert(!MFHIDPPReply(reply,20,1,9,0x3D));
    assert(!MFHIDPPReporting(reply,7,0x53));
    assert(MFHIDPPReporting(reply,20,0x53));
    assert(!MFHIDPPReporting(reply,20,0x56));
    uint8_t error[7]={0x10,1,0xFF,0,9,0x3C,1};
    assert(MFHIDPPNormalize(0x10,error,7,out)==7);
    assert(MFHIDPPNormalize(0x10,error+1,6,out)==7);
    assert(MFHIDPPReply(error,7,1,9,0x3C));
    // Receiver deviceConnection: link flag is byte 4; wpid bytes 5-6 must not matter.
    uint8_t link[7]={0x10,1,0x41,0x04,0x02,0x40,0xB0};
    assert(!MFHIDPPReceiverLinkDown(link,7));
    link[4]=0x42;link[5]=0x2A;assert(MFHIDPPReceiverLinkDown(link,7));
    assert(!MFHIDPPReceiverLinkDown(link,6));
    uint8_t before[3]={0x10,0x12,0x34}, now[3]={0x11,0x12,0x34};
    assert(MFHIDPPOwnership(before,before)==0);
    assert(MFHIDPPOwnership(before,now)==1);
    now[2]++;assert(MFHIDPPOwnership(before,now)==2);
    for (int a=0;a<4;a++) for(int b=0;b<4;b++) for(int c=0;c<4;c++) {
        uint8_t held=a; MFHIDPPEdges e=MFHIDPPTransition(&held,b,c);
        assert(held==(b&c) && e.up==(a&~(b&c)) && e.down==((b&c)&~a));
    }
    uint8_t held=3;
    for(int k=0;k<10000;k++) { MFHIDPPEdges e=MFHIDPPTransition(&held,3,3);assert(!e.up&&!e.down); }
    puts("PASS protocol: framing, slot/CID/reply matching, side-only snapshots, receiver link flag, ownership and 64 transitions");
}
