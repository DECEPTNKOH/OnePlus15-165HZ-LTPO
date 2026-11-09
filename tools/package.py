#!/usr/bin/env python3
"""Build a preview ZIP after checks. Never includes arbitrary module files."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import zipfile
import zlib

ID = 'OnePlus15-165HZ-LTPO'
FILES = (
    'module.prop', 'customize.sh', 'post-fs-data.sh', 'service.sh', 'vrrd.sh',
    'lifecycle.sh', 'settings-state.sh', 'uninstall.sh', 'action.sh', 'diag.sh',
    'scan_camera_pkgs.sh', 'camera_pkgs.default', 'vrr.conf', 'xmlguard.sh',
    'sed/force.sed', 'sed/respect.sed', 'bin/xmlguard.jar',
    'META-INF/com/google/android/update-binary',
    'META-INF/com/google/android/updater-script',
)

def read_file(root, path):
    p = root / path
    p.resolve().relative_to(root)
    if p.is_symlink() or not p.is_file():
        raise ValueError('missing/unsafe file: ' + path)
    data = p.read_bytes()
    if not data:
        raise ValueError('empty file: ' + path)
    return data

def check_jar(data):
    import io
    if len(data) > 4 * 1024 * 1024:
        raise ValueError('JAR too large')
    with zipfile.ZipFile(io.BytesIO(data)) as jar:
        names = jar.namelist()
        if len(set(names)) != len(names) or names.count('classes.dex') != 1:
            raise ValueError('missing/duplicate classes.dex')
        if any(n not in ('META-INF/', 'META-INF/MANIFEST.MF', 'classes.dex') for n in names):
            raise ValueError('unexpected JAR entry')
        info = jar.getinfo('classes.dex')
        if info.file_size > 4 * 1024 * 1024:
            raise ValueError('DEX too large')
        dex = jar.read('classes.dex')
    if len(dex) < 112 or not re.fullmatch(rb'dex\n0[0-9]{2}\x00', dex[:8]):
        raise ValueError('invalid DEX magic/header')
    size, header, endian = struct.unpack_from('<III', dex, 32)
    if size != len(dex) or header not in (112, 120) or endian != 0x12345678:
        raise ValueError('inconsistent DEX header')
    count, offset = struct.unpack_from('<II', dex, 96)
    if count < 1 or offset < header or offset + count * 32 > len(dex):
        raise ValueError('DEX class table missing/out of bounds')
    if hashlib.sha1(dex[32:]).digest() != dex[12:32]:
        raise ValueError('DEX signature mismatch')
    if (zlib.adler32(dex[12:]) & 0xffffffff) != struct.unpack_from('<I', dex, 8)[0]:
        raise ValueError('DEX checksum mismatch')

def metadata(data):
    props = {}
    for line in data.decode('utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        key, sep, value = line.partition('=')
        if not sep or key in props:
            raise ValueError('invalid/duplicate module.prop field')
        props[key] = value
    if any(not props.get(k) for k in ('id', 'name', 'version', 'versionCode', 'author', 'description')):
        raise ValueError('required module.prop field missing')
    if props.get('id') != ID or not re.fullmatch(r'v[0-9]+[.][0-9]+[.][0-9]+-preview[.][0-9]+', props.get('version', '')):
        raise ValueError('wrong module ID or non-preview version')
    if not props.get('versionCode', '').isdigit() or int(props['versionCode']) <= 10800:
        raise ValueError('versionCode must exceed v1.8')
    if 'updateJson' in props:
        raise ValueError('preview must not enable automatic updates')
    return props

def create(root, revision, output=None):
    root = Path(root).resolve()
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('source revision must be a full commit SHA')
    payload = {name: read_file(root, 'module/' + name) for name in FILES}
    payload['LICENSE'] = read_file(root, 'LICENSE')
    payload['PREVIEW.md'] = read_file(root, 'docs/preview-build.md')
    props = metadata(payload['module.prop'])
    check_jar(payload['bin/xmlguard.jar'])
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in sorted(payload.items())}
    manifest = {
        'source_repository': 'https://github.com/DECEPTNKOH/OnePlus15-165HZ-LTPO',
        'source_revision': revision, 'version': props['version'], 'sha256': hashes,
        'status': 'preview; device boot validation pending',
    }
    payload['BUILD-MANIFEST.json'] = (json.dumps(manifest, indent=2, ensure_ascii=False) + '\n').encode()
    checks = {name: hashlib.sha256(data).hexdigest() for name, data in sorted(payload.items())
              if not name.startswith('META-INF/')}
    payload['SHA256SUMS'] = ''.join(digest + '  ' + name + '\n' for name, digest in checks.items()).encode()
    output = Path(output) if output else root / 'dist' / (ID + '-' + props['version'] + '.zip')
    output = output.resolve()
    if output == root or root in output.parents and output.parts[len(root.parts):len(root.parts)+1] == ('module',):
        raise ValueError('output must not overwrite module inputs')
    if output.exists():
        raise ValueError('output already exists; move it aside before rebuilding')
    output.parent.mkdir(parents=True, exist_ok=True)
    tmp = output.with_name(output.name + '.tmp')
    if tmp.exists():
        raise ValueError('temporary output already exists')
    try:
        with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, data in sorted(payload.items()):
                entry = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
                entry.create_system = 3
                mode = 0o444 if name == 'bin/xmlguard.jar' else 0o755 if name.endswith('.sh') or name.endswith('/update-binary') else 0o644
                entry.external_attr = (0o100000 | mode) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, data)
        with zipfile.ZipFile(tmp) as archive:
            if archive.testzip() or set(archive.namelist()) != set(payload):
                raise ValueError('archive integrity/list mismatch')
            for name, digest in hashes.items():
                if hashlib.sha256(archive.read(name)).hexdigest() != digest:
                    raise ValueError('archive content mismatch: ' + name)
        os.replace(tmp, output)
    finally:
        if tmp.exists(): tmp.unlink()
    return output

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-revision', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    subprocess.run(['sh', str(root/'tests/all.sh')], check=True)
    out = create(root, args.source_revision)
    print('PREVIEW_ZIP_READY')
    print(out)
    print(hashlib.sha256(out.read_bytes()).hexdigest())

if __name__ == '__main__': main()
