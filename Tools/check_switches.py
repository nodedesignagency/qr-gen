#!/usr/bin/env python3
"""Catch non-exhaustive switches over the project's own enums.

Swift enforces this at compile time. This exists because CI here has no Swift
toolchain, and adding an enum case is exactly the change that silently breaks a
switch three files away — which is how `Choreography.feed` broke `MotionGlyph`.

Heuristic, so it reports *possible* problems; read the hit before acting on it.
"""
import re, glob, sys


def strip_parens(text):
    """Drop anything inside (), so associated-value labels are not read as cases."""
    out, depth = [], 0
    for ch in text:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth = max(depth - 1, 0)
        elif depth == 0:
            out.append(ch)
    return ''.join(out)


def matching_brace(text, open_index):
    depth, i = 0, open_index
    while i < len(text):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(text)


def enum_cases(source):
    enums = {}
    for m in re.finditer(r'\benum\s+(\w+)[^{]*\{', source):
        end = matching_brace(source, m.end() - 1)
        body = source[m.end():end]
        cases = set()
        for line in body.splitlines():
            line = line.strip()
            if not line.startswith('case '):
                continue
            decl = strip_parens(line[5:].split('//')[0])
            for part in decl.split(','):
                part = part.strip()
                if '=' in part:
                    part = part.split('=')[0].strip()
                name = re.match(r'([A-Za-z_]\w*)$', part)
                if name:
                    cases.add(name.group(1))
        if cases:
            enums[m.group(1)] = cases
    return enums


def main():
    files = {p: open(p).read() for p in sorted(glob.glob('HalftoneQR/**/*.swift', recursive=True))}
    enums = enum_cases('\n'.join(files.values()))

    problems = 0
    for path, text in files.items():
        for m in re.finditer(r'\bswitch\s+[^{\n]+\{', text):
            end = matching_brace(text, m.end() - 1)
            body = text[m.end():end]
            if re.search(r'^\s*default\s*:', body, re.M):
                continue
            # Every pattern in every case label, including `case .a, .b, .c:`.
            handled = set()
            for label in re.finditer(r'^\s*case\s+([^:\n]+):', body, re.M):
                handled |= set(re.findall(r'\.(\w+)', label.group(1)))
            if len(handled) < 2:
                continue
            for name, cases in enums.items():
                if handled <= cases and len(handled) >= len(cases) - 2:
                    missing = cases - handled
                    if missing:
                        line = text[:m.start()].count('\n') + 1
                        print(f'{path}:{line}: switch over {name} may be missing {sorted(missing)}')
                        problems += 1
    print(f'{problems} possible non-exhaustive switches' if problems
          else f'all switches exhaustive across {len(enums)} enums')
    return 0


if __name__ == '__main__':
    sys.exit(main())
