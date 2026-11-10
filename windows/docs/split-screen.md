# Split-screen co-op: two players on one PC (experimental since 1.4.0)

Prototype on branch `splitscreen` (2026-11-08), shipped in 1.4.0; the layouts, the window placement fix and a menu for each window on branch
`split-polish` (2026-11-09), from the first player tests. Windows; the pieces are nxrt's and the launcher's, so Linux can follow.

## How it works

Two games, one in each half of the screen, joined by Link Play over this PC (loopback, the same way as two PCs on a network):

- **The layout:** stacked (top and bottom, each window the screen's full width; the default) or side by side, chosen under "Split screen" in the
  launcher window. Each window fills its half. The game's picture is 16:9, so a half wider than that (stacked, on any usual screen: 32:9 on a 16:9
  one) gets the **wide view** (`NXRT_VK_WIDE`, the Display tab's "Wide view"), which fills it with more of the world; a narrower half (side by side:
  8:9 on a 16:9 screen) shows the whole picture with bars above and below.
- **Window 1** hosts with the player's own save. It plays the keyboard, the mouse and the first controller.
- **Window 2** visits with the **split-screen save** and plays the second controller. It is muted and closes when window 1 closes. It starts without
  the keyboard (window 1 keeps it); **a click on window 2 gives it the keyboard**, so its F1 menu can be used, and a click on window 1 gives it back.
- **Each window's menu:** F1 opens the menu of the window that has the keyboard; a controller's Minus + Plus opens the menu of that controller's
  window, and only that controller works it there.
- **The split-screen save** is made from the player's save the first time (`scripts/splitsave.ps1`) and then kept in its own folder (`<save> (split
  screen)`), so the second player keeps what they pick up. The player's save is only read. The game refuses a second copy of a save in its own session
  (error 9005, "a user with the same user ID is already in the session"); what it compares is the 16-byte user ID in `S00\SYDAT.BIN` at 0x61, a file
  without a checksum ([coop-step1.md](coop-step1.md#why-one-save-is-refused)). The split save is a copy with only that ID changed (SHA-256 of a fixed text
  and the old ID: made again from the same save it is the same second player).
- **Interact everywhere** is on in both: in a story town the visitor can do little without it. `-Story` turns Story co-op on too.

## Starting it

In the launcher window: Link Play tab → "Split screen: two players on this PC", its Layout (with "Story co-op" if wanted) → Play. play.ps1 then
hands over to split.ps1 with the same paths and the layout (linkplay.json's `split_layout`, `stack` or `side`). From a command line:

```
powershell -ExecutionPolicy Bypass -File scripts\split.ps1 -Config <play.json>          # the installed game's paths
powershell -ExecutionPolicy Bypass -File scripts\split.ps1 -ExeFS ... -Dll ... -RomFS ... -Save ... -Exe ... -Shaders ...   # or given one by one
```

Options: `-Story` (Story co-op), `-Keyboard` (player 1 on the keyboard and mouse only, player 2 the first controller), `-Layout side` (side by side
instead of stacked; the wide view goes on for halves wider than 16:9 unless `NXRT_VK_WIDE` is already set), `-Sound2` (window 2 with sound), `-Port` (default 47660), `-SplitSave <folder>`, `-DryRun` (prints both command lines, makes
nothing). Then in the games: window 1, PC → Link Play → Invite Others to Visit → Local connection; window 2, PC → Link Play → Visit a Friend → Local
connection → the host's town.

nxrt's switches behind it (`split.ps1` sets them; `play.ps1` passes them on):

| switch | does |
|---|---|
| `DM_SPLIT=1` / `2` | this game is window 1 or 2: borderless, filling its half of the main display's usable area (vk_window.c), put back there whenever Windows moves it; size and fullscreen requests (F11, Alt+Enter, the Display tab) ignored; window 2 starts without the focus and takes it when clicked; the log console minimized |
| `DM_SPLIT_PAD=<n>` | the controller in place n (1-based, in connection order; the one remembered as player 1 comes first) is this game's player 1; 0 none. Default: the window's number. Other controllers do nothing here, not even in the menu; controllers play while the window is out of focus (front_sdl.c) |
| `DM_SPLIT_LAYOUT=side` | side by side; anything else stacked (top and bottom) |

Window 2's game takes no keyboard or mouse input; with the keyboard (after a click) only its menu does. The game's log console is minimized by nxrt
itself: 1.4.0's launcher started the game minimized instead, and Windows applies a minimized start to the game's first window too. Window 1 then
came back at its starting place, centred at 960x540, instead of in its half (window 2, shown without being activated, escaped it).

## Tested (2026-11-08, this PC)

- `scripts.split_save` (15 checks, stand-in saves): only the ID's 16 bytes differ, every other file is byte-for-byte the same, the player's save is
  unchanged, made once then kept (the second player's changes stay), the same ID when made again, refusals (no system save yet, the same folder, a plain
  copy, a folder holding something else, a file without the game's magic).
- `nxrt.pad_sdl_split` (virtual controllers, DM_SPLIT=2): only the second controller plays, as player 1, also out of focus; the first, the keyboard and the
  mouse do nothing; detached, nothing stays pressed. `nxrt.pad_sdl` (one window as before) still passes.
- **The game**, copies of a Level 2 save (test copies only): `split.ps1 -Story` made the split save, both windows opened side by side (each 1920x1080 on a
  3840x2160 display at 150%), window 1 hosted, window 2 found it (the host's name and Withered Wasteland) and **arrived** (no 9005); both screens show both
  characters. Closing window 1 closed window 2 within a second.
- **Not tested:** two real controllers (none could be connected here: the controller split is covered only by the virtual test), sound from window 1
  with window 2 muted (the switches are play.ps1's own -Silent), a long session, the second player's save after a session.

## Tested (2026-11-09, this PC, branch split-polish)

- **The 1.4.0 bug, reproduced:** 1.4.0's launcher and game, window 1 on its own: it started minimized (Windows applied the minimized start to it), and
  restored it came back at 1440,774, 960x540, the middle of the screen, as the player saw. Window 2 is shown without being activated and escapes it.
- **Fixed, each window on its own** (only 4.8 GB was free, too little for two games at once), on copies of a Level 2 save, 3840x2160 at 150%:
  stacked, window 1 at 0,0 and window 2 at 0,1044, each 3840x1044, the wide view on (a 16:9 camera gets aspect 3.68); side by side, each 1920x2088
  with the picture in the middle and bars above and below. A real click on window 2 gave it the keyboard ("window 2 takes the keyboard" in its log)
  and F1 then opened window 2's menu.
- `nxrt.pad_sdl_split` checks the menu in window 2: the first controller's Minus + Plus leaves it shut, the second's opens it, the first one's B
  leaves it open and the second's closes it. `scripts.split_save` checks split.ps1's layouts (stacked by default with the wide view; side by side
  without), `scripts.play_defaults` the launcher's remembered layout reaching split.ps1.
- **Not tested yet:** both games at once with the fix (memory), a second display, a TV.

## Cost (this PC: Core i9-13900KF, 24 cores / 32 threads; RTX 4070 Ti; 32 GB; both games in town, 1920x1080 windows)

| | each game | both |
|---|---|---|
| frame rate | 59.9 per second, p99 19 ms | both steady |
| CPU | about 2.5 cores busy (8% of 32 threads) | about 5 cores |
| GPU (3D engine) | 13-14% | 27% |
| memory | about 5 GB (2.1-2.2 GB private, the rest the mapped game files) | free memory went from 11.8 GB to 1.1 GB |

What a PC needs, by these numbers (only this PC was measured): memory is the limit. **32 GB recommended, 16 GB is too tight** (two games take about
10-11 GB before Windows and a browser). A CPU with 8 or more cores; a graphics card that runs one game comfortably at 60, since it renders twice
(lowering the game resolution in the Display tab, or the console mode "handheld", 720p, halves the GPU's share).

**The CPU:** split screen is two whole games running at once, each with its own copy of the game's work, so the processor does everything twice. A
PC that holds 60 with one game may not with two, above all a laptop (whose processor slows down when it gets hot). If the frame rate drops, try "30
fps" in the Display tab of both windows' menus: each game then makes half as many frames.

## Limits (by design, as with any Link Play)

- The second player is a **visitor**: the host's town, the host's story. Story co-op's limits apply (docs/story-coop.md): what the visitor does in the
  world counts for the host, story steps only through the host (the story-host branch fixes the host's own story while a session is open).
- The second player starts as a **copy of the first character**: the same name and look. Changing them needs the
  compressed CMNDAT.BIN (not done).
- Both players go through the game's own Link Play menus each time (host, then visit). Automating that is open.
- Window 2's first start copies window 1's shader cache, so it does not compile from nothing.

## What's left

1. ~~Two real controllers on real hardware~~: a player's test of 1.4.0 (2026-11-09: a Ryzen 7 H 255 laptop with an RTX 3080 Ti, a 16:9 TV, two
   controllers, Story co-op and the wide view on) played with one controller per window; Interact everywhere worked for the visitor (watering,
   breaking blocks, Rock Smash, placing things); the saves behaved as written here; "go home" took both players.
2. F1 → Link Play: "Start split screen" from inside the game (window 1 would have to take its half while running). The launcher's choice is done
   (tried as a dry run from a remembered choice; the window itself not clicked through).
3. The second character's name and look (CMNDAT.BIN), so the two can be told apart.
4. Automating the Link Play menus (host and visit) at start.
5. Linux (the same switches; split.ps1's part in play.sh), Mac and iPhone (no second instance on an iPhone).
6. Measure on a 16 GB PC and a mid-range graphics card.
