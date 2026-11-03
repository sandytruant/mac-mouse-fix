// Local signing only: no provisioning profile -> no shared keychain group, so SecureStorage lives in the login keychain.
#pragma once
#import <Foundation/Foundation.h>
#import <Security/Security.h>

static const char MFLocalService[] = "com.andysun.mac-mouse-fix.local.secure-storage.v1";
static const char MFLocalAccount[] = "archive";

static OSStatus MFLocalOpen(SecKeychainRef *keychain) {
#ifdef MF_LOCAL_KEYCHAIN_TEST_PATH
    NSString *path = @MF_LOCAL_KEYCHAIN_TEST_PATH;
#else
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Keychains/login.keychain-db"];
#endif
    return SecKeychainOpen(path.fileSystemRepresentation, keychain);
}

static OSStatus MFLocalFind(SecKeychainRef keychain, SecKeychainItemRef *item) {
    *item = NULL;
    SecKeychainAttribute attrs[] = {
        {kSecServiceItemAttr, sizeof(MFLocalService)-1, (void *)MFLocalService},
        {kSecAccountItemAttr, sizeof(MFLocalAccount)-1, (void *)MFLocalAccount}
    };
    SecKeychainAttributeList list = {2, attrs};
    SecKeychainSearchRef search = NULL;
    OSStatus s = SecKeychainSearchCreateFromAttributes(keychain, kSecGenericPasswordItemClass, &list, &search);
    if (s) return s;
    s = SecKeychainSearchCopyNext(search, item);
    CFRelease(search);
    return s;
}

static OSStatus MFLocalRead(SecKeychainRef keychain, NSData **data) {
    *data = nil;
    SecKeychainItemRef item = NULL;
    OSStatus s = MFLocalFind(keychain, &item);
    if (s) return s;
    UInt32 length = 0; void *bytes = NULL;
    s = SecKeychainItemCopyContent(item, NULL, NULL, &length, &bytes);
    if (!s) {
        *data = [NSData dataWithBytes:bytes length:length];
        SecKeychainItemFreeContent(NULL, bytes);
    }
    CFRelease(item);
    return s;
}

static OSStatus MFLocalUpdate(SecKeychainRef keychain, NSData *data) {
    SecKeychainItemRef item = NULL;
    OSStatus s = MFLocalFind(keychain, &item);
    if (s) return s; // SecureStorage falls back to its add path.
    s = SecKeychainItemModifyContent(item, NULL, (UInt32)data.length, data.bytes);
    CFRelease(item);
    return s;
}

// ACL trusts exactly the App and the Helper, so neither triggers a keychain prompt.
static OSStatus MFLocalCreate(SecKeychainRef keychain, NSData *data, NSArray<NSString *> *executables) {
    NSMutableArray *trusted = [NSMutableArray array];
    for (NSString *path in executables) {
        SecTrustedApplicationRef app = NULL;
        OSStatus s = SecTrustedApplicationCreateFromPath(path.fileSystemRepresentation, &app);
        if (s) return s;
        [trusted addObject:CFBridgingRelease(app)];
    }
    SecAccessRef access = NULL;
    OSStatus s = SecAccessCreate(CFSTR("MMF local secure storage"), (__bridge CFArrayRef)trusted, &access);
    if (s) return s;
    SecKeychainAttribute attrs[] = {
        {kSecServiceItemAttr, sizeof(MFLocalService)-1, (void *)MFLocalService},
        {kSecAccountItemAttr, sizeof(MFLocalAccount)-1, (void *)MFLocalAccount}
    };
    SecKeychainAttributeList list = {2, attrs};
    s = SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass, &list,
        (UInt32)data.length, data.bytes, keychain, access, NULL);
    CFRelease(access);
    return s;
}

static OSStatus MFLocalCreateForCurrentApplication(SecKeychainRef keychain, NSData *data) {
    NSURL *app = NSBundle.mainBundle.bundleURL;
    if ([NSBundle.mainBundle.bundleIdentifier hasSuffix:@".helper"]) // Helper.app -> LoginItems -> Library -> Contents -> App
        for (int i = 0; i < 4; i++) app = app.URLByDeletingLastPathComponent;
    NSString *appExecutable = [NSBundle bundleWithURL:app].executablePath;
    NSString *helperExecutable = [NSBundle bundleWithURL:[app URLByAppendingPathComponent:@"Contents/Library/LoginItems/Mac Mouse Fix Helper.app"]].executablePath;
    if (!appExecutable || !helperExecutable) return errSecParam;
    return MFLocalCreate(keychain, data, @[appExecutable, helperExecutable]);
}
