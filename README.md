# M-Audio Transit USB for modern macOS

[🇺🇦 Українська](#-українська) · [🇬🇧 English](#-english)

---

## 🇺🇦 Українська

### M-Audio Transit USB — сучасна macOS (Apple Silicon / Intel)

Неофіційна заміна старого драйвера 1.8.0. Kext не потрібен: після завантаження прошивки Transit працює як стандартний
USB Audio Class пристрій у вбудованому драйвері macOS.

#### Встановлення (для користувача)
Двічі клікніть `build/Transit USB Installer.pkg` → «Продовжити» → введіть пароль. Потім відключіть і знову підключіть Transit.
Щоб видалити: запустіть той самий `.pkg`, на кроці «Тип встановлення → Налаштувати» виберіть «Видалити Transit USB».
Налаштування (гучність, mute, частота, розрядність, автозавантаження, видалення) — застосунок **Transit USB** у «Програмах».

#### Збірка
```
./Installer/build-pkg.sh      # збирає build/Transit USB.app та build/Transit USB Installer.pkg (потрібен Xcode)
./App/build-app.sh            # лише застосунок
```
Старий швидкий варіант без інсталятора: `./install.sh` / `./uninstall.sh`.

#### Склад
- `App/` — SwiftUI-застосунок налаштувань (CoreAudio + IOKit), `build-app.sh`, генератор значка.
- `Sources/transit-usb/` — CLI/демон: `info`, `dfu-status`, `load-firmware`, `daemon`, `get-rate`, `set-rate`.
- `firmware/ma006101.bin` — прошивка з Windows-драйвера 6.0.1.
- `Installer/` — скрипти й тексти `.pkg` (англійська й українська).
- `legacy-drivers/` — оригінальні драйвери 1.8.0 / 1.5.8, Windows-драйвер 6.0.1 і записи USBPcap (лише для дослідження).
- `REVERSE_ENGINEERING.md` — докладні результати реверсу й експериментів.

Інсталятор не підписаний сертифікатом розробника (ad-hoc): якщо macOS попередить, відкрийте його через правий клік → «Відкрити».

---

## 🇬🇧 English

### M-Audio Transit USB for modern macOS (Apple Silicon / Intel)

An unofficial replacement for the old 1.8.0 driver. No kernel extension is needed: once the firmware is loaded, the Transit
works as a standard USB Audio Class device with macOS' built-in driver.

#### Installation (for users)
Double-click `build/Transit USB Installer.pkg` → Continue → enter your password. Then unplug and re-plug the Transit.
To uninstall: run the same `.pkg`, and on the "Installation Type → Customize" step choose "Uninstall Transit USB".
Settings (volume, mute, sample rate, bit depth, automatic firmware loading, uninstall) are in the **Transit USB** app in Applications.

#### Building
```
./Installer/build-pkg.sh      # builds build/Transit USB.app and build/Transit USB Installer.pkg (Xcode required)
./App/build-app.sh            # app only
```
The old quick way without the installer: `./install.sh` / `./uninstall.sh`.

#### Contents
- `App/` — SwiftUI settings app (CoreAudio + IOKit), `build-app.sh`, icon generator.
- `Sources/transit-usb/` — CLI/daemon: `info`, `dfu-status`, `load-firmware`, `daemon`, `get-rate`, `set-rate`.
- `firmware/ma006101.bin` — firmware from the Windows driver 6.0.1.
- `Installer/` — scripts and texts for the `.pkg` (English and Ukrainian).
- `legacy-drivers/` — the original 1.8.0 / 1.5.8 drivers, the Windows driver 6.0.1 and USBPcap captures (for research only).
- `REVERSE_ENGINEERING.md` — detailed reverse-engineering results and experiments (in English).

The installer is not signed with a developer certificate (ad-hoc): if macOS warns about it, open it with right-click → Open.

---

*Unofficial project, not affiliated with or supported by M-Audio or Avid. Use at your own risk.*
*Неофіційний проєкт, не пов'язаний з M-Audio чи Avid і не підтримується ними. Використовуйте на власний ризик.*
