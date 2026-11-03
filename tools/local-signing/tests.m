// Fake Security transport: this binary never calls a real keychain API.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <assert.h>
static NSData *stored;
static int cursor, creates, updates;
static BOOL aclChecked;
static OSStatus readFailure;
static OSStatus searchCreate(CFTypeRef k, SecItemClass c, const SecKeychainAttributeList *a, SecKeychainSearchRef *s) {
    assert(a->count == 2 && a->attr[0].tag == kSecServiceItemAttr && a->attr[1].tag == kSecAccountItemAttr);
    cursor = 0; *s = (SecKeychainSearchRef)CFBridgingRetain(@"search"); return 0;
}
static OSStatus searchNext(SecKeychainSearchRef s, SecKeychainItemRef *i) {
    if (!stored || cursor++) return errSecItemNotFound;
    *i = (SecKeychainItemRef)CFBridgingRetain(@"item"); return 0;
}
static OSStatus copyContent(SecKeychainItemRef i, SecItemClass *c, SecKeychainAttributeList *a, UInt32 *n, void **b) {
    if (readFailure) return readFailure;
    *n = (UInt32)stored.length; *b = malloc(*n); memcpy(*b, stored.bytes, *n); return 0;
}
static OSStatus freeContent(SecKeychainAttributeList *a, void *b) { free(b); return 0; }
static OSStatus modify(SecKeychainItemRef i, const SecKeychainAttributeList *a, UInt32 n, const void *b) {
    updates++; stored = [NSData dataWithBytes:b length:n]; return 0;
}
static OSStatus fakeTrusted(const char *p, SecTrustedApplicationRef *a) {
    assert(p && p[0] == '/'); *a = (SecTrustedApplicationRef)CFBridgingRetain(@(p)); return 0;
}
static OSStatus accessCreate(CFStringRef label, CFArrayRef apps, SecAccessRef *a) {
    assert(CFArrayGetCount(apps) == 2); aclChecked = YES;
    *a = (SecAccessRef)CFBridgingRetain(@"explicit ACL"); return 0;
}
static OSStatus createItem(SecItemClass c, const SecKeychainAttributeList *a, UInt32 n, const void *b, SecKeychainRef k, SecAccessRef access, SecKeychainItemRef *i) {
    assert(access && aclChecked); creates++;
    if (stored) return errSecDuplicateItem;
    stored = [NSData dataWithBytes:b length:n]; return 0;
}
static OSStatus openKeychain(const char *p, SecKeychainRef *k) {
    assert(strcmp(p, "/fake-only/test.keychain-db") == 0);
    *k = (SecKeychainRef)CFBridgingRetain(@"fake keychain"); return 0;
}
#define SecKeychainOpen openKeychain
#define SecKeychainSearchCreateFromAttributes searchCreate
#define SecKeychainSearchCopyNext searchNext
#define SecKeychainItemCopyContent copyContent
#define SecKeychainItemFreeContent freeContent
#define SecKeychainItemModifyContent modify
#define SecTrustedApplicationCreateFromPath fakeTrusted
#define SecAccessCreate accessCreate
#define SecKeychainItemCreateFromContent createItem
#define MF_LOCAL_KEYCHAIN_TEST_PATH "/fake-only/test.keychain-db"
#import "../../Shared/Config/SecureStorage/LocalKeychain.h"
static void testBundleCreation(SecKeychainRef keychain, NSData *data) {
    assert(MFLocalCreateForCurrentApplication(keychain, data) == 0);
    assert(creates == 1 && aclChecked);
    assert(MFLocalCreateForCurrentApplication(keychain, data) == errSecDuplicateItem);
    stored = nil; creates = 0;
}
static OSStatus createForTest(SecKeychainRef keychain, NSData *data) {
    return MFLocalCreate(keychain, data, @[@"/fake-only/App", @"/fake-only/Helper"]);
}
static void checkQuery(CFDictionaryRef q) {
    NSDictionary *query = (__bridge NSDictionary *)q;
    assert([query[(__bridge id)kSecAttrSynchronizable] isEqual:@YES]);
    assert([query[(__bridge id)kSecAttrLabel] isEqual:@"com.andysun.mac-mouse-fix.dev.secure-storage"]);
}
static OSStatus normalRead(CFDictionaryRef q, CFTypeRef *result) {
    checkQuery(q);
    if (readFailure) return readFailure;
    if (!stored) return errSecItemNotFound;
    *result = CFBridgingRetain(stored); return 0;
}
static OSStatus normalUpdate(CFDictionaryRef q, CFDictionaryRef attributes) {
    checkQuery(q);
    if (!stored) return errSecItemNotFound;
    updates++; stored = ((__bridge NSDictionary *)attributes)[(__bridge id)kSecValueData]; return 0;
}
static OSStatus normalAdd(CFDictionaryRef q, CFTypeRef *result) {
    checkQuery(q);
    if (stored) return errSecDuplicateItem;
    creates++; stored = ((__bridge NSDictionary *)q)[(__bridge id)kSecValueData]; return 0;
}
#define MFLocalCreateForCurrentApplication createForTest
#define SecItemCopyMatching normalRead
#define SecItemUpdate normalUpdate
#define SecItemAdd normalAdd
#import "../../Shared/Config/SecureStorage/SecureStorage.m"

int main(void) { @autoreleasepool {
    SecKeychainRef keychain = NULL;
    assert(MFLocalOpen(&keychain) == 0);
    NSData *data = nil;
    assert(MFLocalRead(keychain, &data) == errSecItemNotFound && !data);
    NSData *original = [NSKeyedArchiver archivedDataWithRootObject:@{@"test": @42} requiringSecureCoding:NO error:NULL];
    testBundleCreation(keychain, original);
    assert(MFLocalUpdate(keychain, original) == errSecItemNotFound);
    assert(creates == 0 && updates == 0);
    NSArray *apps = @[@"/fake-only/App", @"/fake-only/Helper"];
    assert(MFLocalCreate(keychain, original, apps) == 0 && aclChecked);
    assert([stored isEqualToData:original]);
    assert(MFLocalCreate(keychain, original, apps) == errSecDuplicateItem && creates == 1);
    assert(MFLocalRead(keychain, &data) == 0 && [data isEqualToData:original]);
    NSData *changed = [NSKeyedArchiver archivedDataWithRootObject:@{@"test": @43} requiringSecureCoding:NO error:NULL];
    assert(MFLocalUpdate(keychain, changed) == 0 && [stored isEqualToData:changed]);
    assert(!MFLocalValidArchive([NSData data]));
    CFRelease(keychain);
    stored = nil; creates = updates = 0;
    NSMutableDictionary *dict = nil;
    SecureStorageReadError error = readSecureStorage(@"test", &dict);
    assert(error == kSecureStorageReadError_DoesntExistYet && dict && dict.count == 0);
    assert(creates == 0 && updates == 0 && !stored);
    dict[@"test"] = @42;
    assert(writeSecureStorage(@"test", dict, error) && creates == 1);
    NSData *saved = stored;
    dict[@"test"] = @43;
    assert(!writeSecureStorage(@"test", dict, error));
    assert([stored isEqual:saved] && creates == 1);
    error = readSecureStorage(@"test", &dict);
    assert(error == kSecureStorageReadError_ReadSuccessful && [dict[@"test"] isEqual:@42]);
    dict[@"test"] = @43;
    assert(writeSecureStorage(@"test", dict, error) && updates == 1);
    assert(readSecureStorage(@"test", &dict) == 0 && [dict[@"test"] isEqual:@43]);
    readFailure = errSecAuthFailed;
    assert(readSecureStorage(@"test", &dict) == kSecureStorageReadError_UnexpectedError && !dict);
    readFailure = 0;
    stored = [NSKeyedArchiver archivedDataWithRootObject:@"not a dictionary" requiringSecureCoding:NO error:NULL];
    assert(readSecureStorage(@"test", &dict) == kSecureStorageReadError_UnexpectedError && !dict);
    stored = nil;
    assert(writeSecureStorage(@"test", [@{@"test": @44} mutableCopy], kSecureStorageReadError_ReadSuccessful));
    assert(creates == 2); // Update missing -> add, only on an explicit write.
    puts("Production SecureStorage API + fake transport passed (no real keychain accessed)");
} }
