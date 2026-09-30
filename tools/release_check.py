#!/usr/bin/env python3
"""Проверка перед сборкой в App Store: не осталось ли заглушек.

Статические проверки (lint.py) гоняются на каждый пуш и заглушки терпят —
пока сервер не выложен, их и не может не быть. Этот скрипт — для одного
момента: перед архивом в App Store Connect. Нашёл заглушку — код выхода 1
и список, что вписать.

    python3 tools/release_check.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Что и где должно быть заполнено — и подсказка, откуда взять значение.
CHECKS = [
    ('project.yml', r'RecapBackendURL:.*CHANGE-ME',
     'RecapBackendURL — адрес сервера после `wrangler deploy` (docs/backend.md)'),
    ('project.yml', r'RecapSellerName:\s*CHANGE-ME',
     'RecapSellerName — имя продавца, как в App Store Connect → DSA'),
    ('project.yml', r'RecapSellerAddress:\s*CHANGE-ME',
     'RecapSellerAddress — адрес продавца для DSA и условий'),
    ('project.yml', r'RecapContactEmail:\s*CHANGE-ME',
     'RecapContactEmail — почта поддержки'),
    ('Config/Signing.xcconfig', r'^DEVELOPMENT_TEAM\s*=\s*$',
     'DEVELOPMENT_TEAM — Team ID платного аккаунта (Xcode → Settings → Accounts)'),
]


def problems(root=ROOT):
    found = []
    for relative, pattern, hint in CHECKS:
        path = os.path.join(root, relative)
        try:
            text = open(path, encoding='utf-8').read()
        except OSError:
            found.append(f'{relative}: файла нет')
            continue
        if re.search(pattern, text, re.MULTILINE):
            found.append(f'{relative}: {hint}')
    return found


def main():
    found = problems()
    if not found:
        print('Заглушек нет — можно собирать архив.')
        return 0
    print('Перед выпуском нужно заполнить:')
    for item in found:
        print('  - ' + item)
    return 1


if __name__ == '__main__':
    sys.exit(main())
