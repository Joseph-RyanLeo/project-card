[CmdletBinding()]
param([string]$GameExe = "")

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sessionId = (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + ([guid]::NewGuid().ToString("N").Substring(0, 6))
$outputDir = Join-Path $scriptRoot ("Diagnostic-" + $sessionId)
$zipPath = $outputDir + ".zip"
$gameUserDir = Join-Path $env:APPDATA "Godot\app_userdata\Project Card"
$gameLogDir = Join-Path $gameUserDir "logs"
$traceFiles = @()
$processSamples = New-Object System.Collections.Generic.List[object]
$oldTraceFlag = [Environment]::GetEnvironmentVariable("PROJECT_CARD_TRACE_BATTLE_PERFORMANCE", "Process")

function Save-Json([string]$Path, [object]$Value) {
    $Value | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $Path -Encoding utf8
}

function Get-HardwareInfo {
    $info = [ordered]@{ collected_at = (Get-Date).ToString("o"); powershell = $PSVersionTable.PSVersion.ToString() }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $info.os = [ordered]@{ name = $os.Caption; version = $os.Version; build = $os.BuildNumber; architecture = $os.OSArchitecture; total_ram_mb = [math]::Round($os.TotalVisibleMemorySize / 1024); free_ram_mb_before_game = [math]::Round($os.FreePhysicalMemory / 1024) }
    } catch { $info.os_query_error = $_.Exception.Message }
    try {
        $info.cpu = @(Get-CimInstance Win32_Processor | ForEach-Object { [ordered]@{ name = $_.Name; cores = $_.NumberOfCores; logical_processors = $_.NumberOfLogicalProcessors; max_clock_mhz = $_.MaxClockSpeed } })
    } catch { $info.cpu_query_error = $_.Exception.Message }
    try {
        $info.gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object { [ordered]@{ name = $_.Name; driver_version = $_.DriverVersion; reported_vram_mb = [math]::Round($_.AdapterRAM / 1MB); desktop_width = $_.CurrentHorizontalResolution; desktop_height = $_.CurrentVerticalResolution; desktop_refresh_hz = $_.CurrentRefreshRate } })
        # 此处为系统报告的桌面分辨率和显存，不能当成游戏窗口尺寸或精确显存容量。
    } catch { $info.gpu_query_error = $_.Exception.Message }
    return $info
}

try {
    if ($PSVersionTable.PSVersion.Major -lt 5) { throw "需要 Windows PowerShell 5.1 或更新版本。" }
    if ([string]::IsNullOrWhiteSpace($GameExe)) {
        $candidates = @(Get-ChildItem -LiteralPath $scriptRoot -Filter "*.exe" -File | Where-Object { $_.Name -notmatch '(?i)(\.console\.exe$|uninstall|crashhandler|^setup)' } | Sort-Object Name)
        if ($candidates.Count -eq 0) { throw "没有找到游戏 EXE。请把这三个诊断文件直接放到游戏 EXE 所在文件夹；也可以把 EXE 拖到 Run-Diagnostics.cmd 上。" }
        if ($candidates.Count -eq 1) { $GameExe = $candidates[0].FullName }
        else {
            Write-Host "找到多个 EXE，请选择本次测试的游戏："
            for ($i = 0; $i -lt $candidates.Count; $i++) { Write-Host ("{0}. {1}" -f ($i + 1), $candidates[$i].Name) }
            $selection = 0
            if (-not [int]::TryParse((Read-Host "输入编号"), [ref]$selection) -or $selection -lt 1 -or $selection -gt $candidates.Count) { throw "编号无效，未启动游戏。" }
            $GameExe = $candidates[$selection - 1].FullName
        }
    }
    $game = Get-Item -LiteralPath $GameExe
    if ($game.PSIsContainer -or $game.Extension -ne ".exe" -or $game.Name -match '(?i)\.console\.exe$') { throw "请选择游戏主 EXE，不要选 console 控制台包装 EXE。" }
    if (@(Get-Process | Where-Object { $_.ProcessName -eq $game.BaseName }).Count -gt 0) { throw "请先退出已经打开的这款游戏，再运行诊断，避免两份实例混写日志。" }
    New-Item -ItemType Directory -Path $outputDir | Out-Null
    $hardware = Get-HardwareInfo
    $hardware.game = [ordered]@{ filename = $game.Name; sha256 = (Get-FileHash -LiteralPath $game.FullName -Algorithm SHA256).Hash; bytes = $game.Length; modified_at = $game.LastWriteTime.ToString("o"); file_version = $game.VersionInfo.FileVersion }
    Save-Json (Join-Path $outputDir "hardware.json") $hardware
    $savePath = Join-Path $gameUserDir "project_card_run.json"
    if (Test-Path -LiteralPath $savePath -PathType Leaf) { Copy-Item -LiteralPath $savePath -Destination (Join-Path $outputDir "run-before.json") }
    $existingTraceHashes = @{}
    if (Test-Path -LiteralPath $gameLogDir -PathType Container) {
        foreach ($trace in @(Get-ChildItem -LiteralPath $gameLogDir -Filter "battle-performance-*.json" -File)) {
            $existingTraceHashes[$trace.FullName] = (Get-FileHash -LiteralPath $trace.FullName -Algorithm SHA256).Hash
        }
    }
    Write-Host ""
    Write-Host "即将启动游戏。请按 README 的六个步骤复现，每个步骤结束都按 F10。" -ForegroundColor Cyan
    Write-Host "最后退出游戏；保留此窗口，退出后会自动生成 ZIP。"
    Write-Host "采集范围：这款游戏的性能/引擎日志、本局存档、硬件型号和游戏进程统计。文件留在本机，请手动发回 ZIP。"
    $env:PROJECT_CARD_TRACE_BATTLE_PERFORMANCE = "1"
    $engineLog = Join-Path $outputDir "game-engine.log"
    $startTime = Get-Date
    $launchArgs = @("--log-file", ('"' + $engineLog + '"'))
    $gameProcess = Start-Process -FilePath $game.FullName -WorkingDirectory $game.DirectoryName -ArgumentList $launchArgs -RedirectStandardOutput (Join-Path $outputDir "game-stdout.log") -RedirectStandardError (Join-Path $outputDir "game-stderr.log") -PassThru
    $previousCpu = 0.0
    $previousTime = $startTime
    $previousTraceCount = 0
    while (-not $gameProcess.HasExited) {
        try {
            $gameProcess.Refresh()
            if ($gameProcess.HasExited) { break }
            $now = Get-Date
            $cpuSeconds = $gameProcess.TotalProcessorTime.TotalSeconds
            $elapsed = ($now - $previousTime).TotalSeconds
            $oneCorePercent = if ($elapsed -gt 0) { 100 * ($cpuSeconds - $previousCpu) / $elapsed } else { 0 }
            $processSamples.Add([pscustomobject]@{ time = $now.ToString("o"); cpu_seconds_total = $cpuSeconds; cpu_percent_one_core = [math]::Round($oneCorePercent, 2); working_set_mb = [math]::Round($gameProcess.WorkingSet64 / 1MB, 2); private_memory_mb = [math]::Round($gameProcess.PrivateMemorySize64 / 1MB, 2); peak_working_set_mb = [math]::Round($gameProcess.PeakWorkingSet64 / 1MB, 2) })
            $previousCpu = $cpuSeconds
            $previousTime = $now
        } catch { # 进程刚退出时 Windows 可能已释放统计句柄；保留已收集的样本。
            if ($gameProcess.HasExited) { break }
        }
        if (Test-Path -LiteralPath $gameLogDir -PathType Container) {
            $count = @(Get-ChildItem -LiteralPath $gameLogDir -Filter "battle-performance-*.json" -File | Where-Object { $_.LastWriteTime -ge $startTime.AddSeconds(-1) }).Count
            if ($count -ne $previousTraceCount) { Write-Host ("已发现 {0} 份 F10 日志。完成当前步骤后继续下一步。" -f $count); $previousTraceCount = $count }
        }
        Start-Sleep -Milliseconds 1000 # 每秒一次游戏进程采样；不读取屏幕，也不逐帧访问磁盘。
        $gameProcess.Refresh()
    }
    $gameProcess.WaitForExit()
    if ($processSamples.Count -gt 0) { $processSamples | Export-Csv -LiteralPath (Join-Path $outputDir "process-samples.csv") -NoTypeInformation -Encoding UTF8 }
    $traceDir = Join-Path $outputDir "performance"
    New-Item -ItemType Directory -Path $traceDir | Out-Null
    if (Test-Path -LiteralPath $gameLogDir -PathType Container) {
        foreach ($trace in @(Get-ChildItem -LiteralPath $gameLogDir -Filter "battle-performance-*.json" -File | Where-Object { $_.LastWriteTime -ge $startTime.AddSeconds(-1) } | Sort-Object LastWriteTime, Name)) {
            $hash = (Get-FileHash -LiteralPath $trace.FullName -Algorithm SHA256).Hash
            if ($existingTraceHashes.ContainsKey($trace.FullName) -and $existingTraceHashes[$trace.FullName] -eq $hash) { continue }
            Copy-Item -LiteralPath $trace.FullName -Destination $traceDir
            $traceFiles += [ordered]@{ file = $trace.Name; exported_at = $trace.LastWriteTime.ToString("o"); sha256 = $hash }
        }
    }
    if (Test-Path -LiteralPath $savePath -PathType Leaf) { Copy-Item -LiteralPath $savePath -Destination (Join-Path $outputDir "run-after.json") }
    Save-Json (Join-Path $outputDir "session.json") ([ordered]@{ schema_version = 1; started_at = $startTime.ToString("o"); ended_at = (Get-Date).ToString("o"); game = $game.Name; exit_code = $gameProcess.ExitCode; f10_file_count = $traceFiles.Count; traces = @($traceFiles); requested_window = "1920x1080 window, set inside game"; requested_steps = @("idle", "collection_pages", "shop_pack_hover", "minion_drag", "equipment_drag", "battle_start_running_end"); step_assignment = "用户按 README 顺序执行；实际步骤需要结合日志份数与反馈核对，不自动猜测。" })
    Compress-Archive -LiteralPath $outputDir -DestinationPath $zipPath
    Write-Host ""
    if ($traceFiles.Count -eq 0) { Write-Host "没有发现 F10 性能日志。ZIP 中只有硬件/进程/引擎信息，请重新测试并在游戏窗口按 F10。" -ForegroundColor Yellow }
    elseif ($traceFiles.Count -lt 6) { Write-Host ("找到 {0} 份性能日志，少于建议的六份。可以先发回，并说明执行了哪些步骤。" -f $traceFiles.Count) -ForegroundColor Yellow }
    else { Write-Host "诊断收集完成。" -ForegroundColor Green }
    Write-Host "请把以下 ZIP 发回："
    Write-Host $zipPath -ForegroundColor Cyan
} catch {
    Write-Host ("诊断未完成：" + $_.Exception.Message) -ForegroundColor Red
    if (Test-Path -LiteralPath $outputDir -PathType Container) { Write-Host ("已经收集的文件保留在：" + $outputDir) }
    exit 1
} finally {
    [Environment]::SetEnvironmentVariable("PROJECT_CARD_TRACE_BATTLE_PERFORMANCE", $oldTraceFlag, "Process")
}
