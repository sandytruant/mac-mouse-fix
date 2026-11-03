#import "../../Shared/Config/SecureStorage/LocalKeychain.h"
#include <unistd.h>

// Only the optional migration CLI terminates on failure; production returns OSStatus.
__attribute__((noreturn)) static void MFLocalFatal(const char *operation, OSStatus status) {
    fprintf(stderr, "MMF migration: %s failed (%d). No source data changed.\n", operation, (int)status);
    _exit(78);
}

// Defense in depth: do not let direct CLI invocation grant trust to unrelated code.
static void validateTarget(NSString *path, NSString *identifier) {
    if (![path isAbsolutePath] || ![[path stringByResolvingSymlinksInPath] isEqualToString:path])
        MFLocalFatal("target canonical path", errSecParam);
    SecStaticCodeRef code = NULL;
    OSStatus s = SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:path], kSecCSDefaultFlags, &code);
    if (s) MFLocalFatal("target code", s);
    NSString *text = [NSString stringWithFormat:@"identifier \"%@\" and certificate leaf = H\"14EB9D19918E3A3A798CD7D51146682867175B10\"", identifier];
    SecRequirementRef requirement = NULL;
    s = SecRequirementCreateWithString((__bridge CFStringRef)text, kSecCSDefaultFlags, &requirement);
    if (!s) s = SecStaticCodeCheckValidity(code, kSecCSStrictValidate, requirement);
    if (requirement) CFRelease(requirement);
    CFRelease(code);
    if (s) MFLocalFatal("target signing identity", s);
}

// Invoked only inside the Apple Development-signed Migration.app prepared by migrate.sh.
int main(int argc, const char **argv) {
    @autoreleasepool { @try {
        if (argc != 3) MFLocalFatal("arguments (app/helper executables required)", errSecParam);
        validateTarget(@(argv[1]), @"com.andysun.mac-mouse-fix.dev");
        validateTarget(@(argv[2]), @"com.andysun.mac-mouse-fix.dev.helper");
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrSynchronizable: @YES,
            (__bridge id)kSecAttrLabel: @"com.andysun.mac-mouse-fix.dev.secure-storage",
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnData: @YES
        };
        CFTypeRef result = NULL;
        OSStatus s = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        if (s) MFLocalFatal("source query (initialize using normal build first if absent)", s);
        id items = CFBridgingRelease(result);
        if (![items isKindOfClass:NSArray.class] || [items count] != 1)
            MFLocalFatal("source must be unique", errSecDuplicateItem);
        NSData *bytes = items[0];
        if (![bytes isKindOfClass:NSData.class] || !MFLocalValidArchive(bytes))
            MFLocalFatal("source archive validation", errSecDecode);
        SecKeychainRef keychain = NULL;
        s = MFLocalOpen(&keychain);
        if (s) MFLocalFatal("destination open", s);
        s = MFLocalCreate(keychain, bytes, @[@(argv[1]), @(argv[2])]);
        CFRelease(keychain);
        if (s) MFLocalFatal("destination create (never overwrite)", s);
        fprintf(stderr, "Migration created local item; source untouched. No data printed or readback ACL granted.\n");
        return 0;
    } @catch (NSException *e) { MFLocalFatal("migration exception", errSecDecode); } }
}
