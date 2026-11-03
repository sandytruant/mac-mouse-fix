#!/usr/bin/env python3
"""Opt-in real Security API test, ONLY in a disposable keychain with fabricated data.

Does not open login.keychain-db or read any MMF/license records. Creates a temporary
keychain, restores the original search list immediately, and deletes the test
keychain on exit. Three signed processes model migration/App/Helper. UI prompts
are disabled in the probes so missing ACL access fails rather than asking users
for broader permissions.
"""
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
from common import run, sign, DEV, LOCAL

root = pathlib.Path(__file__).resolve().parents[2]
source = r'''
#import "LocalKeychain.h"
#include <stdlib.h>
static void check(OSStatus s, const char *operation) {
    if (s) { fprintf(stderr, "%s: %d\n", operation, (int)s); exit(1); }
}
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc < 3) return 2;
    check(SecKeychainSetUserInteractionAllowed(false), "disable UI");
    NSString *mode = @(argv[1]);
    SecKeychainRef keychain = NULL;
    if ([mode isEqual:@"create"] || [mode isEqual:@"create-current"]) {
        if (argc != 5) return 2;
        CFArrayRef search = NULL;
        check(SecKeychainCopySearchList(&search), "save search list");
        OSStatus created = SecKeychainCreate(argv[2], 15, "fixture-only-pw", false, NULL, &keychain);
        OSStatus restored = SecKeychainSetSearchList(search);
        CFRelease(search);
        check(restored, "restore search list"); check(created, "create disposable keychain");
        NSData *bytes = [NSKeyedArchiver archivedDataWithRootObject:@{@"fixture": @42} requiringSecureCoding:NO error:NULL];
        if ([mode isEqual:@"create-current"])
            check(MFLocalCreateForCurrentApplication(keychain, bytes), "create fixture from current bundle with explicit ACL");
        else
            check(MFLocalCreate(keychain, bytes, @[@(argv[3]), @(argv[4])]), "create fixture with explicit ACL");
        if (MFLocalCreate(keychain, bytes, @[@(argv[3]), @(argv[4])]) != errSecDuplicateItem) return 3;
    } else {
        check(SecKeychainOpen(argv[2], &keychain), "open disposable keychain");
        if ([mode isEqual:@"delete"]) {
            check(SecKeychainDelete(keychain), "delete disposable keychain");
        } else {
            NSData *bytes = nil; check(MFLocalRead(keychain, &bytes), "read fixture");
            NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:bytes error:NULL];
            u.requiresSecureCoding = NO;
            NSDictionary *value = [u decodeTopLevelObjectForKey:NSKeyedArchiveRootObjectKey error:NULL];
            int expected = [mode isEqual:@"read-after-update"] ? 43 : 42;
            if (![value isKindOfClass:NSDictionary.class] || [value[@"fixture"] intValue] != expected) return 4;
            if ([mode isEqual:@"update"]) {
                NSData *updated = [NSKeyedArchiver archivedDataWithRootObject:@{@"fixture": @43} requiringSecureCoding:NO error:NULL];
                check(MFLocalUpdate(keychain, updated), "update fixture");
            }
        }
    }
    CFRelease(keychain);
    return 0;
} }
'''
with tempfile.TemporaryDirectory(prefix='mmf-disposable-keychain-') as temporary:
    temp = pathlib.Path(temporary).resolve()
    src = temp / 'probe.m'
    src.write_text(source)
    base = temp / 'probe'
    run('xcrun', 'clang', '-fobjc-arc', '-Wno-deprecated-declarations',
        '-I', root / 'Shared/Config/SecureStorage', '-framework', 'Foundation',
        '-framework', 'Security', src, '-o', base)
    main_bundle = temp / 'Fixture.app'
    helper_bundle = main_bundle / 'Contents/Library/LoginItems/Helper.app'
    for bundle, identifier in ((main_bundle, 'com.andysun.mac-mouse-fix.dev'),
                               (helper_bundle, 'com.andysun.mac-mouse-fix.dev.helper')):
        (bundle / 'Contents/MacOS').mkdir(parents=True)
        (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'probe', 'CFBundlePackageType': 'APPL',
        }))
    migration = temp / 'migration'
    app = main_bundle / 'Contents/MacOS/probe'
    helper = helper_bundle / 'Contents/MacOS/probe'
    for target, identity in ((migration, DEV), (helper, LOCAL), (app, LOCAL)):
        shutil.copyfile(base, target)
        target.chmod(0o700)
        sign(target, identity)
    keychain = temp / 'fixture.keychain-db'
    try:
        run(migration, 'create', keychain, app, helper, timeout=20)
        run(app, 'read', keychain, timeout=20)
        run(helper, 'update', keychain, timeout=20)
        run(app, 'read-after-update', keychain, timeout=20)
        run(migration, 'delete', keychain, timeout=20)
        run(app, 'create-current', keychain, app, helper, timeout=20)
        run(helper, 'read', keychain, timeout=20)
        run(helper, 'update', keychain, timeout=20)
        run(app, 'read-after-update', keychain, timeout=20)
        run(migration, 'delete', keychain, timeout=20)
        run(helper, 'create-current', keychain, app, helper, timeout=20)
        run(app, 'read', keychain, timeout=20)
        print('PASS: disposable-keychain migration/App/Helper creation, explicit ACL and cross-process read/update; no user records accessed')
    finally:
        if keychain.exists():
            run(migration, 'delete', keychain, timeout=20)
