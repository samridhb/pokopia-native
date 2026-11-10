# play.ps1: plays Pokemon Pokopia 2.0.1 with nxrt (the Vulkan renderer, SDL3 input and sound). See docs/m6-input-gameplay.md for the controls.
#   play.ps1 -ExeFS <ExeFS folder> -Dll <game.dll> -RomFS <RomFS.img or folder> -Save <save folder> [-Work <folder>] [-Silent] [-Fullscreen] [-Window 1600x900] [-Exe <nxrt.exe>]
#            [-LinkPlay] [-Join <IPv4[:port]>|ask] [-Internet [-Room <code>|ask] [-Relay <IPv4[:port]>]] [-CoopHost <port> | -CoopJoin <address:port> [-CoopTcp]] [-Interact] [-Story]
#            [-Settings] [-PadCheck] [-DryRun]
#   play.ps1 -Config <play.json> [any switch above]: an installer build's launcher (docs/M7-REPORT.md): the paths come from play.json, relative ones from its folder,
#            %VARIABLES% expanded; a switch given here wins over the file. A save folder named only by the file is created empty the first time.
# The same script plays 1.0.5 and 2.0.1: -ExeFS, -Dll and -RomFS name one version's files (docs/m6-phase-b.md §1). -PadCheck logs every controller's buttons,
# sticks, gyro and rumble and shows them in the window title (docs/m6-phase-b.md §4). -DryRun prints the command line and starts nothing.
# -Save is the save the game plays on and writes to (the B00 / G00 / S00 folders; the game commits through a work copy beside it, <Save>.work). Point it at a
# copy, never at your only save. -Work holds the shader / pipeline cache (kept between runs: later starts have no compile hitches), temp files and the logs
# (default %LOCALAPPDATA%\pokopia-native). nxrt runs at below-normal priority. Nothing here names a game file: every path comes from the arguments.
# Shaders (an installer build): -Shaders <nxshader cache> (NXRT_SHADER_CACHE), -ShaderBuild <build folder> (NXRT_SHADER_BUILD: its hand-made answers), and for the
# run-time shaders -ShaderTool <nxshader.py> with -Python, -Installer <the installer's lowering steps> and -SpirvTools <folder> (NXRT_SHADER_TOOL, NXSHADER_TOOLS);
# -Fonts <folder> (DM_FONT_DIR), -PipelineSeed <list> (NXRT_VK_PIPELINE_SEED), -Dlc <folder> (DM_AOC_DIR: your own DLC, see below).
# Link Play "Local connection" between our builds (docs/coop-step1c.md, docs/coop-step1d.md): -LinkPlay hosts and finds hosts on this network; -Join <IPv4>[:<port>]
# visits one host by address instead (a home-network address; a VPN's, such as Radmin VPN's 26.x, needs -Internet); -Internet plays across the internet:
# every player gives the host's room code (-Room), and a host without one gets a new code shown in this window; -Relay <IPv4>[:<port>] goes through a relay
# you trust. "ask" for -Join or -Room asks in this window. For tests on one PC:
# -CoopHost <port> hosts on 127.0.0.1:<port>, -CoopJoin 127.0.0.1:<port> joins it; -CoopTcp sends the game's datagrams over the TCP link (through a tunnel).
# Each player needs a save of their own (the game refuses a second copy of the host's save). A second instance on one PC needs its own -Save and -Work.
# -Interact turns on "Interact everywhere" (experimental, docs/coop-interact.md): in every town, not only Palette Town, Link Play visitors can use moves and
# items and build. Every player in a session needs it on (a session refuses a player whose setting differs).
# -Story turns on "Story co-op" (experimental, docs/story-coop.md) on top of Interact everywhere: a visitor talks to the town's NPCs as the host does.
# Every player needs it on too.
# The Link Play window (an installer build's launcher, or -Ask, when no Link Play switch is given): play alone, on this network, host or visit over the
# internet, remembered in %APPDATA%\Pokopia Native\linkplay.json. "Don't ask again" starts the remembered way; Shift held while starting brings it back,
# and so does -Settings (the installer's "Pokopia Settings" launcher).
# A host over the internet gets its room code in a window with a Copy button.
# The window's Controls tab sets this PC's keyboard keys (%APPDATA%\Pokopia Native\controls.json, handed to the game as DM_KEYMAP; the game logs the map):
# click an action, press its key. Keys count by their place on the keyboard; "Reset to defaults" brings back the usual layout. Its Controller buttons page
# sets one button map for every controller (the same file's "pad" object) and can forget the controller kept as player 1 (the game's F1 menu chooses it).
# Its Display tab sets the picture (%APPDATA%\Pokopia Native\display.json; with -Ask or -Config at every start, switches from outside winning): console mode
# (DM_OPMODE), the size the game draws its picture at (NXRT_VK_RESOLUTION: "default" = the monitor's height, or <w>x<h>, from 1280x720 up;
# NXRT_VK_SCALE, a factor, wins), window or full screen and the window size, upscaling (NXRT_VK_UPSCALE) and its sharpness (NXRT_VK_SHARPNESS), 30 fps
# (DM_FPS), vsync off (NXRT_VK_PRESENT=mailbox), the FPS counter (NXRT_FPS_COUNTER), the wide view (NXRT_VK_WIDE=1, experimental). In the game, F1 (or a controller's Minus + Plus) opens the same settings and changes them at once; it saves to the same files
# (NXRT_SETTINGS_DIR, docs/in-game-menu.md). POKOPIA_SETTINGS_DIR puts linkplay.json, controls.json and display.json in another folder (tests).
# The update check (an installer build's launcher, the builder's rules): at most once a day one request to GitHub for the latest release's version, with no
# cookies and nothing about the player, the game or this PC. It runs beside the start for 3 s at most; offline or an error shows nothing. A release newer than
# play.json's pokopia_native shows a notice: in the window when it is open, else in a small window before the game starts (-Silent mutes only the sound).
# "Check for updates" in the window, or "check": false in %LOCALAPPDATA%\Pokopia Native\updates.json (the builder's file too), turns it off.
param(
    [string]$ExeFS = "",
    [string]$Dll = "",
    [string]$RomFS = "",
    [string]$Save = "",
    [string]$Work = "",
    [string]$Exe = "",
    [string]$Config = "",
    [string]$Shaders = "",
    [string]$ShaderBuild = "",
    [string]$ShaderTool = "",
    [string]$Python = "",
    [string]$Installer = "",
    [string]$SpirvTools = "",
    [string]$Fonts = "",
    [string]$PipelineSeed = "",
    [string]$Dlc = "",
    [string]$Window = "",
    [switch]$Silent,
    [switch]$Fullscreen,
    [switch]$Ask,
    [switch]$Settings,
    [switch]$LinkPlay,
    [string]$Join = "",
    [switch]$Internet,
    [string]$Room = "",
    [string]$Relay = "",
    [string]$CoopHost = "",
    [string]$CoopJoin = "",
    [switch]$CoopTcp,
    [switch]$Interact,
    [switch]$Story,
    [switch]$PadCheck,
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$newSave = $false
$installed = ""   # this build's pokopia-native version (play.json): the update check compares the latest release with it
if ($Config) {
    if (-not (Test-Path -LiteralPath $Config)) { Write-Error "not found: $Config"; exit 2 }
    $cfgDir = Split-Path -Parent (Resolve-Path -LiteralPath $Config).Path
    $c = Get-Content -Raw -LiteralPath $Config | ConvertFrom-Json
    $installed = "$($c.pokopia_native)"
    function CfgPath([string]$v) {
        if (-not $v) { return "" }
        $v = [Environment]::ExpandEnvironmentVariables($v)
        if ([System.IO.Path]::IsPathRooted($v)) { return $v } else { return [System.IO.Path]::GetFullPath((Join-Path $cfgDir $v)) }
    }
    if (-not $ExeFS) { $ExeFS = CfgPath $c.exefs }
    if (-not $Dll) { $Dll = CfgPath $c.dll }
    if (-not $RomFS) { $RomFS = CfgPath $c.romfs }
    if (-not $Save) { $Save = CfgPath $c.save; $newSave = $true }
    if (-not $Work) { $Work = CfgPath $c.work }
    if (-not $Exe) { $Exe = CfgPath $c.exe }
    if (-not $Shaders) { $Shaders = CfgPath $c.shaders }
    if (-not $ShaderBuild) { $ShaderBuild = CfgPath $c.shader_build }
    if (-not $ShaderTool) { $ShaderTool = CfgPath $c.shader_tool }
    if (-not $Python) { $Python = CfgPath $c.python }
    if (-not $Installer) { $Installer = CfgPath $c.installer }
    if (-not $SpirvTools) { $SpirvTools = CfgPath $c.spirv_tools }
    if (-not $Fonts) { $Fonts = CfgPath $c.fonts }
    if (-not $PipelineSeed) { $PipelineSeed = CfgPath $c.pipeline_seed }
    if (-not $Dlc) { $Dlc = CfgPath $c.dlc }
}
foreach ($n in @("ExeFS", "Dll", "RomFS", "Save")) { if (-not (Get-Variable $n -ValueOnly)) { Write-Error "-$n is needed (or -Config <play.json>)"; exit 2 } }
# The defaults are resolved here, not in param(): some hosts leave $PSScriptRoot empty there (a script block, -Command, older shells), so -Exe was needed
$here = $PSScriptRoot
if (-not $here -and $PSCommandPath) { $here = Split-Path -Parent $PSCommandPath }
if (-not $here -and $MyInvocation.MyCommand.Path) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Exe) {
    $look = @(); if ($here) { $look += Join-Path $here "..\build\Release\bin\nxrt.exe" }
    $look += (Join-Path (Get-Location).Path "build\Release\bin\nxrt.exe"), (Join-Path (Get-Location).Path "..\build\Release\bin\nxrt.exe")
    $Exe = $look | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $Exe) { Write-Error "nxrt.exe not found ($($look -join ', ')): give -Exe"; exit 2 }
}
if (-not $Work) {
    $la = $env:LOCALAPPDATA; if (-not $la) { $la = [Environment]::GetFolderPath('LocalApplicationData') }
    $Work = Join-Path $la "pokopia-native"
}
if (-not [System.IO.Path]::IsPathRooted($Work)) { $Work = Join-Path (Get-Location).Path $Work }   # nxrt starts in $Work: its paths must not be relative
if ($newSave -and -not (Test-Path -LiteralPath $Save) -and -not $DryRun) { New-Item -ItemType Directory -Force $Save | Out-Null; Write-Host "a new save folder: $Save" }
$must = @($ExeFS, $Dll, $RomFS, $Exe); if (-not ($newSave -and $DryRun)) { $must += $Save }   # a dry run does not make the new save folder
foreach ($p in $must) { if (-not (Test-Path -LiteralPath $p)) { Write-Error "not found: $p"; exit 2 } }
foreach ($m in @("main", "sdk")) { if (-not (Test-Path -LiteralPath (Join-Path $ExeFS $m))) { Write-Error "$ExeFS has no '$m': give the game's ExeFS folder"; exit 2 } }
# Interact everywhere and Story co-op have sites in these game versions only (src/coop/coop_interact.c; ctest coop.play_builds keeps the lists alike). Main's
# build ID is the module ID in its NSO header
$CoopBuilds = [ordered]@{ '76a489f3bd3642fa5e18bd83d32c98ba' = '2.0.1'; '816c5358e8178d802fcec4a7ce5a741a' = '1.0.5' }
$mainBuild = ""
try { $fs = [System.IO.File]::OpenRead((Join-Path $ExeFS "main")); $b = New-Object byte[] 16; $fs.Position = 0x40; if ($fs.Read($b, 0, 16) -eq 16) { $mainBuild = -join ($b | ForEach-Object { $_.ToString("x2") }) }; $fs.Close() } catch {}
$coopOk = $CoopBuilds.Contains($mainBuild)
$coopNeeds = "Pokopia $($CoopBuilds.Values -join ' or ')"
$coopGame = $(if ($mainBuild) { "main $($mainBuild.Substring(0, 16))" } else { "main unreadable" })
$noSave = -not (Get-ChildItem -LiteralPath $Save -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[BGS]00$' })
if ($noSave) {
    Write-Warning "$Save holds no B00 / G00 / S00 folders: the game will start a new save there"
}
if ($CoopHost -and $CoopJoin) { Write-Error "-CoopHost and -CoopJoin: give one"; exit 2 }
if ($CoopHost -and $CoopHost -notmatch '^\d{1,5}$') { Write-Error "-CoopHost wants a port, e.g. 47600"; exit 2 }
if ($CoopJoin -and $CoopJoin -notmatch '^(127\.\d{1,3}\.\d{1,3}\.\d{1,3}|localhost):\d{1,5}$') {
    Write-Error "-CoopJoin wants 127.0.0.1:<port> (loopback only for now; reach another machine through an SSH tunnel to a local port)"; exit 2
}
$ipPort = '^(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}(:\d{1,5})?$'
$roomRx = '^[0-9A-TV-Za-tv-z]{16}$'   # after dashes and spaces are taken out: Crockford's base32 (the game reads I, L and O as 1, 1 and 0)

# The windows' look: the GitHub page's fade colours, as the builder has them (tools/make_readme_art.py). WinForms draws no gradients, so a primary button is
# the fade's middle; buttons are pills and sections white cards with a thin border (PokopiaPill, PokopiaCard)
$UiHex = @{ bg = '#FBF6FD'; card = '#FFFFFF'; border = '#EAE2F2'; ink = '#1C1626'; body = '#3A3346'; muted = '#6A6277'; tint = '#F5EDFF'; tintHover = '#EDE2FF'
            soft = '#FFE3EC'; primary = '#D23CF0'; primaryHover = '#BF2EDD'; problem = '#A32D2D'; problemBg = '#FCEBEB' }
$Ui = @{}
# Compiled once, when a window is shown. PokopiaKeys: the Controls tab's key's scan code (its place) and which Shift or Ctrl it was; the Display tab's monitor
# size in pixels
function Add-PokopiaUi {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    if (-not ('PokopiaPill' -as [type])) {
        Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Drawing2D; using System.Runtime.InteropServices; using System.Windows.Forms;
public static class PokopiaKeys {
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint c, uint t);
    [DllImport("user32.dll")] static extern short GetKeyState(int k);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr w);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr w, IntPtr dc);
    [DllImport("gdi32.dll")] static extern int GetDeviceCaps(IntPtr dc, int i);
    public static uint Scan(int vk) { return MapVirtualKey((uint)vk, 4); }
    public static bool Down(int vk) { return (GetKeyState(vk) & 0x8000) != 0; }
    public static int ScreenHeight() { IntPtr dc = GetDC(IntPtr.Zero); int h = GetDeviceCaps(dc, 117); ReleaseDC(IntPtr.Zero, dc); return h; }   // DESKTOPVERTRES
    public static int ScreenWidth() { IntPtr dc = GetDC(IntPtr.Zero); int w = GetDeviceCaps(dc, 118); ReleaseDC(IntPtr.Zero, dc); return w; }    // DESKTOPHORZRES
}
public static class PokopiaDraw {
    public static GraphicsPath Round(RectangleF r, float rad) {
        GraphicsPath p = new GraphicsPath(); float d = Math.Min(rad * 2, Math.Min(r.Width, r.Height));
        if (d < 1) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
    }
    public static Color Under(Control c) { for (Control p = c.Parent; p != null; p = p.Parent) if (p.BackColor.A == 255) return p.BackColor; return SystemColors.Control; }
    public static Color Mix(Color a, Color b, float k) { return Color.FromArgb((int)(a.R + (b.R - a.R) * k), (int)(a.G + (b.G - a.G) * k), (int)(a.B + (b.B - a.B) * k)); }
}
// A pill: Fill (FillHover under the mouse), the text in ForeColor, the keyboard focus a ring
public class PokopiaPill : Button {
    public Color Fill = Color.White, FillHover = Color.White, Ring = Color.Black; bool over;
    public PokopiaPill() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        FlatStyle = FlatStyle.Flat; FlatAppearance.BorderSize = 0; Cursor = Cursors.Hand; Padding = new Padding(14, 2, 14, 2);
    }
    protected override void OnMouseEnter(EventArgs e) { over = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { over = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics; Color under = PokopiaDraw.Under(this); g.Clear(under); g.SmoothingMode = SmoothingMode.AntiAlias;
        Color f = over && Enabled ? FillHover : Fill; if (!Enabled) f = PokopiaDraw.Mix(f, under, 0.45f);
        using (GraphicsPath p = PokopiaDraw.Round(new RectangleF(1, 1, Width - 2.5f, Height - 2.5f), (Height - 2) / 2f)) {
            using (SolidBrush b = new SolidBrush(f)) g.FillPath(b, p);
            if (Focused && ShowFocusCues) using (Pen pen = new Pen(Ring, 1.5f)) g.DrawPath(pen, p);
        }
        TextRenderer.DrawText(g, Text, Font, ClientRectangle, Enabled ? ForeColor : PokopiaDraw.Mix(ForeColor, under, 0.5f),
                              TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
    }
}
// A window: Ctrl+Tab and Ctrl+Shift+Tab step through its tabs (NextTab, PrevTab), as a tab control's do
public class PokopiaForm : Form {
    public event EventHandler NextTab, PrevTab;
    protected override bool ProcessCmdKey(ref Message m, Keys k) {
        EventHandler h = k == (Keys.Control | Keys.Tab) ? NextTab : k == (Keys.Control | Keys.Shift | Keys.Tab) ? PrevTab : null;
        if (h != null) { h(this, EventArgs.Empty); return true; }
        return base.ProcessCmdKey(ref m, k);
    }
}
// A card: BackColor with a thin Border and round corners on whatever is under it; its controls lie top to bottom
public class PokopiaCard : FlowLayoutPanel {
    public Color Border = Color.Gray; public float Radius = 14;
    public PokopiaCard() { DoubleBuffered = true; ResizeRedraw = true; FlowDirection = FlowDirection.TopDown; WrapContents = false; }
    protected override void OnPaintBackground(PaintEventArgs e) {
        Graphics g = e.Graphics; g.Clear(PokopiaDraw.Under(this)); g.SmoothingMode = SmoothingMode.AntiAlias;
        using (GraphicsPath p = PokopiaDraw.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), Radius))
        using (SolidBrush b = new SolidBrush(BackColor)) using (Pen pen = new Pen(Border)) { g.FillPath(b, p); g.DrawPath(pen, p); }
    }
}
'@
    }
    foreach ($k in $UiHex.Keys) { $script:Ui[$k] = [System.Drawing.ColorTranslator]::FromHtml($UiHex[$k]) }
}
function New-LinkPlayForm([string]$title) {
    Add-PokopiaUi
    $f = New-Object PokopiaForm
    $f.Text = $title; $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.AutoScaleMode = 'Dpi'; $f.AutoSize = $true; $f.AutoSizeMode = 'GrowAndShrink'; $f.TopMost = $true; $f.ShowInTaskbar = $true
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 10); $f.BackColor = $Ui.bg; $f.ForeColor = $Ui.body
    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.FlowDirection = 'TopDown'; $flow.WrapContents = $false; $flow.AutoSize = $true; $flow.AutoSizeMode = 'GrowAndShrink'   # shrinks when the update card goes
    $flow.Padding = New-Object System.Windows.Forms.Padding(20, 16, 20, 18)
    $f.Controls.Add($flow)
    return $f, $flow
}
function New-Label([string]$text, [int]$width = 470, [string]$tone = "") {   # tone: muted (helper text), ink, problem
    $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.AutoSize = $true; $l.MaximumSize = New-Object System.Drawing.Size($width, 0)
    switch ($tone) {
        'muted' { $l.ForeColor = $Ui.muted }
        'ink' { $l.ForeColor = $Ui.ink }
        'problem' { $l.ForeColor = $Ui.problem; $l.BackColor = $Ui.problemBg; $l.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6) }
    }
    $l
}
function New-Title([string]$text, [float]$size = 15, [int]$width = 600) {   # 15 pt is the spec's 20 px title; 10.5 pt a card's
    $l = New-Label $text $width 'ink'; $l.Font = New-Object System.Drawing.Font('Segoe UI Semibold', $size); $l
}
function New-Card([int]$pad = 16) {
    $c = New-Object PokopiaCard; $c.BackColor = $Ui.card; $c.Border = $Ui.border; $c.AutoSize = $true; $c.AutoSizeMode = 'GrowAndShrink'
    $c.Padding = New-Object System.Windows.Forms.Padding($pad); $c.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0); $c
}
function New-Pill([string]$text, [switch]$Primary) {   # primary: the fade's middle with white text; plain: the tint with ink text
    $b = New-Object PokopiaPill; $b.Text = $text; $b.AutoSize = $true; $b.MinimumSize = New-Object System.Drawing.Size(96, 34); $b.Ring = $Ui.ink
    if ($Primary) { $b.Fill = $Ui.primary; $b.FillHover = $Ui.primaryHover; $b.ForeColor = [System.Drawing.Color]::White; $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10) }
    else { $b.Fill = $Ui.tint; $b.FillHover = $Ui.tintHover; $b.ForeColor = $Ui.ink }
    $b
}
function New-Buttons($form, [string[]]$names) {   # right-aligned; the first is the primary and the default (Enter), "Cancel" closes with Cancel
    $row = New-Object System.Windows.Forms.FlowLayoutPanel; $row.FlowDirection = 'RightToLeft'; $row.Size = New-Object System.Drawing.Size(470, 42)
    $row.Margin = New-Object System.Windows.Forms.Padding(0, 14, 0, 0)
    $out = @{}
    foreach ($n in $names) { $b = New-Pill $n -Primary:($n -eq $names[0]); $b.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0); $row.Controls.Add($b); $out[$n] = $b }
    $form.AcceptButton = $out[$names[0]]
    if ($out['Cancel']) { $out['Cancel'].DialogResult = 'Cancel'; $form.CancelButton = $out['Cancel'] }
    return $row, $out
}
# The keyboard's controls (the window's Controls tab, %APPDATA%\Pokopia Native\controls.json, given to the game as DM_KEYMAP; front_map.h front_keymap_parse):
# an action's key as an SDL scancode, the USB usage of the key's place on the keyboard, so a map means the same keys under any layout. The default is the
# game's own layout (WASD, J/K/U/I, ...)
$ControlsDefault = [ordered]@{ A = 13; B = 14; X = 24; Y = 12; L = 20; R = 8; ZL = 29; ZR = 6; Plus = 40; Minus = 43; StickUp = 26; StickLeft = 4; StickDown = 22
                               StickRight = 7; Up = 82; Down = 81; Left = 80; Right = 79; LS = 9; RS = 10; Shake = 44 }
$ControlsLabel = [ordered]@{ A = "A"; B = "B"; X = "X"; Y = "Y"; L = "L"; R = "R"; ZL = "ZL"; ZR = "ZR"; Plus = "+ (Plus)"; Minus = "- (Minus)"
                             StickUp = "Stick up"; StickLeft = "Stick left"; StickDown = "Stick down"; StickRight = "Stick right"; Up = "D-pad up"; Down = "D-pad down"
                             Left = "D-pad left"; Right = "D-pad right"; LS = "Left stick press"; RS = "Right stick press"; Shake = "Shake" }
# The keys a map can use: {set-1 scan code (0xE0.. for the extended ones): @(SDL scancode, name)}. Esc, F11, Alt and the Windows keys are the window's and Windows',
# F1 the in-game menu's
function Get-KeyTable {
    $t = @{}
    $rows = 'QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM'; $first = 0x10, 0x1E, 0x2C
    for ($r = 0; $r -lt 3; $r++) { for ($i = 0; $i -lt $rows[$r].Length; $i++) { $ch = $rows[$r][$i]; $t[$first[$r] + $i] = @((4 + [int]$ch - [int][char]'A'), "$ch") } }
    for ($d = 1; $d -le 10; $d++) { $t[1 + $d] = @((29 + $d), "$($d % 10)") }   # 1..9, 0
    for ($n = 2; $n -le 10; $n++) { $t[0x3A + $n] = @((57 + $n), "F$n") }
    foreach ($m in @(@(0x58, 69, 'F12'), @(0x1C, 40, 'Enter'), @(0x0E, 42, 'Backspace'), @(0x0F, 43, 'Tab'), @(0x39, 44, 'Space'), @(0x0C, 45, '-'), @(0x0D, 46, '='),
                     @(0x1A, 47, '['), @(0x1B, 48, ']'), @(0x2B, 49, '\'), @(0x27, 51, ';'), @(0x28, 52, "'"), @(0x29, 53, '`'), @(0x33, 54, ','), @(0x34, 55, '.'),
                     @(0x35, 56, '/'), @(0x3A, 57, 'Caps Lock'), @(0x56, 100, '\ (ISO)'), @(0xE052, 73, 'Insert'), @(0xE047, 74, 'Home'), @(0xE049, 75, 'Page Up'),
                     @(0xE053, 76, 'Delete'), @(0xE04F, 77, 'End'), @(0xE051, 78, 'Page Down'), @(0xE04D, 79, 'Right arrow'), @(0xE04B, 80, 'Left arrow'),
                     @(0xE050, 81, 'Down arrow'), @(0xE048, 82, 'Up arrow'), @(0xE035, 84, 'Keypad /'), @(0x37, 85, 'Keypad *'), @(0x4A, 86, 'Keypad -'),
                     @(0x4E, 87, 'Keypad +'), @(0x4F, 89, 'Keypad 1'), @(0x50, 90, 'Keypad 2'), @(0x51, 91, 'Keypad 3'), @(0x4B, 92, 'Keypad 4'), @(0x4C, 93, 'Keypad 5'),
                     @(0x4D, 94, 'Keypad 6'), @(0x47, 95, 'Keypad 7'), @(0x48, 96, 'Keypad 8'), @(0x49, 97, 'Keypad 9'), @(0x52, 98, 'Keypad 0'), @(0x53, 99, 'Keypad .'),
                     @(0x1D, 224, 'Left Ctrl'), @(0x2A, 225, 'Left Shift'), @(0xE01D, 228, 'Right Ctrl'), @(0x36, 229, 'Right Shift'))) { $t[$m[0]] = @($m[1], $m[2]) }
    $t
}
# The saved map over the default (a missing or unreadable file, or an action it lacks, keeps the default)
function Read-Controls([string]$file) {
    $m = [ordered]@{}; foreach ($k in $ControlsDefault.Keys) { $m[$k] = $ControlsDefault[$k] }
    try {
        if (Test-Path -LiteralPath $file) {
            $j = Get-Content -Raw -LiteralPath $file | ConvertFrom-Json
            foreach ($k in @($m.Keys)) { $v = $j.$k -as [int]; if ($null -ne $v -and $v -ge 4 -and $v -le 231) { $m[$k] = $v } }
        }
    } catch {}
    $m
}
# The controllers' buttons (the same file's "pad" object, front_map.h front_padmap_parse): one map for every controller, each Switch button's controller input
# by SDL's name for its place (south = the bottom face button). Without a "pad" object the game keeps its own layout, which $PadDefault shows. "player1" and
# "player1_name" name the controller that is player 1 (the game's F1 menu chooses it; here it can only be forgotten)
$PadDefault = [ordered]@{ A = "east"; B = "south"; X = "north"; Y = "west"; L = "leftshoulder"; R = "rightshoulder"; ZL = "lefttrigger"; ZR = "righttrigger"
                          Plus = "start"; Minus = "back"; Up = "dpup"; Down = "dpdown"; Left = "dpleft"; Right = "dpright"; LS = "leftstick"; RS = "rightstick" }
$PadInputs = [ordered]@{ south = "Bottom face button"; east = "Right face button"; west = "Left face button"; north = "Top face button"
                         leftshoulder = "LB / L1 / L"; rightshoulder = "RB / R1 / R"; lefttrigger = "LT / L2 / ZL"; righttrigger = "RT / R2 / ZR"
                         back = "Back / Select / -"; start = "Start / Options / +"; leftstick = "Left stick press"; rightstick = "Right stick press"
                         dpup = "D-pad up"; dpdown = "D-pad down"; dpleft = "D-pad left"; dpright = "D-pad right"; misc1 = "Share / Capture"
                         rightpaddle1 = "Paddle R1"; leftpaddle1 = "Paddle L1"; rightpaddle2 = "Paddle R2"; leftpaddle2 = "Paddle L2"; touchpad = "Touchpad"
                         misc2 = "Extra 2"; misc3 = "Extra 3"; misc4 = "Extra 4"; misc5 = "Extra 5"; misc6 = "Extra 6"; none = "(none)" }
function Read-Pad([string]$file) {
    $r = @{ pad = $null; player1 = ""; player1_name = "" }
    try {
        if (Test-Path -LiteralPath $file) {
            $j = Get-Content -Raw -LiteralPath $file | ConvertFrom-Json
            if ($j.pad) { $m = [ordered]@{}; foreach ($k in $PadDefault.Keys) { $v = "$($j.pad.$k)"; $m[$k] = if ($PadInputs.Contains($v)) { $v } else { $PadDefault[$k] } }; $r.pad = $m }
            if ($j.player1) { $r.player1 = "$($j.player1)" }
            if ($j.player1_name) { $r.player1_name = "$($j.player1_name)" }
        }
    } catch {}
    $r
}
# The picture (the window's Display tab, %APPDATA%\Pokopia Native\display.json), applied at every start through the switches and variables below; a switch
# or variable given from outside wins. The Mac's launcher has the same names (Console mode, Display mode, Upscaling); the in-game menu (F1) the same choices
$DisplayDefault = [ordered]@{ console = 1; resolution = "default"; fullscreen = $false; window = "1280x720"; upscale = "sharp"; sharpness = 5; fps = 60; vsync = $true
                              fps_counter = "off"; wide_view = $false; antialiasing = "smaa" }
$DisplayCounters = @("off", "corner", "detailed")
$DisplayAA = @("off", "fxaa", "smaa")
$DisplaySizes = @("1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160")
# The tallest Default the game draws: 1440 on a graphics card with 4 GB of its own memory or less, as nxrt picks it (front/menu.c monitor_h). The
# registry's display adapters; one under 1 GB is an integrated GPU (nxrt sees its shared memory instead); the 32-bit size stops near 4 GB, so it only
# counts below that. NXRT_VK_VRAM_MB pretends a size, as in nxrt
function Get-DefaultTop {
    $mb = 0
    if ($env:NXRT_VK_VRAM_MB) { $mb = [int64]$env:NXRT_VK_VRAM_MB } else {
        foreach ($k in Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue; if (-not $p) { continue }
            $b = [int64]$p.'HardwareInformation.qwMemorySize'; $d = $p.'HardwareInformation.MemorySize'
            if (-not $b -and $d) { $b = if ($d -is [byte[]]) { [int64][BitConverter]::ToUInt32($d, 0) } else { [int64]$d }; if ($b -ge 4293918720) { $b = 0 } }
            if ($b -ge 1GB -and $b / 1MB -gt $mb) { $mb = $b / 1MB }
        }
    }
    if ($mb -gt 0 -and $mb -le 4608) { 1440 } else { 2160 }
}
function Read-Display([string]$file) {
    $d = [ordered]@{}; foreach ($k in $DisplayDefault.Keys) { $d[$k] = $DisplayDefault[$k] }
    try { if (Test-Path -LiteralPath $file) { (Get-Content -Raw -LiteralPath $file | ConvertFrom-Json).PSObject.Properties | ForEach-Object { if ($d.Contains($_.Name)) { $d[$_.Name] = $_.Value } } } } catch {}
    # the resolution is the size the game draws at ("default" or "<w>x<h>", kept as saved); a factor from before the sizes (1 / 1.5 / 2 / 3) was meant docked
    $r = "$($d.resolution)"; $f = 0.0
    if ($r -ne "default" -and $r -notmatch '^\d+x\d+$') {
        $d.resolution = if ([double]::TryParse($r, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$f) -and $f -ge 1) {
            $h = [int][math]::Round(1080 * $f); "$([int][math]::Round($h * 16 / 9))x$h" } else { $DisplayDefault.resolution }
    }
    if ($DisplayCounters -notcontains "$($d.fps_counter)") { $d.fps_counter = $DisplayDefault.fps_counter }
    if ($DisplayAA -notcontains "$($d.antialiasing)") { $d.antialiasing = $DisplayDefault.antialiasing }
    return $d
}

# The update check, by the builder's rules (nxs2.py update_check): updates.json is shared with it, also its record of the release's downloads. A
# check is recorded only when it worked, so an offline start tries again next time. POKOPIA_UPDATE_URL asks another address (tests: a file:// one),
# POKOPIA_UPDATE_NOW=1 checks within the day too, POKOPIA_UPDATE_ANSWER (later / skip / download) answers the notice without a window
$UpdateApi = "https://api.github.com/repos/xFractals/pokopia-native/releases/latest"
$UpdateAsk = "Check for updates (once a day, asks GitHub for the latest version)"
function Get-UpdateVersion([string]$tag) { if ("$tag".Trim() -match '^v?(\d+)\.(\d+)\.(\d+)$') { [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" } }
function Read-Updates([string]$file) {
    $u = [ordered]@{}
    try { if (Test-Path -LiteralPath $file) { (Get-Content -Raw -LiteralPath $file | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $u[$_.Name] = $_.Value } } } catch {}
    $u
}
function Save-Updates([string]$file, $u) {   # without a byte-order mark: the builder's Python reads it too
    try { New-Item -ItemType Directory -Force (Split-Path -Parent $file) | Out-Null; [System.IO.File]::WriteAllText($file, ($u | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false)) } catch {}
}
# Starts the request when a check is due (on, and none worked in the last 24 hours), in the background: WebClient's own thread, nothing waits for it here
function Start-UpdateCheck([string]$file, [string]$version) {
    $u = Read-Updates $file
    if ($u.check -eq $false -or -not (Get-UpdateVersion $version)) { return $null }
    $last = [datetime]::MinValue
    [void][datetime]::TryParseExact("$($u.last_check)", "yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture,
                                    [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal', [ref]$last)
    if (-not $env:POKOPIA_UPDATE_NOW -and ([datetime]::UtcNow - $last).TotalHours -lt 24) { return $null }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient; $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers['Accept'] = 'application/vnd.github+json'; $wc.Headers['User-Agent'] = "pokopia-native-update-check/$version"
        $url = if ($env:POKOPIA_UPDATE_URL) { $env:POKOPIA_UPDATE_URL } else { $UpdateApi }
        @{ client = $wc; task = $wc.DownloadStringTaskAsync([uri]$url); until = (Get-Date).AddSeconds(3); file = $file; version = $version
           done = $false; info = $null; shown = $false; answer = "" }
    } catch { $null }
}
# The answer, waiting at most $waitMs and never past the check's 3 s: a newer release than this build that was not skipped ({tag, version, name, url}),
# else $null. A stable release is recorded in updates.json; a pre-release, a draft or a failed request changes nothing
function Complete-UpdateCheck($chk, [int]$waitMs = 0) {
    if (-not $chk) { return $null }
    if ($chk.done) { return $chk.info }
    try {
        $left = [int][math]::Max(0, [math]::Min($waitMs, ($chk.until - (Get-Date)).TotalMilliseconds))
        if (-not $chk.task.Wait($left)) { if ((Get-Date) -ge $chk.until) { $chk.client.CancelAsync(); $chk.done = $true }; return $null }
    } catch { $chk.done = $true; return $null }   # offline, refused, rate-limited: nothing to show
    $chk.done = $true
    try {
        $rel = $chk.task.Result | ConvertFrom-Json; $tag = "$($rel.tag_name)"
        if ($rel.draft -or $rel.prerelease -or -not (Get-UpdateVersion $tag)) { return $null }
        $sums = @{}; foreach ($m in [regex]::Matches("$($rel.body)", '(?m)^([0-9a-fA-F]{64})\s+\*?(\S+)\s*$')) { $sums[$m.Groups[2].Value] = $m.Groups[1].Value.ToLower() }
        $assets = @(foreach ($a in @($rel.assets)) {
            if (-not $a.name) { continue }
            $h = if ("$($a.digest)" -match 'sha256:([0-9a-fA-F]{64})') { $Matches[1].ToLower() } elseif ($sums["$($a.name)"]) { $sums["$($a.name)"] } else { "" }
            [ordered]@{ name = "$($a.name)"; size = [int64]$a.size; url = "$($a.browser_download_url)"; sha256 = $h }
        })
        $name = "$($rel.name)"; if (-not $name) { $name = $tag }; $i = $name.IndexOf(': '); if ($i -ge 0) { $name = $name.Substring($i + 2) }
        $page = "$($rel.html_url)"   # opened in the browser: only this project's page on GitHub
        if ($page -notmatch '^https://github\.com/xFractals/pokopia-native/[\w./-]*$') { $page = "https://github.com/xFractals/pokopia-native/releases/tag/$tag" }
        $u = Read-Updates $chk.file
        $u.last_check = [datetime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture)
        $u.latest = $tag; $u.latest_name = $name; $u.latest_url = $page; $u.assets = $assets
        Save-Updates $chk.file $u
        if ($tag -ne "$($u.skipped)" -and (Get-UpdateVersion $tag) -gt (Get-UpdateVersion $chk.version)) {
            $chk.info = @{ tag = $tag; version = "$(Get-UpdateVersion $tag)"; name = $name; url = $page }
        }
    } catch {}
    $chk.info
}
function Set-UpdateAnswer($chk, [string]$answer) {   # "skip" is kept: that version is not shown again, a newer one is
    if ($chk -and $chk.info -and $answer -eq 'skip') { $u = Read-Updates $chk.file; $u.skipped = $chk.info.tag; Save-Updates $chk.file $u }
}
# The notice in a small window of its own (the launcher window shows it as a card instead): What's new opens the release's page, Download opens it and
# closes, Later closes, Skip this version is not shown again. Closing the window is Later
function Show-UpdateNotice($info) {
    $f, $flow = New-LinkPlayForm "Pokopia"
    $flow.Controls.Add((New-Title "Pokopia Native $($info.version) is out" 13 520))
    if ($info.name) { $n = New-Label $info.name 520; $n.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0); $flow.Controls.Add($n) }
    $h = New-Label "Update in the builder: Update my game keeps your save and settings." 520 'muted'; $h.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $flow.Controls.Add($h)
    $row, $btn = New-Buttons $f @('Download', "What's new", 'Later', 'Skip this version'); $row.Width = 540; $flow.Controls.Add($row)
    $res = @{ a = 'later' }; $url = $info.url
    $btn["What's new"].Add_Click({ try { Start-Process $url } catch {} }.GetNewClosure())
    $btn['Download'].Add_Click({ try { Start-Process $url } catch {}; $res.a = 'download'; $f.Close() }.GetNewClosure())
    $btn['Later'].Add_Click({ $f.Close() }.GetNewClosure()); $f.CancelButton = $btn['Later']
    $btn['Skip this version'].Add_Click({ $res.a = 'skip'; $f.Close() }.GetNewClosure())
    $f.Add_Shown({ $f.Activate() }.GetNewClosure())
    [void]$f.ShowDialog()
    $res.a
}
# Before the game starts: the notice, when the check found a release and the launcher window did not show it. Waits for the check's 3 s at most
function Invoke-UpdateNotice($chk) {
    $info = Complete-UpdateCheck $chk 3000
    if (-not $info -or $chk.shown) { return }
    $chk.shown = $true
    $line = "Pokopia Native $($info.version) is out$(if ($info.name) { ": $($info.name)" }). Update in the builder: Update my game keeps your save and settings. $($info.url)"
    $ans = "$env:POKOPIA_UPDATE_ANSWER"
    if ($ans) { Write-Host $line }   # a test's answer; -Silent mutes the sound only, so a muted player still sees the notice
    else { try { $ans = Show-UpdateNotice $info } catch { Write-Host $line; $ans = 'later' } }
    Set-UpdateAnswer $chk $ans
}

# How to play this time: alone, on this network, hosting or visiting over the internet; the keyboard's controls; the picture. $pref holds the last choice,
# $keys the keyboard map, $padc the controllers' (Read-Pad), $disp the display settings; the new choice with the map in .controls, the controllers' in .pad and
# the settings in .display, or $null (Cancel)
function Show-LinkPlay($pref, [string]$title, $keys, $disp, $padc, $chk, [bool]$updOn) {
    $f, $outer = New-LinkPlayForm $title
    $addrRx = $ipPort; $codeRx = $roomRx; $labels = $ControlsLabel; $def = $ControlsDefault; $ddef = $DisplayDefault; $dcnt = $DisplayCounters; $daa = $DisplayAA  # copied here: the event handlers' closures see this function's variables, not the script's
    $pdef = $PadDefault; $pin = $PadInputs; if (-not $padc) { $padc = @{ pad = $null; player1 = ""; player1_name = "" } }
    $ui = $Ui; $white = [System.Drawing.Color]::White
    $outer.Controls.Add((New-Title "Pokopia"))
    $outer.Controls.Add((New-Label "How you play, your controls and the picture, kept for this PC.$(if ($script:installed) { " Pokopia Native $script:installed." })" 600 'muted'))
    # The update notice: a card over the tabs once the check finds a release (filled in by the timer below)
    $note = New-Card 14; $note.BackColor = $ui.soft; $note.Border = $ui.soft; $note.Visible = $false
    $nTitle = New-Title "" 11; $nName = New-Label "" 600; $nName.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $nHelp = New-Label "Update in the builder: Update my game keeps your save and settings." 600 'muted'; $nHelp.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
    $nRow = New-Object System.Windows.Forms.FlowLayoutPanel; $nRow.AutoSize = $true; $nRow.WrapContents = $false; $nRow.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
    $nDl = New-Pill 'Download' -Primary; $nNew = New-Pill "What's new"; $nLater = New-Pill 'Later'; $nSkip = New-Pill 'Skip this version'
    foreach ($b in $nDl, $nNew, $nLater, $nSkip) { $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0); $nRow.Controls.Add($b) }
    foreach ($b in $nNew, $nLater, $nSkip) { $b.Fill = $white; $b.FillHover = $ui.tint }
    foreach ($c in $nTitle, $nName, $nHelp, $nRow) { $note.Controls.Add($c) }
    if ($chk) {
        $nNew.Add_Click({ try { Start-Process $chk.info.url } catch {} }.GetNewClosure())
        $nDl.Add_Click({ try { Start-Process $chk.info.url } catch {}; $chk.answer = 'download'; $note.Visible = $false }.GetNewClosure())
        $nLater.Add_Click({ $chk.answer = 'later'; $note.Visible = $false }.GetNewClosure())
        $nSkip.Add_Click({ $chk.answer = 'skip'; $note.Visible = $false }.GetNewClosure())
    }
    # The tabs: pills over one card that holds the page shown (the current one in the fade's colour, as the builder's current step)
    $strip = New-Object System.Windows.Forms.FlowLayoutPanel; $strip.AutoSize = $true; $strip.WrapContents = $false; $strip.Margin = New-Object System.Windows.Forms.Padding(0, 14, 0, 0)
    $page = New-Card 18
    $pages = @{}; $tabBtn = [ordered]@{}
    foreach ($n in 'Link Play', 'Controls', 'Display') {
        $fl = New-Object System.Windows.Forms.FlowLayoutPanel; $fl.FlowDirection = 'TopDown'; $fl.WrapContents = $false; $fl.AutoSize = $true
        $fl.Margin = New-Object System.Windows.Forms.Padding(0); $page.Controls.Add($fl); $pages[$n] = $fl
        $tb = New-Pill $n; $tb.AccessibleRole = 'PageTab'; $tb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0); $strip.Controls.Add($tb); $tabBtn[$n] = $tb
    }
    $tabSel = @{ cur = 'Link Play' }
    $showTab = {
        param($n) $tabSel.cur = $n
        foreach ($k in $tabBtn.Keys) {
            $pages[$k].Visible = $k -eq $n; $t = $tabBtn[$k]
            if ($k -eq $n) { $t.Fill = $ui.primary; $t.FillHover = $ui.primaryHover; $t.ForeColor = $white } else { $t.Fill = $ui.tint; $t.FillHover = $ui.tintHover; $t.ForeColor = $ui.ink }
            $t.Invalidate()
        }
    }.GetNewClosure()
    foreach ($n in @($tabBtn.Keys)) { $tn = $n; $tabBtn[$n].Add_Click({ & $showTab $tn }.GetNewClosure()) }
    $step = { param($d) $ks = @($tabBtn.Keys); & $showTab $ks[([array]::IndexOf($ks, $tabSel.cur) + $d + $ks.Count) % $ks.Count] }.GetNewClosure()
    $f.Add_NextTab({ & $step 1 }.GetNewClosure()); $f.Add_PrevTab({ & $step -1 }.GetNewClosure())   # Ctrl+Tab, Ctrl+Shift+Tab
    $flow = $pages['Link Play']
    if ($script:noSave) {   # easy to miss: without Import save the game quietly starts a new one
        $ns = New-Label "No save here yet, so the game starts a new one. To play your save from the iPhone, a Mac or another PC, press Cancel and use Import save... in the builder first." 470 'problem'
        $ns.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10); $flow.Controls.Add($ns)
    }
    $flow.Controls.Add((New-Title "How do you want to play?" 10.5))
    $modes = [ordered]@{ alone = "Play alone"; lan = "Link Play with players on this network (the same Wi-Fi)";
                        host = "Host over the internet or a VPN (without a VPN, your router forwards port 47600 to this PC)"; visit = "Visit a host over the internet or a VPN";
                        split = "Split screen: two players on this PC (the second plays a second controller)" }
    $radio = @{}
    $keep = New-Object System.Windows.Forms.CheckBox; $keep.AutoSize = $true; $keep.Margin = New-Object System.Windows.Forms.Padding(34, 2, 0, 0)
    $keep.Text = "Keep my room code from last time ($($pref.host_room))"; $keep.Checked = [bool]$pref.keep_room; $keep.Visible = [bool]$pref.host_room
    foreach ($k in $modes.Keys) {
        $r = New-Object System.Windows.Forms.RadioButton; $r.Text = $modes[$k]; $r.AutoSize = $true; $r.Checked = ($pref.mode -eq $k)
        $r.Margin = New-Object System.Windows.Forms.Padding(12, 4, 0, 0); $flow.Controls.Add($r); $radio[$k] = $r
        if ($k -eq 'host') { $flow.Controls.Add($keep) }   # under its own choice
    }
    if (-not ($radio.Values | Where-Object Checked)) { $radio['alone'].Checked = $true }
    # Under the choices, in one grid so the fields line up: split screen's layout (right under its choice), then visiting's address and code
    $grid = New-Object System.Windows.Forms.TableLayoutPanel; $grid.ColumnCount = 2; $grid.AutoSize = $true; $grid.Margin = New-Object System.Windows.Forms.Padding(30, 4, 0, 0)
    $layC = New-Object System.Windows.Forms.ComboBox; $layC.DropDownStyle = 'DropDownList'; $layC.Width = 230
    [void]$layC.Items.AddRange([object[]]@("Stacked (top and bottom)", "Side by side")); $layC.SelectedIndex = $(if ($pref.split_layout -eq 'side') { 1 } else { 0 })
    $addr = New-Object System.Windows.Forms.TextBox; $addr.Width = 230; $addr.Text = $pref.join
    $code = New-Object System.Windows.Forms.TextBox; $code.Width = 230; $code.Text = $pref.room; $code.CharacterCasing = 'Upper'
    $layL = New-Label "Layout:" 160; $addrL = New-Label "Host's address:" 160; $codeL = New-Label "Room code:" 160
    $grid.Controls.Add($layL, 0, 0); $grid.Controls.Add($layC, 1, 0)
    $grid.Controls.Add($addrL, 0, 1); $grid.Controls.Add($addr, 1, 1)
    $grid.Controls.Add($codeL, 0, 2); $grid.Controls.Add($code, 1, 2)
    $flow.Controls.Add($grid)
    $ie = New-Object System.Windows.Forms.CheckBox; $ie.AutoSize = $true; $ie.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 0)
    $ie.Text = "Interact everywhere (experimental)"; $ie.Checked = [bool]$pref.interact; $flow.Controls.Add($ie)
    $ieNote = New-Label "Visitors can use moves and items and build in every town, not only Palette Town. Every player needs it on." 450 'muted'
    $ieNote.Margin = New-Object System.Windows.Forms.Padding(20, 0, 0, 0); $flow.Controls.Add($ieNote)
    $sc = New-Object System.Windows.Forms.CheckBox; $sc.AutoSize = $true; $sc.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $sc.Text = "Story co-op (experimental)"; $sc.Checked = [bool]$pref.story; $flow.Controls.Add($sc)
    $scNote = New-Label "With Interact everywhere: visitors can talk to the town's story characters. Story requests still count only for the host. Every player needs it on." 450 'muted'
    $scNote.Margin = New-Object System.Windows.Forms.Padding(20, 0, 0, 0); $flow.Controls.Add($scNote)
    $coop = $script:coopOk
    if (-not $coop) {   # another game version: both stay off (the game would log it, nobody reads that)
        $ie.Checked = $false; $sc.Checked = $false
        $cn = New-Label "Interact everywhere and Story co-op need $script:coopNeeds. This game is another version ($script:coopGame), so they stay off." 450 'problem'
        $cn.Margin = New-Object System.Windows.Forms.Padding(20, 6, 0, 0); $flow.Controls.Add($cn)
    }
    $sc.Add_CheckedChanged({ if ($sc.Checked) { $ie.Checked = $true } }.GetNewClosure())   # Story co-op needs Interact everywhere
    $ie.Add_CheckedChanged({ if (-not $ie.Checked) { $sc.Checked = $false } }.GetNewClosure())
    $hint = New-Label "In the game: Link Play, then Local connection (not Online connection). Every player needs their own save and the same pokopia-native version." 470 'muted'
    $hint.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 0); $flow.Controls.Add($hint)
    # Controls: an action's button shows its key; click it, then press the new key. A key another action had moves over, and that action gets this one's old key
    $cf = $pages['Controls']
    $pick = New-Object System.Windows.Forms.FlowLayoutPanel; $pick.AutoSize = $true; $pick.WrapContents = $false; $pick.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $rkb = New-Object System.Windows.Forms.RadioButton; $rkb.Text = "Keyboard keys"; $rkb.AutoSize = $true; $rkb.Checked = $true
    $rpad = New-Object System.Windows.Forms.RadioButton; $rpad.Text = "Controller buttons"; $rpad.AutoSize = $true; $rpad.Margin = New-Object System.Windows.Forms.Padding(16, 3, 3, 3)
    $pick.Controls.Add($rkb); $pick.Controls.Add($rpad); $cf.Controls.Add($pick)
    $kbIntro = New-Label "Click an action, then press its key (Esc cancels). Keys count by their place on the keyboard."; $cf.Controls.Add($kbIntro)
    $st = @{ map = [ordered]@{}; act = $null; done = [datetime]::MinValue }
    foreach ($k in $keys.Keys) { $st.map[$k] = $keys[$k] }
    $tbl = Get-KeyTable; $names = @{}; foreach ($v in $tbl.Values) { $names[[int]$v[0]] = $v[1] }
    $cgrid = New-Object System.Windows.Forms.TableLayoutPanel; $cgrid.ColumnCount = 4; $cgrid.AutoSize = $true; $cgrid.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $kb = [ordered]@{}; $i = 0
    foreach ($a in $labels.Keys) {
        $b = New-Pill ""; $b.AutoSize = $false; $b.MinimumSize = New-Object System.Drawing.Size(0, 0); $b.Size = New-Object System.Drawing.Size(116, 30)
        $b.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0); $b.Margin = New-Object System.Windows.Forms.Padding(2, 2, 14, 2)
        $l = New-Label $labels[$a] 120; $l.Margin = New-Object System.Windows.Forms.Padding(0, 8, 4, 0)
        $cgrid.Controls.Add($l, ($i % 2) * 2, [math]::Floor($i / 2)); $cgrid.Controls.Add($b, ($i % 2) * 2 + 1, [math]::Floor($i / 2))
        $kb[$a] = $b; $i++
    }
    $cf.Controls.Add($cgrid)
    $status = New-Label " `n " 470 'muted'; $status.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $reset = New-Pill "Reset to defaults"; $reset.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
    $cf.Controls.Add($reset)
    # Controller buttons: one map for every controller (controls.json "pad"), face buttons by their place; an input another button had moves over, as the keys
    # do. Player 1 is chosen in the game (F1, Controls), where the controllers can be seen; here it can be forgotten
    $pst = @{ map = [ordered]@{}; custom = $null -ne $padc.pad; p1 = "$($padc.player1)"; p1n = "$($padc.player1_name)"; busy = $false }
    foreach ($k in $pdef.Keys) { $pst.map[$k] = if ($padc.pad) { $padc.pad[$k] } else { $pdef[$k] } }
    $padIntro = New-Label "Choose the controller button for each Switch button; one map for every controller. Face buttons go by their place: the bottom one is A on an Xbox pad and B on a Switch pad."
    $pgrid = New-Object System.Windows.Forms.TableLayoutPanel; $pgrid.ColumnCount = 4; $pgrid.AutoSize = $true; $pgrid.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $pc = [ordered]@{}; $i = 0; $inKeys = @($pin.Keys); $inNames = @($pin.Values)
    foreach ($a in $pdef.Keys) {
        $c = New-Object System.Windows.Forms.ComboBox; $c.DropDownStyle = 'DropDownList'; $c.Width = 150; [void]$c.Items.AddRange([object[]]$inNames); $c.Margin = New-Object System.Windows.Forms.Padding(2, 2, 14, 2)
        $l = New-Label $labels[$a] 120; $l.Margin = New-Object System.Windows.Forms.Padding(0, 6, 4, 0)
        $pgrid.Controls.Add($l, ($i % 2) * 2, [math]::Floor($i / 2)); $pgrid.Controls.Add($c, ($i % 2) * 2 + 1, [math]::Floor($i / 2))
        $pc[$a] = $c; $i++
    }
    $preset = New-Pill "Reset to defaults"; $preset.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
    $p1row = New-Object System.Windows.Forms.FlowLayoutPanel; $p1row.AutoSize = $true; $p1row.WrapContents = $false; $p1row.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $p1 = New-Label ""; $p1.Margin = New-Object System.Windows.Forms.Padding(0, 6, 8, 0)
    $p1forget = New-Pill "Forget"
    $p1row.Controls.Add($p1); $p1row.Controls.Add($p1forget)
    $pshow = {
        $pst.busy = $true; foreach ($a in $pc.Keys) { $pc[$a].SelectedIndex = [array]::IndexOf($inKeys, [string]$pst.map[$a]) }; $pst.busy = $false
        $p1.Text = if ($pst.p1) { "Player 1: $(if ($pst.p1n) { $pst.p1n } else { 'a controller' }), whenever it is connected (the game's F1 menu, Controls, chooses another)." }
                   else { "Player 1: the first controller connected. To choose one, open the game's menu (F1), Controls, Controller." }
        $p1forget.Visible = [bool]$pst.p1
    }.GetNewClosure()
    foreach ($a in @($pc.Keys)) {
        $act = $a
        $pc[$a].Add_SelectedIndexChanged({
            if ($pst.busy -or $pc[$act].SelectedIndex -lt 0) { return }
            $new = $inKeys[$pc[$act].SelectedIndex]; $old = $pst.map[$act]; if ($new -eq $old) { return }
            $msg = "$($labels[$act]): $($pin[$new])."
            if ($new -ne 'none') { foreach ($o in @($pst.map.Keys)) { if ($o -ne $act -and $pst.map[$o] -eq $new) { $pst.map[$o] = $old; $msg = "$($labels[$act]): $($pin[$new]), which $($labels[$o]) had; $($labels[$o]) takes the old button." } } }
            $pst.map[$act] = $new; $pst.custom = $true; & $pshow; $status.Text = $msg
        }.GetNewClosure())
    }
    $preset.Add_Click({ foreach ($k in $pdef.Keys) { $pst.map[$k] = $pdef[$k] }; $pst.custom = $false; & $pshow; $status.Text = "Back to the game's own controller layout." }.GetNewClosure())
    $p1forget.Add_Click({ $pst.p1 = ""; $pst.p1n = ""; & $pshow; $status.Text = "Player 1 is the first controller connected again." }.GetNewClosure())
    $cf.Controls.Add($padIntro); $cf.Controls.Add($pgrid); $cf.Controls.Add($preset); $cf.Controls.Add($p1row)
    $cf.Controls.Add($status)
    $ctlPage = { $k = $rkb.Checked; foreach ($c in @($kbIntro, $cgrid, $reset)) { $c.Visible = $k }; foreach ($c in @($padIntro, $pgrid, $preset, $p1row)) { $c.Visible = -not $k }; $status.Text = " `n " }.GetNewClosure()
    $rkb.Add_CheckedChanged($ctlPage); & $pshow; & $ctlPage
    $show = { foreach ($a in $kb.Keys) { $v = [int]$st.map[$a]; $kb[$a].Text = if ($names[$v]) { $names[$v] } else { "(none)" } } }.GetNewClosure()
    & $show
    foreach ($a in @($kb.Keys)) {
        $act = $a
        $kb[$a].Add_Click({
            if (((Get-Date) - $st.done).TotalMilliseconds -lt 400) { return }   # the key that ended a capture can click the button it landed on
            & $show; $st.act = $act; $kb[$act].Text = "Press a key..."; $status.Text = "Press the key for $($labels[$act]) (Esc cancels)."
        }.GetNewClosure())
        $kb[$a].Add_PreviewKeyDown({ if ($st.act) { $_.IsInputKey = $true } }.GetNewClosure())   # Tab, Enter and the arrows reach KeyDown instead of moving the focus
    }
    $f.KeyPreview = $true
    $f.Add_KeyDown({
        if (-not $st.act) { return }
        $_.Handled = $true; $_.SuppressKeyPress = $true
        $act = $st.act; $st.act = $null; $st.done = Get-Date
        $vk = [int]$_.KeyCode
        if ($vk -eq 27) { & $show; $status.Text = "Cancelled."; return }
        if ($vk -eq 16) { $vk = if ([PokopiaKeys]::Down(0xA1)) { 0xA1 } else { 0xA0 } } elseif ($vk -eq 17) { $vk = if ([PokopiaKeys]::Down(0xA3)) { 0xA3 } else { 0xA2 } }
        $hit = if ($vk -in 18, 91, 92, 122) { $null } else { $tbl[[int][PokopiaKeys]::Scan($vk)] }
        if (-not $hit) { & $show; $status.Text = "That key can't be used: Esc, F11, Alt and the Windows keys belong to the game's window and to Windows."; return }
        $sdl = [int]$hit[0]; $old = $st.map[$act]; $msg = "$($labels[$act]): $($hit[1])."
        foreach ($o in @($st.map.Keys)) { if ($o -ne $act -and [int]$st.map[$o] -eq $sdl) { $st.map[$o] = $old; $msg = "$($labels[$act]): $($hit[1]), which $($labels[$o]) had; $($labels[$o]) takes the old key." } }
        $st.map[$act] = $sdl; & $show; $status.Text = $msg
    }.GetNewClosure())
    $reset.Add_Click({ foreach ($k in $def.Keys) { $st.map[$k] = $def[$k] }; $st.act = $null; & $show; $status.Text = "Back to the default keys." }.GetNewClosure())
    # Display: the console mode the game draws for, the window, the upscaling to a window larger than the picture, the frame rate and vsync
    $df = $pages['Display']
    $dg = New-Object System.Windows.Forms.TableLayoutPanel; $dg.ColumnCount = 2; $dg.AutoSize = $true
    $addRow = { param($text, $ctl) $l = New-Label $text 150; $l.Margin = New-Object System.Windows.Forms.Padding(0, 7, 6, 0); $dg.Controls.Add($l, 0, $script:drow); $dg.Controls.Add($ctl, 1, $script:drow); $script:drow++ }
    $script:drow = 0
    $combo = { param($items, $sel) $c = New-Object System.Windows.Forms.ComboBox; $c.DropDownStyle = 'DropDownList'; $c.Width = 280; foreach ($i in $items) { [void]$c.Items.Add($i) }; $c.SelectedIndex = [math]::Max(0, [array]::IndexOf($items, $sel)); $c }
    $consoleItems = @("Docked (TV)", "Handheld")
    $cm = & $combo $consoleItems $consoleItems[$(if ([int]$disp.console -eq 0) { 1 } else { 0 })]; & $addRow "Console mode:" $cm
    # Resolution: the size the game draws its picture at, as the in-game menu lists it (front/menu.c res_list_h, res_text): Default (the monitor's height,
    # from the game's own up to 2160, or 1440 on a 4 GB card), then 1280x720 (a Steam Deck's screen), 1600x900, the game's own 1920x1080 and larger. A
    # saved size not in the list stays as it is; one below 720 draws 1280x720. The game's own is 1920x1080 in both console modes (front/menu.c base_h)
    $rst = @{ mon = $(try { [PokopiaKeys]::ScreenHeight() } catch { 0 }); monw = $(try { [PokopiaKeys]::ScreenWidth() } catch { 0 }); vals = @(); orig = [string]$disp.resolution
              top = $(try { Get-DefaultTop } catch { 2160 }) }
    $rs = New-Object System.Windows.Forms.ComboBox; $rs.DropDownStyle = 'DropDownList'; $rs.Width = 280
    $resFill = {
        param([string]$want)
        $base = 1080
        $mh = if ($rst.mon -gt 0) { [math]::Min($rst.top, [math]::Max($base, $rst.mon)) } else { $base }
        $vals = @("default"); $labs = @("Default: your monitor ($([int]($mh * 16 / 9))x$mh)")
        foreach ($h in 720, 900, 1080, 1440, 2160) {
            $vals += "$([int]($h * 16 / 9))x$h"; $labs += "$([int]($h * 16 / 9))x$h$(if ($h -eq $base) { " (the game's own)" } elseif ($h -eq 720) { " (a Steam Deck's screen)" })"
        }
        $i = [array]::IndexOf($vals, $want)
        if ($i -lt 0 -and $want -match '^\d+x(\d+)$') { if ([int]$Matches[1] -le 720) { $i = 1 } else { $vals += $want; $labs += $want; $i = $vals.Count - 1 } }
        $rst.vals = $vals; $rs.Items.Clear(); foreach ($l in $labs) { [void]$rs.Items.Add($l) }; $rs.SelectedIndex = [math]::Max(0, $i)
    }.GetNewClosure()
    & $resFill $rst.orig; $rst.origIdx = $rs.SelectedIndex; $rst.cmIdx = $cm.SelectedIndex
    & $addRow "Resolution:" $rs
    $dmItems = @("Window", "Full screen")
    $dm = & $combo $dmItems $dmItems[$(if ($disp.fullscreen) { 1 } else { 0 })]; & $addRow "Display mode:" $dm
    $ws = & $combo $DisplaySizes ([string]$disp.window); & $addRow "Window size:" $ws
    $upItems = @("Sharp", "Standard (softer)")
    $up = & $combo $upItems $upItems[$(if ($disp.upscale -eq 'standard') { 1 } else { 0 })]
    $upNote = New-Label "" 260 'muted'; $upNote.Margin = New-Object System.Windows.Forms.Padding(6, 7, 0, 0)
    $upBox = New-Object System.Windows.Forms.FlowLayoutPanel; $upBox.AutoSize = $true; $upBox.WrapContents = $false; $upBox.Margin = New-Object System.Windows.Forms.Padding(0)
    $upBox.Controls.Add($up); $upBox.Controls.Add($upNote); & $addRow "Upscaling:" $upBox
    $sh = New-Object System.Windows.Forms.TrackBar; $sh.Minimum = 0; $sh.Maximum = 10; $sh.TickFrequency = 1; $sh.Width = 280; $sh.Value = [math]::Min(10, [math]::Max(0, [int]$disp.sharpness)); & $addRow "Sharpness:" $sh
    $aaItems = @("Off", "FXAA", "SMAA")   # smooths the 3D picture's jagged edges; the HUD and text stay sharp (vk_aa.c)
    $aa = & $combo $aaItems $aaItems[[math]::Max(0, [array]::IndexOf($daa, [string]$disp.antialiasing))]; & $addRow "Anti-aliasing:" $aa
    $fpsItems = @("60 fps", "50 fps", "45 fps", "40 fps", "30 fps")   # 40 is smooth on 120 Hz screens, 45 and 50 with G-Sync / FreeSync (docs/frame-rate-30.md)
    $fp = & $combo $fpsItems $fpsItems[[math]::Max(0, [array]::IndexOf($fpsItems, "$([int]$disp.fps) fps"))]; & $addRow "Frame rate:" $fp
    $vs = New-Object System.Windows.Forms.CheckBox; $vs.Text = "On (off: less delay, may tear)"; $vs.AutoSize = $true; $vs.Checked = [bool]$disp.vsync; $vs.Margin = New-Object System.Windows.Forms.Padding(3, 6, 0, 0); & $addRow "Vsync:" $vs
    $cnItems = @("Off", "Corner", "Detailed")
    $cn = & $combo $cnItems $cnItems[[math]::Max(0, [array]::IndexOf($dcnt, [string]$disp.fps_counter))]; & $addRow "FPS counter:" $cn
    $wv = New-Object System.Windows.Forms.CheckBox; $wv.Text = "On (experimental: fills a screen wider than 16:9)"; $wv.AutoSize = $true; $wv.Checked = [bool]$disp.wide_view; $wv.Margin = New-Object System.Windows.Forms.Padding(3, 6, 0, 0); & $addRow "Wide view:" $wv
    $df.Controls.Add($dg)
    $fitNote = New-Label ""; $fitNote.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0); $df.Controls.Add($fitNote)
    $dnote = New-Label ("Resolution is the size the game draws its picture at: bigger looks sharper but works your graphics card harder; Default matches your monitor. " +
                        "Console mode: docked is the game's TV mode, handheld its portable mode; both draw 1920x1080 here, and Resolution keeps its size. " +
                        "In the game, F1 opens these settings too.")
    $dnote.ForeColor = $ui.muted; $dnote.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0); $df.Controls.Add($dnote)
    $dreset = New-Pill "Reset to defaults"; $dreset.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0); $df.Controls.Add($dreset)
    # The picture against the window, as the in-game menu says it: larger (the extra detail is not seen), stretched (upscaling and sharpness matter), the same
    $dsync = {
        $ws.Enabled = $dm.SelectedIndex -eq 0
        $base = 1080
        $mh = if ($rst.mon -gt 0) { $rst.mon } else { 1080 }; $mw = if ($rst.monw -gt 0) { $rst.monw } else { [int]($mh * 16 / 9) }
        $v = [string]$rst.vals[[math]::Max(0, $rs.SelectedIndex)]
        $ph = if ($v -match 'x(\d+)$') { [int]$Matches[1] } else { [math]::Min($rst.top, [math]::Max($base, $mh)) }; $ph = [math]::Min(2160, [math]::Max(720, $ph))
        if ($dm.SelectedIndex -eq 0 -and [string]$ws.SelectedItem -match '^(\d+)x(\d+)$') { $wwid = [int]$Matches[1]; $whgt = [int]$Matches[2] } else { $wwid = $mw; $whgt = $mh }
        $k = [math]::Min($wwid / ($ph * 16 / 9), $whgt / $ph)
        $fitNote.Text = if ($k -lt 0.99) { "Your window (${wwid}x$whgt) is smaller than the picture, so you won't see the extra detail. Make the window bigger or use full screen." }
                        elseif ($k -gt 1.01) { "The picture is stretched to fill your window. Upscaling and Sharpness choose how that looks." } else { "" }
        $up.Enabled = $k -gt 1.01; $sh.Enabled = $k -gt 1.01 -and $up.SelectedIndex -eq 0
        $upNote.Text = if ($k -gt 1.01) { "" } else { "Not used: the picture isn't stretched" }
    }.GetNewClosure()
    $dm.Add_SelectedIndexChanged($dsync); $up.Add_SelectedIndexChanged($dsync); $rs.Add_SelectedIndexChanged($dsync); $ws.Add_SelectedIndexChanged($dsync)
    $cm.Add_SelectedIndexChanged({ & $resFill ([string]$rst.vals[[math]::Max(0, $rs.SelectedIndex)]); & $dsync }.GetNewClosure())
    & $dsync
    $dreset.Add_Click({
        $cm.SelectedIndex = 0; & $resFill "default"; $dm.SelectedIndex = 0; $ws.SelectedIndex = [math]::Max(0, $ws.Items.IndexOf($ddef.window)); $up.SelectedIndex = 0
        $sh.Value = $ddef.sharpness; $fp.SelectedIndex = 0; $vs.Checked = $ddef.vsync; $cn.SelectedIndex = 0; $wv.Checked = $ddef.wide_view; $aa.SelectedIndex = [array]::IndexOf($daa, $ddef.antialiasing); & $dsync
    }.GetNewClosure())
    foreach ($c in $note, $strip, $page) { $outer.Controls.Add($c) }   # first: the pages measure their wrapped labels in the window's font
    $sz = @(foreach ($k in $true, $false) {   # the card fits the largest page; the Controls page both ways (keys, controller buttons)
        foreach ($c in @($kbIntro, $cgrid, $reset)) { $c.Visible = $k }; foreach ($c in @($padIntro, $pgrid, $preset, $p1row)) { $c.Visible = -not $k }; $cf.PreferredSize })
    & $ctlPage
    $sz += $pages['Link Play'].PreferredSize, $pages['Display'].PreferredSize
    $w = ($sz | ForEach-Object Width | Measure-Object -Maximum).Maximum; $h = ($sz | ForEach-Object Height | Measure-Object -Maximum).Maximum
    $page.AutoSize = $false; $page.Size = New-Object System.Drawing.Size(($w + $page.Padding.Horizontal), ($h + $page.Padding.Vertical)); $w = $page.Width
    $note.MinimumSize = New-Object System.Drawing.Size($w, 0); $note.MaximumSize = New-Object System.Drawing.Size($w, 0)
    foreach ($l in $nTitle, $nName, $nHelp) { $l.MaximumSize = New-Object System.Drawing.Size(($w - 28), 0) }
    & $showTab 'Link Play'
    $again = New-Object System.Windows.Forms.CheckBox; $again.AutoSize = $true; $again.Margin = New-Object System.Windows.Forms.Padding(2, 14, 0, 0)
    $again.Text = "Don't ask again (Pokopia Settings, or Shift held while starting, shows this window)"; $again.Checked = -not $pref.ask
    $outer.Controls.Add($again)
    $updBox = New-Object System.Windows.Forms.CheckBox; $updBox.AutoSize = $true; $updBox.Margin = New-Object System.Windows.Forms.Padding(2, 4, 0, 0)
    $updBox.Text = $UpdateAsk; $updBox.Checked = $updOn; $updBox.Visible = [bool]$script:installed; $outer.Controls.Add($updBox)
    if ($chk) {   # the check runs on: its answer shows in the card when it comes (3 s at most)
        $done = ${function:Complete-UpdateCheck}
        $tm = New-Object System.Windows.Forms.Timer; $tm.Interval = 150
        $tm.Add_Tick({
            $info = & $done $chk 0
            if ($info -and $updBox.Checked) {
                $tm.Stop(); $chk.shown = $true
                $nTitle.Text = "Pokopia Native $($info.version) is out"; $nName.Text = "$($info.name)"; $nName.Visible = [bool]$info.name; $note.Visible = $true
            } elseif ($chk.done) { $tm.Stop() }
        }.GetNewClosure())
        $f.Add_Shown({ $tm.Start() }.GetNewClosure()); $f.Add_FormClosed({ $tm.Stop() }.GetNewClosure())
    }
    $row, $btn = New-Buttons $f @('Play', 'Cancel'); $row.Width = $w; $outer.Controls.Add($row)
    $sync = { foreach ($c in $addrL, $addr, $codeL, $code) { $c.Enabled = $radio['visit'].Checked }; $layL.Enabled = $layC.Enabled = $radio['split'].Checked; $keep.Enabled = $radio['host'].Checked; $ie.Enabled = $coop -and -not $radio['alone'].Checked; $sc.Enabled = $ie.Enabled }.GetNewClosure()
    foreach ($r in $radio.Values) { $r.Add_CheckedChanged($sync) }
    & $sync
    $btn['Play'].Add_Click({
        if ($radio['visit'].Checked) {
            $a = $addr.Text.Trim(); $c = ($code.Text -replace '[-\s]', '')
            if ($a -notmatch $addrRx) { [void][System.Windows.Forms.MessageBox]::Show($f, "Type the host's internet address, for example 203.0.113.7.", $title); return }
            if ($c -notmatch $codeRx) { [void][System.Windows.Forms.MessageBox]::Show($f, "Type the host's room code: 16 letters and digits, XXXX-XXXX-XXXX-XXXX.", $title); return }
        }
        $f.DialogResult = 'OK'; $f.Close()
    }.GetNewClosure())
    $f.Add_Shown({ $f.Activate() }.GetNewClosure())
    if ($f.ShowDialog() -ne 'OK') { return $null }
    $mode = ($radio.Keys | Where-Object { $radio[$_].Checked } | Select-Object -First 1)
    $new = @{} + $pref
    $new.mode = $mode; $new.ask = -not $again.Checked; $new.keep_room = $keep.Checked; $new.interact = $ie.Checked; $new.story = $sc.Checked
    $new.split_layout = $(if ($layC.SelectedIndex -eq 1) { "side" } else { "stack" })
    if (-not $coop) { $new.interact = $pref.interact; $new.story = $pref.story }   # kept for a game version that has them
    if ($mode -eq 'visit') { $new.join = $addr.Text.Trim(); $new.room = $code.Text.Trim().ToUpper() }
    $new.controls = $st.map
    $new.updates = $updBox.Checked
    $new.pad = @{ map = $pst.map; custom = $pst.custom; p1 = $pst.p1; p1n = $pst.p1n }
    $new.display = [ordered]@{ console = $(if ($cm.SelectedIndex -eq 1) { 0 } else { 1 })
                               resolution = $(if ($rs.SelectedIndex -eq $rst.origIdx -and $cm.SelectedIndex -eq $rst.cmIdx) { $rst.orig } else { [string]$rst.vals[$rs.SelectedIndex] })   # untouched: as saved
                               fullscreen = ($dm.SelectedIndex -eq 1); window = [string]$ws.SelectedItem
                               upscale = $(if ($up.SelectedIndex -eq 1) { "standard" } else { "sharp" }); sharpness = $sh.Value; fps = [int]($fpsItems[$fp.SelectedIndex] -replace " fps", ""); vsync = $vs.Checked
                               fps_counter = $dcnt[$cn.SelectedIndex]; wide_view = $wv.Checked; antialiasing = $daa[$aa.SelectedIndex] }
    return $new
}
# A host's room code, big, with a Copy button: the players who visit need it (and this PC's internet address)
function Show-RoomCode([string]$code, [string]$title, [string]$relay) {
    $f, $outer = New-LinkPlayForm $title
    $outer.Controls.Add((New-Title "Your room code" 15 470))
    $flow = New-Card 18; $outer.Controls.Add($flow)
    $flow.Controls.Add((New-Label "Your room code for this session. Give it to the players who visit:" 440))
    $box = New-Object System.Windows.Forms.TextBox; $box.ReadOnly = $true; $box.Text = $code; $box.TextAlign = 'Center'; $box.Width = 440
    $box.BorderStyle = 'None'; $box.BackColor = $Ui.tint; $box.ForeColor = $Ui.ink
    $box.Font = New-Object System.Drawing.Font('Consolas', 22, [System.Drawing.FontStyle]::Bold); $box.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 10)
    $flow.Controls.Add($box)
    if ($relay) { $flow.Controls.Add((New-Label "They also need the relay's address ($relay). In the game: Link Play, then Local connection, then host." 440 'muted')) }
    else {
        $flow.Controls.Add((New-Label ("They also need this PC's internet address (search ""what is my IP"" on this network), and your router must forward port " +
                                       "47600, TCP and UDP, to this PC. In the game: Link Play, then Local connection, then host.") 440 'muted'))
    }
    $flow = $outer
    $row, $btn = New-Buttons $f @('Start the game', 'Copy'); $row.Width = 478
    $btn['Copy'].Add_Click({
        try { [System.Windows.Forms.Clipboard]::SetText($code); $btn['Copy'].Text = 'Copied' } catch { $btn['Copy'].Text = 'Copy failed: select it' }
    }.GetNewClosure())
    $btn['Start the game'].DialogResult = 'OK'
    $flow.Controls.Add($row)
    $f.Add_Shown({ $f.Activate(); $box.SelectAll() }.GetNewClosure())
    [void]$f.ShowDialog()
}

$windowed = $false   # the Link Play window chose this session's way: the room code goes in a window too
$settingsDir = if ($env:POKOPIA_SETTINGS_DIR) { $env:POKOPIA_SETTINGS_DIR } else { Join-Path ([Environment]::GetFolderPath('ApplicationData')) "Pokopia Native" }   # POKOPIA_SETTINGS_DIR: another folder (tests)
$keysFile = Join-Path $settingsDir "controls.json"; $dispFile = Join-Path $settingsDir "display.json"
$env:NXRT_SETTINGS_DIR = $settingsDir   # the in-game menu (F1) saves its changes there too
$disp = Read-Display $dispFile
# The update check starts now and runs beside the rest (an installer build's launcher; not split screen's two games, nor a dry run unless a test asks)
$updFile = Join-Path $(if ($env:POKOPIA_SETTINGS_DIR) { $env:POKOPIA_SETTINGS_DIR } else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) "Pokopia Native" }) "updates.json"
$updChk = if ($installed -and -not $env:DM_SPLIT -and (-not $DryRun -or $env:POKOPIA_UPDATE_URL)) { Start-UpdateCheck $updFile $installed }
if (($Config -or $Ask) -and -not ($LinkPlay -or $Join -or $Internet -or $Room -or $Relay -or $CoopHost -or $CoopJoin -or $env:DM_COOP)) {   # a dry run reads the remembered way, no window
    $prefFile = Join-Path $settingsDir "linkplay.json"
    $pref = @{ mode = "alone"; join = ""; room = ""; host_room = ""; keep_room = $false; ask = $true; interact = $false; story = $false; split_layout = "stack" }
    try { if (Test-Path -LiteralPath $prefFile) { (Get-Content -Raw -LiteralPath $prefFile | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $pref[$_.Name] = $_.Value } } } catch {}
    try { Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $forms = $true } catch { $forms = $false; Write-Warning "no Windows Forms: Link Play starts the remembered way" }
    if ($forms -and -not $DryRun) {
        [System.Windows.Forms.Application]::EnableVisualStyles()
        $shift = ([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Shift) -ne 0
        if ($pref.ask -or $shift -or $Settings) {
            Add-PokopiaUi
            $keys = Read-Controls $keysFile; $padc = Read-Pad $keysFile
            $updOn = (Read-Updates $updFile).check -ne $false
            $new = Show-LinkPlay $pref "Pokopia" $keys $disp $padc $updChk $updOn
            if ($updChk -and $updChk.shown) { Set-UpdateAnswer $updChk $updChk.answer }   # Skip this version holds even after Cancel
            if (-not $new) { Write-Host "cancelled"; exit 0 }
            if ([bool]$new.updates -ne $updOn) { $u = Read-Updates $updFile; $u.check = [bool]$new.updates; Save-Updates $updFile $u }
            if (-not $new.updates) { $updChk = $null }
            $new.Remove('updates')
            $chosen = $new.controls; $new.Remove('controls'); $padNew = $new.pad; $new.Remove('pad')
            $nd = $new.display; $new.Remove('display')
            if ($nd.Keys | Where-Object { "$($nd[$_])" -ne "$($disp[$_])" }) {   # changed in the Display tab: saved for this PC
                try { New-Item -ItemType Directory -Force $settingsDir | Out-Null; $nd | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $dispFile } catch { Write-Warning "the display settings were not saved: $dispFile" }
            }
            $disp = $nd
            $pref = $new
            try { New-Item -ItemType Directory -Force (Split-Path -Parent $prefFile) | Out-Null; $pref | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $prefFile } catch {}
            $padChanged = ([bool]$padNew.custom -ne ($null -ne $padc.pad)) -or ($padNew.custom -and ($padNew.map.Keys | Where-Object { "$($padNew.map[$_])" -ne "$($padc.pad[$_])" })) -or
                          ("$($padNew.p1)" -ne "$($padc.player1)")
            if (($chosen.Keys | Where-Object { [int]$chosen[$_] -ne [int]$keys[$_] }) -or $padChanged) {   # changed in the window (Reset to defaults too): saved for this PC
                # the keys, then the controllers' map (only when one was chosen) and player 1, kept as the game's menu wrote them unless changed here
                $o = [ordered]@{ version = 1 }; foreach ($k in $chosen.Keys) { $o[$k] = [int]$chosen[$k] }
                if ($padNew.custom) { $o.pad = $padNew.map }
                $o.player1 = "$($padNew.p1)"; $o.player1_name = "$($padNew.p1n)"
                try { New-Item -ItemType Directory -Force $settingsDir | Out-Null; $o | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $keysFile } catch { Write-Warning "the controls were not saved: $keysFile" }
            }
        }
        $windowed = $true
    }
    switch ($pref.mode) {
        'lan' { $LinkPlay = $true }
        'host' { $Internet = $true; if ($pref.keep_room -and $pref.host_room) { $Room = $pref.host_room } }
        'visit' { $Internet = $true; $Join = $pref.join; $Room = $pref.room }
        'split' {   # split.ps1 starts the two games (docs/split-screen.md)
            $sa = @{}; foreach ($n in "Config", "ExeFS", "Dll", "RomFS", "Save", "Work", "Exe", "Shaders") { $v = Get-Variable $n -ValueOnly; if ($v) { $sa[$n] = $v } }
            if ($pref.story) { $sa.Story = $true }; if ($DryRun) { $sa.DryRun = $true }
            $sa.Layout = $(if ($pref.split_layout -eq 'side') { "side" } else { "stack" })
            Invoke-UpdateNotice $updChk
            & (Join-Path $here "split.ps1") @sa; exit $LASTEXITCODE
        }
    }
    if ($pref.mode -ne 'alone' -and $pref.interact) { $Interact = $true }
    if ($pref.mode -ne 'alone' -and $pref.story) { $Story = $true }
}
if ($Join -or $Internet -or $Room -or $Relay) { $LinkPlay = $true }
if ($LinkPlay -and ($CoopHost -or $CoopJoin)) { Write-Error "-LinkPlay / -Join / -Internet and -CoopHost / -CoopJoin: give one kind"; exit 2 }
if ($LinkPlay) {
    if ($Join -eq "ask") { $Join = (Read-Host "The host's address (for example 203.0.113.7, or 192.168.1.20:47600)").Trim(); if (-not $Join) { Write-Error "no address given"; exit 2 } }
    if ($Join -and $Join -notmatch $ipPort) { Write-Error "-Join wants the host's IPv4 address, for example 203.0.113.7 or 192.168.1.20:47600 (got '$Join')"; exit 2 }
    if ($Join -and -not $Internet) {   # outside internet play the game refuses any other address (coop_ldn.c): say so before it starts
        $o = [int[]](($Join -split ':')[0] -split '\.')
        $lanAddr = $o[0] -eq 127 -or $o[0] -eq 10 -or ($o[0] -eq 172 -and $o[1] -ge 16 -and $o[1] -le 31) -or ($o[0] -eq 192 -and $o[1] -eq 168) -or ($o[0] -eq 169 -and $o[1] -eq 254)
        if (-not $lanAddr) {
            $vpn = if ($o[0] -eq 26) { " (Radmin VPN's range)" } elseif ($o[0] -eq 25) { " (Hamachi's range)" } elseif ($o[0] -eq 100 -and $o[1] -ge 64 -and $o[1] -le 127) { " (carrier NAT, or Tailscale's range)" } else { "" }
            Write-Error ("$Join$vpn is not a home-network address. Through a VPN or the internet, play over the internet: the host chooses `"Host over the internet or a VPN`" " +
                         "and gives you the room code, and you visit with -Internet -Join $Join -Room <code> (or `"Visit a host over the internet or a VPN`" in the Link Play window)"); exit 2
        }
    }
    if ($Room -eq "ask") { $Room = (Read-Host "The host's room code (XXXX-XXXX-XXXX-XXXX)").Trim(); if (-not $Room) { Write-Error "no room code given"; exit 2 } }
    if ($Room -and (($Room -replace '[-\s]', '') -notmatch '^[0-9A-TV-Za-tv-z]{16}$')) { Write-Error "-Room wants 16 letters and digits, XXXX-XXXX-XXXX-XXXX (got '$Room')"; exit 2 }
    if ($Relay -and -not $Internet) { Write-Error "-Relay goes with -Internet"; exit 2 }
    if ($Relay -and $Relay -notmatch $ipPort) { Write-Error "-Relay wants the relay's IPv4 address[:port] (got '$Relay')"; exit 2 }
    if ($Internet -and $Join -and -not $Room) { Write-Error "visiting over the internet needs the host's room code: -Room XXXX-XXXX-XXXX-XXXX (or -Room ask)"; exit 2 }
    if ($Internet -and -not $Room) {   # this PC hosts: a new code for this session, shown below (the game would only log its own)
        $b = New-Object byte[] 16; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
        $abc = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; $s = -join ($b | ForEach-Object { $abc[$_ % 32] })   # 256 is a multiple of 32: no bias
        $Room = "$($s.Substring(0, 4))-$($s.Substring(4, 4))-$($s.Substring(8, 4))-$($s.Substring(12, 4))"
    }
    $env:DM_COOP = "auto"
    if ($Join) { $env:DM_COOP_JOIN = $Join }
    if ($Internet) { $env:DM_COOP_INTERNET = "1"; $env:DM_COOP_ROOM = $Room.ToUpper() }
    if ($Relay) { $env:DM_COOP_RELAY = $Relay }
    Write-Host ""
    if ($Join) { Write-Host "Link Play: visiting $Join. In the game: Link Play, Local connection, then look for a town." }
    else { Write-Host "Link Play: on. In the game: Link Play, Local connection, to host or to look for towns$(if (-not $Internet) { ' on this network' })." }
    if ($Internet) {
        Write-Host "Internet play, room code: $($env:DM_COOP_ROOM)" -ForegroundColor Yellow
        if ($Relay) { Write-Host "Through the relay $Relay`: every player needs this code and the relay's address." }
        elseif (-not $Join) { Write-Host "Visitors need this code and this PC's internet address; your router must forward port 47600 (TCP and UDP) to this PC." }
        Write-Host "Nothing is encrypted: anyone on the way can read the game's traffic."
    }
    Write-Host ""
    if ($Internet -and -not $Join -and -not $DryRun) {   # this PC hosts over the internet: the room code in a window with a Copy button
        try {
            Add-Type -AssemblyName System.Windows.Forms, System.Drawing; [System.Windows.Forms.Application]::EnableVisualStyles()
            Show-RoomCode $env:DM_COOP_ROOM "Pokopia - your room code" $Relay
        } catch { Write-Warning "the room code window did not open: the code is above" }
        if ($windowed) {   # "Keep my room code" offers this one next time
            $pref.host_room = $env:DM_COOP_ROOM
            try { $pref | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $prefFile } catch {}
        }
    }
} elseif ($CoopHost) { $env:DM_COOP = "host:$CoopHost" } elseif ($CoopJoin) { $env:DM_COOP = "join:$CoopJoin" }
if ($CoopTcp) { $env:DM_COOP_TCP = "1" }
if ($Story) { $Interact = $true }
if ($Interact) {
    if (-not $env:DM_COOP) { Write-Error "-Interact$(if ($Story) { ' (and -Story)' }) goes with Link Play (-LinkPlay, -Join, -Internet, -CoopHost or -CoopJoin)"; exit 2 }
    $env:DM_COOP_INTERACT = "1"
    if ($Story) { $env:DM_COOP_STORY = "1" }
    if (-not $coopOk) { Write-Warning "Interact everywhere$(if ($Story) { ' and Story co-op' }) need $coopNeeds; this game is another version ($coopGame), so they stay off" }
    else {
        Write-Host "Interact everywhere: on (experimental). Every player needs it on; a session refuses a player whose setting differs."
        if ($Story) { Write-Host "Story co-op: on (experimental). Every player needs it on as well." }
    }
}
if ($env:DM_COOP -and -not $LinkPlay) { Write-Host "Link Play: DM_COOP=$env:DM_COOP$(if ($env:DM_COOP_TCP) { ', datagrams over TCP' })" }
$cache = Join-Path $Work "cache"; $temp = Join-Path $Work "temp"; $logs = Join-Path $Work "logs"
if (-not $DryRun) { New-Item -ItemType Directory -Force $cache, $temp, $logs | Out-Null }

$env:NXRT_VK_CACHE_DIR = $cache            # shaders and pipelines, kept between runs
$env:DM_AUDIO = if ($Silent) { "0" } else { "1" }   # the sound card (SDL3); the silent sink stands in when there is none
if ($Config -or $Ask) {   # the Display tab's settings, saved for this PC; a switch or variable given from outside wins
    if (-not $env:DM_OPMODE) { $env:DM_OPMODE = "$([int]$disp.console)" }
    if (-not $env:NXRT_VK_SCALE -and -not $env:NXRT_VK_RESOLUTION) { $env:NXRT_VK_RESOLUTION = [string]$disp.resolution }
    if (-not $Window -and -not $Fullscreen -and -not $env:NXRT_VK_WINDOW -and -not $env:NXRT_VK_FULLSCREEN) { if ($disp.fullscreen) { $Fullscreen = $true } elseif ($disp.window) { $Window = [string]$disp.window } }
    if (-not $env:NXRT_VK_UPSCALE) { $env:NXRT_VK_UPSCALE = [string]$disp.upscale }
    if (-not $env:NXRT_VK_SHARPNESS) { $env:NXRT_VK_SHARPNESS = ([int]$disp.sharpness / 10.0).ToString([System.Globalization.CultureInfo]::InvariantCulture) }
    if (-not $env:DM_FPS -and @(30, 40, 45, 50) -contains [int]$disp.fps) { $env:DM_FPS = [string][int]$disp.fps }
    if (-not $env:NXRT_VK_PRESENT -and -not $disp.vsync) { $env:NXRT_VK_PRESENT = "mailbox" }
    if (-not $env:NXRT_FPS_COUNTER -and $disp.fps_counter -ne "off") { $env:NXRT_FPS_COUNTER = [string]$disp.fps_counter }
    if (-not $env:NXRT_VK_WIDE -and $disp.wide_view -eq $true) { $env:NXRT_VK_WIDE = "1" }
    if (-not $env:NXRT_VK_AA) { $env:NXRT_VK_AA = [string]$disp.antialiasing }
}
if ($Window) { $env:NXRT_VK_WINDOW = $Window }
if ($Fullscreen) { $env:NXRT_VK_FULLSCREEN = "1" }
if ($PadCheck) { $env:DM_PAD_CHECK = "1"; $env:DM_RUMBLE_LOG = "1"; $env:DM_MOTION_LOG = "1" }   # the controller check (front_sdl.c), the game's vibration and motion (hle_hid.c)
if (-not $env:DM_KEYMAP -and (Test-Path -LiteralPath $keysFile)) { $env:DM_KEYMAP = $keysFile }   # this PC's controls (the window's Controls tab); the game logs the map it uses
if ($Shaders) {   # an installer build's shader cache (nxs_rt.c), and the run-time shaders translated into it on demand
    $env:NXRT_SHADER_CACHE = $Shaders
    if ($ShaderBuild) { $env:NXRT_SHADER_BUILD = $ShaderBuild }
    if ($SpirvTools) { $env:NXSHADER_TOOLS = $SpirvTools }
    if ($ShaderTool) {
        $py = $Python; $pyArg = ""
        if (-not $py -or -not (Test-Path -LiteralPath $py)) {   # the Python the build used has moved: the launcher's, else whatever is on the PATH
            $found = Get-Command py.exe, python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
            $py = if ($found) { $found.Source } else { "" }; if ($found -and $found.Name -eq "py.exe") { $pyArg = " -3" }
        }
        if ($py -and [System.IO.Path]::GetFileName($py) -ieq "pythonw.exe") {   # a build made from the 1.1.0 window: under pythonw every console tool the translator runs opens a window
            $pc = Join-Path (Split-Path -Parent $py) "python.exe"; if (Test-Path -LiteralPath $pc) { $py = $pc }
        }
        if ($py) {
            $env:NXRT_SHADER_TOOL = "`"$py`"$pyArg -I `"$ShaderTool`" --cache `"$Shaders`"" + $(if ($Installer) { " --installer `"$Installer`"" } else { "" })
        } else { Write-Warning "no Python found: shaders the game makes while it runs cannot be translated (their draws are skipped)" }
    }
}
if ($Fonts) { $env:DM_FONT_DIR = $Fonts }
if ($PipelineSeed) { $env:NXRT_VK_PIPELINE_SEED = $PipelineSeed }
# Your own DLC: nxs2.py import-dlc copies it from your dump of the DLC you bought into the build's dlc folder, one numbered folder per add-on
# content. Only a folder that is really there is passed on (DM_AOC_DIR, hle_misc.c and hle_fs.c); without one the game owns no add-on content.
if ($Dlc -and (Test-Path -LiteralPath $Dlc -PathType Container) -and (Get-ChildItem -LiteralPath $Dlc -Directory | Where-Object { $_.Name -match '^[1-9][0-9]*$' })) {
    $env:DM_AOC_DIR = $Dlc
}
Invoke-UpdateNotice $updChk   # when the window did not show it: before the game starts, the check waited for 3 s at most
$args_ = @((Resolve-Path -LiteralPath $ExeFS).Path, "--dll", (Resolve-Path -LiteralPath $Dll).Path, "--romfs", (Resolve-Path -LiteralPath $RomFS).Path,
           "--save", [System.IO.Path]::GetFullPath($Save), "--temp", $temp, "--log", $logs, "--gfx", "vulkan")
if ($DryRun) {
    Write-Host "exe: $((Resolve-Path -LiteralPath $Exe).Path)"; Write-Host "work: $Work"; Write-Host "args: $($args_ -join ' ')"
    Write-Host "env: NXRT_VK_CACHE_DIR=$env:NXRT_VK_CACHE_DIR DM_AUDIO=$env:DM_AUDIO DM_PAD_CHECK=$env:DM_PAD_CHECK"
    if ($Shaders) { Write-Host "shaders: NXRT_SHADER_CACHE=$env:NXRT_SHADER_CACHE NXRT_SHADER_BUILD=$env:NXRT_SHADER_BUILD NXSHADER_TOOLS=$env:NXSHADER_TOOLS"; Write-Host "shader tool: $env:NXRT_SHADER_TOOL" }
    if ($Fonts -or $PipelineSeed) { Write-Host "fonts: $env:DM_FONT_DIR; pipeline seed: $env:NXRT_VK_PIPELINE_SEED" }
    if ($env:DM_COOP) { Write-Host "link play: DM_COOP=$env:DM_COOP DM_COOP_INTERACT=$env:DM_COOP_INTERACT DM_COOP_STORY=$env:DM_COOP_STORY DM_COOP_JOIN=$env:DM_COOP_JOIN DM_COOP_INTERNET=$env:DM_COOP_INTERNET DM_COOP_ROOM=$env:DM_COOP_ROOM" }
    if ($env:DM_KEYMAP) { Write-Host "keys: DM_KEYMAP=$env:DM_KEYMAP" }
    Write-Host "display: DM_OPMODE=$env:DM_OPMODE NXRT_VK_SCALE=$env:NXRT_VK_SCALE NXRT_VK_RESOLUTION=$env:NXRT_VK_RESOLUTION NXRT_VK_WINDOW=$env:NXRT_VK_WINDOW NXRT_VK_FULLSCREEN=$env:NXRT_VK_FULLSCREEN NXRT_VK_UPSCALE=$env:NXRT_VK_UPSCALE NXRT_VK_SHARPNESS=$env:NXRT_VK_SHARPNESS DM_FPS=$env:DM_FPS NXRT_VK_PRESENT=$env:NXRT_VK_PRESENT NXRT_FPS_COUNTER=$env:NXRT_FPS_COUNTER NXRT_VK_WIDE=$env:NXRT_VK_WIDE NXRT_VK_AA=$env:NXRT_VK_AA"
    exit 0
}
Write-Host "Pokopia: keyboard WASD move, mouse look (click the picture; Esc releases the mouse), J/K/U/I = A/B/X/Y, Return = +, Tab = -, F11 fullscreen."
Write-Host "Controllers work as Switch controllers (Xbox / PlayStation / Switch Pro). Save: $Save. Logs: $logs"
# Start-Process quotes nothing: an argument with a space (a save under "Pokopia Native") is passed in quotes, an inner quote escaped
$quoted = $args_ | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }
$exePath = (Resolve-Path -LiteralPath $Exe).Path
# Files unzipped from a download keep Windows' "came from the internet" mark, and Start-Process then refuses nxrt.exe with "The operation was
# canceled by the user": the runtime's folder loses the mark first
Get-ChildItem -LiteralPath (Split-Path -Parent $exePath) -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
# Split screen: nxrt minimizes its own log console (vk_window.c). Started minimized, Windows would minimize the game's window too, and bring it back
# where it was made instead of in its half
$p = Start-Process -FilePath $exePath -ArgumentList $quoted -WorkingDirectory $Work -PassThru
try { $p.PriorityClass = 'BelowNormal' } catch {}
$p.WaitForExit()
exit $p.ExitCode
