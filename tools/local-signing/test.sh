#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
# Compile the actual production implementation with only infrastructure stubbed.
python3 - "$tmp" <<'PY'
from pathlib import Path
import sys, plistlib
p = Path(sys.argv[1])
for bundle, identifier in (
    (p / 'Fixture.app', 'com.andysun.mac-mouse-fix.dev'),
    (p / 'Fixture.app/Contents/Library/LoginItems/Helper.app', 'com.andysun.mac-mouse-fix.dev.helper'),
):
    (bundle / 'Contents/MacOS').mkdir(parents=True)
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'probe', 'CFBundlePackageType': 'APPL',
    }))
(p / 'Logging.h').write_text('#define DDLogDebug(...) ((void)0)\n#define DDLogError(...) ((void)0)\n')
(p / 'Threads.h').write_text('#define assertRunLoop(...) ((void)0)\n')
(p / 'Constants.h').write_text('''#include <assert.h>
#define MFErrorDomain @"test"
#define isclass(value, cls) [(value) isKindOfClass:[cls class]]
#define mfrequire(condition, ...) assert(condition)
''')
for source in Path('.').glob('*.py'):
    compile(source.read_text(), str(source), 'exec')
PY
for local in 0 1; do
    xcrun clang -fobjc-arc -Wno-deprecated-declarations -I "$tmp" \
        -DMF_LOCAL_SIGNING="$local" -DIS_MAIN_APP=1 \
        -framework Foundation -framework Security tests.m -o "$tmp/tests-$local"
    app="$tmp/Fixture.app/Contents/MacOS/probe"
    helper="$tmp/Fixture.app/Contents/Library/LoginItems/Helper.app/Contents/MacOS/probe"
    cp "$tmp/tests-$local" "$app"
    cp "$tmp/tests-$local" "$helper"
    "$app"
    "$helper"
done
# Compile real bundle-resolution and migration code; no app build or launch.
xcrun clang -fobjc-arc -Wno-deprecated-declarations -framework Foundation -framework Security -fsyntax-only migrate.m
