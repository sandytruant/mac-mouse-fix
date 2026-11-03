import argparse
import pathlib
import shutil
import tempfile
from common import run, sign, pair, LOCAL

parser = argparse.ArgumentParser(description='Build only; never install or launch MMF')
parser.add_argument('--output', default='~/Downloads/MMF-local-signing', help='New directory; existing paths always refused')
args = parser.parse_args()
out = pathlib.Path(args.output).expanduser().absolute()
if out.exists() or out.is_symlink():
    raise SystemExit('Output already exists; choose a new --output (nothing overwritten)')
root = pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='mmf-local-build-') as temporary:
    temp = pathlib.Path(temporary)
    src = temp / 'source'
    src.mkdir()
    # Do NOT use git archive or gitignore filters: vendored/untracked dependencies are needed.
    excludes = ['.git', '.env', '.env.*', '*.env', 'DerivedData', 'derivedData',
                'derived-data', '.build', '__pycache__', '*.p12', '*.pfx', '*.key', '*.pem']
    command = ['rsync', '-a']
    for pattern in excludes:
        command += ['--exclude', pattern]
    if out.is_relative_to(root):
        command += ['--exclude', '/' + str(out.relative_to(root))]
    run(*command, str(root) + '/', str(src) + '/')
    derived = temp / 'DerivedData'
    run('xcodebuild', '-project', src / 'Mouse Fix.xcodeproj', '-scheme', 'App - Release',
        '-configuration', 'Release', '-derivedDataPath', derived, 'build',
        'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO',
        'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_ENTITLEMENTS=',
        'ENABLE_HARDENED_RUNTIME=NO', 'OTHER_CFLAGS=$(inherited) -DMF_LOCAL_SIGNING=1')
    app = derived / 'Build/Products/Release/Mac Mouse Fix.app'
    # Refuse to publish unless both SecureStorage translation units received the macro.
    for target in ('Mac Mouse Fix', 'Mac Mouse Fix Helper'):
        intermediates = derived / f'Build/Intermediates.noindex/Mouse Fix.build/Release/{target}.build'
        responses = list(intermediates.rglob('*.resp'))
        if not any('MF_LOCAL_SIGNING=1' in p.read_text() for p in responses):
            raise RuntimeError(f'Cannot confirm local macro for {target}; inspect build response files')
    for p in app.rglob('embedded.provisionprofile'):
        p.unlink()
    # Sign Mach-O leaves first, then every enclosing code bundle deepest-first.
    magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
             b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf'}
    paths = sorted(app.rglob('*'), key=lambda p: len(p.parts), reverse=True)
    for p in paths:
        if p.is_symlink() or not p.is_file():
            continue
        with p.open('rb') as f:
            if f.read(4) in magic:
                sign(p)
    for p in paths:
        if not p.is_symlink() and p.is_dir() and p.suffix in ('.app', '.framework', '.xpc', '.bundle'):
            sign(p)
    sign(app)
    pair(app.resolve(), LOCAL)
    out.mkdir(parents=True, exist_ok=False)
    shutil.copytree(app, out / app.name, symlinks=True)
    pair((out / app.name).resolve(), LOCAL)
print(f'Built (not installed or launched): {out / app.name}')
