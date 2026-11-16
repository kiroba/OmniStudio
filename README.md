# OmniStudio

OmniStudio — the creation engine for The Omniverse (create and sign in Studio; nodes carry and stream; the Hub lives it). Split out of [kiroba/The-Omniverse](https://github.com/kiroba/The-Omniverse) with its git history (Oct 30 2026). This repo was renamed from Phaser-Studio to **kiroba/OmniStudio** (verified Nov 15, 2026); internal names still lag — the pubspec/package is still `phaser_studio` — and that sweep is separate.

## Status (Nov 16, 2026)

- **Desktop build + API hook — merged Nov 15, 2026 (PR #13).** Windows + Linux desktop builds, and a read-only loopback API hook (port 9200, token auth; health / state / library v1) so tools can view inside OmniStudio. George views through the hook — there is no embedded in-app chatbot/persona.
- **Content:** .omnimod figure and stage-prop packs are staged and compiled here, with real Ed25519 pack signing; OmniStudio is the authoring home for Halo skill packs.
- Still owed: the laptop runtime test (app opens, hook answers on 127.0.0.1:9200 with the token file).

## Build
```
flutter pub get
flutter build apk --release --target-platform android-arm64
```
Shared code comes from [Omni-Core-UI](https://github.com/kiroba/Omni-Core-UI), pinned by tag in `pubspec.yaml`. Android package: `com.omniverse.phaser_studio`.

CI here makes test builds (debug key). Signed releases still come from the monorepo's `release.yml` until release orchestration moves.

`design/` holds NotebookLM design screens (UI only, not wired yet).
`tool/build_multi_app_suite.py` is the old generator, kept for reference.
