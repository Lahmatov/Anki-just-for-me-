#!/usr/bin/env bash
#
# Проверяет проект целиком и собирает ошибки в один файл.
#
#   ./tools/check.sh          — всё: линтер, генерация, тесты ядра, сборка
#   ./tools/check.sh core     — только тесты ядра (быстро, без Xcode)
#   ./tools/check.sh app      — только сборка приложения
#
# Результат — build-errors.txt рядом с проектом. Его можно прислать целиком:
# там уже только ошибки, без тысячи строк обычного вывода xcodebuild.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPORT="$ROOT/build-errors.txt"
RAW="$(mktemp)"
MODE="${1:-all}"
FAILED=0

: > "$REPORT"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
note() { printf '  %s\n' "$1"; }

# --- Проверка инструментов -------------------------------------------------

if [ "$MODE" != "core" ]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    say "Не найден xcodegen"
    note "Установи: brew install xcodegen"
    note "Он нужен, потому что .xcodeproj не лежит в репозитории —"
    note "проект собирается из project.yml, чтобы его структура была видна в диффах."
    exit 1
  fi
  if ! command -v xcodebuild >/dev/null 2>&1; then
    say "Не найден xcodebuild"
    note "Нужен Xcode. Если он установлен, выполни:"
    note "  sudo xcode-select -s /Applications/Xcode.app"
    exit 1
  fi
fi

# --- Статические проверки --------------------------------------------------

say "Статические проверки (без компилятора)"
if python3 "$ROOT/tools/lint.py" > "$RAW" 2>&1; then
  note "$(tail -2 "$RAW" | head -1)"
else
  FAILED=1
  {
    echo "=== СТАТИЧЕСКИЕ ПРОВЕРКИ ==="
    cat "$RAW"
    echo
  } >> "$REPORT"
  note "Есть замечания — записаны в build-errors.txt"
fi

# --- Генерация проекта -----------------------------------------------------

if [ "$MODE" != "core" ]; then
  say "Генерирую проект из project.yml"
  if ! xcodegen generate > "$RAW" 2>&1; then
    {
      echo "=== ГЕНЕРАЦИЯ ПРОЕКТА НЕ УДАЛАСЬ ==="
      cat "$RAW"
    } >> "$REPORT"
    say "Не удалось сгенерировать проект — подробности в build-errors.txt"
    exit 1
  fi
  note "AJFM.xcodeproj готов"
fi

# --- Тесты ядра ------------------------------------------------------------

if [ "$MODE" = "all" ] || [ "$MODE" = "core" ]; then
  if ! command -v swift >/dev/null 2>&1; then
    say "Не найден swift"
    note "Нужен Xcode или Command Line Tools: xcode-select --install"
    exit 1
  fi
  say "Тесты ядра (без симулятора)"
  if (cd Core && swift test) > "$RAW" 2>&1; then
    PASSED=$(grep -Eo "Executed [0-9]+ tests" "$RAW" | tail -1)
    note "${PASSED:-тесты прошли}"
  else
    FAILED=1
    {
      echo "=== ЯДРО: ОШИБКИ ==="
      if grep -qE "error:|XCTAssert" "$RAW"; then
        grep -E "error:|XCTAssert.*failed|Fatal error" "$RAW" \
          | sed 's|'"$ROOT"'/||' | sort -u | head -100
        echo
        echo "--- проваленные тесты ---"
        grep -E "Test Case .* failed" "$RAW" | head -40
      else
        echo "(строк error: нет; последние строки вывода)"
        tail -40 "$RAW" | sed 's|'"$ROOT"'/||'
      fi
      echo
    } >> "$REPORT"
    note "Есть проблемы — записаны в build-errors.txt"
  fi
fi

# --- Сборка приложения -----------------------------------------------------

if [ "$MODE" = "all" ] || [ "$MODE" = "app" ]; then
  say "Сборка приложения (симулятор, без подписи)"
  if xcodebuild \
      -project AJFM.xcodeproj \
      -scheme AJFM \
      -destination 'generic/platform=iOS Simulator' \
      -configuration Debug \
      CODE_SIGNING_ALLOWED=NO \
      build > "$RAW" 2>&1; then
    note "Приложение собралось"
  else
    FAILED=1
    COUNT=$(grep -cE "error:" "$RAW" || true)
    {
      echo "=== ПРИЛОЖЕНИЕ: ОШИБКИ КОМПИЛЯЦИИ ==="
      if [ "$COUNT" -gt 0 ]; then
        grep -E "error:" "$RAW" | sed 's|'"$ROOT"'/||' | sort -u | head -100
        echo
        echo "--- предупреждения (первые 30) ---"
        grep -E "warning:" "$RAW" | sed 's|'"$ROOT"'/||' | sort -u | head -30
      else
        # Сборка упала не на компиляции: не тот симулятор, подпись, xcodegen.
        echo "(строк error: нет — похоже, дело не в коде; последние строки вывода)"
        tail -60 "$RAW" | sed 's|'"$ROOT"'/||'
      fi
      echo
    } >> "$REPORT"

    note "Ошибок компиляции: $COUNT — записаны в build-errors.txt"
  fi
fi

# --- Итог ------------------------------------------------------------------

rm -f "$RAW"

if [ "$FAILED" -eq 0 ]; then
  rm -f "$REPORT"
  say "Всё чисто"
  if ! grep -qE "^DEVELOPMENT_TEAM = .+" Config/Signing.xcconfig 2>/dev/null; then
    note "Для запуска на телефоне впиши Team ID в Config/Signing.xcconfig"
    note "(Xcode → Settings → Accounts → твой Apple ID → колонка Team ID)"
  fi
  note "Дальше: открой AJFM.xcodeproj, выбери iPhone и нажми ⌘R"
  note "Тесты приложения (работа с базой) — ⌘U"
  exit 0
fi

say "Есть что чинить"
note "Файл: build-errors.txt"
note "Его можно прислать целиком — там только ошибки, без лишнего вывода."
exit 1
