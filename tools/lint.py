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
    (('tr(', 'Counted.', 'trCount(', 'trForm(', 'Loc.language'), 'AJFMCore'),
]


def check_imports():
    for path in ALL:
        src = read(path)
        for tokens, module in IMPORT_RULES:
            if module == 'AJFMCore' and '/Core/' in path:
                continue
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


CYRILLIC = re.compile('[А-Яа-яЁё]')
# Файлы, где русский текст — сама суть: правила склонения и название языка.
UNTRANSLATED_OK = ('RussianPlural.swift', 'AppLanguage.swift')
# Журнал и подписи расходов в нём — диагностика, её не переводим.
LOG_CALLS = ('Log.info', 'Log.warning', 'Log.error', 'Log.failure', 'Log.debug',
             'budget.record')


def scan_literals(src):
    """Позиции строковых литералов и код, где литералы и комментарии забиты
    пробелами, — чтобы считать скобки и запятые, не спотыкаясь о текст."""
    literals, code = [], list(src)
    i, n = 0, len(src)
    while i < n:
        if src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            code[i:j] = ' ' * (j - i); i = j; continue
        if src.startswith('/*', i):
            j = src.find('*/', i); j = n if j < 0 else j + 2
            code[i:j] = ' ' * (j - i); i = j; continue
        if src.startswith('"""', i):
            j = src.find('"""', i + 3); j = n if j < 0 else j + 3
            literals.append((i, src[i:j])); code[i:j] = ' ' * (j - i); i = j; continue
        if src[i] == '"':
            j = i + 1
            while j < n and src[j] != '"' and src[j] != '\n':
                j += 2 if src[j] == '\\' else 1
            j += 1
            literals.append((i, src[i:j])); code[i:j] = ' ' * (j - i); i = j; continue
        i += 1
    return literals, ''.join(code)


def enclosing_calls(code, pos):
    """Все объемлющие скобки изнутри наружу: (имя перед скобкой, номер
    аргумента, метка аргумента, метка перед самой скобкой — для кортежей
    вида `ru: ("один", "два")`)."""
    calls, depth, commas, i = [], 0, 0, pos - 1
    segment_end, nearest_comma = pos, None
    while i >= 0:
        c = code[i]
        if c in ')]}':
            depth += 1
        elif c in '([{':
            if depth:
                depth -= 1
            else:
                if c == '(':
                    head = code[max(0, i - 80):i]
                    name = re.search(r'([\w.]+)\s*$', head)
                    before = re.search(r'(\w+)\s*:\s*$', head)
                    arg_from = nearest_comma if nearest_comma is not None else i
                    label = re.match(r'\s*(\w+)\s*:', code[arg_from + 1:segment_end])
                    calls.append((name.group(1) if name else '', commas,
                                  label.group(1) if label else None,
                                  before.group(1) if before else None))
                commas, segment_end, nearest_comma = 0, i, None
        elif c == ',' and depth == 0:
            if nearest_comma is None:
                nearest_comma = i
            commas += 1
        i -= 1
    return calls


def check_untranslated():
    """Русский текст на экране — только через tr(ru, pt, en).

    Строка, забытая при переводе, на португальском интерфейсе вылезла бы
    кириллицей. Журнал событий не переводится — это диагностика.
    """
    for path in CORE + APP:
        if '/Tests/' in path or path.endswith(UNTRANSLATED_OK):
            continue
        src = read(path)
        literals, code = scan_literals(src)
        for start, text in literals:
            if not CYRILLIC.search(text):
                continue
            calls = enclosing_calls(code, start)
            if any(call[0] in LOG_CALLS for call in calls):
                continue
            if calls:
                name, index, label, label_before = calls[0]
                if name == 'tr' and index == 0:
                    continue
                if 'ru' in (label, label_before):
                    continue
            line = src.count('\n', 0, start) + 1
            problems.append(
                f"{os.path.basename(path)}:{line}: русский текст вне tr(): "
                f"{text[:50]}")


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
    check_untranslated()
    sys.exit(report())
