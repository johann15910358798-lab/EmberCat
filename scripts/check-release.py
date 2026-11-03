#!/usr/bin/env python3
"""Validate a locally prepared release against its signed application bundle."""
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import sys
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
REPO_URL = 'https://github.com/johann15910358798-lab/EmberCat'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check(folder):
    app = ROOT / 'dist/EmberCat.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    source = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    require(info == source, 'Build Info.plist does not match the source configuration')
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    require(info['SUFeedURL'] == f'{REPO_URL}/releases/latest/download/appcast.xml', 'Unexpected update feed')
    require(len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32, 'Invalid public key')
    require(info['SURequireSignedFeed'] and info['SUVerifyUpdateBeforeExtraction'], 'Signing checks must be enabled')

    items = ET.parse(folder / 'appcast.xml').findall('./channel/item')
    require(len(items) == 1, 'This release feed must contain exactly the prepared version')
    item = items[0]
    require(item.findtext(SPARKLE + 'version') == build, 'Appcast build mismatch')
    require(item.findtext(SPARKLE + 'shortVersionString') == version, 'Appcast version mismatch')
    require(item.findtext(SPARKLE + 'minimumSystemVersion') == info['LSMinimumSystemVersion'], 'Minimum macOS mismatch')
    enclosure = item.find('enclosure')
    require(enclosure is not None, 'Missing update enclosure')
    name = f'EmberCat-{version}'
    archive = folder / f'{name}.zip'
    require(enclosure.attrib['url'] == f'{REPO_URL}/releases/download/v{version}/{name}.zip', 'Unexpected download URL')
    require(int(enclosure.attrib['length']) == archive.stat().st_size, 'Archive length mismatch')
    require(len(base64.b64decode(enclosure.attrib[SPARKLE + 'edSignature'], validate=True)) == 64, 'Invalid EdDSA signature encoding')

    checksums = {}
    for line in (folder / 'SHA256SUMS.txt').read_text().splitlines():
        digest, filename = line.split(maxsplit=1)
        require(filename in [f'{name}.dmg', f'{name}.zip', 'appcast.xml'], 'Unexpected checksum filename')
        with (folder / filename).open('rb') as file:
            actual = hashlib.file_digest(file, 'sha256').hexdigest()
        require(actual == digest, f'Checksum mismatch: {filename}')
        checksums[filename] = actual
    require(len(checksums) == 3, 'Missing release checksums')

    expected = {}
    for base, directories, files in os.walk(app, followlinks=False):
        for entry in directories + files:
            path = Path(base) / entry
            if path.is_symlink() or path.is_file():
                expected['EmberCat.app/' + path.relative_to(app).as_posix()] = path
    verified = set()
    with ZipFile(archive) as zipped:
        for entry in zipped.infolist():
            if entry.is_dir() or entry.filename.startswith('__MACOSX/'):
                continue
            require(entry.filename in expected and entry.filename not in verified,
                    f'Unexpected or duplicate archive member: {entry.filename}')
            path = expected[entry.filename]
            data = zipped.read(entry)
            mode = entry.external_attr >> 16
            require(stat.S_ISLNK(mode) == path.is_symlink(), f'Symlink type mismatch: {entry.filename}')
            original = os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
            require(hashlib.sha256(data).digest() == hashlib.sha256(original).digest(),
                    f'Archived contents differ: {entry.filename}')
            verified.add(entry.filename)
    require(verified == expected.keys(), 'Archive is missing bundle files')
    return {'passed': True, 'version': version, 'build': build,
            'bundleFilesAndLinksVerified': len(verified), 'checksums': checksums,
            'scope': 'local package and metadata; cryptographic verification uses Sparkle sign_update; no publication implied'}


if __name__ == '__main__':
    try:
        print(json.dumps(check(Path(sys.argv[1]).resolve()), indent=2))
    except (IndexError, KeyError, ValueError, OSError, ET.ParseError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
