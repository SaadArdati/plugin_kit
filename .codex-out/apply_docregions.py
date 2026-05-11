#!/usr/bin/env python3
from __future__ import annotations

import csv
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, List, Tuple

ROOT = Path.cwd()
INVENTORY = ROOT / '.codex-out' / 'inventory.tsv'
OUT_PLAN = ROOT / '.codex-out' / 'docregion-plan.tsv'

REAL_CODE = 'real-code'
EXCLUDED_PREFIXES = (
    'example/villain_lair/',
    'example/model_embassy/',
)

ALLOWED_PREFIXES = (
    'packages/',
    'example/',
)

DOCREGION_START_RE = re.compile(r'^\s*//\s+#docregion\s+([a-z0-9][a-z0-9-]*)\s*$')
DOCREGION_END_RE = re.compile(r'^\s*//\s+#enddocregion\s+([a-z0-9][a-z0-9-]*)\s*$')


def read_lines(path: Path) -> List[str]:
    return path.read_text(encoding='utf-8').splitlines(keepends=True)


def lines_no_eol(lines: List[str]) -> List[str]:
    return [line.rstrip('\r\n') for line in lines]


def common_dedent(lines: List[str]) -> List[str]:
    non_empty = [ln for ln in lines if ln.strip()]
    if not non_empty:
        return lines[:]
    indents = []
    for ln in non_empty:
        match = re.match(r'^[ \t]*', ln)
        indents.append(len(match.group(0)) if match else 0)
    dedent = min(indents) if indents else 0
    if dedent == 0:
        return lines[:]
    out: List[str] = []
    for ln in lines:
        count = 0
        while count < len(ln) and count < dedent and ln[count] in (' ', '\t'):
            count += 1
        out.append(ln[count:])
    return out


def extract_fenced_code(lines: List[str]) -> List[str]:
    fence_indices = [i for i, line in enumerate(lines) if line.strip().startswith('```')]
    if len(fence_indices) >= 2:
        start = fence_indices[0] + 1
        end = fence_indices[-1]
        return lines[start:end]
    return lines


def strip_leading_comment(line: str) -> str:
    stripped = line.lstrip()
    for prefix in ('///', '//'):
        if stripped.startswith(prefix):
            rest = stripped[len(prefix):]
            if rest.startswith(' '):
                rest = rest[1:]
            return rest
    return stripped


def line_match_score(src: str, doc: str) -> int:
    if src == doc:
        return 4
    s = src.strip()
    d = doc.strip()
    if s == d:
        return 3
    ds = strip_leading_comment(doc).strip()
    ss = strip_leading_comment(src).strip()
    if s == ds and ds != d:
        return 2
    if ss == d and ss != s:
        return 2
    if ss == ds and (ss != s or ds != d):
        return 1
    return 0


def find_contiguous_matches(src_lines: List[str], doc_lines: List[str]) -> List[Tuple[int, int, int]]:
    matches: List[Tuple[int, int, int]] = []
    if not doc_lines:
        return matches
    n = len(src_lines)
    m = len(doc_lines)
    if m > n:
        return matches
    for start in range(0, n - m + 1):
        score = 0
        exact = 0
        ok = True
        for offset in range(m):
            cur = line_match_score(src_lines[start + offset], doc_lines[offset])
            if cur == 0:
                ok = False
                break
            score += cur
            if src_lines[start + offset] == doc_lines[offset]:
                exact += 1
        if ok:
            matches.append((start, score, exact))
    return matches


def kebab(value: str) -> str:
    value = re.sub(r'([a-z0-9])([A-Z])', r'\1-\2', value)
    value = value.replace('_', '-')
    value = value.lower()
    value = re.sub(r'[^a-z0-9-]+', '-', value)
    value = re.sub(r'-+', '-', value).strip('-')
    return value or 'snippet'


def extract_symbol_from_lines(lines: List[str]) -> str:
    scan = [ln.strip() for ln in lines if ln.strip()]
    if not scan:
        return 'snippet'

    patterns = [
        re.compile(r'^(?:abstract\s+|sealed\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)\b'),
        re.compile(r'^enum\s+([A-Za-z_][A-Za-z0-9_]*)\b'),
        re.compile(r'^mixin\s+([A-Za-z_][A-Za-z0-9_]*)\b'),
        re.compile(r'^extension(?:\s+type)?\s+([A-Za-z_][A-Za-z0-9_]*)\b'),
        re.compile(r'^typedef\s+([A-Za-z_][A-Za-z0-9_]*)\b'),
    ]

    for ln in scan[:12]:
        if ln.startswith('@'):
            continue
        for pat in patterns:
            m = pat.search(ln)
            if m:
                return kebab(m.group(1))

    for ln in scan[:12]:
        if ln.startswith('@'):
            continue
        m = re.search(r'\bget\s+([A-Za-z_][A-Za-z0-9_]*)\b', ln)
        if m:
            return kebab(m.group(1))

    for ln in scan[:12]:
        if ln.startswith('@'):
            continue
        m = re.search(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*\(', ln)
        if m:
            return kebab(m.group(1))

    for ln in scan[:12]:
        if ln.startswith('@'):
            continue
        m = re.search(r'\b([A-Za-z_][A-Za-z0-9_]*)\b', ln)
        if m:
            return kebab(m.group(1))

    return 'snippet'


def derive_region_base(source_path: str, doc_lines: List[str], first_line: str) -> str:
    stem = kebab(Path(source_path).stem)
    candidates = [first_line] + doc_lines[:8]
    symbol = extract_symbol_from_lines(candidates)
    if symbol == stem or symbol.startswith(stem + '-'):
        return symbol
    if stem in ('main', 'test') and symbol != 'snippet':
        parent = kebab(Path(source_path).parent.name)
        if parent and parent != 'src':
            return f'{parent}-{symbol}'
    return f'{stem}-{symbol}' if symbol else f'{stem}-snippet'


def is_allowed_source(rel_path: str) -> bool:
    if any(rel_path.startswith(prefix) for prefix in EXCLUDED_PREFIXES):
        return False
    if not rel_path.endswith('.dart'):
        return False
    return any(rel_path.startswith(prefix) for prefix in ALLOWED_PREFIXES)


def main() -> int:
    with INVENTORY.open(encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f, delimiter='\t')
        all_rows = [row for row in reader if row['classification'] == REAL_CODE]

    source_states: Dict[str, Dict[str, object]] = {}
    used_names: Dict[str, set[str]] = defaultdict(set)

    plan_rows: List[Dict[str, str]] = []
    insertions = 0
    mismatches = 0
    already_marked = 0
    region_counts: Counter[str] = Counter()

    for row in all_rows:
        doc_file = row['doc_file']
        start_line = int(row['start_line'])
        end_line = int(row['end_line'])
        candidate_source = row['candidate_source']
        first_line = row['first_line']

        plan = {
            'doc_file': doc_file,
            'start_line': str(start_line),
            'end_line': str(end_line),
            'candidate_source': candidate_source,
            'region_name': '',
            'source_first_line': '',
            'source_last_line': '',
            'notes': '',
        }

        if not is_allowed_source(candidate_source):
            plan['region_name'] = '(mismatch)'
            plan['notes'] = 'excluded-source-path'
            mismatches += 1
            plan_rows.append(plan)
            continue

        source_path = ROOT / candidate_source
        if not source_path.exists():
            plan['region_name'] = '(mismatch)'
            plan['notes'] = 'source-file-missing'
            mismatches += 1
            plan_rows.append(plan)
            continue

        doc_path = ROOT / doc_file
        doc_lines_all = doc_path.read_text(encoding='utf-8').splitlines()
        if start_line < 1 or end_line > len(doc_lines_all) or end_line < start_line:
            plan['region_name'] = '(mismatch)'
            plan['notes'] = 'invalid-doc-range'
            mismatches += 1
            plan_rows.append(plan)
            continue

        shown_slice_raw = doc_lines_all[start_line - 1 : end_line]
        shown_slice_raw = extract_fenced_code(shown_slice_raw)
        shown_slice = common_dedent(shown_slice_raw)

        state = source_states.get(candidate_source)
        if state is None:
            src_lines = read_lines(source_path)
            src_no_nl = lines_no_eol(src_lines)
            source_states[candidate_source] = {
                'lines': src_lines,
                'plain': src_no_nl,
            }
            state = source_states[candidate_source]
            for plain in src_no_nl:
                m = DOCREGION_START_RE.match(plain)
                if m:
                    used_names[candidate_source].add(m.group(1))

        src_lines = state['lines']  # type: ignore[assignment]
        src_plain = state['plain']  # type: ignore[assignment]

        variants = []
        seen_variant = set()
        for variant in (shown_slice_raw, shown_slice):
            key = '\n'.join(variant)
            if key not in seen_variant:
                seen_variant.add(key)
                variants.append(variant)

        match_map: Dict[int, Tuple[int, int, int]] = {}
        for variant in variants:
            matches = find_contiguous_matches(src_plain, variant)
            for start, score, exact in matches:
                existing = match_map.get(start)
                if existing is None or (score, exact) > (existing[1], existing[2]):
                    match_map[start] = (len(variant), score, exact)

        if not match_map:
            plan['region_name'] = '(mismatch)'
            plan['notes'] = '(mismatch)'
            mismatches += 1
            plan_rows.append(plan)
            continue

        first_line_stripped = first_line.strip()
        ranked: List[Tuple[int, int, int, int]] = []
        for start, (length, score, exact) in match_map.items():
            start_line_text = src_plain[start].strip() if start < len(src_plain) else ''
            first_hit = 1 if first_line_stripped and start_line_text == first_line_stripped else 0
            ranked.append((start, length, score, exact * 2 + first_hit))

        ranked.sort(key=lambda item: (item[2], item[3], -item[0]), reverse=True)
        best_start, best_len, best_score, _ = ranked[0]
        best_end = best_start + best_len - 1

        ambiguous = len(ranked) > 1 and ranked[0][2] == ranked[1][2]

        prev_line = src_plain[best_start - 1] if best_start - 1 >= 0 else ''
        next_line = src_plain[best_end + 1] if best_end + 1 < len(src_plain) else ''
        prev_match = DOCREGION_START_RE.match(prev_line)
        next_match = DOCREGION_END_RE.match(next_line)

        if prev_match and next_match and prev_match.group(1) == next_match.group(1):
            region = prev_match.group(1)
            plan['region_name'] = region
            plan['source_first_line'] = str(best_start + 1)
            plan['source_last_line'] = str(best_end + 1)
            plan['notes'] = '(already-marked)'
            already_marked += 1
            plan_rows.append(plan)
            continue

        base = derive_region_base(candidate_source, shown_slice, first_line)
        region_name = base
        suffix = 2
        while region_name in used_names[candidate_source]:
            region_name = f'{base}-{suffix}'
            suffix += 1
        used_names[candidate_source].add(region_name)

        line_text = src_lines[best_start]
        indent_match = re.match(r'^[ \t]*', line_text)
        indent = indent_match.group(0) if indent_match else ''
        eol = '\n'
        if line_text.endswith('\r\n'):
            eol = '\r\n'
        elif line_text.endswith('\n'):
            eol = '\n'

        start_marker = f'{indent}// #docregion {region_name}{eol}'
        end_marker = f'{indent}// #enddocregion {region_name}{eol}'

        src_lines.insert(best_start, start_marker)
        src_lines.insert(best_end + 2, end_marker)

        src_plain = lines_no_eol(src_lines)
        state['plain'] = src_plain

        source_first = best_start + 2
        source_last = best_end + 2

        plan['region_name'] = region_name
        plan['source_first_line'] = str(source_first)
        plan['source_last_line'] = str(source_last)
        if ambiguous:
            plan['notes'] = 'ok; multiple matches picked highest-score'
        else:
            plan['notes'] = 'ok'
        if len(plan['notes']) > 120:
            plan['notes'] = plan['notes'][:120]

        plan_rows.append(plan)
        insertions += 1
        region_counts[candidate_source] += 1

    for rel, state in source_states.items():
        source_path = ROOT / rel
        source_path.write_text(''.join(state['lines']), encoding='utf-8')  # type: ignore[index]

    with OUT_PLAN.open('w', encoding='utf-8', newline='') as f:
        fieldnames = [
            'doc_file',
            'start_line',
            'end_line',
            'candidate_source',
            'region_name',
            'source_first_line',
            'source_last_line',
            'notes',
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter='\t')
        writer.writeheader()
        writer.writerows(plan_rows)

    print(f'Total real-code rows processed: {len(all_rows)}')
    print(f'Successful marker insertions: {insertions}')
    print(f'Mismatches: {mismatches}')
    print('Top 10 source files by region count:')
    for path, count in region_counts.most_common(10):
        print(f'{path}\t{count}')
    print(f'Already-marked: {already_marked}')

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
