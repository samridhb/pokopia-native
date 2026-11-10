// Shared by menu.c and the tabs kept in files of their own (menu_controls.c, menu_linkplay.c): the colours, the drawing calls, the input kinds and the panel's geometry
#pragma once
#include "menu.h"

#define RGBA(r, g, b, a) ((uint32_t)(r) | (uint32_t)(g) << 8 | (uint32_t)(b) << 16 | (uint32_t)(a) << 24)
// The GitHub page's fade colours, as the builder and the launchers have them: the panel #FBF6FD with a #EAE2F2 edge, ink #1C1626 titles, body
// #3A3346, muted #6A6277, pills in the tint, the highlighted row #FFEAF3. C_SEL is the selection: a rectangle in it is drawn as the fade
// (#FF3D8E -> #D23CF0 -> #8A3FFC, left to right; menu.frag), with white text on it. C_CHOSEN is a chosen page while its row is not the selected one
static const uint32_t C_DIM = RGBA(28, 22, 38, 150), C_PANEL = RGBA(251, 246, 253, 250), C_EDGE = RGBA(234, 226, 242, 255), C_TITLE = RGBA(28, 22, 38, 255),
                      C_TEXT = RGBA(58, 51, 70, 255), C_SOFT = RGBA(106, 98, 119, 255), C_PILL = RGBA(237, 226, 255, 255), C_SEL = RGBA(210, 60, 240, 255),
                      C_SELTEXT = RGBA(255, 255, 255, 255), C_TAB = RGBA(230, 217, 252, 255), C_LIST = RGBA(255, 255, 255, 255), C_OFF = RGBA(171, 165, 179, 255),
                      C_HI = RGBA(255, 234, 243, 255), C_CHOSEN = RGBA(244, 206, 251, 255), C_BAD = RGBA(163, 45, 45, 255);
enum { IN_UP = 1, IN_DOWN, IN_LEFT, IN_RIGHT, IN_OK, IN_BACK, IN_TABL, IN_TABR, IN_CLICK };

// The panel in window pixels, the scale (1 at 1080 lines), the text size and the top of a tab's rows
typedef struct mn_panel { float px, py, pw, ph, u, fs, y0; } mn_panel;
void mn_rect(mn_list *l, float x, float y, float w, float h, float r, uint32_t c);
void mn_text(mn_list *l, const char *t, float x, float y, float px, uint32_t c);   // its top at y
float mn_text_w(const char *t, float px);
float mn_fit(const char *t, float px, float w, float u);                           // smaller until it fits
int mn_inside(float x, float y, float x0, float y0, float w, float h);
void mn_status(const char *t);                                                       // the last change's line

// The Link Play tab (menu_linkplay.c). With the menu's lock held, except lp_event: the window thread, each SDL event before anything else
int lp_event(const SDL_Event *e);
int lp_rows(void);                                                // its buttons
int lp_pick(const mn_panel *p, float x, float y);                 // the button under the mouse, -1 none
void lp_input(const mn_panel *p, int kind, float x, float y, int *sel);
void lp_draw(mn_list *out, const mn_panel *p, int sel);
const char *lp_hint(int sel);
void lp_ctl(const char *cmd);   // DM_CTL "menu lp ..." (tests): status, settings, mode <launcher name>, join <address>, room <code>, keep|interact|story 0|1, apply, copy room|invite

// The Controls tab (menu_controls.c): the keyboard's keys and the controllers' buttons, and which controller is player 1. With the menu's lock held
void ct_init(void);              // menu_init: the maps the game started with
void ct_close(void);             // the menu closed: nothing awaited
int ct_capturing(void);          // a key or a button is awaited (the tabs stay put)
int ct_event(const SDL_Event *e);   // the window thread, the menu open: the key or button awaited; 1 taken
int ct_rows(void);
int ct_pick(const mn_panel *p, float x, float y);
void ct_input(const mn_panel *p, int kind, float x, float y, int *sel);
void ct_draw(mn_list *out, const mn_panel *p, int sel);
const char *ct_hint(int sel);
void ct_ctl(const char *cmd);    // DM_CTL "menu reset|key ...|ct ..." (tests)
