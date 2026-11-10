# The Steam Deck's frame: the first batch of work (2026-11-09)

**Why.** A Steam Deck OLED player reported the mid-40s in caves and the high teens in the main hub (1.4.0). A read-through of the replay, the
Vulkan backend, the translated shaders and the runtime's threads found where a busy scene costs more on a Deck than it needs to:

- **The replay thread does fixed work at every draw.** By estimate that is about 8 µs a draw on a Deck core. A hub with 2–3 times the field's
  draws comes to 36–54 ms, which is high teens, whatever the resolution.
- **On the GPU side, the Deck draws 1920x1080 to show 1280x720.**

The shaders themselves were not the problem; translation adds an estimated 10–15 %.

## What changed

| Piece | Where | Off switch |
|---|---|---|
| Vertex input set only when it differs from the draw before; on RADV each `vkCmdSetVertexInputEXT` is a vertex-shader prolog lookup | `vk_replay.c` `set_vertex_input` | `NXRT_VK_BIND_KEEP=0` |
| A descriptor set already bound at its number with the same layout is not bound again (it was bound for every stage at every draw) | `vk_replay.c` the draw | `NXRT_VK_BIND_KEEP=0` |
| A texture read from guest memory is checked once per game submission. It used to scan every page's write generation at every bind: 1,000+ loads for a large atlas. A submission's uploads all run before its draws, so a second check could only upload over the first. | `vk_tex.c` `refresh`, `vk_submit.c` `vks_sub_serial` | `NXRT_VK_TEX_ONCE=0` |
| Linux only (not Android): timed guest waits wait on their condition variable to the deadline itself, so a wake ends them at once. Before, the last 1.5–2.5 ms slept deaf to wakes and then yielded through the rest: Windows' timer numbers, where Linux's timer is exact to its 1 µs slack. Guest sleeps sleep to the deadline. Spin waits and runs of yields back off after 200 µs instead of 2 ms. The present thread's pacing sleeps without yielding through its end. | `host/hle_thread.c` (`LINUX_TIMERS`), `vk_present.c` `sleep_until` | `DM_SPIN_POLL`, `DM_YIELD_BACKOFF` (µs) |
| Resolution below 1x (factors 0.5 to just under 1): 1280x720 and 1600x900 in F1's Resolution list. A picture drawn smaller is upscaled sharp on a larger window. | `vk_tex.c` `scale_clamp`, `front/menu.c`, `vk_present.c` | — (a size picked in F1) |
| A Steam Deck starts at 1280x720 with FXAA (it was 1920x1080 shrunk to 1280x720, with SMAA), until the player picks a resolution or anti-aliasing | `scripts/play.sh`; the installer's launcher window | — |

## Diagnostics added

- **The frame-pacing line** (`[nvn] frame pacing`) adds:
  - **`SyncWait blocked`:** ms a frame, waits a frame, and how many submissions behind the newest the waited sync was. 0 means the game waits for
    what it just submitted, so its thread, the replay and the GPU take turns.
  - **`drains`:** finalizes, readbacks, `QueueFinish` and `MapVirtual` waiting for the whole replay queue.
- **The replay line** (`[vk] replay up to frame`) counts the set binds and vertex inputs kept from the draw before.
- **F1 → FPS counter → Detailed** shows the GPU's time and the replay thread's time a frame beside the frame time. A Deck player's screenshot then
  tells which one is short.
- **`NXRT_VK_DYNAMIC=0`** bakes vertex input and colour blending into each pipeline, for an A/B on RADV (no vertex prolog or fragment epilog; more
  pipelines).

## Measured (2026-11-09)

**Setup.** The graphics session's run on this PC: losttest's route into the field on a copy of the save, the clock fixed, 7,800 presents, a warm
cache, statistics from frame 4,500. i9-13900KF and RTX 4070 Ti. No Deck was measured.

**The replay's work, pinned to two E-cores** (mask 0x30000, CPU-bound), at 1920x1080 docked. Two pairs, the second in reverse order:

| | Replay thread | Frame rate |
|---|---|---|
| `NXRT_VK_BIND_KEEP=0 NXRT_VK_TEX_ONCE=0` (before) | 9.98 / 10.11 ms a frame | 37.9 / 41.7 |
| this branch | 8.94 / 9.55 ms a frame | 45.3 / 39.2 |

- **The replay thread:** about 0.8 ms less a frame (−8 %).
- **The frame rate:** on two E-cores it moves by ±4 between runs of the same build, so these runs show no difference either way.
- **What the replay line counts** (handheld field, about 2,600 draws a frame): 2,407 vertex inputs and 3,285 descriptor set binds kept from
  the draw before.
- **Uploads and write faults** (3.1 ms and 1.8 ms a frame here) are now about half of what is left: the next piece of work.

**Resolution** (handheld field, all cores):
- GPU time: 2.74 ms a frame at 1920x1080, 2.24 ms at 1280x720 (−18 % on this GPU; more of a Deck's GPU time depends on pixels).
- The 1280x720 screenshots match the 1920x1080 ones apart from size: lighting, shadows, outlines and the HUD.
- The log's RED lines are the same two in both runs.

**Waits.** `SyncWait blocked` was 0.00 ms a frame (no waits) and drains 0.02 a frame: on this PC the game never waits for the GPU or the replay.
A Deck's line says whether it does there.

**Not measurable here:** the Linux sleep and wait changes (Windows keeps its own path).

## The second batch: uploads and write faults

**Where the CPU went.** In the field, the replay thread's uploads of guest memory took about 3 ms a frame on two E-cores, and about 400 write faults
a frame cost 1.7 ms more. The 300-frame memory line and `NXRT_VK_UPLOAD_TOP=1`, now with write faults counted by MB, show three causes:

- **Rescans.** Every buffer binding of every draw rescanned its pages: about 9,300 range checks a frame.
- **A slow ring.** All faults land in pool 0. Most of them come from a ring the game streams its per-frame data through, about 64 MB that comes
  round every ~40 frames. The rule "hot after 3 frames in a row" never caught it, so each page faulted and was protected again at every pass.
- **One small area.** About 70 faults a frame come from MB 82–91 of pool 0. The pages there are written every frame in a 4 MB pattern. Not changed
  yet: the next thing to look at.

| Piece | Where | Off switch |
|---|---|---|
| A buffer range already found current in this submission, with nothing in its pool written since, is not scanned again. That holds when nothing is waiting on a GPU write and nothing is uncommitted. The tracker now counts the writes to each range (`nvn_dirty_span_writes`). | `vk_mem.c` `vkm_use`, `gfx/nvn_dirty.c` | `NXRT_VK_SYNC_MEMO=0` |
| A page is hot once rewritten 3 times, each within 64 frames of the one before (it was 3 frames in a row). A rewrite that came from a GPU write-back does not count. Hot pages cool a slice a frame, each once every 1,920 frames; all at once, the ring's pages faulted back in bursts. | `vk_mem.c` `page_rewritten`, `vkm_frame_tick` | `NXRT_VK_HOT_HIST=0` |
| `NXRT_VK_UPLOAD_TOP=1` also logs the MBs with the most write faults | `gfx/nvn_dirty.c` `nvn_dirty_fault_where` | — |

**Measured on two E-cores** (mask 0x30000), field, 1920x1080. Two pairs; off is `NXRT_VK_HOT_HIST=0 NXRT_VK_SYNC_MEMO=0`:

| | Replay thread | Uploads (CPU) | Write faults | Frame rate |
|---|---|---|---|---|
| off | 9.65 / 9.00 ms | 3.15 / 2.97 ms | 401 / 400 (1.67 / 1.71 ms) | 37.4 / 44.8 |
| on | 7.54 / 7.45 ms | 1.75 / 1.77 ms | 94 / 90 (0.56 / 0.52 ms) | 40.5 / 43.9 |

- **The replay thread:** 1.8 ms less a frame (−20 %).
- **Both batches together:** from about 10.0 to 7.5 ms a frame on two E-cores.
- **The frame rate:** again within the run-to-run swing on two E-cores.
- **On Linux** a fault and its re-protection cost several times what they cost on Windows (3.7 + 2.7 µs idle, 7.7 + 5.5 µs with seven busy
  threads in WSL), so the ~310 fewer faults a frame count for more on a Deck.

**What the counters show** (all cores):
- **The memo** answers about 6,600 of the 9,300 range checks a frame.
- **Write faults** come down from about 430 to about 75–105 a frame, with 16,400 hot pages.
- **Uploaded bytes** are unchanged (1.4–1.7 MB a frame): the ring's pages were copied at use before as well.
