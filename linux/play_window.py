"""play_window.py: the Linux game's launcher window, in the builder's look (nxs2_gui.py). windows-native's scripts/play.sh starts it before the
game: how to play (alone, Link Play on this network, over the internet), the host's address and room code, Interact everywhere and Story co-op,
the picture's basics, "ask again next time", the update check's off switch, and the update notice when a newer release is out (nxs2.py's
update_check: once a day, 3 s, updates.json shared with the builder).
It writes what play.sh's prompts wrote (linkplay.json, display.json in the settings folder); play.sh falls back to those prompts when no window
can open here (exit 11: no display, or a Python without Tk).
    play_window.py launch --settings <folder> --installed <version> [--game-version <v>] [--coop-ok | --coop-needs <text> --coop-game <text>]
                          [--no-save] [--console-default 0|1]       exit 0: play; 10: cancelled
    play_window.py notice --installed <version> [--quiet]          the once-a-day check (3 s at most); a newer release in a small window of
                                                                    its own, or with --quiet (or no window here) one line on stderr
<version> is play.json's pokopia_native: the build's, which can be older than the builder that made it.
    play_window.py room <code>                                      the room code of this session, to give to the players who visit"""
import argparse, json, os, pathlib, re, sys, threading, webbrowser

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))   # nxs2.py and nxs2_gui.py: the installer's folder (the build's runtime/installer)
import nxs2  # noqa: E402

PLAY, CANCELLED, NO_WINDOW = 0, 10, 11
IPPORT = re.compile(r'((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])(:[0-9]{1,5})?')
ROOMRX = re.compile(r'[0-9A-TV-Za-tv-z]{16}')   # dashes and spaces taken out: Crockford's base32
MODES = (('alone', 'Play alone', ''),
         ('host', 'Link Play: host here', "Players on this network join this computer's address."),
         ('join', 'Link Play: join a host on this network', "By the host's address."),
         ('inet-host', 'Host over the internet', 'Your router forwards port 47600 here. The room code comes up as the game starts.'),
         ('inet-visit', 'Visit a host over the internet', "The host's address and room code."))
PICTURE = (('console', 'Console mode', (('Docked', 1), ('Handheld', 0))),
           ('fullscreen', 'Display', (('Window', False), ('Full screen', True))),
           ('antialiasing', 'Anti-aliasing', (('Off', 'off'), ('FXAA', 'fxaa'), ('SMAA', 'smaa'))),
           ('fps', 'Frame rate', (('60', 60), ('30', 30))),
           ('fps_counter', 'FPS counter', (('Off', 'off'), ('Corner', 'corner'), ('Detailed', 'detailed'))))
CHECK_TEXT = 'Check for updates (once a day, asks GitHub for the latest version)'
NOSAVE_TEXT = ('No save here yet, so the game starts a new one. To play your save from the phone, a Mac or another PC, cancel and run '
               'nxs2.py import-save first.')


UPDATE_LINE = 'Update in the builder: Update my game keeps your save and settings.'
RELEASES = 'https://github.com/xFractals/pokopia-native/releases/'


def notice_from(state, installed):
    """The notice for the release updates.json names when it is newer than this build's version and not skipped, else None"""
    tag, mine = state.get('latest') or '', nxs2.version_of(installed)
    v = nxs2.version_of(tag)
    if state.get('check') is False or not v or not mine or v <= mine or tag == state.get('skipped'): return None
    ver = '.'.join(map(str, v)); name = state.get('latest_name') or ''   # the release name's part after the colon
    url = state.get('latest_url') or ''
    return {'tag': tag, 'title': f'Pokopia Native {ver} is out', 'line': '' if name in (tag, f'Pokopia Native {ver}') else name,
            'url': url if url.startswith(RELEASES) else RELEASES + 'tag/' + tag}


def check_now(installed, timeout=3.0):
    """The once-a-day check (nxs2.update_check keeps updates.json), given up after the timeout even when the name lookup hangs. The notice only
    on the start that really asked GitHub, so "Later" shows it again at the next day's check; else None"""
    before, done = nxs2.update_state().get('last_check'), threading.Event()
    def ask():
        try: nxs2.update_check(timeout=timeout)
        except Exception: pass
        finally: done.set()
    threading.Thread(target=ask, daemon=True).start()
    if not done.wait(timeout + 0.5): return None
    s = nxs2.update_state()
    return notice_from(s, installed) if s.get('last_check') != before else None


def checking(): return nxs2.update_state().get('check') is not False


def set_checking(on):
    if checking() != bool(on): nxs2.update_state(check=bool(on))


def read_json(path):
    try:
        d = json.loads(pathlib.Path(path).read_text(encoding='utf-8'))
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError): return {}


def write_json(path, d):
    path = pathlib.Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f'.{os.getpid()}.tmp'); tmp.write_text(json.dumps(d, indent=1) + '\n', encoding='utf-8'); os.replace(tmp, path)


def room_text(code):
    r = re.sub(r'[- ]', '', code).upper()
    return '-'.join(r[i:i + 4] for i in range(0, 16, 4)) if ROOMRX.fullmatch(r) else code.strip()


def tk_or_none():
    """tkinter and the builder's look, or None where no window can open (no display, no Tk, a Tk that cannot reach the display)"""
    if not (os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')): return None
    try:
        import tkinter as tk
        import nxs2_gui as g
        root = tk.Tk(className='pokopia')
    except Exception: return None
    root.withdraw(); g.linux_look(root); root.configure(bg=g.C['bg'])
    return tk, g, root


def place(root, w):
    """w wide and as tall as it asks (at most the screen), centred: shown first, since its labels fold to their width only once on screen"""
    sw, sh = root.winfo_screenwidth(), root.winfo_screenheight()
    root.update_idletasks(); h = min(root.winfo_reqheight(), sh - 60)
    root.geometry(f'{w}x{h}+{max(0, (sw - w) // 2)}+{max(0, (sh - h) // 3 - 40)}'); root.deiconify(); root.lift(); root.focus_force()
    root.after(120, grow, root)   # once on screen (a resize while it maps can be lost)


def grow(root):   # as tall as it now asks (labels folded, the update notice added), at most the screen; sized only (a move with it is lost
    root.update_idletasks(); h = min(root.winfo_reqheight(), root.winfo_screenheight() - 60)   # on some desktops)
    if h > root.winfo_height(): root.geometry(f'{root.winfo_width()}x{h}')


def widgets(tk, g):
    """The launcher's controls in the builder's look: a radio row, a check box, a row of choices (the chosen one in the fade) and an entry"""
    C, F = g.C, g.F
    notes = []   # the helper lines under the choices: left out on a short screen

    def paint(w, bg):   # a frame and everything in it on a new background
        try: w.configure(bg=bg)
        except tk.TclError: pass
        for c in w.winfo_children():
            if not isinstance(c, (tk.Entry, Chips)) and not getattr(c, 'own_bg', False): paint(c, bg)

    class Row(tk.Canvas):
        """A rounded row whose fill follows its state: widgets go in .body"""
        def __init__(self, parent, pad=8, radius=12):
            super().__init__(parent, bg=parent['bg'], highlightthickness=0, bd=0, height=2 * pad)
            self.fill, self.pad, self.radius = parent['bg'], pad, radius
            self.body = tk.Frame(self, bg=self.fill)
            self.item = self.create_window(pad, pad, window=self.body, anchor='nw')
            self.body.bind('<Configure>', self.fit); self.bind('<Configure>', self.fit)

        def fit(self, _=None):
            w = self.winfo_width()
            if w > 2 * self.pad: self.itemconfigure(self.item, width=w - 2 * self.pad)
            h = self.body.winfo_reqheight() + 2 * self.pad
            if int(float(self.cget('height'))) != h: self.configure(height=h)
            self.delete('bg')
            if self.fill != self['bg']: g.rrect(self, 0, 0, w - 1, h - 1, self.radius, fill=self.fill, outline=self.fill, tags='bg')
            self.tag_lower('bg')

        def set_fill(self, fill):
            if fill != self.fill: self.fill = fill; paint(self.body, fill); self.fit()

    class Mark(tk.Canvas):   # a radio dot or a check box, drawn
        def __init__(self, parent, kind):
            s = round(18 * g.SCALE)
            super().__init__(parent, width=s, height=s, bg=parent['bg'], highlightthickness=0, bd=0)
            self.own_bg, self.kind, self.s = False, kind, s

        def draw(self, on, enabled=True):
            s, k = self.s, self.s / 18
            self.delete('all')
            ring = C['sel'] if on and enabled else C['soft'] if enabled else C['edge']
            if self.kind == 'radio':
                self.create_oval(1, 1, s - 2, s - 2, outline=ring, width=max(1.5, 1.5 * k), fill=C['card'])
                if on: self.create_oval(5 * k, 5 * k, s - 6 * k, s - 6 * k, outline='', fill=C['sel'] if enabled else C['edge'])
            elif on:
                g.rrect(self, 1, 1, s - 2, s - 2, 4 * k, fill=C['sel'] if enabled else C['edge'], outline=C['sel'] if enabled else C['edge'])
                self.create_line(4.5 * k, 9.5 * k, 7.5 * k, 12.5 * k, 13.5 * k, 5.5 * k, fill=C['seltext'], width=max(2, 2 * k), capstyle='round', joinstyle='round')
            else: g.rrect(self, 1, 1, s - 2, s - 2, 4 * k, fill=C['card'], outline=ring, width=max(1.5, 1.5 * k))

    class Radio:
        def __init__(self, parent, var, value, text, note):
            self.var, self.value, self.row = var, value, Row(parent)
            self.row.value = value
            b = self.row.body
            self.mark = Mark(b, 'radio'); self.mark.grid(row=0, column=0, rowspan=2, sticky='n', padx=(2, 10), pady=(2, 0))
            g.label(b, text, 11, fg=C['title']).grid(row=0, column=1, sticky='ew')
            if note: notes.append(g.label(b, note, 9, fg=C['soft'])); notes[-1].grid(row=1, column=1, sticky='ew')
            b.columnconfigure(1, weight=1)
            self.hover = False
            for w in [self.row, b] + list(b.winfo_children()):
                w.bind('<Button-1>', lambda e: var.set(value)); w.configure(cursor='hand2')
                w.bind('<Enter>', lambda e: self.set_hover(True)); w.bind('<Leave>', lambda e: self.set_hover(False))
            var.trace_add('write', lambda *a: self.draw()); self.draw()

        def set_hover(self, on): self.hover = on; self.draw()

        def draw(self):
            on = self.var.get() == self.value
            self.row.set_fill(C['pill'] if on else C['pill_hi'] if self.hover else self.row['bg']); self.mark.draw(on)

    class Check:
        def __init__(self, parent, var, text, note=''):
            self.var, self.enabled = var, True
            self.frame = tk.Frame(parent, bg=parent['bg'])
            self.mark = Mark(self.frame, 'check'); self.mark.grid(row=0, column=0, rowspan=2, sticky='n', padx=(0, 10), pady=(2, 0))
            self.text = g.label(self.frame, text, 11, fg=C['title']); self.text.grid(row=0, column=1, sticky='ew')
            self.note = g.label(self.frame, note, 9, fg=C['soft'])
            if note: self.note.grid(row=1, column=1, sticky='ew'); notes.append(self.note)
            self.frame.columnconfigure(1, weight=1)
            for w in (self.frame, self.mark, self.text, self.note):
                w.bind('<Button-1>', lambda e: self.enabled and var.set(not var.get())); w.configure(cursor='hand2')
            var.trace_add('write', lambda *a: self.draw()); self.draw()

        def set_enabled(self, on):
            self.enabled = on; self.text.configure(fg=C['title'] if on else C['soft'])
            for w in (self.frame, self.mark, self.text, self.note): w.configure(cursor='hand2' if on else 'arrow')
            self.draw()

        def draw(self): self.mark.draw(bool(self.var.get()), self.enabled)

    class Chips(tk.Frame):
        """A row of choices: the chosen one filled with the fade"""
        def __init__(self, parent, var, choices):
            super().__init__(parent, bg=parent['bg'])
            self.var, self.font, self.bold, self.chips = var, g.tkfont.Font(font=F(10)), g.tkfont.Font(font=F(10, True)), []
            for text, value in choices:
                w, h = self.bold.measure(text) + 28, self.font.metrics('linespace') + 10
                cv = tk.Canvas(self, width=w, height=h, bg=parent['bg'], highlightthickness=0, bd=0, cursor='hand2')
                cv.pack(side='left', padx=(0, 6)); cv.bind('<Button-1>', lambda e, v=value: var.set(v))
                cv.bind('<Enter>', lambda e, c=cv: self.draw(c, True)); cv.bind('<Leave>', lambda e, c=cv: self.draw(c, False))
                cv.text, cv.value = text, value; self.chips.append(cv)
            var.trace_add('write', lambda *a: [self.draw(c) for c in self.chips]); [self.draw(c) for c in self.chips]

        def draw(self, cv, hover=False):
            w, h = int(cv.cget('width')), int(cv.cget('height')); cv.delete('all')
            if self.var.get() == cv.value:
                g.fade_rrect(cv, 0, 0, w - 1, h - 1, h / 2, 0.9 if hover else 1.0); fg, font = C['seltext'], self.bold
            else:
                fill = C['pill_hi'] if hover else C['pill']; g.rrect(cv, 0, 0, w - 1, h - 1, h / 2, fill=fill, outline=fill); fg, font = C['title'], self.font
            cv.create_text(w / 2, h / 2, text=cv.text, font=font, fill=fg)

    class Field:
        """A rounded entry: its border takes the fade's middle while it has the focus"""
        def __init__(self, parent, var, width=24):
            self.round = g.Round(parent, fill=C['card'], edge=C['edge'], pad=6, radius=10)
            self.entry = tk.Entry(self.round.body, textvariable=var, width=width, font=F(11), bd=0, relief='flat', highlightthickness=0,
                                  bg=C['card'], fg=C['title'], insertbackground=C['title'], disabledbackground=C['card'], disabledforeground=C['soft'])
            self.entry.pack(fill='x', padx=4, pady=1)
            self.entry.bind('<FocusIn>', lambda e: self.edge(C['sel'])); self.entry.bind('<FocusOut>', lambda e: self.edge(C['edge']))

        def edge(self, colour): self.round.edge = colour; self.round.fit()

    return Row, Radio, Check, Chips, Field, notes


def notice_card(tk, g, parent, notice, on_done):
    """The update notice: what is out, the update's one line, and What's new / Download / Later / Skip this version"""
    C = g.C
    card = g.Round(parent, fill=C['light'], edge=C['light'], pad=14, radius=14)
    b = card.body
    g.label(b, notice['title'], 13, True, fg=C['title']).pack(fill='x')
    if notice['line']: g.label(b, notice['line'], 11, fg=C['text']).pack(fill='x', pady=(2, 0))
    g.label(b, UPDATE_LINE, 10, fg=C['soft']).pack(fill='x', pady=(2, 8))
    row = tk.Frame(b, bg=b['bg']); row.pack(fill='x')

    def act(kind):
        if kind in ('new', 'download'): webbrowser.open(notice['url'])
        if kind == 'skip': nxs2.update_state(skipped=notice['tag'])
        on_done(kind)
    g.Pill(row, 'Download', lambda: act('download'), 'primary', 10).pack(side='left')
    g.Pill(row, "What's new", lambda: act('new'), size=10).pack(side='left', padx=(8, 0))
    g.Pill(row, 'Skip this version', lambda: act('skip'), size=10).pack(side='right')
    g.Pill(row, 'Later', lambda: act('later'), size=10).pack(side='right', padx=(0, 8))
    return card


def launch(a, look=None):
    look = look or tk_or_none()
    if not look: return NO_WINDOW
    tk, g, root = look
    C = g.C
    Row, Radio, Check, Chips, Field, notes = widgets(tk, g)
    settings = pathlib.Path(a.settings)
    pref, disp, checks = read_json(settings / 'linkplay.json'), read_json(settings / 'display.json'), checking()
    result = {'code': CANCELLED}
    root.title('Pokopia - Play')
    pad = round(18 * g.SCALE)

    top = tk.Frame(root, bg=C['bg']); top.pack(fill='x', padx=pad, pady=(pad, 0))
    g.label(top, 'Pokemon Pokopia', 20, True, fg=C['title'], wrap=False).pack(side='left')
    sub = '  ·  '.join(x for x in (f'Pokopia Native {a.installed}' if a.installed else '', f'game {a.game_version}' if a.game_version else '') if x)
    g.label(top, sub, 10, fg=C['soft'], wrap=False).pack(side='left', padx=(14, 0), pady=(10, 0))
    tk.Frame(root, bg=C['edge'], height=2).pack(fill='x', padx=pad, pady=(10, 0))

    slot = tk.Frame(root, bg=C['bg']); slot.pack(fill='x', padx=pad)   # the update notice goes here when the check finds a newer release
    if a.no_save:
        warn = g.Round(root, fill=C['card'], pad=12, radius=14); warn.pack(fill='x', padx=pad, pady=(14, 0))
        g.label(warn.body, NOSAVE_TEXT, 10, fg=C['warn']).pack(fill='x')

    cols = tk.Frame(root, bg=C['bg']); cols.pack(fill='both', expand=True, padx=pad, pady=(14, 0))
    cols.columnconfigure(0, weight=3, uniform='c'); cols.columnconfigure(1, weight=2, uniform='c')

    # How to play
    play = g.Round(cols, pad=16, radius=16); play.grid(row=0, column=0, sticky='nsew', padx=(0, 14))
    pb = play.body
    g.label(pb, 'How do you want to play?', 13, True, fg=C['title']).pack(fill='x')
    g.label(pb, 'In the game: Link Play, then Local connection.', 10, fg=C['soft']).pack(fill='x', pady=(2, 8))
    mode = tk.StringVar(value=pref.get('mode') if pref.get('mode') in [m[0] for m in MODES] else 'alone')
    for value, text, note in MODES: Radio(pb, mode, value, text, note).row.pack(fill='x', pady=1)

    where = tk.Frame(pb, bg=pb['bg']); where.pack(fill='x')
    addr, room = tk.StringVar(value=str(pref.get('join') or '')), tk.StringVar(value=str(pref.get('room') or ''))
    addr_box, room_box = tk.Frame(where, bg=pb['bg']), tk.Frame(where, bg=pb['bg'])
    g.label(addr_box, "The host's address (for example 192.168.1.20)", 10, fg=C['text']).pack(fill='x', pady=(10, 4))
    addr_field = Field(addr_box, addr); addr_field.round.pack(fill='x')
    g.label(room_box, "The host's room code (XXXX-XXXX-XXXX-XXXX)", 10, fg=C['text']).pack(fill='x', pady=(10, 4))
    room_field = Field(room_box, room); room_field.round.pack(fill='x')

    coop = tk.Frame(pb, bg=pb['bg']); coop.pack(fill='x', pady=(12, 0))
    interact, story = tk.BooleanVar(value=pref.get('interact') is True), tk.BooleanVar(value=pref.get('story') is True)
    ie = Check(coop, interact, 'Interact everywhere (experimental)',
               'Visitors can use moves and items and build in every town, not only Palette Town. Every player needs it on.')
    ie.frame.pack(fill='x')
    sc = Check(coop, story, 'Story co-op (experimental)',
               "Visitors can talk to the town's story characters. Story requests still count only for the host. Every player needs it on.")
    sc.frame.pack(fill='x', pady=(8, 0))
    if not a.coop_ok:
        g.label(coop, f'These need {a.coop_needs or "Pokopia 2.0.1 or 1.0.5"}. This game is another version'
                      f'{f" ({a.coop_game})" if a.coop_game else ""}, so they stay off.', 9, fg=C['warn']).pack(fill='x', pady=(8, 0))

    def follow(*_):
        m = mode.get()
        addr_box.pack_forget(); room_box.pack_forget()
        if m in ('join', 'inet-visit'): addr_box.pack(fill='x')
        if m == 'inet-visit': room_box.pack(fill='x')
        linked = m != 'alone' and a.coop_ok
        ie.set_enabled(linked); sc.set_enabled(linked and interact.get())
        error.set('')
    mode.trace_add('write', follow); interact.trace_add('write', follow)

    # The picture and the rest
    right = tk.Frame(cols, bg=C['bg']); right.grid(row=0, column=1, sticky='nsew')
    pic = g.Round(right, pad=16, radius=16); pic.pack(fill='x')
    g.label(pic.body, 'The picture', 13, True, fg=C['title']).pack(fill='x')
    g.label(pic.body, 'F1 in the game changes these and more while you play.', 10, fg=C['soft']).pack(fill='x', pady=(2, 4))
    grid = tk.Frame(pic.body, bg=C['card']); grid.pack(fill='x'); grid.columnconfigure(1, weight=1)
    defaults = {'console': a.console_default, 'fullscreen': False, 'antialiasing': 'smaa', 'fps': 60, 'fps_counter': 'off'}
    shown, pvars = {}, {}
    for key, title, choices in PICTURE:
        v = disp.get(key, defaults[key])
        if key == 'console': v = 0 if v in (0, '0', False) else 1
        if v not in [c[1] for c in choices]: v = defaults[key]
        shown[key] = v
        pvars[key] = (tk.IntVar if key in ('console', 'fps') else tk.BooleanVar if key == 'fullscreen' else tk.StringVar)(value=v)
        r = len(shown) - 1
        g.label(grid, title, 10, fg=C['text'], wrap=False).grid(row=r, column=0, sticky='w', padx=(0, 12), pady=(6, 0))
        Chips(grid, pvars[key], choices).grid(row=r, column=1, sticky='w', pady=(6, 0))

    opts = g.Round(right, pad=16, radius=16); opts.pack(fill='x', pady=(14, 0))
    again, check = tk.BooleanVar(value=pref.get('ask') is not False), tk.BooleanVar(value=checks)
    Check(opts.body, again, 'Ask again next time', 'Off: the game starts this way. The "Pokopia Settings" launcher brings this back.').frame.pack(fill='x')
    Check(opts.body, check, CHECK_TEXT).frame.pack(fill='x', pady=(10, 0))

    bottom = tk.Frame(root, bg=C['bg']); bottom.pack(fill='x', padx=pad, pady=pad)
    help_link = g.label(bottom, 'Stuck? Ask in the Discord', 10, fg=C['title'], wrap=False, cursor='hand2')
    help_link.configure(font=g.F(10) + ('underline',)); help_link.pack(side='left')
    help_link.bind('<Button-1>', lambda e: webbrowser.open(g.DISCORD))
    error = tk.StringVar()
    tk.Label(bottom, textvariable=error, font=g.F(10), fg=C['bad'], bg=C['bg'], anchor='e', justify='right').pack(side='left', fill='x', expand=True, padx=12)

    def go():
        m, j, r = mode.get(), addr.get().strip(), room.get().strip()
        if m in ('join', 'inet-visit') and not IPPORT.fullmatch(j):
            error.set("The host's address is four numbers with dots, for example 192.168.1.20 (or 203.0.113.7:47600)."); addr_field.entry.focus_set(); return
        if m == 'inet-visit' and not ROOMRX.fullmatch(re.sub(r'[- ]', '', r)):
            error.set('The room code is 16 letters and digits: XXXX-XXXX-XXXX-XXXX.'); room_field.entry.focus_set(); return
        p = read_json(settings / 'linkplay.json')   # what play.sh's prompts kept, plus the new choice
        p.update(mode=m, ask=bool(again.get()))
        if m in ('join', 'inet-visit'): p['join'] = j
        if m == 'inet-visit': p['room'] = room_text(r)
        if m != 'alone' and a.coop_ok: p.update(interact=bool(interact.get()), story=bool(interact.get() and story.get()))
        d = read_json(settings / 'display.json')   # only what was changed here: the rest stays as F1 saved it (a Deck's console mode
        changed = {k: pvars[k].get() for k in shown if pvars[k].get() != shown[k]}   # follows the Deck until it is picked)
        try:
            write_json(settings / 'linkplay.json', p)
            if changed: write_json(settings / 'display.json', dict(d, **{k: bool(v) if k == 'fullscreen' else v for k, v in changed.items()}))
        except OSError as e:
            error.set(f'Could not save the settings in {settings}: {e.strerror}'); return
        set_checking(check.get())
        result['code'] = PLAY; root.destroy()

    g.Pill(bottom, 'Play', go, 'primary', 12).pack(side='right')
    g.Pill(bottom, 'Cancel', root.destroy, size=12).pack(side='right', padx=(0, 10))
    root.bind('<Return>', lambda e: go()); root.bind('<Escape>', lambda e: root.destroy())
    follow()

    # The update check, beside the window (3 s at most); the notice slides in at the top when a newer release is out
    box = {}
    def poll():
        if 'r' not in box: return root.after(150, poll)
        notice = box['r']
        if notice and check.get():
            holder = {}
            holder['card'] = notice_card(tk, g, slot, notice, lambda kind: kind != 'new' and holder['card'].destroy())
            holder['card'].pack(fill='x', pady=(14, 0))
            root.update(); grow(root)
    if checks:
        threading.Thread(target=lambda: box.setdefault('r', a.found or check_now(a.installed)), daemon=True).start(); root.after(150, poll)

    root.protocol('WM_DELETE_WINDOW', root.destroy)
    width = round(980 * g.SCALE)
    if root.winfo_screenheight() < round(940 * g.SCALE):   # a short screen (the Steam Deck's 800, with room for the notice): no helper lines
        for n in notes: n.grid_remove()
    place(root, width)
    root.minsize(round(760 * g.SCALE), round(420 * g.SCALE))
    if a.shot: shoot(root, a.shot)
    root.mainloop()
    return result['code']


def notice(a, look=None):
    """The check when the launcher window is not shown: a newer release in a small window of its own (the game starts meanwhile)"""
    n = a.found or check_now(a.installed)
    if not n: return 0
    print(f'{n["title"]}{": " + n["line"] if n["line"] else ""}. {UPDATE_LINE} {n["url"]}', file=sys.stderr)
    look = None if a.quiet else (look or tk_or_none())
    if not look: return 0
    tk, g, root = look
    root.title('Pokopia Native update')
    body = tk.Frame(root, bg=g.C['bg']); body.pack(fill='both', expand=True, padx=round(18 * g.SCALE), pady=round(18 * g.SCALE))
    notice_card(tk, g, body, n, lambda kind: kind != 'new' and root.destroy()).pack(fill='x')
    root.bind('<Escape>', lambda e: root.destroy())
    place(root, round(560 * g.SCALE))
    if a.shot: shoot(root, a.shot)
    root.mainloop()
    return 0


def room(a, look=None):
    look = look or tk_or_none()
    if not look: return NO_WINDOW
    tk, g, root = look
    C = g.C
    root.title('Pokopia - your room code')
    body = tk.Frame(root, bg=C['bg']); body.pack(fill='both', expand=True, padx=round(22 * g.SCALE), pady=round(20 * g.SCALE))
    g.label(body, 'Your room code for this session', 13, True, fg=C['title']).pack(fill='x')
    card = g.Round(body, pad=14, radius=14); card.pack(fill='x', pady=(10, 0))
    tk.Label(card.body, text=a.code, font=(g.MONO, 22 if not g.MAC else 28, 'bold'), fg=C['title'], bg=C['card']).pack()
    g.label(body, 'Give it to the players who visit, with this computer\'s internet address.', 10, fg=C['soft']).pack(fill='x', pady=(10, 0))
    row = tk.Frame(body, bg=C['bg']); row.pack(fill='x', pady=(14, 0))
    def copy():
        root.clipboard_clear(); root.clipboard_append(a.code); copied.set('Copied')
    copied = tk.StringVar()
    g.Pill(row, 'Start the game', root.destroy, 'primary', 11).pack(side='right')
    g.Pill(row, 'Copy', copy, size=11).pack(side='right', padx=(0, 10))
    tk.Label(row, textvariable=copied, font=g.F(10), fg=C['ok'], bg=C['bg']).pack(side='right', padx=(0, 10))
    root.bind('<Return>', lambda e: root.destroy()); root.bind('<Escape>', lambda e: root.destroy())
    place(root, round(480 * g.SCALE))
    if a.shot: shoot(root, a.shot)
    root.mainloop()
    return 0


def shoot(root, path):   # --shot <png>: a picture of the window (from the X server, Pillow), then closed; the project's own layout check
    def go():
        root.update_idletasks(); root.update()
        try:
            from PIL import ImageGrab
            x, y = root.winfo_rootx(), root.winfo_rooty()
            ImageGrab.grab(bbox=(x, y, x + root.winfo_width(), y + root.winfo_height()), xdisplay=os.environ.get('DISPLAY')).save(path)
        except Exception as e: print(f'play_window: no picture: {e}', file=sys.stderr)
        root.destroy()
    root.after(1500, go)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    la = sub.add_parser('launch'); la.add_argument('--settings', required=True); la.add_argument('--installed', default='')
    la.add_argument('--game-version', default=''); la.add_argument('--coop-ok', action='store_true'); la.add_argument('--coop-needs', default='')
    la.add_argument('--coop-game', default=''); la.add_argument('--no-save', action='store_true'); la.add_argument('--console-default', type=int, default=1)
    no = sub.add_parser('notice'); no.add_argument('--installed', required=True); no.add_argument('--quiet', action='store_true')
    ro = sub.add_parser('room'); ro.add_argument('code')
    for p in (la, no, ro): p.add_argument('--shot', default='')
    a = ap.parse_args(argv)
    a.found = None   # a notice already in hand (tests)
    try: return {'launch': launch, 'notice': notice, 'room': room}[a.cmd](a)
    except KeyboardInterrupt: return CANCELLED


if __name__ == '__main__':
    sys.exit(main())
