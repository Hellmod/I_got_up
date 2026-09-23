# Wstałem! — przygotowanie do publikacji w App Store

## Stan techniczny (gotowe ✅)

- ✅ Nazwa na ekranie głównym: **Wstałem!** (`CFBundleDisplayName`)
- ✅ Ikona 1024×1024 bez kanału alpha (wymóg App Store)
- ✅ Bundle ID: `com.4lcah5j7v4.AlarmClock`
- ✅ Wersja: `MARKETING_VERSION = 1.0`, build: `CURRENT_PROJECT_VERSION = 1`
- ✅ `ITSAppUsesNonExemptEncryption = false` — pomija pytanie o eksport szyfrowania przy każdym uploadzie
- ✅ `NSAlarmKitUsageDescription` — opis uprawnień do alarmów
- ✅ Minimalny system: iOS 26.0 (wymóg AlarmKit)
- ✅ Tylko iPhone (`TARGETED_DEVICE_FAMILY = 1`) — brak wymogu zrzutów iPada
- ✅ Zrzuty ekranu 6,9″ (1320×2868) gotowe: `AppStore_Screenshots/` → `en/` i `pl/` (onboarding, lista alarmów, „Czy już wstałeś?")
- ✅ Lokalizacja: 20 języków (język wybierany automatycznie z systemu) — pl, en, de, es, fr, pt-BR, ru, ja, zh-Hans, zh-Hant, ar, hi, it, nl, sv, tr, uk, id, ko, vi, th
- ⚠️ Tłumaczenia 10 nowszych języków (it, nl, sv, tr, uk, id, ko, vi, th, zh-Hant) to pierwsze podejście AI — zalecany przegląd native speakera przed finalną publikacją

## Kroki w App Store Connect (do zrobienia ręcznie)

1. **Utwórz rekord aplikacji**: [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+** → New App
   - Platform: iOS · Name: **Wstałem!** · Język główny: Polski
   - Bundle ID: `com.4lcah5j7v4.AlarmClock` · SKU: np. `wstalem-001`
2. **Archiwizacja**: Xcode → wybierz urządzenie **Any iOS Device (arm64)** → Product → **Archive** → Organizer → **Distribute App** → App Store Connect
3. **Zrzuty ekranu**: gotowe w `AppStore_Screenshots/` (slot iPhone 6,9″), osobno `en/` i `pl/` — wgraj je w App Store Connect. Tylko iPhone, więc **iPad NIE jest potrzebny**.
4. **Prywatność aplikacji**: sekcja App Privacy → **Data Not Collected** (wszystkie dane trzymane lokalnie w UserDefaults, zero sieci, zero analityki)
5. **Kategoria**: Lifestyle (ew. Utilities) · **Ocena wiekowa**: 4+
6. **Uwagi dla recenzenta** (App Review Notes): patrz niżej
7. Submit for Review

## Teksty do sklepu (gotowe do wklejenia)

### Nazwa
> Wstałem!

### Podtytuł (30 znaków)
> Budzik, który sprawdza sen

### Opis (PL)
> **Wstałem! to budzik, którego nie oszukasz.**
>
> Każdy budzik można wyłączyć przez sen. Wstałem! jako jedyny po wyłączeniu alarmu pyta, czy NAPRAWDĘ wstałeś — a jeśli nie odpowiesz, dzwoni ponownie. Pełnoekranowym, głośnym alarmem systemowym, nie cichym powiadomieniem.
>
> **Jak to działa:**
> 1. Alarm dzwoni jak w systemowym Zegarze — pełny ekran, dźwięk przebija tryb cichy
> 2. Po wyłączeniu, po kilku minutach dostajesz pytanie: „Czy już wstałeś?"
> 3. Brak odpowiedzi = alarm dzwoni od nowa. Bez litości. 😈
>
> **Funkcje:**
> • Prawdziwe alarmy systemowe (AlarmKit) — działają nawet gdy aplikacja jest zamknięta
> • Wake-Up Check — konfigurowalne opóźnienie i czas na odpowiedź; po wyłączeniu alarmu odliczanie do ponownego dzwonka widać na ekranie blokady, a zmiotnięcie go nie zatrzyma
> • Drzemka o dowolnej długości — z odliczaniem widocznym na ekranie blokady
> • Powtarzanie w wybrane dni tygodnia
> • Historia: kiedy wyłączyłeś, ile drzemek, kiedy potwierdziłeś wstanie
> • 20 języków — aplikacja sama dopasowuje się do języka systemu
> • Zero reklam, zero śledzenia, zero kont — wszystko zostaje na Twoim telefonie

### Słowa kluczowe (100 znaków)
> budzik,alarm,pobudka,wstawanie,drzemka,sen,poranek,wake up,nie zaśpij,potwierdzenie

### Promotional text (170 znaków)
> Jedyny budzik, który sprawdza, czy naprawdę wstałeś. Nie odpowiesz — zadzwoni znowu. Idealny dla śpiochów i mistrzów drzemki.

### App Review Notes (EN)
> The app uses the AlarmKit framework (iOS 26+) to schedule real system
> alarms. On first launch it asks for the Alarms permission only (no
> notifications are used). To test: add an alarm 1–2 minutes ahead, lock the
> device, wait for the full-screen alarm. After stopping it, a "Wake-Up
> Check" countdown starts, shown on the Lock Screen and in-app; if you don't
> confirm you're up in time, a real alarm rings again. Swiping the countdown
> away does not cancel it — an offset backup alarm guarantees the re-ring.
> No account, no network calls, all data stored locally.

## Store copy (EN — for the primary English listing)

### Subtitle (30 chars)
> The alarm that checks you woke

### Description (EN)
> **Wstałem! ("I'm up!") is the alarm you can't cheat.**
>
> Any alarm can be switched off in your sleep. Wstałem! is the one that, after you stop it, asks whether you REALLY got up — and if you don't answer, it rings again. With a real, loud, full-screen system alarm, not a quiet notification.
>
> **How it works:**
> 1. The alarm rings like the built-in Clock — full screen, cutting through silent mode
> 2. After you stop it, a few minutes later you're asked: "Are you up yet?"
> 3. No response = the alarm rings again. No mercy. 😈
>
> **Features:**
> • Real system alarms (AlarmKit) — work even when the app is closed
> • Wake-Up Check — configurable delay and response time; after you stop the alarm the countdown to the re-ring shows on the Lock Screen, and swiping it away won't stop it
> • Snooze of any length — with a live Lock Screen countdown
> • Repeat on chosen weekdays
> • History: when you stopped it, how many snoozes, when you confirmed you were up
> • 20 languages — the app follows your system language
> • No ads, no tracking, no accounts — everything stays on your phone

### Keywords (100 chars)
> alarm,wake up,wakeup,morning,snooze,sleep,oversleep,heavy sleeper,confirm,alarm clock,get up

### Promotional text (170 chars)
> The only alarm that checks you actually got up. Don't answer and it rings again. Built for heavy sleepers and snooze addicts.

## Nazwa — uzasadnienie i warianty

Wybrana: **Wstałem!** — to dokładnie ten przycisk, w który klikasz każdego ranka;
krótka, zapamiętywalna, unikalna na polskim rynku.

Alternatywy gdyby była zajęta: „Wstawaj!", „No Wstań", „Pobudka+";
wersja międzynarodowa: **I'm Up!** / **WakeProof**.
