// Local signing only: file-keychain storage. Never selects the default keychain.
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

// Enumerate to reject ambiguity rather than updating an arbitrary matching item.
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
    if (!s) {
        SecKeychainItemRef extra = NULL;
        OSStatus next = SecKeychainSearchCopyNext(search, &extra);
        if (extra) CFRelease(extra);
        if (next != errSecItemNotFound) {
            CFRelease(*item); *item = NULL;
            s = next ? next : errSecDuplicateItem;
        }
    }
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
    if (s) return s; // Creation is the caller's explicit add path.
    s = SecKeychainItemModifyContent(item, NULL, (UInt32)data.length, data.bytes);
    CFRelease(item);
    return s;
}

static BOOL MFLocalValidArchive(NSData *data) {
    @try {
        NSError *error = nil;
        NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
        u.requiresSecureCoding = NO; // Same archive format as SecureStorage; never reserialize during migration.
        id value = [u decodeTopLevelObjectForKey:NSKeyedArchiveRootObjectKey error:&error];
        return !error && [value isKindOfClass:NSDictionary.class];
    } @catch (NSException *e) { return NO; }
}

// An explicit trusted list grants only App and Helper access, not all applications.
// Never pass NULL or an empty trusted list; existing items are never replaced.
static OSStatus MFLocalCreate(SecKeychainRef keychain, NSData *data, NSArray<NSString *> *executables) {
    SecKeychainItemRef existing = NULL;
    OSStatus s = MFLocalFind(keychain, &existing);
    if (existing) CFRelease(existing);
    if (s != errSecItemNotFound) return s ?: errSecDuplicateItem;
    if (executables.count != 2 || !MFLocalValidArchive(data)) return errSecParam;
    NSMutableArray *trusted = [NSMutableArray array];
    for (NSString *path in executables) {
        SecTrustedApplicationRef app = NULL;
        s = SecTrustedApplicationCreateFromPath(path.fileSystemRepresentation, &app);
        if (s) return s;
        [trusted addObject:CFBridgingRelease(app)];
    }
    SecAccessRef access = NULL;
    s = SecAccessCreate(CFSTR("MMF local secure storage"), (__bridge CFArrayRef)trusted, &access);
    if (s) return s;
    SecKeychainAttribute attrs[] = {
        {kSecServiceItemAttr, sizeof(MFLocalService)-1, (void *)MFLocalService},
        {kSecAccountItemAttr, sizeof(MFLocalAccount)-1, (void *)MFLocalAccount}
    };
    SecKeychainAttributeList list = {2, attrs};
    s = SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass, &list,
        (UInt32)data.length, data.bytes, keychain, access, NULL);
    CFRelease(access);
    return s; // No readback: a migration CLI creator is not in the trusted list.
}

static OSStatus MFLocalCreateForCurrentApplication(SecKeychainRef keychain, NSData *data) {
    NSBundle *current = NSBundle.mainBundle;
    NSString *mainID = @"com.andysun.mac-mouse-fix.dev";
    NSString *helperID = [mainID stringByAppendingString:@".helper"];
    NSURL *mainURL = current.bundleURL;
    if ([current.bundleIdentifier isEqualToString:helperID]) {
        // Helper.app -> LoginItems -> Library -> Contents -> Main.app
        for (int i = 0; i < 4; i++) mainURL = mainURL.URLByDeletingLastPathComponent;
    } else if (![current.bundleIdentifier isEqualToString:mainID]) return errSecParam;
    NSBundle *main = [NSBundle bundleWithURL:mainURL];
    if (![main.bundleIdentifier isEqualToString:mainID]) return errSecParam;
    NSURL *loginItems = [mainURL URLByAppendingPathComponent:@"Contents/Library/LoginItems" isDirectory:YES];
    NSArray<NSURL *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtURL:loginItems
        includingPropertiesForKeys:nil options:0 error:NULL];
    NSBundle *helper = nil;
    for (NSURL *url in children) {
        NSBundle *candidate = [NSBundle bundleWithURL:url];
        if ([candidate.bundleIdentifier isEqualToString:helperID]) {
            if (helper) return errSecDuplicateItem;
            helper = candidate;
        }
    }
    if (!helper || ([current.bundleIdentifier isEqualToString:helperID] &&
        ![helper.bundleURL.URLByResolvingSymlinksInPath isEqual:current.bundleURL.URLByResolvingSymlinksInPath])) return errSecParam;
    NSString *appExecutable = main.executablePath;
    NSString *helperExecutable = helper.executablePath;
    if (!appExecutable || !helperExecutable ||
        ![NSFileManager.defaultManager isExecutableFileAtPath:appExecutable] ||
        ![NSFileManager.defaultManager isExecutableFileAtPath:helperExecutable]) return errSecParam;
    return MFLocalCreate(keychain, data, @[appExecutable, helperExecutable]);
}
