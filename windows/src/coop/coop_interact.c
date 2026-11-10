// coop_interact: "Interact everywhere" (docs/coop-interact.md), an experimental opt-in for Link Play outside Palette Town, and "Story co-op"
// (docs/story-coop.md), the experimental step after it. MIT, our own code.
// The game keeps a session's permissions in a 36-bit mask (GameMgr+0x8c; its top bits are the online / host / visitor bits at +0x90) and rebuilds it
// whenever a session starts or the town changes. In a story area (stage type 1: Withered Wasteland and the other story towns) an online player always
// gets the Spectator pattern, whatever the host chose; Palette Town with Spectator Mode Off gets the normal online pattern. One site per supported main
// build swaps the first for the second while the session's own Spectator flag is clear. Each port reaches the site its own way (nxnative: an
// observation gate; Windows: nxrt interprets the function) and calls coop_interact_site with the registers there. Every player must have it on:
// coop_mods_add puts it in the mods fingerprint, so a session refuses a player whose setting differs.
#include "coop.h"
#include <stdlib.h>
#include <string.h>

// The mask builder's story-area online block. At the site (movk x13, #1, lsl #32) x13 holds the pattern's bits 0-31 (Spectator: bits 23-26 and 31)
// and the movk adds bit 32 (online); x22 is the session's Spectator flag, 0 in every story area, and x20 the builder's host argument. The normal online
// pattern sets bits 1-28 and 30. Bit 0 switches the story system on (the per-frame story update, 2.0.1 main+0xba660, and the quest and event code):
// alone the mask is 0x7fffffff, and every online pattern clears it, so a host's requests and story conversations stop while a session is open.
// 2.0.1 main (76a489f3…); 1.0.5 main (816c5358…), where the builder is the same instruction for instruction
static const coop_site g_sites[] = {
    {"76a489f3bd3642fa5e18bd83d32c98ba", 0xb0f60, 0xb1030, 0xf2c0002du, COOP_SITE_MASK, "permission mask: story areas get Palette Town's Spectator-Off pattern"},
    {"816c5358e8178d802fcec4a7ce5a741a", 0xa61e0, 0xa62b0, 0xf2c0002du, COOP_SITE_MASK, "permission mask: story areas get Palette Town's Spectator-Off pattern"},
};

// Story co-op. The A button asks a chain of handlers (2.0.1 main+0x4c3ec8) what it does; the talk handler (2.0.1 main+0x4c024c) gives an online
// player who is not the host a visitor's reply (kinds 0xa/0xb, no conversation) unless the NPC is one of three every visitor may talk to. At the site
// (orr w8, w25, w0) w0 is IsHost's answer, so a visitor takes the host's path: the NPC's own conversation. 1.0.5's handler has the same site at the
// same offset, between the same calls (stage == 0x11, IsHost); its other differences are struct offsets.
// The host's story while a session is open (2.0.1). A story Pokémon's talks are picked by conditions from a table (main+0x34c2958, ids 1-0xde): the
// story and request talks carry 0x19 "not online" (main+0x4cfe10) or 0x60 (main+0x4d4844, not online and more), and their Link Play stand-in, "Looks
// like they want to meet <the town's owner>! Bring <owner> here to say hi!", carries 0x22 "online" (main+0x4d04fc, a tail call into IsOnline). So in any
// session the owner's own requests stop at that line. For the host, those three conditions read IsOnline as false: the sites sit right after the
// IsOnline call (x0), and for 0x22 inside IsOnline (main+0x207c4, x8), reached there only through the interpreted tail call. The mask builder's first
// instruction (ROLE) forgets the role; the story-area site (MASK) records whether this player hosts there
static const coop_site g_story[] = {
    {"76a489f3bd3642fa5e18bd83d32c98ba", 0x4c024c, 0x4c06d8, 0x2a000328u, COOP_SITE_TALK, "talk: a visitor gets the NPC's conversation, as the host"},
    {"76a489f3bd3642fa5e18bd83d32c98ba", 0xb0f60, 0xb0f74, 0xaa0003f3u, COOP_SITE_ROLE, "permission mask: the builder starts"},
    {"76a489f3bd3642fa5e18bd83d32c98ba", 0x4cfe10, 0x4cfe20, 0x52800028u, COOP_SITE_ALONE, "talk condition 0x19 (not online): the host's story talks"},
    {"76a489f3bd3642fa5e18bd83d32c98ba", 0x4d4844, 0x4d4860, 0x37001da0u, COOP_SITE_ALONE, "talk condition 0x60 (not online and more): the host's story talks"},
    {"76a489f3bd3642fa5e18bd83d32c98ba", 0x4d04fc, 0x207c4, 0x12000100u, COOP_SITE_ALONE8, "talk condition 0x22 (online): not the host's \"bring the owner here\" line"},
    {"816c5358e8178d802fcec4a7ce5a741a", 0x469424, 0x4698b0, 0x2a000328u, COOP_SITE_TALK, "talk: a visitor gets the NPC's conversation, as the host"},
};
static _Atomic int g_role_sites, g_story_host;   // the ROLE site is attached (this build has the host's sites); this player hosts in a story area

// The Spectator Mode text, which Interact everywhere makes untrue in a story area (stage type 1: stages 1-10).
// - Hosting there, the Link Play screens show "When playing with others in this town, everyone will be restricted to playing in Spectator Mode"
//   and "Certain moves and items can't be used ..." with the settings: after Invite Others to Visit, the stage-type-1 check (2.0.1 main+0xf29bdc)
//   picks the Link Play state, 3 (the story area's, with the notes) or 4 (another town's, straight on). STAGEONE, right after the call, answers no.
//   The settings rows take that state as their context (main+0x1011018), which decides how the Spectator Mode row behaves (below).
// - The settings row's refresher (2.0.1 main+0x100e72c) shows the save's Spectator Mode setting (row+0x400: 0 On, 1 Off, as the getter wrote it)
//   and forces "On" outside Palette Town (stage 12), and in the connected screens (row+0x424 3 or 5) everywhere. At SPECROW (cmp w8, #0xc; w8 the
//   stage, x19 the row) a story area takes Palette Town's path showing "Off"; at SPECROW2 (cmp w9, #3; w9 the screen) that row's screen is not a
//   forcing one.
// - The option list's handler (2.0.1 main+0x1007380) locks the Spectator Mode row (row+0x42b) outside Palette Town only in the hosting context (1);
//   in state 4's it would let the row change, and choosing On there says "This Palette Town is currently in Spectator Mode". SPECLOCK (cmp w8, #1;
//   w8 the context) gives that check the hosting context in a story area, so the row stays locked, as the game has it there.
// 1.0.5's functions are the same instruction for instruction (sizes; the refresher's struct offsets too), at other addresses
static const coop_site g_text[] = {
    {"76a489f3bd3642fa5e18bd83d32c98ba", 0xf29400, 0xf29be0, 0x7200001fu, COOP_SITE_STAGEONE, "Link Play: no Spectator Mode notes when hosting in a story area"},
    {"76a489f3bd3642fa5e18bd83d32c98ba", 0x100e72c, 0x100e7cc, 0x7100311fu, COOP_SITE_SPECROW, "Link Play settings: Spectator Mode shows Off in a story area"},
    {"76a489f3bd3642fa5e18bd83d32c98ba", 0x100e72c, 0x100e7dc, 0x71000d3fu, COOP_SITE_SPECROW2, "Link Play settings: ... in the connected screens too"},
    {"76a489f3bd3642fa5e18bd83d32c98ba", 0x1007380, 0x10076b4, 0x7100051fu, COOP_SITE_SPECLOCK, "Link Play settings: ... and stays locked there"},
    {"816c5358e8178d802fcec4a7ce5a741a", 0xe539a0, 0xe54180, 0x7200001fu, COOP_SITE_STAGEONE, "Link Play: no Spectator Mode notes when hosting in a story area"},
    {"816c5358e8178d802fcec4a7ce5a741a", 0xf2996c, 0xf29a0c, 0x7100311fu, COOP_SITE_SPECROW, "Link Play settings: Spectator Mode shows Off in a story area"},
    {"816c5358e8178d802fcec4a7ce5a741a", 0xf2996c, 0xf29a1c, 0x71000d3fu, COOP_SITE_SPECROW2, "Link Play settings: ... in the connected screens too"},
    {"816c5358e8178d802fcec4a7ce5a741a", 0xf227a0, 0xf22ad4, 0x7100051fu, COOP_SITE_SPECLOCK, "Link Play settings: ... and stays locked there"},
};
static _Atomic uint64_t g_off_row;   // the row SPECROW showed "Off" in, for SPECROW2 a few instructions later
static _Atomic int g_spec_story;     // the last Spectator Mode row refreshed was in a story area with Interact everywhere on (for SPECLOCK)

static int sites_of(const coop_site *t, size_t nt, const char *main_build, const coop_site **out) {
    int n = 0;
    *out = NULL;
    if (!main_build) return 0;
    for (size_t i = 0; i < nt; i++)
        if (!strncmp(main_build, t[i].build, strlen(t[i].build))) { if (!n) *out = &t[i]; n++; }
    return n;
}
int coop_interact_sites(const char *main_build, const coop_site **out) { return sites_of(g_sites, sizeof g_sites / sizeof g_sites[0], main_build, out); }
int coop_story_sites(const char *main_build, const coop_site **out) { return sites_of(g_story, sizeof g_story / sizeof g_story[0], main_build, out); }
int coop_text_sites(const char *main_build, const coop_site **out) { return sites_of(g_text, sizeof g_text / sizeof g_text[0], main_build, out); }

int coop_story_on(void) {
    const char *e = getenv("DM_COOP_STORY");
    return e && !strcmp(e, "1");
}

int coop_interact_on(void) {
    const char *e = getenv("DM_COOP_INTERACT");
    return (e && !strcmp(e, "1")) || coop_story_on();
}

void coop_interact_site(int id, uint64_t *x) {
    if (id == COOP_SITE_ROLE) { g_role_sites = 1; g_story_host = 0; }
    if (id == COOP_SITE_MASK && !(x[22] & 1)) {   // the movk that follows adds bit 32; with Story co-op the host keeps its story system (bit 0)
        g_story_host = g_role_sites && coop_story_on() && (x[20] & 1);
        x[13] = g_story_host ? 0x5fffffff : 0x5ffffffe;
    }
    if (id == COOP_SITE_TALK && coop_story_on()) x[0] = 1;           // IsHost: yes
    if (id == COOP_SITE_ALONE && g_story_host) x[0] = 0;             // IsOnline's answer: no
    if (id == COOP_SITE_ALONE8 && g_story_host) x[8] = 0;            // GameMgr's online bit, read inside IsOnline: clear
    if (id == COOP_SITE_STAGEONE && coop_interact_on()) x[0] = 0;    // the stage-type-1 check's answer: no
    if (id == COOP_SITE_SPECROW) {
        g_off_row = 0; g_spec_story = coop_interact_on() && x[8] >= 1 && x[8] <= 10;
        if (g_spec_story && x[19]) {
            *(volatile uint32_t *)(uintptr_t)(x[19] + 0x400) = 1; x[8] = 12; g_off_row = x[19];   // "Off", and Palette Town's path keeps it
        }
    }
    if (id == COOP_SITE_SPECROW2 && g_off_row && g_off_row == x[19]) x[9] = 0;   // not a screen that forces "On"
    if (id == COOP_SITE_SPECLOCK && g_spec_story) x[8] = 1;             // the hosting context: locked outside Palette Town
}

uint64_t coop_mods_add(uint64_t h, const char *name) {
    if (!h) h = 0xcbf29ce484222325ull;   // FNV-1a, as nxnative's cheat fingerprint (ldn_glue.c): each name, then 0xFF
    for (const char *p = name; *p; p++) { h ^= (uint8_t)*p; h *= 0x100000001b3ull; }
    h ^= 0xFF; h *= 0x100000001b3ull;
    return h;
}
