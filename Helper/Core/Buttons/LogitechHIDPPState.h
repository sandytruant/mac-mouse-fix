// Mac Mouse Fix — licensed under the MMF License.
// Framing/state approach informed by PR #2094; side-button-only policy.
#ifndef MF_LOGITECH_HIDPP_STATE_H
#define MF_LOGITECH_HIDPP_STATE_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>
static inline size_t MFHIDPPNormalize(uint32_t id, const uint8_t *in, size_t n, uint8_t out[20]) {
    size_t expected = id == 0x11 ? 20 : id == 0x10 ? 7 : 0;
    if (!in || !expected) return 0;
    memset(out, 0, 20);
    if (n == expected && in[0] == id) memcpy(out, in, n);
    else if (n == expected - 1) { out[0] = (uint8_t)id; memcpy(out + 1, in, n); }
    else return 0;
    return expected;
}
static inline uint8_t MFHIDPPButtonBit(uint16_t cid) { return cid == 0x53 ? 1 : cid == 0x56 ? 2 : 0; }
static inline bool MFHIDPPReply(const uint8_t *r, size_t n, uint8_t device, uint8_t feature, uint8_t command) {
    if (!r || (n != 7 && n != 20) || r[1] != device || !(command & 15)) return false;
    return (r[2] == feature && r[3] == command) ||
           (r[2] == 0xFF && r[4] == feature && r[5] == command);
}
static inline bool MFHIDPPReporting(const uint8_t *r, size_t n, uint16_t cid) {
    return n >= 9 && r[4] == (cid >> 8) && r[5] == (cid & 255);
}
// HID++1 receiver deviceConnection (0x41): protocol at 3, flags at 4 (bit 6 = link not established), wpid at 5-6.
static inline bool MFHIDPPReceiverLinkDown(const uint8_t *r, size_t n) {
    return r && n >= 7 && (r[4] & 0x40);
}
static inline bool MFHIDPPButtonSnapshot(const uint8_t *r, size_t n, uint8_t device, uint8_t feature, uint8_t *mask) {
    if (!r || n != 20 || r[0] != 0x11 || r[1] != device || !feature || r[2] != feature || r[3]) return false;
    *mask = 0;
    for (size_t i = 4; i < 12; i += 2) *mask |= MFHIDPPButtonBit((uint16_t)(r[i] << 8 | r[i+1]));
    return true;
}
typedef struct { uint8_t up, down; } MFHIDPPEdges;
static inline MFHIDPPEdges MFHIDPPTransition(uint8_t *held, uint8_t snapshot, uint8_t owned) {
    uint8_t next = snapshot & owned;
    MFHIDPPEdges e = { (uint8_t)(*held & ~next), (uint8_t)(next & ~*held) };
    *held = next;
    return e;
}
// 0 = original; 1 = our temporary diversion; 2 = foreign change.
static inline int MFHIDPPOwnership(const uint8_t before[3], const uint8_t now[3]) {
    if (!memcmp(before, now, 3)) return 0;
    uint8_t expected[3]; memcpy(expected, before, 3); expected[0] |= 1;
    return !memcmp(expected, now, 3) ? 1 : 2;
}
#endif
