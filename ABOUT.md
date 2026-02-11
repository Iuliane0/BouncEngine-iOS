# About BouncEngine

BouncEngine is a retro physics puzzle game inspired by the classic Nokia Bounce games. It's built from the ground up as a modern web game with a nostalgic soul — pixel art, chunky physics, and levels that feel like they belong on a phone from 2005, but running smoothly on anything with a browser.

## The Game

The idea is straightforward: guide a bouncing ball through obstacle-filled levels. You pick up collectibles, avoid hazards, and try to reach the end. Some levels are forgiving, some are not. The community has pushed the difficulty well beyond the original Nokia levels — packs like "Hard 22" and "Sharp Edges" are not for the faint of heart.

Everything about the game is designed around feel. The menus use a frosted-glass UI with subtle blur and lighting effects. There's a rain shader that falls over the main menu's skyline. The intro sequence plays a short credits roll with a gapless audio transition before dropping you into the menu. It's a small game, but it cares about the details.

## How It Works

BouncEngine runs entirely in the browser. The engine renders on an HTML5 canvas at 320×180 base resolution, then scales up to fill whatever screen you're on — keeping the pixel art sharp at any size. Everything from the physics to the audio to the level loading is custom JavaScript, no game frameworks or libraries.

The game works offline through a service worker that caches all assets on your first visit. After that, levels load from cache whether you have signal or not. When a new version goes live, the game checks on launch and updates itself in the background — no manual downloads, no app store reviews, just the latest version next time you open it.

## Community

BouncEngine is open to community contributions, particularly level packs. Several creators have already added their own packs with unique styles — from precision platforming to more exploratory designs. The level system is built to grow, and new packs can be added without touching the engine code.

## iOS

The iOS app is a thin native wrapper that loads the web game and provides a proper mobile experience — locked to landscape, full-screen with a dimmed home indicator, and persistent audio that doesn't cut out when you switch apps briefly. All game updates, caching, and offline support are handled by the web layer, so the app stays current without needing updates through any app store.
