# The 30 fps setting

Status, 2026-11-05: works. The launcher's Display tab has offered "Frame rate: 30 fps" (`DM_FPS=30`) since the Display tab came, but nothing in the
runtime read it: `gfx_fps_target()` answered 30 and no one asked (found by Quantum in his 1.2.4 package; the 1.2.6 notes list it as a known issue).

## How nxnative does it

nxnative (MIT, `dm/gfx/nvn/nvn_mtl.m` `mtl_fps_target`, `dm/gfx/nvn/hle_nvn.c` `nvn_game_fps` / `fps_present_cap` / `present_itv`): a game with a frame
step or an engine limiter the host can write (`hle_fpslock.c`) is told the cap; any other game, Pokopia among them (its profile names no `fps_target`
and it has neither), gets the display link at 30 Hz ("power-saving mode"). The game's acquires then wait for the link's ticks, so it presents 30 frames a
second, and the game's own pacing decides whether its world still runs at the right speed.

## Here

The emulated display (`hle_nvn.c`, `nxrt_nvn_display`, `present_itv`) shows each frame for the game's present interval in vsyncs; under the 30 fps
cap that interval is at least 2. A frame then stays on screen two vsyncs, the swap chain's textures are free half as often, and `WindowAcquireTexture`
holds the game at 30 a second, as the Mac's 30 Hz link does. The present period handed to the Vulkan present thread follows (33.3 ms). A game that asks
for a longer interval itself keeps it. Without `DM_FPS=30` nothing changes.

## Tests

2.0.1, a copy of the play save, the clock fixed, the same scripted walk (3 s forward) and camera turn (1 s) at 60 and at 30:

| | 60 fps | 30 fps |
|---|---|---|
| presents / s in the field | 56.9–59.9 | 30.00–30.01 |
| present interval p50 / p99 | 16.6 / 22–65 ms | 33.2 / 37–39 ms |
| vsyncs that showed no new frame | 0–16 per 300 frames | 0 |
| shown after the present | 14–28 ms | 52–57 ms |
| after the walk and the turn | | the same place and view as at 60 |

Pokopia's movement and camera are frame-time based, so at 30 the world runs at the right speed. The picture reaches the screen about a frame later at
30 (the swap chain of three lets the game run up to two frames ahead).

## 40, 45 and 50 fps

Asked for by a split-screen tester (two games on one PC, about 45–50 fps each and a hot PC): a steady rate between 30 and 60. They are in the
in-game menu's and the Settings window's Frame rate list, and in `DM_FPS`.

- **How.** 30 divides 60, so it stays two vsyncs a frame. 40, 45 and 50 do not divide 60. Under them the emulated display (`nxrt_nvn_display`)
  ticks at the cap's own rate, a frame a tick (25, 22.2 and 20 ms; `present_pace`), and starts its grid over when the rate changes. The swap chain
  then holds the game's acquires to that rate, as at 30. The host's present thread already presents on the period it is handed (`vk_present.c`), so
  the frames leave evenly.
- **On the screen.** 40 is even on a 120 Hz screen (three refreshes a frame). 45 and 50 are even with a variable refresh (G-Sync, FreeSync). On a
  fixed 60 or 144 Hz screen a frame stays two or one, or four or three, refreshes in turn; 48 would be the even choice at 144 Hz.
- **The game keeps its speed.** Pokopia steps its world by measured time, not by vsyncs. During a camera turn at 40, frames that took longer (a
  screenshot being written) moved the view by 23–71 pixels in proportion, never in whole-vsync steps. The same timed walk and turn ends in the same
  place and view at 40 as at 60.

| 2.0.1, RTX 4070 Ti (40: the field; 45 and 50: the title and the way in) | 40 fps | 45 fps | 50 fps |
|---|---|---|---|
| presents / s | 39.2–40.0 | 45.00 | 49.2–50.0 |
| interval p50 / p95 | 25.00 / 25.4–25.7 ms | 22.22 / 22.5 ms | 20.00 / 20.3–20.4 ms |

The longer frames (p99 up to 68 ms at 40) are the screenshots the test writes.
