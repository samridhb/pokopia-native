# test_update.ps1 -Repo <repository> (ctest scripts.update_check): play.ps1's update check with stand-in files and -DryRun. The release comes from a
# stand-in (POKOPIA_UPDATE_URL: a file, or this test's own server on 127.0.0.1) and the notice is answered without a window (POKOPIA_UPDATE_ANSWER), so
# nothing asks GitHub. A newer release is told about and recorded (with its downloads' checksums, for the builder); the same version and a pre-release
# are not; once a day; Skip this version; offline and a server that never answers (the 3 s cap); "check": false; a build without a version; -Silent
# (it mutes the sound only: the notice still comes).
param([Parameter(Mandatory = $true)][string]$Repo)
$ErrorActionPreference = "Stop"
$t = Join-Path ([System.IO.Path]::GetTempPath()) ("nxrt-test-update-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force "$t\ExeFS", "$t\save\B00" | Out-Null
foreach ($f in "ExeFS\main", "ExeFS\sdk", "game.dll", "RomFS.img", "nxrt.exe") { Set-Content -Path "$t\$f" -Value "stand-in" }
$play = Join-Path $Repo "scripts\play.ps1"
$settings = "$t\settings"; $upd = "$settings\updates.json"; $fail = 0; $ms = 0
function Config([string]$version) {
    $c = [ordered]@{ exe = "$t\nxrt.exe"; exefs = "ExeFS"; dll = "game.dll"; romfs = "RomFS.img"; save = "save"; work = "work" }
    if ($version) { $c.pokopia_native = $version }
    $c | ConvertTo-Json | Set-Content -Encoding UTF8 "$t\play.json"
}
function Release-Json([string]$tag, [bool]$pre = $false) {   # GitHub's answer, the fields the check reads; the Linux zip's checksum only in the notes
    @{ tag_name = $tag; name = "Pokopia Native $($tag.TrimStart('v')): Stand-in notes"; html_url = "https://github.com/xFractals/pokopia-native/releases/tag/$tag"
       prerelease = $pre; draft = $false; body = "Checksums:`n$('cd' * 32)  Pokopia-Native-for-Linux.zip`n"
       assets = @(@{ name = "Pokopia-Native-for-Windows.zip"; size = 1234; digest = "sha256:$('AB' * 32)"
                     browser_download_url = "https://github.com/xFractals/pokopia-native/releases/download/$tag/Pokopia-Native-for-Windows.zip" },
                  @{ name = "Pokopia-Native-for-Linux.zip"; size = 99; browser_download_url = "https://github.com/xFractals/pokopia-native/releases/download/$tag/Pokopia-Native-for-Linux.zip" }) } |
        ConvertTo-Json -Depth 4
}
function Release([string]$tag, [bool]$pre = $false) { $f = "$t\release-$tag-$pre.json"; Release-Json $tag $pre | Set-Content -Encoding UTF8 $f; ([uri]$f).AbsoluteUri }
# One start: the notice's lines. Its own process with a time limit: a notice window that opened by mistake would wait for a click forever
function Play([string]$url, [string]$answer = "later", [switch]$Now, [switch]$Silent) {
    $env:POKOPIA_SETTINGS_DIR = $settings; $env:POKOPIA_UPDATE_URL = $url; $env:POKOPIA_UPDATE_ANSWER = $answer; $env:POKOPIA_UPDATE_NOW = $(if ($Now) { "1" } else { "" })
    $a = "-NoProfile -ExecutionPolicy Bypass -File `"$play`" -Config `"$t\play.json`" -DryRun$(if ($Silent) { ' -Silent' })"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process powershell -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput "$t\out.txt" -RedirectStandardError "$t\err.txt"
    if (-not $p.WaitForExit(60000)) { $p.Kill(); Write-Host "FAIL: play.ps1 did not finish in 60 s (a window waiting?)"; $script:fail++ }
    $script:ms = $sw.ElapsedMilliseconds
    $out = @(Get-Content "$t\out.txt") + @(Get-Content "$t\err.txt")
    if (-not ($out | Where-Object { $_ -like "exe: *" })) { Write-Host "FAIL: the dry run did not finish`n$($out -join "`n")"; $script:fail++ }
    return , @($out | Where-Object { $_ -like "Pokopia Native * is out*" })
}
function State { if (Test-Path $upd) { Get-Content -Raw $upd | ConvertFrom-Json } }
function Check([string]$name, [bool]$ok, [string]$why = "") { if ($ok) { Write-Host "ok: $name" } else { Write-Host "FAIL: $name $why"; $script:fail++ } }

$quiet = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)   # accepts in the background, never answers
$server = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)  # answers one request as GitHub would, and keeps it
$srv = $null
try {
    Config "1.4.0"
    $newer = Release "v1.4.1"
    $n = Play $newer; $s = State
    Check "a newer release is told about" ($n.Count -eq 1 -and $n[0] -eq ("Pokopia Native 1.4.1 is out: Stand-in notes. Update in the builder: Update my game keeps your save " +
                                                                       "and settings. https://github.com/xFractals/pokopia-native/releases/tag/v1.4.1")) "($n)"
    Check "it is recorded" ($s.latest -eq "v1.4.1" -and $s.latest_name -eq "Stand-in notes" -and $s.latest_url -like "*/releases/tag/v1.4.1" -and
                            $s.last_check -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$' -and -not $s.skipped) "($($s | ConvertTo-Json -Compress))"
    Check "with its downloads' checksums for the builder (the digest, else the notes)" ((($s.assets | Where-Object name -eq "Pokopia-Native-for-Windows.zip").sha256 -ceq ('ab' * 32)) -and
                                                                                     (($s.assets | Where-Object name -eq "Pokopia-Native-for-Linux.zip").sha256 -ceq ('cd' * 32)))
    Check "updates.json has no byte-order mark (the builder's Python reads it)" ([IO.File]::ReadAllBytes($upd)[0] -eq 0x7B)
    $first = $s.last_check
    $n = Play (Release "v1.4.2")
    Check "once a day: no second request the same day" ($n.Count -eq 0 -and (State).last_check -eq $first -and (State).latest -eq "v1.4.1")
    $n = Play $newer "skip" -Now
    Check "Skip this version is kept" ($n.Count -eq 1 -and (State).skipped -eq "v1.4.1")
    $n = Play $newer -Now
    Check "a skipped version is not shown again" ($n.Count -eq 0) "($n)"
    $n = Play (Release "v1.4.2") -Now
    Check "a version newer than the skipped one is" ($n.Count -eq 1 -and $n[0] -like "Pokopia Native 1.4.2 is out*") "($n)"
    $n = Play (Release "v1.4.0") -Now
    Check "the same version: nothing (and it is recorded)" ($n.Count -eq 0 -and (State).latest -eq "v1.4.0") "($n)"
    $n = Play (Release "v1.5.0" $true) -Now
    Check "a pre-release: nothing, not recorded" ($n.Count -eq 0 -and (State).latest -eq "v1.4.0") "($n)"
    $n = Play (Release "v1.5.0-android-beta.3") -Now
    Check "a tag that is not a plain version: nothing" ($n.Count -eq 0 -and (State).latest -eq "v1.4.0") "($n)"
    $before = (State).last_check
    $n = Play ([uri]"$t\missing.json").AbsoluteUri -Now
    Check "offline (nothing there): nothing shown or recorded" ($n.Count -eq 0 -and (State).last_check -eq $before) "($n)"
    $n = Play "http://127.0.0.1:9/" -Now
    Check "offline (refused): nothing shown or recorded" ($n.Count -eq 0 -and (State).last_check -eq $before) "($n)"
    $n = Play (Release "v1.4.4") "skip" -Now -Silent
    Check "-Silent still shows the notice (and takes its answer)" ($n.Count -eq 1 -and $n[0] -like "Pokopia Native 1.4.4 is out*" -and (State).skipped -eq "v1.4.4") "($n)"
    # GitHub's request: the two headers and nothing about the player (this test's server keeps what it was sent)
    $server.Start(); $port = $server.LocalEndpoint.Port
    $srv = [powershell]::Create().AddScript({
        param($l, $body, $log)
        $c = $l.AcceptTcpClient(); $s = $c.GetStream(); $s.ReadTimeout = 20000; $buf = New-Object byte[] 8192; $req = ""
        while ($req -notmatch "`r`n`r`n") { $k = $s.Read($buf, 0, $buf.Length); if ($k -le 0) { break }; $req += [Text.Encoding]::ASCII.GetString($buf, 0, $k) }
        [IO.File]::WriteAllText($log, $req)
        $b = [Text.Encoding]::UTF8.GetBytes($body)
        $h = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($b.Length)`r`nConnection: close`r`n`r`n")
        $s.Write($h, 0, $h.Length); $s.Write($b, 0, $b.Length); $s.Flush(); $c.Close()
    }).AddArgument($server).AddArgument((Release-Json "v1.4.3")).AddArgument("$t\request.txt")
    [void]$srv.BeginInvoke()
    $n = Play "http://127.0.0.1:$port/repos/xFractals/pokopia-native/releases/latest" -Now
    $req = if (Test-Path "$t\request.txt") { Get-Content -Raw "$t\request.txt" } else { "" }
    Check "over HTTP: told about" ($n.Count -eq 1 -and $n[0] -like "Pokopia Native 1.4.3 is out*") "($n)"
    Check "the request: GET, the two headers, no cookie" ($req -match '^GET /repos/xFractals/pokopia-native/releases/latest HTTP/1\.1' -and
                                                          $req -match '(?m)^User-Agent: pokopia-native-update-check/1\.4\.0\r?$' -and
                                                          $req -match '(?m)^Accept: application/vnd\.github\+json\r?$' -and $req -notmatch '(?mi)^Cookie:') "`n$req"
    # The 3 s cap: against a start without a check, a server that never answers adds 3 s at most
    @{ check = $false } | ConvertTo-Json | Set-Content -Encoding UTF8 $upd
    $n = Play $newer -Now; $base = $ms
    Check "check: false: nothing asked or recorded" ($n.Count -eq 0 -and -not (State).last_check -and (State).check -eq $false) "($n)"
    Remove-Item $upd
    $quiet.Start()
    $n = Play "http://127.0.0.1:$($quiet.LocalEndpoint.Port)/" -Now
    Check "a server that never answers: nothing, and the start waits 3 s at most ($ms ms against $base ms)" ($n.Count -eq 0 -and $ms -lt $base + 3800 -and -not (Test-Path $upd)) "($n)"
    Config ""
    $n = Play $newer -Now
    Check "a build without a version (no pokopia_native in play.json): no check" ($n.Count -eq 0 -and -not (Test-Path $upd)) "($n)"
} finally {
    $quiet.Stop(); $server.Stop(); if ($srv) { $srv.Dispose() }
    foreach ($v in "POKOPIA_SETTINGS_DIR", "POKOPIA_UPDATE_URL", "POKOPIA_UPDATE_ANSWER", "POKOPIA_UPDATE_NOW") { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
    Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue
}
if ($fail) { Write-Host "$fail check(s) failed"; exit 1 }
Write-Host "all update checks passed"
