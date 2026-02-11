# BouncEngine

**BouncEngine** is a retro-styled physics puzzle game built entirely with web technologies — playable in the browser at [bouncengi.net](https://bouncengi.net) and now available as a native iOS app.

## About the Game

BouncEngine is a love letter to classic Nokia-era puzzle games. You control a bouncing ball through handcrafted obstacle courses, navigating tricky terrain and collecting pickups to complete each level. The gameplay is simple to understand but gets challenging fast — precision, timing, and a bit of patience go a long way.

The game features a pixel-art aesthetic with a dark, moody atmosphere — think rain shaders, lens blur, and a cityscape skyline behind glassy menus. The soundtrack is seamless, looping through an intro and ambient track that blends into the gameplay.

### Level Packs

Levels are organized into community-contributed packs, each with its own style and difficulty curve:

- **Originals** by Nokia — The core 11 levels that started it all
- **The Vibe** by Halit Uslu
- **Hard 22** by TahirMoulvi
- **Fever Dreams** by Rob Linklater
- **Crawlspace** by IgorBounce
- **Czech Waters** by DaemonCZ
- **Hollow** by Bogoutdinov
- **Danger Pond** by Jarkko Mutkala
- **Precision Chamber** by TiggerfanaticSazzi
- **Sharp Edges** by EhmaBounce
- **Buoyancy Control** by Evan Bigall
- **Fly 'n' Dive** by Snuuba
- **Eventide** by radu3000

Over 60 levels and growing, with new community packs added over time.

### Features

- Pixel-art visuals with real-time rain shader and dynamic lighting
- Gapless Web Audio soundtrack with intro/loop crossfade
- Full offline support — play without an internet connection after the first load
- Automatic over-the-air updates — the game updates itself when new content is available
- Mobile and desktop support with landscape-optimized layout
- Community-created level packs with their own difficulty and character
- Account system for online features (in progress)

## iOS App

This repository contains the iOS wrapper for BouncEngine. The app loads the game from [bouncengi.net](https://bouncengi.net) and provides a native experience — landscape orientation, persistent audio, and full-screen immersion with a dimmed home indicator.

The game's own service worker handles caching, offline play, and updates. When a new version is published to the web, the app picks it up automatically — no App Store update needed.

### Building

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`. Builds run automatically via GitHub Actions on every push to `main`, producing an unsigned `.ipa` artifact.

To build locally:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project BouncEngine.xcodeproj -scheme BouncEngine -sdk iphoneos -configuration Release build
```

## Links

- **Play now:** [bouncengi.net](https://bouncengi.net)
