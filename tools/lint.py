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
APP = sorted(glob.glob(os.path.join(ROOT, 'App/**/*.swift'), recursive=True)
             # Виджет — тот же код приложения, только в своём процессе.
             + glob.glob(os.path.join(ROOT, 'Widget/**/*.swift'), recursive=True)
             + glob.glob(os.path.join(ROOT, 'Shared/**/*.swift'), recursive=True))
ALL = CORE + CORE_TESTS + APP


def is_test(path):
    """Тесты — и модульные (Tests/), и UI (UITests/): их сообщения не интерфейс."""
    return '/Tests/' in path or '/UITests/' in path

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
                r'^((?:public |private |fileprivate |internal |final |@\w+\s+)*)'
                r'(?:public\s+)?(?:final\s+)?(struct|class|enum|protocol)\s+(\w+)',
                read(path), re.M):
            # private на уровне файла виден только в файле — с другим не столкнётся
            # (так устроены `private struct Previews` в каждом экране).
            if re.search(r'\b(private|fileprivate)\b', match.group(1)):
                continue
            seen.setdefault(match.group(3), []).append(os.path.basename(path))
    for name, files in seen.items():
        if len(files) > 1:
            problems.append(f"тип {name} объявлен несколько раз: {', '.join(files)}")


CYRILLIC = re.compile('[А-Яа-яЁё]')
# Файлы, где русский текст — сама суть: правила склонения и название языка.
UNTRANSLATED_OK = ('RussianPlural.swift', 'AppLanguage.swift')
NOT_UI_MARK = 'lint: не интерфейс'
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
        if is_test(path) or path.endswith(UNTRANSLATED_OK):
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
            # Название превью видно только в Xcode Canvas.
            if src.splitlines()[line - 1].lstrip().startswith('#Preview('):
                continue
            # Кириллица, которую не показывают, а сопоставляют (шаблоны
            # разбора «2 сезон 5 серия»), помечается в строке явно.
            if NOT_UI_MARK in src.splitlines()[line - 1]:
                continue
            problems.append(
                f"{os.path.basename(path)}:{line}: русский текст вне tr(): "
                f"{text[:50]}")


# Секреты в журнал не пишутся (MASVS-STORAGE-2): журнал виден на экране
# и уходит в обращение в поддержку. Ловим подстановку в вызов журнала
# переменной, чьё имя говорит «это секрет».
SECRET_NAME = re.compile(r'(?i)(token(?!s|izer)|api_?key|secret|password|private_?key|pepper)')
LOG_CALL = re.compile(r'\b(?:Log\.(?:debug|info|warning|error|failure)|print|NSLog|'
                      r'console\.(?:log|warn|error|info))\s*\(')


def call_text(src, start):
    """Текст вызова от открывающей скобки до парной — даже на несколько строк."""
    depth, i = 0, start
    while i < len(src):
        if src[i] == '(':
            depth += 1
        elif src[i] == ')':
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
        i += 1
    return src[start:]


def secrets_in_call(text):
    """Имена-секреты в подстановках: Swift \\(x) и JS ${x}, а также голые аргументы JS."""
    found = []
    for expr in re.findall(r'\\\(([^()]*(?:\([^()]*\))?[^()]*)\)', text):
        found += SECRET_NAME.findall(expr)
    for expr in re.findall(r'\$\{([^}]*)\}', text):
        found += SECRET_NAME.findall(expr)
    # Аргументы вне строк: console.log("x", token).
    bare = re.sub(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|`[^`]*`', '""', text)
    found += SECRET_NAME.findall(bare)
    return found


def check_secret_logging():
    backend = sorted(glob.glob(os.path.join(ROOT, 'backend/src/**/*.ts'), recursive=True))
    for path in [p for p in ALL if not is_test(p)] + backend:
        src = read(path)
        for match in LOG_CALL.finditer(src):
            text = call_text(src, match.end() - 1)
            names = secrets_in_call(text)
            if names:
                line = src.count('\n', 0, match.start()) + 1
                problems.append(
                    f"{os.path.relpath(path, ROOT)}:{line}: в журнал уходит "
                    f"похожее на секрет: {', '.join(sorted(set(names)))}")


# Пределы App Store Connect: длиннее — не сохранит форма, а fastlane deliver
# упадёт в момент выпуска. Лучше узнать об этом в CI.
STORE_LIMITS = {'name.txt': 30, 'subtitle.txt': 30, 'keywords.txt': 100,
                'promotional_text.txt': 170, 'description.txt': 4000,
                'release_notes.txt': 4000}
STORE_LOCALES = ('ru', 'pt-PT', 'en-US')


def check_store_metadata():
    base = os.path.join(ROOT, 'fastlane/metadata')
    if not os.path.isdir(base):
        return
    for locale in STORE_LOCALES:
        for name, limit in STORE_LIMITS.items():
            path = os.path.join(base, locale, name)
            if not os.path.exists(path):
                problems.append(f"fastlane/metadata/{locale}/{name}: нет файла")
                continue
            text = read(path).strip()
            if not text:
                problems.append(f"fastlane/metadata/{locale}/{name}: пусто")
            elif len(text) > limit:
                problems.append(
                    f"fastlane/metadata/{locale}/{name}: {len(text)} знаков, предел {limit}")
            if name == 'keywords.txt' and ', ' in text:
                # Пробел после запятой App Store считает знаком — это потерянное место.
                problems.append(f"fastlane/metadata/{locale}/{name}: пробел после запятой")


# Правила навыка ios-architecture: проверяются здесь, чтобы не держались
# только на памяти того, кто пишет код.
LEGACY_STATE = re.compile(r'\b(ObservableObject|@Published|@StateObject|@ObservedObject|@EnvironmentObject)\b')
LEGACY_NAV = re.compile(r'\b(NavigationView|PreviewProvider)\b|NavigationLink\(destination:|NavigationLink \{'
                        r'|NavigationStack \{')
# Единственный голый NavigationStack — внутри routedStack, на пути роутера.
NAV_HOME = 'Router.swift'
# Экраны-обёртки над UIKit: в Canvas без устройства они пусты или ходят в сеть.
NO_PREVIEW_OK = ('DocumentCameraView.swift', 'ShareSheet.swift', 'YouGlishView.swift')


def check_architecture():
    for path in APP:
        if is_test(path):
            continue
        name = os.path.basename(path)
        _, code = scan_literals(read(path))
        for regex, rule in ((LEGACY_STATE, 'вместо него @Observable'),
                            (LEGACY_NAV, 'вместо него AppRoute + routedStack / RoutedStack, превью — #Preview')):
            for match in regex.finditer(code):
                if name == NAV_HOME:
                    continue
                line = code.count('\n', 0, match.start()) + 1
                problems.append(f"{name}:{line}: {match.group(0)} — {rule} (ios-architecture)")
        # @Observable без @MainActor — данные экрана меняются с любого потока.
        for match in re.finditer(r'@Observable\s*\n((?:\s*@\w+\s*\n)*)\s*(?:final\s+)?class\s+(\w+)', code):
            if '@MainActor' not in match.group(1) and '@MainActor' not in code[max(0, match.start() - 40):match.start()]:
                line = code.count('\n', 0, match.start()) + 1
                problems.append(f"{name}:{line}: @Observable {match.group(2)} без @MainActor (ios-architecture)")
        # Каждый экран — с превью на mock-данных.
        if '/Views/' in path and name not in NO_PREVIEW_OK:
            declares_view = re.search(r'^(?:private )?struct \w+(?:<[^>]*>)?\s*:\s*[^{]*\bView\b', code, re.M)
            if declares_view and '#Preview' not in code:
                problems.append(f"{name}: нет #Preview с mock-данными (ios-architecture, правило 4)")


def report():
    tests = sum(
        len(re.findall(r'func test\w+', read(p)))
        for p in ALL if is_test(p))
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
    check_secret_logging()
    check_store_metadata()
    check_architecture()
    sys.exit(report())
