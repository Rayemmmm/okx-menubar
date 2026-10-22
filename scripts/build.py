#!/usr/bin/env python3
"""Build locally; never inspect account configuration or change an installed app."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--node', default=shutil.which('node'), help='Node.js 20+ executable')
parser.add_argument('--skip-install', action='store_true', help='Use previously installed locked dependencies')
args = parser.parse_args()
if sys.platform != 'darwin':
    raise SystemExit('This AppKit app must be built on macOS.')
if not args.node or not Path(args.node).is_file():
    raise SystemExit('Install Node.js 20+ first, or pass --node /absolute/path/to/node.')
node = Path(args.node).resolve()
version = subprocess.check_output([str(node), '--version'], text=True).strip()
if int(version.lstrip('v').split('.')[0]) < 20:
    raise SystemExit('Node.js 20 or later is required.')
runtime = root / 'Resources/runtime'
if not args.skip_install:
    npm = shutil.which('npm') or str(node.parent / 'npm')
    subprocess.run([npm, 'ci', '--ignore-scripts', '--no-audit', '--no-fund', '--prefix', str(runtime)], check=True)
if not (runtime / 'node_modules/@okx_ai/okx-trade-mcp/dist/index.js').is_file():
    raise SystemExit('Pinned official MCP dependency is missing; run npm ci first.')

build = root / 'build'
build.mkdir(exist_ok=True)
app = build / 'OKX ReadOnly.app'
if app.exists():
    if not app.is_dir() or app.is_symlink():
        raise SystemExit('Unexpected build output path; stopped.')
    shutil.rmtree(app)
contents = app / 'Contents'
(contents / 'MacOS').mkdir(parents=True)
resources = contents / 'Resources'
shutil.copytree(root / 'Resources', resources)
shutil.copy2(node, resources / 'runtime/node')
icon_dir = build / 'icon-png'
module_cache = build / 'swift-module-cache'
subprocess.run(['swiftc', '-swift-version', '5', '-O', '-framework', 'AppKit',
                '-module-cache-path', str(module_cache), str(root / 'Sources/main.swift'),
                '-o', str(contents / 'MacOS/OKXReadOnly')], check=True)
subprocess.run([str(contents / 'MacOS/OKXReadOnly'), '--self-test'], check=True)
subprocess.run(['swiftc', '-framework', 'AppKit', '-module-cache-path', str(module_cache),
                str(root / 'scripts/make-icon.swift'), '-o', str(build / 'make-icon')], check=True)
subprocess.run([str(build / 'make-icon'), str(icon_dir)], check=True)
iconset = build / 'OKXReadOnly.iconset'
iconset.mkdir(exist_ok=True)
for size in [16, 32, 128, 256, 512]:
    shutil.copy2(icon_dir / f'{size}.png', iconset / f'icon_{size}x{size}.png')
    shutil.copy2(icon_dir / f'{size*2}.png', iconset / f'icon_{size}x{size}@2x.png')
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(resources / 'OKXReadOnly.icns')], check=True)
info = {
    'CFBundleExecutable': 'OKXReadOnly', 'CFBundleIdentifier': 'io.github.rayemmmm.okxreadonly',
    'CFBundleName': 'OKX ReadOnly', 'CFBundleDisplayName': 'OKX ReadOnly',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.0.0',
    'CFBundleVersion': '1', 'CFBundleIconFile': 'OKXReadOnly.icns',
    'LSMinimumSystemVersion': '13.0', 'LSUIElement': True, 'NSHighResolutionCapable': True,
}
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print('Built: ' + str(app))
