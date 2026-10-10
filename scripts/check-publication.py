#!/usr/bin/env python3
"""Check Git's index and optional history without printing sensitive values."""
import argparse
import re
import subprocess
import sys

BLOCKED_PARTS = {
    b'.opencode', b'.sisyphus', b'.claude', b'.omc', b'.superpowers',
    b'.vercel', b'node_modules', b'.next', b'.dart_tool', b'__pycache__',
    b'.venv', b'build', b'target', b'tmp',
}
BLOCKED_NAMES = {
    b'opencode.json', b'local.properties', b'key.properties', b'BACKLOG.md',
    b'id_rsa', b'id_ed25519',
}
BLOCKED_SUFFIXES = (b'.jks', b'.keystore', b'.p12', b'.pfx', b'.apk', b'.ipa',
                    b'.so', b'.dylib', b'.a', b'.log', b'.gitbundle')
BLOCKED_PREFIXES = (b'docs/planning/', b'docs/tickets/', b'docs/findings/',
                    b'audit/', b'apps/website/todos/')
CONTENT_RULES = {
    'personal home path': re.compile(rb'/(?:Users|home)/[A-Za-z0-9_.-]+(?:/|\b)'),
    'private network address': re.compile(rb'\b(?:192\.168|10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b'),
    'personal email provider': re.compile(rb'\b[A-Za-z0-9._%+-]+@(?:gmail|qq|163|outlook|hotmail)\.com\b',re.I),
    'private key envelope': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
}
SAFE_EMAIL = re.compile(rb'(?:[^<>\s]+@users\.noreply\.github\.com|noreply@github\.com)\Z')


def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.PIPE)


def reject_path(path, mode):
    parts = path.split(b'/')
    if any(part.lower() in BLOCKED_PARTS for part in parts):
        return 'private tooling or generated directory'
    if parts[-1] in BLOCKED_NAMES or path.endswith(BLOCKED_SUFFIXES):
        return 'private configuration or generated file'
    if path.startswith(BLOCKED_PREFIXES):
        return 'internal process record'
    if parts[-1].startswith(b'.env') and parts[-1] != b'.env.example':
        return 'environment configuration'
    if mode in (b'120000', b'160000'):
        return 'symlink or submodule requires explicit publication review'
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--history', action='store_true', help='also inspect every reachable commit and annotated tag')
    options = parser.parse_args()
    failures = []
    seen = set()

    def content(data, label):
        for rule, pattern in CONTENT_RULES.items():
            if pattern.search(data):
                failures.append((label, rule))

    def blob(mode, oid, path):
        reason = reject_path(path, mode)
        label = path.decode('utf-8', errors='backslashreplace')
        if reason:
            failures.append((label, reason))
        if oid not in seen and mode not in (b'120000', b'160000'):
            seen.add(oid)
            content(git('cat-file', 'blob', oid.decode('ascii')), label)

    def identity(data, label, roles):
        for role in roles:
            match = re.search(rb'^' + role + rb' .*?<([^<>]+)> ', data, re.M)
            if not match or not SAFE_EMAIL.fullmatch(match.group(1)):
                failures.append((label, 'author, committer or tagger email requires a public noreply identity'))

    for entry in git('ls-files', '--stage', '-z').split(b'\0'):
        if not entry:
            continue
        header, path = entry.split(b'\t', 1)
        mode, oid, stage = header.split()
        if stage != b'0':
            failures.append(('index', 'unresolved merge entry'))
            continue
        blob(mode, oid, path)

    if options.history:
        for commit in git('rev-list', '--all').splitlines():
            oid = commit.decode('ascii')
            raw = git('cat-file', 'commit', oid)
            identity(raw, 'commit ' + oid[:12], (b'author', b'committer'))
            content(raw, 'commit ' + oid[:12])
            for entry in git('ls-tree', '-r', '-z', oid).split(b'\0'):
                if not entry:
                    continue
                header, path = entry.split(b'\t', 1)
                mode, kind, object_id = header.split()
                blob(mode, object_id, path)
        for ref in git('for-each-ref', '--format=%(objecttype) %(objectname)', 'refs/tags').splitlines():
            kind, oid = ref.split()
            if kind == b'tag':
                raw = git('cat-file', 'tag', oid.decode('ascii'))
                identity(raw, 'annotated tag', (b'tagger',))
                content(raw, 'annotated tag')

    if failures:
        print('Publication check failed (values intentionally omitted):', file=sys.stderr)
        for path, reason in sorted(set(failures)):
            print('  ' + repr(path) + ': ' + reason, file=sys.stderr)
        return 1
    print('Publication checks passed: ' + str(len(seen)) + ' distinct Git blobs reviewed.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (subprocess.CalledProcessError, ValueError, OSError):
        print('Publication check could not complete; refusing to pass.', file=sys.stderr)
        sys.exit(2)
