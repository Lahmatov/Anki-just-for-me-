#!/usr/bin/env python3
"""Статические проверки Swift-кода, не требующие компилятора.

Не заменяет сборку, но ловит те ошибки, которые уже дважды оказывались
блокерами: пропущенный импорт и публичная структура без public-инициализатора.
Полезно, когда Mac под рукой нет.

    python3 tools/lint.py
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = sorted(glob.glob(os.path.join(ROOT, 'Core/Sources/**/*.swift'), recursive=True))
CORE_TESTS = sorted(glob.glob(os.path.join(ROOT, 'Core/Tests/**/*.swift'), recursive=True))
APP = sorted(glob.glob(os.path.join(ROOT, 'App/**/*.swift'), recursive=True))
ALL = CORE + CORE_TESTS + APP

problems = []


def read(path):
    with open(path, encoding='utf-8') as handle:
        return handle.read()


def strip_literals(src):
    """Убирает комментарии и строки — иначе скобки внутри них ломают счёт."""
    out, i, n, state = [], 0, len(src), None
    while i < n:
        c = src[i]
        if state is None:
            if src.startswith('//', i):
                state = 'line'; i += 2; continue
            if src.startswith('/*', i):
                state = 'block'; i += 2; continue
            if c == '#' and src.startswith('#"', i):
                state = 'raw'; i += 2; continue
            if c == '"':
                if src.startswith('"""', i):
                    state = 'multiline'; i += 3; continue
                state = 'string'; i += 1; continue
            out.append(c); i += 1
        elif state == 'line':
            if c == '\n':
                state = None; out.append(c)
            i += 1
        elif state == 'block':
            if src.startswith('*/', i):
                state = None; i += 2; continue
            i += 1
        elif state == 'raw':
            if src.startswith('"#', i):
                state = None; i += 2; continue
            i += 1
        elif state == 'string':
            if c == '\\':
                i += 2; continue
            if c == '"':
                state = None
            i += 1
        elif state == 'multiline':
            if src.startswith('"""', i):
                state = None; i += 3; continue
            i += 1
    return ''.join(out)


def check_brackets():
    for path in ALL:
        code = strip_literals(read(path))
        for opening, closing in (('{', '}'), ('(', ')'), ('[', ']')):
            delta = code.count(opening) - code.count(closing)
            if delta:
                problems.append(
                    f"{os.path.basename(path)}: небаланс {opening}{closing} = {delta:+d}")


IMPORT_RULES = [
    (('ModelContext', 'modelContext', '@Query', '@Model', 'FetchDescriptor',
      'PersistentIdentifier', 'ModelContainer'), 'SwiftData'),
    (('Chart(', 'BarMark', 'LineMark', 'AxisMarks'), 'Charts'),
    (('UIPasteboard', 'UIImpactFeedback', 'UINotificationFeedback',
      'UIActivityViewController', 'UIViewControllerRepresentable'), 'UIKit'),
    (('WKWebView',), 'WebKit'),
    (('AVSpeech', 'AVAudioEngine', 'AVAudioSession', 'AVAudioFile',
      'AVAudioPlayer', 'AVAudioApplication'), 'AVFoundation'),
    (('SFSpeech',), 'Speech'),
    (('UNMutable', 'UNUserNotification', 'UNCalendar'), 'UserNotifications'),
    (('Logger(',), 'os'),
    (('SecItemAdd', 'SecItemCopyMatching', 'SecItemDelete'), 'Security'),
    (('@Observable',), 'Observation'),
    ((': View', 'some View', '@AppStorage', '@Environment'), 'SwiftUI'),
]


def check_imports():
    for path in ALL:
        src = read(path)
        for tokens, module in IMPORT_RULES:
            used = [t for t in tokens if t in src]
            if used and f'import {module}' not in src:
                problems.append(
                    f"{os.path.basename(path)}: нет import {module} "
                    f"(используется {', '.join(used[:3])})")


def check_public_inits():
    """Публичная структура, создаваемая вне модуля, нуждается в public init.

    Синтезированный инициализатор — internal, поэтому из приложения такую
    структуру не создать. Дважды оказывалось блокером сборки.
    """
    app_src = '\n'.join(read(p) for p in APP)
    for path in CORE:
        src = read(path)
        for match in re.finditer(
                r'public struct (\w+)[^{]*\{(.*?)\n\}', src, re.S):
            name, body = match.group(1), match.group(2)
            if 'public init' in body:
                continue
            # Ищем создание снаружи: «Name(» с аргументом, не объявление.
            if re.search(r'(?<![\w.])' + name + r'\s*\(\s*[\w"]', app_src):
                problems.append(
                    f"{os.path.basename(path)}: public struct {name} создаётся "
                    "из приложения, но не имеет public init")


def check_duplicate_types():
    seen = {}
    for path in CORE + APP:
        for match in re.finditer(
                r'^(?:public |private |internal |final |@\w+\s+)*'
                r'(?:public\s+)?(?:final\s+)?(struct|class|enum|protocol)\s+(\w+)',
                read(path), re.M):
            seen.setdefault(match.group(2), []).append(os.path.basename(path))
    for name, files in seen.items():
        if len(files) > 1:
            problems.append(f"тип {name} объявлен несколько раз: {', '.join(files)}")


def report():
    tests = sum(
        len(re.findall(r'func test\w+', read(p)))
        for p in ALL if '/Tests/' in p)
    print(f"Файлов: {len(ALL)}, тестов: {tests}")
    if problems:
        print(f"\nНайдено проблем: {len(problems)}")
        for problem in problems:
            print(f"  • {problem}")
        return 1
    print("Статические проверки пройдены")
    return 0


if __name__ == '__main__':
    check_brackets()
    check_imports()
    check_public_inits()
    check_duplicate_types()
    sys.exit(report())
