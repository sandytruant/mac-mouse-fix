"""Local-only signing utilities. No keychain commands and no data logging."""
import pathlib
import plistlib
import subprocess

LOCAL = '14EB9D19918E3A3A798CD7D51146682867175B10'
DEV = 'D29CA5D4DF876EB1B717FE43629A7FB219615BF6'
BUNDLE = 'com.andysun.mac-mouse-fix.dev'
HELPER = 'Contents/Library/LoginItems/Mac Mouse Fix Helper.app'


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def app_path(path):
    # Standard /Applications is admin-group writable. Do not reject normal
    # installation locations; pair() verifies the actual code identity below.
    p = pathlib.Path(path).expanduser().resolve()
    if not p.is_dir():
        raise RuntimeError('App directory does not exist')
    return p


def verify(app, identity, identifier):
    requirement = f'identifier "{identifier}" and certificate leaf = H"{identity}"'
    # codesign interprets a requirement as a filename unless prefixed with '='.
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', '-R', '=' + requirement, app)


def pair(app, identity):
    app = app_path(app)
    helper = app_path(app / HELPER)
    verify(app, identity, BUNDLE)
    verify(helper, identity, BUNDLE + '.helper')
    if identity == LOCAL:
        if list(app.rglob('embedded.provisionprofile')):
            raise RuntimeError('Local bundle must not contain provisioning profiles')
        for bundle in (app, helper):
            raw = run('/usr/bin/codesign', '-d', '--entitlements', ':-', bundle,
                      stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
            entitlements = plistlib.loads(raw) if raw.strip() else {}
            if entitlements:
                raise RuntimeError('Local app/helper must have no entitlements')
            detail = run('/usr/bin/codesign', '-dv', bundle, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE).stderr
            if b'runtime' in detail:
                raise RuntimeError('Local hardened runtime must be disabled')
    return app, helper


def executable(app):
    with open(app / 'Contents/Info.plist', 'rb') as f:
        name = plistlib.load(f)['CFBundleExecutable']
    p = app / 'Contents/MacOS' / name
    if p.resolve() != p or not p.is_file() or '/' in name:
        raise RuntimeError('Invalid executable path')
    return p


def stopped():
    # Check all users; never kill anything. Conservative false positives are safe.
    output = run('/bin/ps', '-axo', 'comm=', stdout=subprocess.PIPE).stdout.decode()
    if any('Mac Mouse Fix' in line for line in output.splitlines()):
        raise RuntimeError('Stop old AND local Mac Mouse Fix app/helper before migration; no process was killed')


def sign(path, identity=LOCAL, entitlements=None):
    args = ['/usr/bin/codesign', '--force', '--sign', identity, '--timestamp=none']
    if identity == LOCAL:
        args += ['--options', '0']
    if entitlements:
        args += ['--entitlements', str(entitlements)]
    run(*args, path)
