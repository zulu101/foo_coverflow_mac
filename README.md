# foo_coverflow_mac

A native **coverflow** view for [foobar2000 for macOS](https://www.foobar2000.org/mac).
Browse your media library by album cover, flip a cover to see its track list,
and play exactly the track you want.

Windows coverflow components such as `foo_chronflow` don't run on the Mac
version of foobar2000, so this one is written from scratch in Objective-C++ and
Core Animation on top of the official foobar2000 SDK.

<img width="1492" height="920" alt="Bildschirmfoto 2026-11-09 um 22 22 08" src="https://github.com/user-attachments/assets/a46c72fd-a5ce-49f1-ba12-6eb6e8145eb7" />


## Features

- 3D coverflow of all albums in the media library, grouped by album artist + album
- Cover art from embedded pictures or external files (`folder.jpg` etc.), loaded in the background
- Reflections, smooth scrolling with trackpad, mouse wheel or keyboard
- Click the centered cover to **flip** it: the back shows album, artist, year,
  track count, total length and the track list
- **Double-click a track** (or press Return) to play only that track; it is
  added to the active playlist if it isn't there yet
- Right-click a track: play, add to playlist, add the whole album to playlist
- Click next to the back side, press Esc or keep scrolling to flip back
- Updates automatically when the media library changes

## Requirements

- foobar2000 for macOS **2.24 or newer** (third-party UI elements); tested with 2.25.10
- macOS 14 or newer, Apple Silicon (arm64)

## Installation

1. Download the `.fb2k-component` file from the [Releases](../../releases) page, or build it yourself (see below).
2. In foobar2000 open *Preferences → Components*, install the file and restart foobar2000.
3. Add the element `coverflow` to your layout (*View → Layout → Edit Layout*).

Example: coverflow across the full window width, above the playlist:

```text
splitter horizontal style=thin
 coverflow
 playlist
 playback-controls
```

Drag the splitter to change its height. The height sets the cover size, the
width sets how many albums you see side by side.

## Controls

| Action | Result |
| --- | --- |
| Swipe, scroll wheel, ← → ↑ ↓ | Previous / next album |
| Page Up / Page Down, Home / End | Jump 10 albums / to first or last |
| Click a side cover | Move it to the center |
| Click the center cover, Space, Return | Flip to the track list |
| Double-click a track, Return | Play this track |
| Right-click a track | Play / add to playlist / add album |
| Click next to the back side, click its header, Esc, scroll | Flip back |

## Building

Requirements: Xcode (command line tools are used, no project file needed).

```sh
./build.sh           # builds build/foo_coverflow_mac-<version>.fb2k-component
./build.sh install   # also copies the component into ~/Library/foobar2000-v2/user-components
```

On the first run the script downloads the
[foobar2000 SDK](https://www.foobar2000.org/SDK) into `vendor/sdk` and builds
its static libraries. Restart foobar2000 after installing a new build.

## Project layout

| File | Purpose |
| --- | --- |
| `src/ui_element.mm` | Registers the `coverflow` UI element with foobar2000 |
| `src/CoverflowViewController.mm` | Glue: library, cover loading, flip animation, playback |
| `src/CoverflowView.mm` | The 3D coverflow (layer-hosting view, Core Animation) |
| `src/AlbumBackView.mm` | Back side with album info and track list |
| `src/AlbumModel.mm` | Reads albums from the media library, loads covers, playlist actions |

## License

MIT, see [LICENSE](LICENSE). The foobar2000 SDK is not part of this repository
and is subject to its own license.
