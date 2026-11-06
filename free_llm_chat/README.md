# Free LLM Chat

Minimal native chat client (Flutter) for **[Manifest](https://manifest.build)**, the open-source LLM
router/gateway. Windows 10 `.exe` + Android `.apk` from one codebase. Arabic / English (RTL/LTR), light/dark.
No backend of its own, no accounts, no analytics. The Manifest agent key lives in the OS secure store.

Manifest is the **only** backend: it picks the model and runs the fallback chain. The app sends one request
(`POST {base}/v1/chat/completions`, OpenAI format, streaming) and tells you, on every reply, which model answered
and whether it can cost money.

## Prerequisites
- Flutter SDK 3.22+ (`flutter doctor` must be green for Windows and Android)
- Windows: Visual Studio 2022 with "Desktop development with C++" (include ATL)
- Android: Android Studio + SDK, a device with USB debugging or an emulator
- A running Manifest (self-hosted with Docker, or Manifest Cloud), see below

## Windows prerequisite: Developer Mode
Plugins need symlink support. Enable it once: Settings > Privacy & security > For developers > Developer Mode
(or run `start ms-settings:developers`). Without it `flutter pub get` / `flutter build` fails with a symlink error.

## Setup (once)
```powershell
.\tool\setup.ps1
```
Generates `windows/` and `android/`, adds the INTERNET permission, `usesCleartextTraffic="true"` (so `http://` to
your LAN works on Android 9+), sets Android minSdk 23, and runs `flutter pub get`.

## Run
```powershell
flutter run -d windows
flutter devices
flutter run -d <android-device-id>
```

## Build release
```powershell
flutter build windows --release    # build\windows\x64\runner\Release\free_llm_chat.exe (ship the whole Release folder)
flutter build apk --release        # build\app\outputs\flutter-apk\app-release.apk
```
The APK is signed with the debug key, fine for sideloading. For your own key see
https://docs.flutter.dev/deployment/android#sign-the-app

## Verify
```powershell
flutter doctor -v
flutter analyze        # should report no issues
flutter test
flutter build windows --release
flutter build apk --release
```
After `setup.ps1`, `android/app/src/main/AndroidManifest.xml` must contain `android.permission.INTERNET` and
`usesCleartextTraffic="true"`, and the Android build file must set `minSdk` to at least 23.

## Run Manifest yourself (Docker)
Manifest's own quick start (see https://manifest.build/self-hosted/):
```bash
bash <(curl -sSL https://raw.githubusercontent.com/mnfst/manifest/main/docker/install.sh)
```
1. Open http://localhost:2099 and sign up. The first account becomes the admin.
2. Connect at least one provider (API key, subscription or local model) in the dashboard.
3. Create an agent (newer Manifest docs call it a *harness*) and copy its key. It always starts with `mnfst_`.
4. On Routing, set the default tier's model and fallbacks (see "Make `auto` safe" below).

Notes:
- The installer is a bash script. On Windows run it from WSL or Git Bash with Docker Desktop running. Check
  Manifest's `docker/DOCKER_README.md` if it differs on your machine.
- By default the Docker Compose setup listens on `127.0.0.1` only. To reach it from a phone on your network, per
  Manifest's Docker docs: in `docker-compose.yml` change the port mapping from `"127.0.0.1:2099:2099"` to
  `"2099:2099"`, set `BETTER_AUTH_URL` in `.env` to the address you use (e.g. `http://192.168.1.20:2099`), then
  `docker compose up -d`.

## Connect the app
Open Settings:
1. Press **Self-hosted** (`http://localhost:2099`) or **Manifest Cloud** (`https://app.manifest.build`). The field
   stays editable: the Cloud "Set up agent" dialog may show another base URL, copy it from there if so.
2. Paste the agent key (`mnfst_...`). It is masked, stored with `flutter_secure_storage`, and never logged.
3. **Test connection** calls `GET /v1/models?cost=true` with what is typed (nothing is saved) and reports how many
   models are free / paid / unknown. **Save** stores it and reloads the price list.

The base URL can be typed with or without `/v1`, with or without a trailing slash (a pasted
`.../v1/chat/completions` also works). Requests always go to `{base}/v1/...`.

- **Windows `.exe` on the same PC:** `localhost` works.
- **Android:** `localhost` is the phone itself. Use the PC's LAN IP (`http://192.168.1.20:2099`) and expose
  Manifest on the LAN (above). In the Android emulator the host PC is `10.0.2.2`.
- **Plain `http://` is accepted only for localhost and LAN addresses** (loopback, 10/8, 172.16/12, 192.168/16,
  169.254/16, 100.64/10 such as Tailscale, `.local`/`.lan`, single-word host names). Anything else must be `https://`,
  otherwise the key would travel unencrypted. Android's `usesCleartextTraffic` is global and cannot be limited to
  LAN ranges, so this rule is enforced by the app. `https://` (Manifest Cloud) is not affected.
- Manifest Cloud needs a Pro subscription to route requests at all (error M204, per Manifest's API docs).

The model chip under the composer (and Settings > Model) opens the model picker: `auto` first, then every model from
`/v1/models?cost=true`, coloured by billing class. `auto` lets Manifest route (with its fallbacks); choosing a specific
model skips routing and fallbacks.

## The paid-model warning
Manifest returns no "free/paid" flag and no cost header, so the app classifies models itself from the per-1M-token
prices in `GET /v1/models?cost=true`:

| Class | Rule | Shown as |
|---|---|---|
| Paid | input price > 0 or output price > 0 | red, with prices |
| No per-token charge | input and output are both 0 | green: "free or covered by a subscription" |
| Unknown | no price data, only one price and it is 0, or the model is not in the list | amber, "may be paid" |

What the app does:
- **Price list:** kept in memory only; reloaded on app start, after you save settings, from the refresh button in the
  model picker, and every 10 minutes. If a load fails, every model is treated as unknown and the app says so.
- **Specific model selected:** if it is paid or unknown, a dialog shows the model and its price (`$X in / $Y out per 1M
  tokens`) with *Send once*, *Cancel*, and *Switch to auto & send*. Cancel puts your text back in the composer.
- **`auto` selected:** the app cannot know the model before sending, so a persistent notice shows above the composer
  whenever the list contains any paid or unknown model (or could not be loaded).
- **Every reply:** the app reads `X-Manifest-Model` and `X-Manifest-Provider` as soon as the response headers arrive
  (before the first token), looks the model up in the list, and shows a badge: green / red with prices / amber. If
  `X-Manifest-Fallback-From` is present it also shows "Fell back from ...". If the headers are missing it shows "Served
  model unknown" in amber. The badge is saved with the chat.
- **Estimated cost:** on paid replies, if the response carries `usage`, the app shows an estimate computed from the list
  prices, labelled as an estimate.
- **Settings > Warn about paid models** is on by default. Turning it off asks for confirmation and removes the dialog and
  the `auto` notice. The per-reply badge is always shown.

### Limits you should know
- **`auto` is only detected after the fact.** The badge appears when the response starts, when the request is already
  running upstream. Nothing in the client can stop an `auto` request from reaching a paid model.
- **0 means "no per-token charge", not "free".** Free tiers and subscription-covered routes both report 0 and cannot be
  told apart. A subscription route can still use up your subscription quota.
- **Matching is heuristic.** Manifest's docs show the served model without its provider prefix (`claude-sonnet-4-6` +
  `anthropic`) while the list uses `provider/model` IDs. The app tries the exact ID, `provider/model`, and a `/model`
  suffix (each also with a `-subscription` variant). If several entries match with different billing (a normal route and a
  `-subscription` route of the same model) the result is amber, never green. If no entry matches it is amber too.
- **Prices are a snapshot** from the last list load; a reply's badge keeps the prices it was classified with.
- **The cost estimate is often missing.** The app asks for `stream_options.include_usage`, but Manifest only forwards that
  to OpenAI and OpenRouter. Other providers do not return `usage` through it, so no estimate is shown.
- **Manifest answering by itself** (a spend block, no provider connected, a model it cannot serve) reports `manifest` as
  model and provider. The app shows "Answered by Manifest itself (no model called)", not a price.
- **Timeout:** the app waits 90 s for the first byte; Manifest's own per-attempt timeout defaults to 180 s, so a long
  fallback chain can outlast the app. If the app gives up, Manifest may still finish the request, and it can still be billed.
- A failure in the middle of a stream is not retried by Manifest; you keep the text received so far.

### Make `auto` safe (do this in Manifest)
The reliable protection is configured in Manifest, not in the app:
- Routing: set the default tier's model and its up-to-5 fallbacks to models with no per-token charge only, and connect only
  the providers you want.
- Limits: add a **hard limit** (a spending cap per agent/key, with the block action). When it trips, Manifest answers with an
  HTTP 200 whose text starts with `[🦚 Manifest M200]` and nothing is sent to a provider. The app recognizes such messages and
  shows them as an error instead of an answer (it also does this for other `[... Manifest Mxxx]` messages, e.g. M005 for a bad key).

## Errors the app explains
Bad key (401 / M005), rate limit (429 / M201-M203), payment or quota problem (402 / M204), spending limit reached (M200),
model not available for this key (M302 / M101), every fallback failed (`X-Manifest-Fallback-Exhausted: true` or body code
`fallback_exhausted`), **connection refused** (Manifest is not running: start it with `docker compose up -d`, check the
port; on Android use the PC's LAN IP), timeouts and other network errors.

## Upgrading from the multi-provider version
The first launch after the update shows a one-time notice: keys saved for other providers are no longer used and are then
deleted from secure storage (put those keys in Manifest instead). The old "Manifest (router)" entry is carried over (its
URL and `mnfst_` key become the new settings). Old chats still open; replies from the old auto-switch simply have no badge.

## Structure
- `lib/data`: `manifest_config.dart` (URL normalization), `manifest_cost.dart` (classifier, price list, lookup, estimate),
  `manifest_headers.dart` (`X-Manifest-*` parsing), `served_by.dart` (per-reply billing info), `manifest_client.dart`
  (`/v1/models`), `llm_provider.dart` (streaming chat), `secret_store.dart`, chat models and Hive history
- `lib/state`: `SettingsController`, `ModelCatalogController` (price list), `ChatController`
- `lib/ui`: chat, history drawer, settings, model picker, paid-model widgets, `markdown_view.dart`
- `lib/core`: AR/EN strings (`strings.dart`, two maps `_en` / `_ar`), error types
- `test/`: unit tests for the classifier, header parsing, URL normalization, provider, client, settings migration, history

## Notes
- Long chats: only the most recent messages that fit a character budget are sent (`kMaxHistoryChars` in `lib/data/history.dart`);
  the full chat stays in your history.
- Fonts (Inter + Noto Sans Arabic) are fetched once by `google_fonts` and cached; offline first run falls back to system fonts.
- Desktop: Enter sends, Shift+Enter = new line.
- Messages: copy, edit (user messages), regenerate (last reply).
