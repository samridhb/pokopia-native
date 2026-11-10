# 32-lane subgroups on 64-lane GPUs (#40)

**The problem.** NVN's shaders are written for NVIDIA's 32-lane warps, and the translated SPIR-V keeps those assumptions:
- it reads a ballot's `.x`;
- it clamps shuffle source lanes to 31;
- it votes over 32 lanes.

AMD's GPUs run 64-lane subgroups. RDNA can be asked for 32 per pipeline (subgroup size control, `NXRT_VK_SUBGROUP32=1`); GCN (Polaris: RX 470–590,
Vega) cannot. #40's RX 570 shows dark smeared patches on the ground and squares in the sky. Those look like a tiled pass (light lists, cluster bounds)
computing wrong results for half of each subgroup.

## The rewrite (`vk/vk_shader.c`, `vkspv_sg32_emulate`)

Applied in `vksh_make` when a module is made; the shader cache is unchanged. Each 32-lane half of a 64-lane subgroup acts as one warp:

| In the translation | Becomes |
|---|---|
| the lane index (`SubgroupLocalInvocationId`) | `lane & 31` |
| `SubgroupSize` | 32 |
| `LtMask` (and Eq/Ge/Gt/Le): loaded whole, or `.x` through an access chain | the lane's half's word in `.x`, 0 in the rest |
| `OpGroupNonUniformBallot` | the same, moved likewise |
| `OpGroupNonUniformAny` | the half's word of a ballot of the predicate, not 0 |
| `OpGroupNonUniformAll` | the half's word of that ballot equals the half's word of a ballot of `true` (the active lanes) |
| `OpGroupNonUniformShuffle` | source lane `(id & 31) \| (lane & 32)` |

- A module without a lane index of its own gets one, declared and added to its entry points.
- Any other subgroup operation, or the subgroup count/id, leaves the module as it is, with a red log line. NVN's translations have none: across the
  4,031 modules of our cache, 49 use subgroups (34 fragment, 15 compute), with only these four operations and the lane index and `LtMask`.

**On 32-lane subgroups it changes nothing.** The half is always the first, and a ballot's or mask's upper words are 0. The one difference is a shuffle
from lane 32 or above, where the original is undefined. A check of every one of the cache's 49 shuffles found that the translator discards that
result anyway: its in-bounds test selects the lane's own value instead. So the rewrite is safe wherever size control gives 32.

## When

`NXRT_VK_SUBGROUP32` (`vk_dev.c`):

| Value | Size control | Rewrite |
|---|---|---|
| unset | off | where subgroups may have 64 lanes (the device's size or largest size is 64: AMD) |
| `1` | where the driver allows | as unset |
| `0` | off | off (the driver's size, as translated) |
| `emulate` | off | on any GPU (a test: on NVIDIA's 32 lanes the results are the same) |

The log says which: `subgroups of 64 lanes (sizes 32 to 64): shaders that use them act on 32-lane halves`, then one line per rewritten shader.

**Fewer than 32 lanes** (lavapipe's 8, some Intel GPUs): a subgroup holds less than a warp, so the rewrite cannot help and stays off. Where size
control allows 32, `NXRT_VK_SUBGROUP32=1` gives NVN's results; otherwise the shaders run as translated. The tests skip their GPU and corpus parts there.

## Tests

- **`nxrt.vk_sg32`:**
  - `test_sg32.comp` (the lane index, a shuffle, a ballot, `LtMask.x`, Any, All, with lanes leaving early) is rewritten and checked on its words.
  - So is `test_sg32_vote.comp` (no lane index of its own), and `test_sg32_bcast.comp` (a broadcast: left as it is).
  - On a GPU the rewritten shaders give what 32-lane warps give (a CPU model), whatever the GPU's subgroup size. On 32-lane subgroups they give exactly
    what the shaders as compiled give.
- **`nxrt.vk_sg32_corpus`:** every module of the shader caches in `NXRT_TEST_CORPUS` that uses subgroups is rewritten (nothing left for 64 lanes) and
  made with validation on, and the compute ones are made into pipelines. That is 49 of 49 in our cache and 47 of 47 in the 1.4.0 kit's, with 15 + 15
  compute pipelines and no validation errors.
- **In the game on an RTX 4070 Ti:** the downloaded 1.4.0 game was run with `NXRT_VK_SUBGROUP32=emulate` (7 shaders rewritten in the field) and
  without, with the same input at the same frames. Vulkan validation had 0 errors, and the pictures look alike. Pixel for pixel the game's own timing
  dominates: two runs without the rewrite differ in 0.4–1.9 million pixels of 2.07 million, and the run with it differs from one without by the same
  (0.5–1.4 million). `DM_DETCLOCK`, which would make runs repeat exactly, stalls after the first present on this build, with or without the replay
  thread.
- **Not tested here: a 64-lane GPU.** The RTX cannot run 64-lane subgroups, so the halves' arithmetic is proven on #40's RX 570.
