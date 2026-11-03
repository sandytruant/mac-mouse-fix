import argparse
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
from common import run, pair, executable, stopped, sign, verify, LOCAL, DEV, BUNDLE

parser = argparse.ArgumentParser(description='Explicit one-time migration; never deletes/overwrites source or destination')
parser.add_argument('--source-app', required=True, help='Valid original Apple Development-signed app, with embedded profile')
parser.add_argument('--local-app', required=True, help='Local-signed app at its FINAL trusted location')
parser.add_argument('--confirm-migration', action='store_true', required=True)
args = parser.parse_args()
stopped()
source, source_helper = pair(pathlib.Path(args.source_app).expanduser().resolve(), DEV)
local, local_helper = pair(pathlib.Path(args.local_app).expanduser().resolve(), LOCAL)
root = pathlib.Path(__file__).resolve().parents[2]
profile = source / 'Contents/embedded.provisionprofile'
if not profile.is_file():
    raise SystemExit('Original embedded provisioning profile is required')
# Extract actual signed entitlements, not project template substitutions.
entitlements = run('/usr/bin/codesign', '-d', '--entitlements', ':-', source,
                   stdout=subprocess.PIPE).stdout
parsed = plistlib.loads(entitlements)
if not parsed.get('keychain-access-groups'):
    raise SystemExit('Original signed app has no keychain access groups')
with tempfile.TemporaryDirectory(prefix='mmf-migration-') as temporary:
    temp = pathlib.Path(temporary)
    app = temp / 'Migration.app'
    contents = app / 'Contents'
    macos = contents / 'MacOS'
    macos.mkdir(parents=True)
    tool = macos / 'Migration'
    run('xcrun', 'clang', '-arch', 'arm64', '-fobjc-arc', '-framework', 'Foundation',
        '-framework', 'Security', root / 'tools/local-signing/migrate.m', '-o', tool)
    with (contents / 'Info.plist').open('wb') as f:
        plistlib.dump({'CFBundleIdentifier': BUNDLE, 'CFBundleExecutable': 'Migration',
                       'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1'}, f)
    shutil.copyfile(profile, contents / 'embedded.provisionprofile')
    ent = temp / 'entitlements.plist'
    ent.write_bytes(entitlements)
    sign(app, DEV, ent)
    verify(app, DEV, BUNDLE)
    # Recheck immediately before touching either store. No launch/kill of MMF.
    pair(source, DEV)
    pair(local, LOCAL)
    stopped()
    run(tool, executable(local), executable(local_helper))
# Temporary Migration.app and entitlements removed even on failure.
