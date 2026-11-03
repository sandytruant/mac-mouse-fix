import argparse
import pathlib
import shutil
import subprocess
import tempfile

LOCAL = '14EB9D19918E3A3A798CD7D51146682867175B10'  # SHA-1 of the "andysun Local Code Signing" certificate


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def sign(path):
    run('/usr/bin/codesign', '--force', '--sign', LOCAL, '--timestamp=none', '--options', '0', path)


parser = argparse.ArgumentParser(description='Build and locally sign Mac Mouse Fix (arm64)')
parser.add_argument('--output', default='~/Downloads/MMF-local-signing')
args = parser.parse_args()
out = pathlib.Path(args.output).expanduser().absolute()
root = pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='mmf-local-build-') as temporary:
    temp = pathlib.Path(temporary)
    # Build from a copy so the Release build-number bump doesn't touch the working tree.
    # Not `git archive`: vendored/untracked dependencies are needed.
    src = temp / 'source'
    run('rsync', '-a', '--exclude', '.git', '--exclude', 'DerivedData', str(root) + '/', str(src) + '/')
    derived = temp / 'DerivedData'
    run('xcodebuild', '-project', src / 'Mouse Fix.xcodeproj', '-scheme', 'App - Release',
        '-configuration', 'Release', '-derivedDataPath', derived, 'build',
        'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO',
        'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_ENTITLEMENTS=',
        'ENABLE_HARDENED_RUNTIME=NO', 'OTHER_CFLAGS=$(inherited) -DMF_LOCAL_SIGNING=1')
    app = derived / 'Build/Products/Release/Mac Mouse Fix.app'
    # Without the macro, SecureStorage would silently use the shared keychain group, which needs a profile.
    for target in ('Mac Mouse Fix', 'Mac Mouse Fix Helper'):
        intermediates = derived / f'Build/Intermediates.noindex/Mouse Fix.build/Release/{target}.build'
        if not any('MF_LOCAL_SIGNING=1' in p.read_text() for p in intermediates.rglob('*.resp')):
            raise RuntimeError(f'MF_LOCAL_SIGNING did not reach {target}')
    for p in app.rglob('embedded.provisionprofile'):
        p.unlink()
    # Sign Mach-O files first, then enclosing bundles deepest-first, then the app.
    magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
             b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf'}
    paths = sorted(app.rglob('*'), key=lambda p: len(p.parts), reverse=True)
    for p in paths:
        if p.is_file() and not p.is_symlink():
            with p.open('rb') as f:
                if f.read(4) in magic:
                    sign(p)
    for p in paths:
        if p.is_dir() and not p.is_symlink() and p.suffix in ('.app', '.framework', '.xpc', '.bundle'):
            sign(p)
    sign(app)
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    out.mkdir(parents=True, exist_ok=True)
    shutil.copytree(app, out / app.name, symlinks=True)
print(f'Built: {out / app.name}')
