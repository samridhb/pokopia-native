"""test_play_window.py: the Linux launcher's update check (linux/play_window.py on nxs2.py's update_check and updates.json), without the
network: a stand-in answers for GitHub's API, and updates.json lives in a temporary POKOPIA_SETTINGS_DIR. No window is opened.
    python tools/test_play_window.py"""
import io, json, os, pathlib, sys, tempfile, time, unittest, urllib.request

HERE = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'linux'))
import play_window as pw  # noqa: E402
nxs2 = pw.nxs2


def release(tag='v1.4.1', name='Pokopia Native 1.4.1: Faster on the Steam Deck', **kw):
    return dict({'tag_name': tag, 'name': name, 'html_url': f'https://github.com/xFractals/pokopia-native/releases/tag/{tag}',
                 'draft': False, 'prerelease': False, 'assets': [], 'body': ''}, **kw)


class Check(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.env = os.environ.get('POKOPIA_SETTINGS_DIR'); os.environ['POKOPIA_SETTINGS_DIR'] = self.dir.name
        self.urlopen, self.calls, self.answer = urllib.request.urlopen, [], release()
        urllib.request.urlopen = self.fake

    def tearDown(self):
        urllib.request.urlopen = self.urlopen
        if self.env is None: os.environ.pop('POKOPIA_SETTINGS_DIR', None)
        else: os.environ['POKOPIA_SETTINGS_DIR'] = self.env
        self.dir.cleanup()

    def fake(self, req, timeout=None):
        self.calls.append((req.full_url, dict(req.header_items()), timeout))
        if isinstance(self.answer, Exception): raise self.answer
        if callable(self.answer): return self.answer()
        return io.BytesIO(json.dumps(self.answer).encode())

    def state(self, **d):
        (pathlib.Path(self.dir.name) / 'updates.json').write_text(json.dumps(d), encoding='utf-8')

    def saved(self): return json.loads((pathlib.Path(self.dir.name) / 'updates.json').read_text(encoding='utf-8'))

    def test_newer(self):
        n = pw.check_now('1.4.0')
        self.assertEqual(n['title'], 'Pokopia Native 1.4.1 is out')
        self.assertEqual(n['line'], 'Faster on the Steam Deck')
        self.assertEqual(n['url'], 'https://github.com/xFractals/pokopia-native/releases/tag/v1.4.1')
        url, headers, timeout = self.calls[0]
        self.assertEqual(url, 'https://api.github.com/repos/xFractals/pokopia-native/releases/latest')
        self.assertEqual(headers.get('Accept'), 'application/vnd.github+json')
        self.assertTrue(headers.get('User-agent', '').startswith('pokopia-native-update-check/'))
        self.assertNotIn('Cookie', headers)
        self.assertEqual(timeout, 3.0)
        self.assertEqual(self.saved()['latest'], 'v1.4.1')

    def test_same(self):
        self.answer = release('v1.4.0', 'Pokopia Native 1.4.0: Linux and the Steam Deck')
        self.assertIsNone(pw.check_now('1.4.0'))
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.saved()['latest'], 'v1.4.0')

    def test_build_older_than_builder(self):   # play.json's version, not the builder's TOOL_VERSION
        self.answer = release(nxs2.TOOL_VERSION.join(('v', '')), f'Pokopia Native {nxs2.TOOL_VERSION}: x')
        self.assertIsNotNone(pw.check_now('1.3.6'))

    def test_skipped(self):
        self.state(skipped='v1.4.1')
        self.assertIsNone(pw.check_now('1.4.0'))
        self.assertEqual(len(self.calls), 1)
        self.state(skipped='v1.4.1')
        self.answer = release('v1.4.2', 'Pokopia Native 1.4.2: More')
        self.assertEqual(pw.check_now('1.4.0')['title'], 'Pokopia Native 1.4.2 is out')   # a newer one than the skipped one shows

    def test_offline(self):
        self.state(last_check='2026-11-01T10:00:00Z')
        for answer in (OSError('no network'), urllib.error.HTTPError('u', 403, 'rate limit', {}, None), {'message': 'Not Found'}):
            self.answer = answer
            self.assertIsNone(pw.check_now('1.4.0'))
            self.assertEqual(self.saved(), {'last_check': '2026-11-01T10:00:00Z'})   # nothing kept: the next start asks again
        self.assertEqual(len(self.calls), 3)

    def test_slow_network(self):   # the 3 s cap holds even when the request never comes back
        def hang():
            time.sleep(5); raise OSError("too late")   # nothing written after the test has ended
        self.answer = hang
        t = time.monotonic()
        self.assertIsNone(pw.check_now('1.4.0', timeout=0.3))
        self.assertLess(time.monotonic() - t, 1.5)

    def test_check_false(self):
        self.state(check=False)
        self.assertIsNone(pw.check_now('1.4.0'))
        self.assertEqual(self.calls, [])   # the off switch: no request at all
        self.assertFalse(pw.checking())
        pw.set_checking(True)
        self.assertTrue(self.saved()['check'])
        pw.set_checking(False)
        self.assertFalse(self.saved()['check'])

    def test_once_a_day(self):
        self.assertIsNotNone(pw.check_now('1.4.0'))
        self.assertIsNone(pw.check_now('1.4.0'))   # the same day: no second request, no second notice ("Later" waits for tomorrow)
        self.assertEqual(len(self.calls), 1)
        s = self.saved(); s['last_check'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() - 25 * 3600)); self.state(**s)
        self.assertIsNotNone(pw.check_now('1.4.0'))
        self.assertEqual(len(self.calls), 2)

    def test_prerelease_never_counts(self):
        for answer in (release(prerelease=True), release(draft=True), release('v1.5.0-android-beta.3')):
            self.answer = answer
            self.assertIsNone(pw.check_now('1.4.0'))

    def test_missing_file_means_on(self):
        self.assertTrue(pw.checking())
        self.assertFalse((pathlib.Path(self.dir.name) / 'updates.json').exists())

    def test_notice_from(self):
        s = {'latest': 'v1.4.1', 'latest_name': 'Pokopia Native 1.4.1', 'latest_url': 'https://example.com/x'}
        n = pw.notice_from(s, '1.4.0')
        self.assertEqual((n['line'], n['url']), ('', 'https://github.com/xFractals/pokopia-native/releases/tag/v1.4.1'))
        self.assertIsNone(pw.notice_from(s, ''))
        self.assertIsNone(pw.notice_from(dict(s, check=False), '1.4.0'))
        self.assertIsNotNone(pw.notice_from(dict(s, latest='v1.10.0'), '1.9.3'))   # numbers, not text


class Launcher(unittest.TestCase):
    def test_room_text(self):
        self.assertEqual(pw.room_text('abcd efgh-jkmn pqrs'), 'ABCD-EFGH-JKMN-PQRS')
        self.assertEqual(pw.room_text('nope'), 'nope')

    def test_address(self):
        for ok in ('192.168.1.20', '203.0.113.7:47600'): self.assertTrue(pw.IPPORT.fullmatch(ok))
        for bad in ('256.1.1.1', 'host.local', '1.2.3'): self.assertFalse(pw.IPPORT.fullmatch(bad))

    def test_no_display(self):
        env = {k: os.environ.pop(k) for k in ('DISPLAY', 'WAYLAND_DISPLAY') if k in os.environ}
        try: self.assertEqual(pw.main(['launch', '--settings', tempfile.gettempdir()]), pw.NO_WINDOW)
        finally: os.environ.update(env)


def can_open():
    if not (os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')): return False
    try:
        import tkinter; r = tkinter.Tk(); r.destroy(); return True
    except Exception: return False


@unittest.skipUnless(can_open(), 'no display or no Tk here')
class Window(unittest.TestCase):
    """The launcher window opened for real: Play pressed (Return) after the given steps, what it saved read back"""
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory(); self.settings = pathlib.Path(self.dir.name)
        self.env = os.environ.get('POKOPIA_SETTINGS_DIR'); os.environ['POKOPIA_SETTINGS_DIR'] = self.dir.name
        self.check_now, self.shoot = pw.check_now, pw.shoot
        pw.check_now = lambda installed, timeout=3.0: None

    def tearDown(self):
        pw.check_now, pw.shoot = self.check_now, self.shoot
        if self.env is None: os.environ.pop('POKOPIA_SETTINGS_DIR', None)
        else: os.environ['POKOPIA_SETTINGS_DIR'] = self.env
        self.dir.cleanup()

    def run_window(self, steps, linkplay=None, display=None):
        for name, d in (('linkplay.json', linkplay), ('display.json', display)):
            if d is not None: (self.settings / name).write_text(json.dumps(d), encoding='utf-8')
        def drive(root, _):
            def walk(w):
                yield w
                for c in w.winfo_children(): yield from walk(c)
            def go(i=0):
                if i == len(steps): return root.destroy()   # still open after the last step: cancelled
                step = steps[i]
                if step == 'play': root.event_generate('<Return>')
                else: next(w for w in walk(root) if getattr(w, 'value', None) == step).event_generate('<Button-1>', x=4, y=4)
                root.after(300, go, i + 1)
            root.after(600, go); root.after(10000, root.destroy)   # never left open
        pw.shoot = drive
        code = pw.main(['launch', '--settings', self.dir.name, '--installed', '1.4.0', '--coop-ok', '--shot', 'x'])
        read = lambda n: json.loads((self.settings / n).read_text(encoding='utf-8')) if (self.settings / n).exists() else None
        return code, read('linkplay.json'), read('display.json')

    def test_visit_saved(self):
        code, lp, disp = self.run_window(['play'], {'mode': 'inet-visit', 'join': '203.0.113.7', 'room': 'abcd efgh jkmn pqrs', 'interact': True,
                                                    'story': True, 'host_room': 'K7QF-2M9X-HT4W-RB8C'}, {'console': 0})
        self.assertEqual(code, pw.PLAY)
        self.assertEqual(lp, {'mode': 'inet-visit', 'join': '203.0.113.7', 'room': 'ABCD-EFGH-JKMN-PQRS', 'interact': True, 'story': True,
                              'host_room': 'K7QF-2M9X-HT4W-RB8C', 'ask': True})
        self.assertEqual(disp, {'console': 0})   # nothing changed here: nothing added

    def test_bad_address_stays_open(self):
        code, lp, _ = self.run_window(['play'], {'mode': 'join', 'join': 'host.local'})
        self.assertEqual(code, pw.CANCELLED)
        self.assertEqual(lp, {'mode': 'join', 'join': 'host.local'})

    def test_choices_written(self):
        code, lp, disp = self.run_window(['host', 'fxaa', 'play'], None, {'fps': 30, 'vsync': False})
        self.assertEqual(code, pw.PLAY)
        self.assertEqual((lp['mode'], lp['ask'], lp['interact'], lp['story']), ('host', True, False, False))
        self.assertEqual(disp, {'fps': 30, 'vsync': False, 'antialiasing': 'fxaa'})   # F1's other settings kept

    def test_frame_rate_cap(self):
        code, _, disp = self.run_window([45, 'play'], None, {})
        self.assertEqual((code, disp), (pw.PLAY, {'fps': 45}))

    def test_cancel(self):
        code, lp, disp = self.run_window([])
        self.assertEqual((code, lp, disp), (pw.CANCELLED, None, None))


if __name__ == '__main__':
    unittest.main(verbosity=1)
