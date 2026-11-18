# M-Audio Transit USB — сучасна macOS (Apple Silicon / Intel)

Неофіційна заміна старого драйвера 1.8.0. Kext не потрібен: після завантаження прошивки Transit працює як стандартний
USB Audio Class пристрій у вбудованому драйвері macOS.

## Встановлення (для користувача)
Двічі клікніть `build/Transit USB Installer.pkg` → «Продовжити» → введіть пароль. Потім відключіть і знову підключіть Transit.
Щоб видалити: запустіть той самий `.pkg`, на кроці «Тип встановлення → Налаштувати» виберіть «Видалити Transit USB».
Налаштування (гучність, mute, частота, розрядність, автозавантаження, видалення) — застосунок **Transit USB** у «Програмах».

## Збірка
```
./Installer/build-pkg.sh      # збирає build/Transit USB.app та build/Transit USB Installer.pkg (потрібен Xcode)
./App/build-app.sh            # лише застосунок
```
Старий швидкий варіант без інсталятора: `./install.sh` / `./uninstall.sh`.

## Склад
- `App/` — SwiftUI-застосунок налаштувань (CoreAudio + IOKit), `build-app.sh`, генератор значка.
- `Sources/transit-usb/` — CLI/демон: `info`, `dfu-status`, `load-firmware`, `daemon`, `get-rate`, `set-rate`.
- `firmware/ma006101.bin` — прошивка з Windows-драйвера 6.0.1.
- `Installer/` — скрипти й тексти `.pkg` (англійська й українська).
- `REVERSE_ENGINEERING.md` — докладні результати реверсу й експериментів.

Інсталятор не підписаний сертифікатом розробника (ad-hoc): якщо макОС попередить, відкрийте його через правий клік → «Відкрити».
