# Wstałem! — przygotowanie do publikacji w App Store

## Stan techniczny (gotowe ✅)

- ✅ Nazwa na ekranie głównym: **Wstałem!** (`CFBundleDisplayName`)
- ✅ Ikona 1024×1024 bez kanału alpha (wymóg App Store)
- ✅ Bundle ID: `com.4lcah5j7v4.AlarmClock`
- ✅ Wersja: `MARKETING_VERSION = 1.0`, build: `CURRENT_PROJECT_VERSION = 1`
- ✅ `ITSAppUsesNonExemptEncryption = false` — pomija pytanie o eksport szyfrowania przy każdym uploadzie
- ✅ `NSAlarmKitUsageDescription` — opis uprawnień do alarmów
- ✅ Minimalny system: iOS 26.0 (wymóg AlarmKit)

## Kroki w App Store Connect (do zrobienia ręcznie)

1. **Utwórz rekord aplikacji**: [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+** → New App
   - Platform: iOS · Name: **Wstałem!** · Język główny: Polski
   - Bundle ID: `com.4lcah5j7v4.AlarmClock` · SKU: np. `wstalem-001`
2. **Archiwizacja**: Xcode → wybierz urządzenie **Any iOS Device (arm64)** → Product → **Archive** → Organizer → **Distribute App** → App Store Connect
3. **Zrzuty ekranu** (wymagane): iPhone 6,9″ (np. 16 Pro Max) — lista alarmów, ekran dodawania, systemowy ekran alarmu, ekran „Czy już wstałeś?", historia
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
> • Wake-Up Check — konfigurowalne opóźnienie i czas na odpowiedź
> • Drzemka wprost z ekranu alarmu (5/10/15 min)
> • Powtarzanie w wybrane dni tygodnia
> • Historia: kiedy wyłączyłeś, ile drzemek, kiedy potwierdziłeś wstanie
> • Odliczanie do następnego alarmu przy każdej pozycji listy
> • Zero reklam, zero śledzenia, zero kont — wszystko zostaje na Twoim telefonie

### Słowa kluczowe (100 znaków)
> budzik,alarm,pobudka,wstawanie,drzemka,sen,poranek,wake up,nie zaśpij,potwierdzenie

### Promotional text (170 znaków)
> Jedyny budzik, który sprawdza, czy naprawdę wstałeś. Nie odpowiesz — zadzwoni znowu. Idealny dla śpiochów i mistrzów drzemki.

### App Review Notes (EN)
> The app uses the AlarmKit framework (iOS 26+) to schedule real system
> alarms. On first launch it asks for the Alarms permission and the
> Notifications permission (used only for the "wake-up check" follow-up
> reminders). To test: add an alarm 1–2 minutes ahead, lock the device,
> wait for the full-screen alarm. After stopping it, a "did you wake up?"
> notification arrives after the configured delay; ignoring it re-rings
> a real alarm. No account, no network calls, all data stored locally.

## Nazwa — uzasadnienie i warianty

Wybrana: **Wstałem!** — to dokładnie ten przycisk, w który klikasz każdego ranka;
krótka, zapamiętywalna, unikalna na polskim rynku.

Alternatywy gdyby była zajęta: „Wstawaj!", „No Wstań", „Pobudka+";
wersja międzynarodowa: **I'm Up!** / **WakeProof**.
