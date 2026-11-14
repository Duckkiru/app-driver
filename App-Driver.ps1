$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

$isInsideWT = -not [string]::IsNullOrWhiteSpace($env:WT_SESSION)
$script:IsInsideWindowsTerminal = $isInsideWT

if (-not $isAdmin) {
    $psExe = if ($PSVersionTable.PSEdition -eq 'Core' -or (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)) {
        "pwsh.exe"
    } else {
        "powershell.exe"
    }

    $isWebSource = [string]::IsNullOrWhiteSpace($PSCommandPath) -or -not (Test-Path -LiteralPath $PSCommandPath)
    $workDir = if (-not $isWebSource) {
        Split-Path -Parent (Resolve-Path -LiteralPath $PSCommandPath).Path
    } else {
        if ($PWD -and $PWD.Path -and (Test-Path -LiteralPath $PWD.Path)) { $PWD.Path } else { [Environment]::GetFolderPath('UserProfile') }
    }

    if ($isWebSource) {
        $psArgs = "-NoProfile -Sta -ExecutionPolicy Bypass -Command `"Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/Duckkiru/app-driver/main/App-Driver.ps1' | Invoke-Expression`""
    } else {
        $scriptTarget = (Resolve-Path -LiteralPath $PSCommandPath).Path
        $psArgs = "-NoProfile -Sta -ExecutionPolicy Bypass -File `"$scriptTarget`""
        if ($args -and $args.Count -gt 0) {
            $forwarded = foreach ($arg in $args) {
                $argStr = "$arg"
                if ($argStr -match '[\s"]') {
                    '`"' + ($argStr -replace '"', '\"') + '`"'
                } else {
                    $argStr
                }
            }
            $psArgs += " " + ($forwarded -join " ")
        }
    }

    function Get-WindowsTerminalPath {
        foreach ($bin in @('wt.exe', 'wtd.exe', 'wt')) {
            $cmd = Get-Command -Name $bin -CommandType Application -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
                return $cmd.Source
            }
        }

        $aliasCandidates = @(
            (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe\wt.exe"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\wt.exe"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\Microsoft.WindowsTerminal_8wekyb3d8bbwe\wt.exe"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"),
            (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wtd.exe")
        )
        foreach ($candidate in $aliasCandidates) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
                return $candidate
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION)) {
            return "wt.exe"
        }

        return $null
    }

    function Test-UacCancelled ($errorRecord) {
        if (-not $errorRecord) { return $false }
        $currEx = $errorRecord.Exception
        while ($currEx) {
            if ($currEx -is [System.ComponentModel.Win32Exception] -and $currEx.NativeErrorCode -eq 1223) {
                return $true
            }
            if ($currEx.Message -match "canceled by the user|cancelled by the user") {
                return $true
            }
            $currEx = $currEx.InnerException
        }
        return $false
    }

    $wtExe = Get-WindowsTerminalPath
    $elevationSuccess = $false

    if ($isInsideWT -or $wtExe) {
        $targetWt = if ($wtExe) { $wtExe } else { "wt.exe" }

        $safeWorkDir = $workDir.TrimEnd('\')
        if ($safeWorkDir -match '^[a-zA-Z]:$') {
            $safeWorkDir += '\\'
        }

        $wtPsArgs = $psArgs -replace '(?<!\\);', '\;'
        $wtArgs = "-d `"$safeWorkDir`" $psExe $wtPsArgs"

        try {
            Start-Process -FilePath $targetWt -ArgumentList $wtArgs -Verb RunAs -ErrorAction Stop
            $elevationSuccess = $true
            [Environment]::Exit(0)
        } catch {
            if (Test-UacCancelled $_) {
                Write-Host "`n[!] Bạn đã từ chối cấp quyền Administrator (UAC)." -ForegroundColor Yellow
                Write-Host "[*] App-Driver cần quyền Administrator để thực hiện sửa lỗi hệ thống và quản lý Driver.`n" -ForegroundColor DarkGray
                exit
            }
        }
    }

    if (-not $elevationSuccess) {
        try {
            $startParams = @{
                FilePath     = $psExe
                ArgumentList = $psArgs
                Verb         = "RunAs"
                ErrorAction  = "Stop"
            }
            if (Test-Path -LiteralPath $workDir) {
                $startParams["WorkingDirectory"] = $workDir
            }
            Start-Process @startParams
            $elevationSuccess = $true
            [Environment]::Exit(0)
        } catch {
            if (Test-UacCancelled $_) {
                Write-Host "`n[!] Bạn đã từ chối cấp quyền Administrator (UAC)." -ForegroundColor Yellow
                Write-Host "[*] App-Driver cần quyền Administrator để thực hiện sửa lỗi hệ thống và quản lý Driver.`n" -ForegroundColor DarkGray
                exit
            }

            if ($psExe -ne "powershell.exe" -and (Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue)) {
                try {
                    $fallbackParams = @{
                        FilePath     = "powershell.exe"
                        ArgumentList = $psArgs
                        Verb         = "RunAs"
                        ErrorAction  = "Stop"
                    }
                    if (Test-Path -LiteralPath $workDir) {
                        $fallbackParams["WorkingDirectory"] = $workDir
                    }
                    Start-Process @fallbackParams
                    $elevationSuccess = $true
                    [Environment]::Exit(0)
                } catch {
                    if (Test-UacCancelled $_) {
                        Write-Host "`n[!] Bạn đã từ chối cấp quyền Administrator (UAC)." -ForegroundColor Yellow
                        Write-Host "[*] App-Driver cần quyền Administrator để thực hiện sửa lỗi hệ thống và quản lý Driver.`n" -ForegroundColor DarkGray
                        exit
                    }
                    Write-Host "`n[x] Lỗi khởi chạy quyền Administrator: $($_.Exception.Message)" -ForegroundColor Red
                    exit
                }
            } else {
                Write-Host "`n[x] Lỗi khởi chạy quyền Administrator: $($_.Exception.Message)" -ForegroundColor Red
                exit
            }
        }
    }
    exit
}

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}

if ($Host -and $Host.UI -and $Host.UI.RawUI) {
    try {
        $Host.UI.RawUI.WindowTitle = "App-Driver - Terminal Console"
    } catch {
    }
}

try { Clear-Host } catch {}
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "   ___                ____       _                " -ForegroundColor Cyan
Write-Host "  / _ | ___  ___ ____/ __ \____ (_)  _____ ____   " -ForegroundColor Cyan
Write-Host " / __ |/ _ \/ _ \___/ /_/ / __/ / | / / -_) __/   " -ForegroundColor Cyan
Write-Host "/_/ |_/ .__/ .__/  /_____/_/ /_/|___/\__/_/      " -ForegroundColor Cyan
Write-Host "     /_/  /_/      Windows Software & Driver Suite" -ForegroundColor DarkCyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "[!] Vui lòng KHÔNG đóng cửa sổ Terminal này khi đang sử dụng giao diện App-Driver.`n" -ForegroundColor Yellow

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$appsRawJson = @'
[
  {
    "ID":  "Google.Chrome",
    "Name":  "Google Chrome",
    "Domain":  "google.com/chrome",
    "Aliases":  [
            "Google Chrome",
            "Google.Chrome"
          ],
    "Category":  "Web Browsers",
    "Url":  "https://www.google.com/chrome/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/google-chrome.png",
    "IDn":  1
  },
  {
    "ID":  "Mozilla.Firefox",
    "Name":  "Mozilla Firefox",
    "Domain":  "firefox.com",
    "Aliases":  [
            "Mozilla Firefox",
            "Firefox",
            "Mozilla.Firefox"
          ],
    "Category":  "Web Browsers",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/firefox.png",
    "IDn":  2
  },
  {
    "ID":  "Brave.Brave",
    "Name":  "Brave Browser",
    "Domain":  "brave.com",
    "Aliases":  [
            "Brave",
            "BraveSoftware",
            "Brave.Brave",
            "Brave Browser"
          ],
    "Category":  "Web Browsers",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/brave.png",
    "IDn":  3
  },
  {
    "ID":  "LibreWolf.LibreWolf",
    "Name":  "LibreWolf",
    "Domain":  "librewolf.net",
    "Aliases":  [
            "LibreWolf",
            "LibreWolf.LibreWolf"
          ],
    "Category":  "Web Browsers",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/librewolf.png",
    "IDn":  4
  },
  {
    "ID":  "Vivaldi.Vivaldi",
    "Name":  "Vivaldi",
    "Domain":  "vivaldi.com",
    "Aliases":  [
            "Vivaldi",
            "Vivaldi.Vivaldi"
          ],
    "Category":  "Web Browsers",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/vivaldi.png",
    "IDn":  5
  },
  {
    "ID":  "TorProject.TorBrowser",
    "Name":  "Tor Browser",
    "Domain":  "torproject.org",
    "Aliases":  [
            "Tor Browser",
            "TorProject.TorBrowser"
          ],
    "Category":  "Web Browsers",
    "IDn":  6
  },
  {
    "ID":  "Opera.OperaGX",
    "Name":  "Opera GX",
    "Domain":  "opera.com/gx",
    "Aliases":  [
            "Opera GX",
            "OperaGX",
            "Opera.OperaGX"
          ],
    "Category":  "Web Browsers",
    "Url":  "https://www.opera.com/gx",
    "IconUrl":  "https://img.icons8.com/fluency/96/opera-gx.png",
    "IDn":  7
  },
  {
    "ID":  "Microsoft.Edge",
    "Name":  "Microsoft Edge",
    "Domain":  "microsoft.com/edge",
    "Aliases":  [
            "Microsoft Edge",
            "Microsoft.Edge"
          ],
    "Category":  "Web Browsers",
    "Url":  "https://www.microsoft.com/edge",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/microsoft-edge.png",
    "IDn":  8
  },
  {
    "ID":  "Zen-Team.Zen-Browser",
    "Name":  "Zen Browser",
    "Domain":  "zen-browser.app",
    "Aliases":  [
            "Zen Browser",
            "Zen",
            "Zen-Team.Zen-Browser"
          ],
    "Category":  "Web Browsers",
    "Url":  "https://zen-browser.app/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zen-browser.png",
    "IDn":  9
  },
  {
    "ID":  "Ablaze.Floorp",
    "Name":  "Floorp",
    "Domain":  "floorp.app",
    "Aliases":  [
            "Ablaze Floorp",
            "Floorp",
            "Ablaze.Floorp"
          ],
    "Category":  "Web Browsers",
    "Url":  "https://floorp.app/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=floorp.app\u0026sz=128",
    "IDn":  10
  },
  {
    "ID":  "Discord.Discord",
    "Name":  "Discord",
    "Domain":  "discord.com",
    "Aliases":  [
            "Discord",
            "Discord.Discord"
          ],
    "Category":  "Communication",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/discord.png",
    "IDn":  11
  },
  {
    "ID":  "Telegram.TelegramDesktop",
    "Name":  "Telegram",
    "Domain":  "telegram.org",
    "Aliases":  [
            "Telegram Desktop",
            "Telegram",
            "TelegramDesktop",
            "Telegram.TelegramDesktop"
          ],
    "Category":  "Communication",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/telegram.png",
    "IDn":  12
  },
  {
    "ID":  "OpenWhisperSystems.Signal",
    "Name":  "Signal",
    "Domain":  "signal.org",
    "Aliases":  [
            "Signal",
            "OpenWhisperSystems.Signal"
          ],
    "Category":  "Communication",
    "IconUrl":  "https://img.icons8.com/fluency/96/signal-app.png",
    "IDn":  13
  },
  {
    "ID":  "VNGCorp.Zalo",
    "Name":  "Zalo",
    "Domain":  "zalo.me",
    "Aliases":  [
            "Zalo",
            "VNGCorp.Zalo"
          ],
    "Category":  "Communication",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zalo.png",
    "IDn":  14
  },
  {
    "ID":  "Zoom.Zoom",
    "Name":  "Zoom Workplace",
    "Domain":  "zoom.us",
    "Aliases":  [
            "Zoom Workplace",
            "Zoom",
            "Zoom.Zoom"
          ],
    "Category":  "Communication",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zoom.png",
    "IDn":  15
  },
  {
    "ID":  "SlackTechnologies.Slack",
    "Name":  "Slack",
    "Domain":  "slack.com",
    "Aliases":  [
            "Slack",
            "SlackTechnologies.Slack"
          ],
    "Category":  "Communication",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/slack.png",
    "IDn":  16
  },
  {
    "ID":  "9NKSQGP7F2NH",
    "Name":  "WhatsApp",
    "Domain":  "whatsapp.com",
    "Aliases":  [
            "WhatsApp",
            "WhatsApp.WhatsApp",
            "9NKSQGP7F2NH"
          ],
    "Category":  "Communication",
    "Source":  "msstore",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/whatsapp.png",
    "IDn":  17
  },
  {
    "ID":  "Microsoft.Teams",
    "Name":  "Microsoft Teams",
    "Domain":  "teams.microsoft.com",
    "Aliases":  [
            "Microsoft Teams",
            "Microsoft Teams (work or school)",
            "MSTeams",
            "Microsoft.Teams"
          ],
    "Category":  "Communication",
    "Url":  "https://www.microsoft.com/en-us/microsoft-teams/download-app",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/microsoft-teams.png",
    "IDn":  18
  },
  {
    "ID":  "RustDesk.RustDesk",
    "Name":  "RustDesk",
    "Domain":  "rustdesk.com",
    "Aliases":  [
            "RustDesk",
            "RustDesk.RustDesk"
          ],
    "Category":  "Remote Desktop",
    "GitHubRepo":  "rustdesk/rustdesk",
    "AssetRegex":  "x86_64\\.msi$",
    "FallbackUrl":  "https://github.com/rustdesk/rustdesk/releases/latest",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/rustdesk.png",
    "IDn":  19
  },
  {
    "ID":  "AnyDesk.AnyDesk",
    "Name":  "AnyDesk",
    "Domain":  "anydesk.com",
    "Aliases":  [
            "AnyDesk",
            "AnyDesk.AnyDesk"
          ],
    "Category":  "Remote Desktop",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/anydesk.png",
    "IDn":  20
  },
  {
    "ID":  "DucFabulous.UltraViewer",
    "Name":  "UltraViewer",
    "Domain":  "ultraviewer.net",
    "Aliases":  [
            "UltraViewer",
            "DucFabulous.UltraViewer"
          ],
    "Category":  "Remote Desktop",
    "IDn":  21
  },
  {
    "ID":  "TeamViewer.TeamViewer",
    "Name":  "TeamViewer",
    "Domain":  "teamviewer.com",
    "Aliases":  [
            "TeamViewer",
            "TeamViewer.TeamViewer"
          ],
    "Category":  "Remote Desktop",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=teamviewer.com\u0026sz=128",
    "IDn":  22
  },
  {
    "ID":  "Parsec.Parsec",
    "Name":  "Parsec",
    "Domain":  "parsec.app",
    "Aliases":  [
            "Parsec",
            "Parsec.Parsec"
          ],
    "Category":  "Remote Desktop",
    "Url":  "https://parsec.app/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=parsec.app\u0026sz=128",
    "IDn":  23
  },
  {
    "ID":  "MoonlightGameStreamingProject.Moonlight",
    "Name":  "Moonlight",
    "Domain":  "moonlight-stream.org",
    "Aliases":  [
            "Moonlight Game Streaming Client",
            "Moonlight",
            "MoonlightGameStreamingProject.Moonlight"
          ],
    "Category":  "Remote Desktop",
    "Url":  "https://moonlight-stream.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=moonlight-stream.org\u0026sz=128",
    "IDn":  24
  },
  {
    "ID":  "Google.ChromeRemoteDesktopHost",
    "Name":  "Chrome Remote Desktop",
    "Domain":  "remotedesktop.google.com",
    "Aliases":  [
            "Chrome Remote Desktop Host",
            "Google.ChromeRemoteDesktopHost"
          ],
    "Category":  "Remote Desktop",
    "Url":  "https://remotedesktop.google.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=remotedesktop.google.com\u0026sz=128",
    "IDn":  25
  },
  {
    "ID":  "Google.Antigravity",
    "Name":  "Antigravity",
    "Domain":  "antigravity.google",
    "Aliases":  [
            "Antigravity",
            "Google.Antigravity"
          ],
    "Category":  "Antigravity",
    "Url":  "https://antigravity.google/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=antigravity.google\u0026sz=128",
    "IDn":  26
  },
  {
    "ID":  "Google.AntigravityIDE",
    "Name":  "Antigravity IDE",
    "Domain":  "antigravity.google",
    "Aliases":  [
            "Antigravity IDE",
            "Antigravity IDE (User)",
            "Google.AntigravityIDE"
          ],
    "Category":  "Antigravity",
    "Url":  "https://antigravity.google/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=antigravity.google\u0026sz=128",
    "IDn":  27
  },
  {
    "ID":  "Google.AntigravityCLI",
    "Name":  "Antigravity CLI",
    "Domain":  "antigravity.google",
    "Aliases":  [
            "Antigravity CLI",
            "Google.AntigravityCLI"
          ],
    "Category":  "Antigravity",
    "Url":  "https://antigravity.google/docs",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=antigravity.google\u0026sz=128",
    "IDn":  28
  },
  {
    "ID":  "OpenAI.ChatGPT",
    "Name":  "ChatGPT",
    "Domain":  "chatgpt.com",
    "Aliases":  [
            "ChatGPT",
            "OpenAI.ChatGPT"
          ],
    "Category":  "AI \u0026 Assistants",
    "Url":  "https://chatgpt.com/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/chatgpt.png",
    "IDn":  29
  },
  {
    "ID":  "Anthropic.Claude",
    "Name":  "Claude",
    "Domain":  "claude.ai",
    "Aliases":  [
            "Claude",
            "Anthropic.Claude"
          ],
    "Category":  "AI \u0026 Assistants",
    "Url":  "https://claude.ai/download",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/claude-ai.png",
    "IDn":  30
  },
  {
    "ID":  "Ollama.Ollama",
    "Name":  "Ollama",
    "Domain":  "ollama.com",
    "Aliases":  [
            "Ollama",
            "Ollama.Ollama"
          ],
    "Category":  "AI \u0026 Assistants",
    "Url":  "https://ollama.com/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/ollama.png",
    "IconBg":  "light",
    "IDn":  31
  },
  {
    "ID":  "ElementLabs.LMStudio",
    "Name":  "LM Studio",
    "Domain":  "lmstudio.ai",
    "Aliases":  [
            "LM Studio",
            "ElementLabs.LMStudio"
          ],
    "Category":  "AI \u0026 Assistants",
    "Url":  "https://lmstudio.ai/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=lmstudio.ai\u0026sz=128",
    "IDn":  32
  },
  {
    "ID":  "Jan.Jan",
    "Name":  "Jan AI (Local LLM)",
    "Domain":  "jan.ai",
    "Aliases":  [
            "Jan",
            "Jan AI",
            "Jan.Jan"
          ],
    "Category":  "AI \u0026 Assistants",
    "GitHubRepo":  "menlorelabs/jan",
    "AssetRegex":  "x64-setup\\.exe$",
    "Url":  "https://jan.ai/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=jan.ai\u0026sz=128",
    "IDn":  33
  },
  {
    "ID":  "nomic.gpt4all",
    "Name":  "GPT4All",
    "Domain":  "nomic.ai",
    "Aliases":  [
            "GPT4All",
            "nomic.gpt4all"
          ],
    "Category":  "AI \u0026 Assistants",
    "Url":  "https://www.nomic.ai/gpt4all",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=nomic.ai\u0026sz=128",
    "IDn":  34
  },
  {
    "ID":  "JetBrains.Toolbox",
    "Name":  "JetBrains Toolbox",
    "Domain":  "jetbrains.com",
    "Aliases":  [
            "JetBrains Toolbox",
            "JetBrains.Toolbox"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/toolbox-app/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/Toolbox_icon.png",
    "IDn":  35
  },
  {
    "ID":  "JetBrains.IntelliJIDEA.Community",
    "Name":  "IntelliJ IDEA Community",
    "Domain":  "jetbrains.com/idea",
    "Aliases":  [
            "IntelliJ IDEA Community Edition",
            "JetBrains.IntelliJIDEA.Community"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/idea/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/IntelliJ_IDEA_icon.png",
    "IDn":  36
  },
  {
    "ID":  "JetBrains.IntelliJIDEA.Ultimate",
    "Name":  "IntelliJ IDEA Ultimate",
    "Domain":  "jetbrains.com/idea",
    "Aliases":  [
            "IntelliJ IDEA Ultimate Edition",
            "JetBrains.IntelliJIDEA.Ultimate"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/idea/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/IntelliJ_IDEA_icon.png",
    "IDn":  37
  },
  {
    "ID":  "JetBrains.PyCharm.Community",
    "Name":  "PyCharm Community",
    "Domain":  "jetbrains.com/pycharm",
    "Aliases":  [
            "PyCharm Community Edition",
            "JetBrains.PyCharm.Community"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/pycharm/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/PyCharm_icon.png",
    "IDn":  38
  },
  {
    "ID":  "JetBrains.PyCharm.Professional",
    "Name":  "PyCharm Professional",
    "Domain":  "jetbrains.com/pycharm",
    "Aliases":  [
            "PyCharm Professional Edition",
            "JetBrains.PyCharm.Professional"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/pycharm/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/PyCharm_icon.png",
    "IDn":  39
  },
  {
    "ID":  "JetBrains.WebStorm",
    "Name":  "WebStorm",
    "Domain":  "jetbrains.com/webstorm",
    "Aliases":  [
            "WebStorm",
            "JetBrains.WebStorm"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/webstorm/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/WebStorm_icon.png",
    "IDn":  40
  },
  {
    "ID":  "JetBrains.PhpStorm",
    "Name":  "PhpStorm",
    "Domain":  "jetbrains.com/phpstorm",
    "Aliases":  [
            "PhpStorm",
            "JetBrains.PhpStorm"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/phpstorm/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/PhpStorm_icon.png",
    "IDn":  41
  },
  {
    "ID":  "JetBrains.GoLand",
    "Name":  "GoLand",
    "Domain":  "jetbrains.com/go",
    "Aliases":  [
            "GoLand",
            "JetBrains.GoLand"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/go/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/GoLand_icon.png",
    "IDn":  42
  },
  {
    "ID":  "JetBrains.Rider",
    "Name":  "Rider",
    "Domain":  "jetbrains.com/rider",
    "Aliases":  [
            "JetBrains Rider",
            "Rider",
            "JetBrains.Rider"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/rider/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/Rider_icon.png",
    "IDn":  43
  },
  {
    "ID":  "JetBrains.CLion",
    "Name":  "CLion",
    "Domain":  "jetbrains.com/clion",
    "Aliases":  [
            "CLion",
            "JetBrains.CLion"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/clion/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/CLion_icon.png",
    "IDn":  44
  },
  {
    "ID":  "JetBrains.DataGrip",
    "Name":  "DataGrip",
    "Domain":  "jetbrains.com/datagrip",
    "Aliases":  [
            "DataGrip",
            "JetBrains.DataGrip"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/datagrip/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/DataGrip_icon.png",
    "IDn":  45
  },
  {
    "ID":  "JetBrains.RustRover",
    "Name":  "RustRover",
    "Domain":  "jetbrains.com/rust",
    "Aliases":  [
            "RustRover",
            "JetBrains.RustRover"
          ],
    "Category":  "JetBrains",
    "Url":  "https://www.jetbrains.com/rust/",
    "IconUrl":  "https://resources.jetbrains.com/storage/products/company/brand/logos/RustRover_icon.png",
    "IDn":  46
  },
  {
    "ID":  "Microsoft.VisualStudioCode",
    "Name":  "VS Code",
    "Domain":  "code.visualstudio.com",
    "Aliases":  [
            "Visual Studio Code",
            "VS Code",
            "VSCode",
            "Microsoft.VisualStudioCode"
          ],
    "Category":  "Development",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/vscode.png",
    "IDn":  47
  },
  {
    "ID":  "Anysphere.Cursor",
    "Name":  "Cursor",
    "Domain":  "cursor.com",
    "Aliases":  [
            "Cursor",
            "Anysphere.Cursor"
          ],
    "Category":  "Development",
    "Url":  "https://www.cursor.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=cursor.com\u0026sz=128",
    "IDn":  48
  },
  {
    "ID":  "Git.Git",
    "Name":  "Git",
    "Domain":  "git-scm.com",
    "Aliases":  [
            "Git",
            "Git.Git"
          ],
    "Category":  "Development",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/git.png",
    "IDn":  49
  },
  {
    "ID":  "Microsoft.WindowsTerminal",
    "Name":  "Windows Terminal",
    "Domain":  "microsoft.com",
    "Aliases":  [
            "Windows Terminal",
            "Bảng điều khiển Windows",
            "Microsoft.WindowsTerminal"
          ],
    "IconUrl":  "https://cdn.jsdelivr.net/gh/selfhst/icons/png/windows-terminal.png",
    "Category":  "Development",
    "Url":  "https://learn.microsoft.com/en-us/windows/terminal/",
    "IDn":  50
  },
  {
    "ID":  "Microsoft.WindowsTerminal.Preview",
    "Name":  "Windows Terminal Preview",
    "Domain":  "microsoft.com",
    "Aliases":  [
            "Windows Terminal Preview",
            "Microsoft.WindowsTerminal.Preview"
          ],
    "IconUrl":  "https://raw.githubusercontent.com/microsoft/terminal/main/res/terminal/images-Pre/Square44x44Logo.targetsize-64.png",
    "Category":  "Development",
    "Url":  "https://learn.microsoft.com/en-us/windows/terminal/",
    "IDn":  51
  },
  {
    "ID":  "Python.Python.3.13",
    "Name":  "Python 3.13",
    "Domain":  "python.org",
    "Aliases":  [
            "Python 3.13",
            "Python.Python.3.13"
          ],
    "Category":  "Development",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/python.png",
    "IDn":  52
  },
  {
    "ID":  "OpenJS.NodeJS.LTS",
    "Name":  "Node.js LTS",
    "Domain":  "nodejs.org",
    "Aliases":  [
            "Node.js",
            "NodeJS",
            "OpenJS.NodeJS.LTS"
          ],
    "Category":  "Development",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/nodejs.png",
    "IDn":  53
  },
  {
    "ID":  "Notepad++.Notepad++",
    "Name":  "Notepad++",
    "Domain":  "notepad-plus-plus.org",
    "Aliases":  [
            "Notepad++",
            "NotepadPlusPlus",
            "Notepad++.Notepad++"
          ],
    "Category":  "Development",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/selfhst/icons/png/notepad-plus-plus.png",
    "IDn":  54
  },
  {
    "ID":  "GoLang.Go",
    "Name":  "Go",
    "Domain":  "go.dev",
    "Aliases":  [
            "Go Programming Language",
            "GoLang",
            "GoLang.Go"
          ],
    "Category":  "Development",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/go.png",
    "IDn":  55
  },
  {
    "ID":  "Rustlang.Rustup",
    "Name":  "Rust (rustup)",
    "Domain":  "rust-lang.org",
    "Aliases":  [
            "Rustup",
            "Rustup: the Rust toolchain installer",
            "Rustlang.Rustup"
          ],
    "Category":  "Development",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/selfhst/icons/png/rust-light.png",
    "IDn":  56
  },
  {
    "ID":  "Microsoft.PowerShell",
    "Name":  "PowerShell 7",
    "Domain":  "learn.microsoft.com/powershell",
    "Aliases":  [
            "PowerShell",
            "Microsoft.PowerShell"
          ],
    "Category":  "Development",
    "Url":  "https://github.com/PowerShell/PowerShell",
    "IconUrl":  "https://img.icons8.com/color/96/powershell.png",
    "IDn":  57
  },
  {
    "ID":  "GitHub.GitHubDesktop",
    "Name":  "GitHub Desktop",
    "Domain":  "desktop.github.com",
    "Aliases":  [
            "GitHub Desktop",
            "GitHub.GitHubDesktop"
          ],
    "Category":  "Development",
    "Url":  "https://desktop.github.com/",
    "IconUrl":  "https://avatars.githubusercontent.com/u/19267068?s=128\u0026v=4",
    "IDn":  58
  },
  {
    "ID":  "GitHub.cli",
    "Name":  "GitHub CLI",
    "Domain":  "cli.github.com",
    "Aliases":  [
            "GitHub CLI",
            "GitHub.cli"
          ],
    "Category":  "Development",
    "Url":  "https://cli.github.com/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/github-light.png",
    "IDn":  59
  },
  {
    "ID":  "SublimeHQ.SublimeText.4",
    "Name":  "Sublime Text 4",
    "Domain":  "sublimetext.com",
    "Aliases":  [
            "Sublime Text",
            "Sublime Text 4",
            "SublimeHQ.SublimeText.4"
          ],
    "Category":  "Development",
    "Url":  "https://www.sublimetext.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=sublimetext.com\u0026sz=128",
    "IDn":  60
  },
  {
    "ID":  "Neovim.Neovim",
    "Name":  "Neovim",
    "Domain":  "neovim.io",
    "Aliases":  [
            "Neovim",
            "Neovim.Neovim"
          ],
    "Category":  "Development",
    "Url":  "https://neovim.io/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=neovim.io\u0026sz=128",
    "IDn":  61
  },
  {
    "ID":  "astral-sh.uv",
    "Name":  "uv (Python Manager)",
    "Domain":  "docs.astral.sh",
    "Aliases":  [
            "uv",
            "astral-sh.uv"
          ],
    "Category":  "Development",
    "Url":  "https://docs.astral.sh/uv/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=docs.astral.sh\u0026sz=128",
    "IDn":  62
  },
  {
    "ID":  "Codeium.Windsurf",
    "Name":  "Windsurf IDE",
    "Domain":  "windsurf.com",
    "Aliases":  [
            "Windsurf",
            "Codeium.Windsurf"
          ],
    "Category":  "Development",
    "Url":  "https://windsurf.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=windsurf.com\u0026sz=128",
    "IDn":  63
  },
  {
    "ID":  "ZedIndustries.Zed",
    "Name":  "Zed Editor",
    "Domain":  "zed.dev",
    "Aliases":  [
            "Zed",
            "ZedIndustries.Zed"
          ],
    "Category":  "Development",
    "Url":  "https://zed.dev/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=zed.dev\u0026sz=128",
    "IDn":  64
  },
  {
    "ID":  "VSCodium.VSCodium",
    "Name":  "VSCodium",
    "Domain":  "vscodium.com",
    "Aliases":  [
            "VSCodium",
            "VSCodium.VSCodium"
          ],
    "Category":  "Development",
    "GitHubRepo":  "VSCodium/vscodium",
    "AssetRegex":  "VSCodiumSetup-x64-[0-9.]+\\.exe$",
    "Url":  "https://vscodium.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=vscodium.com\u0026sz=128",
    "IDn":  65
  },
  {
    "ID":  "Microsoft.VisualStudio.2022.Community",
    "Name":  "Visual Studio 2022 Community",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Visual Studio Community 2022",
            "Microsoft.VisualStudio.2022.Community"
          ],
    "Category":  "Development",
    "Url":  "https://visualstudio.microsoft.com/vs/community/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=visualstudio.microsoft.com\u0026sz=128",
    "IDn":  66
  },
  {
    "ID":  "Microsoft.VisualStudio.2022.BuildTools",
    "Name":  "VS 2022 Build Tools (C++)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Visual Studio Build Tools 2022",
            "Microsoft.VisualStudio.2022.BuildTools"
          ],
    "Category":  "Development",
    "Url":  "https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=visualstudio.microsoft.com\u0026sz=128",
    "IDn":  67
  },
  {
    "ID":  "Google.AndroidStudio",
    "Name":  "Android Studio",
    "Domain":  "developer.android.com",
    "Aliases":  [
            "Android Studio",
            "Google.AndroidStudio"
          ],
    "Category":  "Development",
    "Url":  "https://developer.android.com/studio",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=developer.android.com\u0026sz=128",
    "IDn":  68
  },
  {
    "ID":  "Oven-sh.Bun",
    "Name":  "Bun (JS Runtime)",
    "Domain":  "bun.sh",
    "Aliases":  [
            "Bun",
            "Oven-sh.Bun"
          ],
    "Category":  "Development",
    "Url":  "https://bun.sh/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=bun.sh\u0026sz=128",
    "IDn":  69
  },
  {
    "ID":  "pnpm.pnpm",
    "Name":  "pnpm",
    "Domain":  "pnpm.io",
    "Aliases":  [
            "pnpm",
            "pnpm.pnpm"
          ],
    "Category":  "Development",
    "Url":  "https://pnpm.io/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=pnpm.io\u0026sz=128",
    "IDn":  70
  },
  {
    "ID":  "Yarn.Yarn",
    "Name":  "Yarn",
    "Domain":  "yarnpkg.com",
    "Aliases":  [
            "Yarn",
            "Yarn.Yarn"
          ],
    "Category":  "Development",
    "Url":  "https://yarnpkg.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=yarnpkg.com\u0026sz=128",
    "IDn":  71
  },
  {
    "ID":  "Kitware.CMake",
    "Name":  "CMake",
    "Domain":  "cmake.org",
    "Aliases":  [
            "CMake",
            "Kitware.CMake"
          ],
    "Category":  "Development",
    "Url":  "https://cmake.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=cmake.org\u0026sz=128",
    "IDn":  72
  },
  {
    "ID":  "LLVM.LLVM",
    "Name":  "LLVM / Clang",
    "Domain":  "llvm.org",
    "Aliases":  [
            "LLVM",
            "LLVM.LLVM"
          ],
    "Category":  "Development",
    "Url":  "https://llvm.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=llvm.org\u0026sz=128",
    "IDn":  73
  },
  {
    "ID":  "MSYS2.MSYS2",
    "Name":  "MSYS2 (MinGW-w64)",
    "Domain":  "msys2.org",
    "Aliases":  [
            "MSYS2",
            "MSYS2 64bit",
            "MSYS2.MSYS2"
          ],
    "Category":  "Development",
    "Url":  "https://www.msys2.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=msys2.org\u0026sz=128",
    "IDn":  74
  },
  {
    "ID":  "JanDeDobbeleer.OhMyPosh",
    "Name":  "Oh My Posh",
    "Domain":  "ohmyposh.dev",
    "Aliases":  [
            "Oh My Posh",
            "JanDeDobbeleer.OhMyPosh"
          ],
    "Category":  "Development",
    "GitHubRepo":  "JanDeDobbeleer/oh-my-posh",
    "AssetRegex":  "install-amd64\\.exe$",
    "Url":  "https://ohmyposh.dev/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=ohmyposh.dev\u0026sz=128",
    "IDn":  75
  },
  {
    "ID":  "Fastfetch-cli.Fastfetch",
    "Name":  "Fastfetch",
    "Domain":  "github.com/fastfetch-cli/fastfetch",
    "Aliases":  [
            "Fastfetch",
            "Fastfetch-cli.Fastfetch"
          ],
    "Category":  "Development",
    "Url":  "https://github.com/fastfetch-cli/fastfetch",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=github.com\u0026sz=128",
    "IDn":  76
  },
  {
    "ID":  "Docker.DockerDesktop",
    "Name":  "Docker Desktop",
    "Domain":  "docker.com",
    "Aliases":  [
            "Docker Desktop",
            "Docker",
            "Docker.DockerDesktop"
          ],
    "Category":  "Database \u0026 DevOps",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/docker.png",
    "IDn":  77
  },
  {
    "ID":  "Postman.Postman",
    "Name":  "Postman",
    "Domain":  "postman.com",
    "Aliases":  [
            "Postman",
            "Postman.Postman"
          ],
    "Category":  "Database \u0026 DevOps",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/postman.png",
    "IDn":  78
  },
  {
    "ID":  "DBeaver.DBeaver.Community",
    "Name":  "DBeaver CE",
    "Domain":  "dbeaver.io",
    "Aliases":  [
            "DBeaver",
            "DBeaver CE",
            "DBeaver Community",
            "DBeaver.DBeaver.Community"
          ],
    "Category":  "Database \u0026 DevOps",
    "IconUrl":  "https://raw.githubusercontent.com/dbeaver/dbeaver/devel/plugins/org.jkiss.dbeaver.ui.app.standalone/icons/dbeaver256.png",
    "IDn":  79
  },
  {
    "ID":  "Microsoft.WSL",
    "Name":  "WSL (Linux Subsystem)",
    "Domain":  "learn.microsoft.com/windows/wsl",
    "Aliases":  [
            "Windows Subsystem for Linux",
            "Microsoft.WSL"
          ],
    "Category":  "Database \u0026 DevOps",
    "Url":  "https://learn.microsoft.com/windows/wsl/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/tux.png",
    "IDn":  80
  },
  {
    "ID":  "Oracle.VirtualBox",
    "Name":  "Oracle VirtualBox",
    "Domain":  "virtualbox.org",
    "Aliases":  [
            "Oracle VirtualBox",
            "Oracle VM VirtualBox",
            "Oracle.VirtualBox"
          ],
    "Category":  "Database \u0026 DevOps",
    "Url":  "https://www.virtualbox.org/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/virtualbox.png",
    "IDn":  81
  },
  {
    "ID":  "Bruno.Bruno",
    "Name":  "Bruno (API Client)",
    "Domain":  "usebruno.com",
    "Aliases":  [
            "Bruno",
            "Bruno.Bruno"
          ],
    "Category":  "Database \u0026 DevOps",
    "GitHubRepo":  "usebruno/bruno",
    "AssetRegex":  "x64_win\\.exe$",
    "Url":  "https://www.usebruno.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=usebruno.com\u0026sz=128",
    "IDn":  82
  },
  {
    "ID":  "HeidiSQL.HeidiSQL",
    "Name":  "HeidiSQL",
    "Domain":  "heidisql.com",
    "Aliases":  [
            "HeidiSQL",
            "HeidiSQL.HeidiSQL"
          ],
    "Category":  "Database \u0026 DevOps",
    "Url":  "https://www.heidisql.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=heidisql.com\u0026sz=128",
    "IDn":  83
  },
  {
    "ID":  "MongoDB.Compass.Full",
    "Name":  "MongoDB Compass",
    "Domain":  "mongodb.com",
    "Aliases":  [
            "MongoDB Compass",
            "MongoDB.Compass.Full"
          ],
    "Category":  "Database \u0026 DevOps",
    "Url":  "https://www.mongodb.com/products/tools/compass",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/mongodb.png",
    "IDn":  84
  },
  {
    "ID":  "PostgreSQL.pgAdmin",
    "Name":  "pgAdmin 4",
    "Domain":  "pgadmin.org",
    "Aliases":  [
            "pgAdmin 4",
            "PostgreSQL.pgAdmin"
          ],
    "Category":  "Database \u0026 DevOps",
    "Url":  "https://www.pgadmin.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=pgadmin.org\u0026sz=128",
    "IDn":  85
  },
  {
    "ID":  "RedisInsight.RedisInsight",
    "Name":  "Redis Insight",
    "Domain":  "redis.io",
    "Aliases":  [
            "Redis Insight",
            "RedisInsight",
            "RedisInsight.RedisInsight"
          ],
    "Category":  "Database \u0026 DevOps",
    "Url":  "https://redis.io/insight/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/redis.png",
    "IDn":  86
  },
  {
    "ID":  "PuTTY.PuTTY",
    "Name":  "PuTTY (SSH/Serial)",
    "Domain":  "chiark.greenend.org.uk",
    "Aliases":  [
            "PuTTY",
            "PuTTY release",
            "PuTTY.PuTTY"
          ],
    "Category":  "Database \u0026 DevOps",
    "Url":  "https://www.chiark.greenend.org.uk/~sgtatham/putty/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=putty.org.ru\u0026sz=128",
    "IDn":  87
  },
  {
    "ID":  "Eugeny.Tabby",
    "Name":  "Tabby Terminal",
    "Domain":  "tabby.sh",
    "Aliases":  [
            "Tabby",
            "Eugeny.Tabby"
          ],
    "Category":  "Database \u0026 DevOps",
    "GitHubRepo":  "Eugeny/tabby",
    "AssetRegex":  "setup-x64\\.exe$",
    "Url":  "https://tabby.sh/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=tabby.sh\u0026sz=128",
    "IDn":  88
  },
  {
    "ID":  "Microsoft.DotNet.Framework.Runtime",
    "Name":  ".NET Framework 4.8.1",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Framework 4.8.1 Runtime",
            "Microsoft .NET Framework Runtime",
            "Microsoft.DotNet.Framework.Runtime"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  89
  },
  {
    "ID":  "Microsoft.DotNet.DesktopRuntime.3_1",
    "Name":  ".NET Desktop Runtime 3.1",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Windows Desktop Runtime 3.1",
            "DesktopRuntime.3_1",
            "Microsoft.DotNet.DesktopRuntime.3_1"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  90
  },
  {
    "ID":  "Microsoft.DotNet.DesktopRuntime.5",
    "Name":  ".NET Desktop Runtime 5.0",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Windows Desktop Runtime 5.0",
            "DesktopRuntime.5",
            "Microsoft.DotNet.DesktopRuntime.5"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  91
  },
  {
    "ID":  "Microsoft.DotNet.DesktopRuntime.6",
    "Name":  ".NET Desktop Runtime 6 (LTS)",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Windows Desktop Runtime 6.0",
            "DesktopRuntime.6",
            "Microsoft.DotNet.DesktopRuntime.6"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  92
  },
  {
    "ID":  "Microsoft.DotNet.DesktopRuntime.6.x86",
    "Name":  ".NET Desktop Runtime 6 (x86)",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Windows Desktop Runtime 6.0 (x86)",
            "Microsoft.DotNet.DesktopRuntime.6.x86"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  93
  },
  {
    "ID":  "Microsoft.DotNet.DesktopRuntime.7",
    "Name":  ".NET Desktop Runtime 7",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Windows Desktop Runtime 7.0",
            "DesktopRuntime.7",
            "Microsoft.DotNet.DesktopRuntime.7"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  94
  },
  {
    "ID":  "Microsoft.DotNet.DesktopRuntime.7.x86",
    "Name":  ".NET Desktop Runtime 7 (x86)",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Windows Desktop Runtime 7.0 (x86)",
            "Microsoft.DotNet.DesktopRuntime.7.x86"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  95
  },
  {
    "ID":  "Microsoft.DotNet.DesktopRuntime.8",
    "Name":  ".NET Desktop Runtime 8 (LTS)",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Windows Desktop Runtime 8.0",
            "DesktopRuntime.8",
            "Microsoft.DotNet.DesktopRuntime.8"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  96
  },
  {
    "ID":  "Microsoft.DotNet.DesktopRuntime.8.x86",
    "Name":  ".NET Desktop Runtime 8 (x86)",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Windows Desktop Runtime 8.0 (x86)",
            "Microsoft.DotNet.DesktopRuntime.8.x86"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  97
  },
  {
    "ID":  "Microsoft.DotNet.DesktopRuntime.9",
    "Name":  ".NET Desktop Runtime 9",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Windows Desktop Runtime 9.0",
            "DesktopRuntime.9",
            "Microsoft.DotNet.DesktopRuntime.9"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  98
  },
  {
    "ID":  "Microsoft.DotNet.DesktopRuntime.10",
    "Name":  ".NET Desktop Runtime 10",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Windows Desktop Runtime 10.0",
            "DesktopRuntime.10",
            "Microsoft.DotNet.DesktopRuntime.10"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  99
  },
  {
    "ID":  "Microsoft.DotNet.DesktopRuntime.Preview",
    "Name":  ".NET Desktop Runtime 11 Preview",
    "Domain":  "dotnet.microsoft.com",
    "Aliases":  [
            "Microsoft .NET Windows Desktop Runtime 11.0 Preview",
            "Microsoft.DotNet.DesktopRuntime.Preview"
          ],
    "Category":  ".NET Runtimes",
    "Url":  "https://dotnet.microsoft.com/en-us/download/dotnet",
    "IconUrl":  "https://raw.githubusercontent.com/dotnet/brand/main/logo/dotnet-logo.png",
    "IDn":  100
  },
  {
    "ID":  "EclipseAdoptium.Temurin.8.JRE",
    "Name":  "Java 8 JRE (LTS)",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JRE with Hotspot 8",
            "Temurin 8 JRE",
            "EclipseAdoptium.Temurin.8.JRE"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  101
  },
  {
    "ID":  "EclipseAdoptium.Temurin.8.JDK",
    "Name":  "Java 8 JDK (LTS)",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 8",
            "Temurin 8",
            "OpenJDK 8",
            "EclipseAdoptium.Temurin.8.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  102
  },
  {
    "ID":  "EclipseAdoptium.Temurin.11.JRE",
    "Name":  "Java 11 JRE (LTS)",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JRE with Hotspot 11",
            "Temurin 11 JRE",
            "EclipseAdoptium.Temurin.11.JRE"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  103
  },
  {
    "ID":  "EclipseAdoptium.Temurin.11.JDK",
    "Name":  "Java 11 JDK (LTS)",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 11",
            "Temurin 11",
            "OpenJDK 11",
            "EclipseAdoptium.Temurin.11.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  104
  },
  {
    "ID":  "EclipseAdoptium.Temurin.16.JDK",
    "Name":  "Java 16 JDK",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 16",
            "Temurin 16",
            "EclipseAdoptium.Temurin.16.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  105
  },
  {
    "ID":  "EclipseAdoptium.Temurin.17.JRE",
    "Name":  "Java 17 JRE (LTS)",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JRE with Hotspot 17",
            "Temurin 17 JRE",
            "EclipseAdoptium.Temurin.17.JRE"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  106
  },
  {
    "ID":  "EclipseAdoptium.Temurin.17.JDK",
    "Name":  "Java 17 JDK (LTS)",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 17",
            "Temurin 17",
            "OpenJDK 17",
            "EclipseAdoptium.Temurin.17.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  107
  },
  {
    "ID":  "EclipseAdoptium.Temurin.18.JDK",
    "Name":  "Java 18 JDK",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 18",
            "Temurin 18",
            "EclipseAdoptium.Temurin.18.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  108
  },
  {
    "ID":  "EclipseAdoptium.Temurin.19.JDK",
    "Name":  "Java 19 JDK",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 19",
            "Temurin 19",
            "EclipseAdoptium.Temurin.19.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  109
  },
  {
    "ID":  "EclipseAdoptium.Temurin.20.JDK",
    "Name":  "Java 20 JDK",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 20",
            "Temurin 20",
            "EclipseAdoptium.Temurin.20.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  110
  },
  {
    "ID":  "EclipseAdoptium.Temurin.21.JRE",
    "Name":  "Java 21 JRE (LTS)",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JRE with Hotspot 21",
            "Temurin 21 JRE",
            "EclipseAdoptium.Temurin.21.JRE"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  111
  },
  {
    "ID":  "EclipseAdoptium.Temurin.21.JDK",
    "Name":  "Java 21 JDK (LTS)",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 21",
            "Temurin 21",
            "OpenJDK 21",
            "EclipseAdoptium.Temurin.21.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  112
  },
  {
    "ID":  "EclipseAdoptium.Temurin.22.JDK",
    "Name":  "Java 22 JDK",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 22",
            "Temurin 22",
            "EclipseAdoptium.Temurin.22.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  113
  },
  {
    "ID":  "EclipseAdoptium.Temurin.23.JDK",
    "Name":  "Java 23 JDK",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 23",
            "Temurin 23",
            "EclipseAdoptium.Temurin.23.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  114
  },
  {
    "ID":  "EclipseAdoptium.Temurin.24.JDK",
    "Name":  "Java 24 JDK",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 24",
            "Temurin 24",
            "EclipseAdoptium.Temurin.24.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  115
  },
  {
    "ID":  "EclipseAdoptium.Temurin.25.JDK",
    "Name":  "Java 25 JDK",
    "Domain":  "adoptium.net",
    "Aliases":  [
            "Eclipse Temurin JDK with Hotspot 25",
            "Temurin 25",
            "EclipseAdoptium.Temurin.25.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://adoptium.net/temurin/releases/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  116
  },
  {
    "ID":  "Oracle.JavaRuntimeEnvironment",
    "Name":  "Oracle Java 8 JRE",
    "Domain":  "java.com",
    "Aliases":  [
            "Java 8",
            "Oracle.JavaRuntimeEnvironment"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://www.java.com/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  117
  },
  {
    "ID":  "Amazon.Corretto.25.JDK",
    "Name":  "Amazon Corretto 25 JDK",
    "Domain":  "aws.amazon.com/corretto",
    "Aliases":  [
            "Amazon Corretto 25",
            "Amazon Corretto (x64)",
            "Amazon.Corretto.25.JDK"
          ],
    "Category":  "Java Runtimes",
    "Url":  "https://aws.amazon.com/corretto/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/java.png",
    "IconBg":  "light",
    "IDn":  118
  },
  {
    "ID":  "Microsoft.VCRedist.2005.x64",
    "Name":  "VC++ 2005 (x64)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ 2005 Redistributable (x64)",
            "Microsoft Visual C++ 2005 Redistributable - x64",
            "Microsoft.VCRedist.2005.x64"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  119
  },
  {
    "ID":  "Microsoft.VCRedist.2005.x86",
    "Name":  "VC++ 2005 (x86)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ 2005 Redistributable (x86)",
            "Microsoft Visual C++ 2005 Redistributable - x86",
            "Microsoft.VCRedist.2005.x86"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  120
  },
  {
    "ID":  "Microsoft.VCRedist.2008.x64",
    "Name":  "VC++ 2008 (x64)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ 2008 Redistributable - x64",
            "Microsoft Visual C++ 2008 Redistributable (x64)",
            "Microsoft.VCRedist.2008.x64"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  121
  },
  {
    "ID":  "Microsoft.VCRedist.2008.x86",
    "Name":  "VC++ 2008 (x86)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ 2008 Redistributable - x86",
            "Microsoft Visual C++ 2008 Redistributable (x86)",
            "Microsoft.VCRedist.2008.x86"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  122
  },
  {
    "ID":  "Microsoft.VCRedist.2010.x64",
    "Name":  "VC++ 2010 (x64)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ 2010 x64 Redistributable",
            "Microsoft Visual C++ 2010 Redistributable - x64",
            "Microsoft Visual C++ 2010 Redistributable (x64)",
            "Microsoft.VCRedist.2010.x64"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  123
  },
  {
    "ID":  "Microsoft.VCRedist.2010.x86",
    "Name":  "VC++ 2010 (x86)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ 2010 x86 Redistributable",
            "Microsoft Visual C++ 2010 Redistributable - x86",
            "Microsoft Visual C++ 2010 Redistributable (x86)",
            "Microsoft.VCRedist.2010.x86"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  124
  },
  {
    "ID":  "Microsoft.VCRedist.2012.x64",
    "Name":  "VC++ 2012 (x64)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ 2012 Redistributable (x64)",
            "Microsoft Visual C++ 2012 Redistributable - x64",
            "Microsoft.VCRedist.2012.x64"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  125
  },
  {
    "ID":  "Microsoft.VCRedist.2012.x86",
    "Name":  "VC++ 2012 (x86)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ 2012 Redistributable (x86)",
            "Microsoft Visual C++ 2012 Redistributable - x86",
            "Microsoft.VCRedist.2012.x86"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  126
  },
  {
    "ID":  "Microsoft.VCRedist.2013.x64",
    "Name":  "VC++ 2013 (x64)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ 2013 Redistributable (x64)",
            "Microsoft Visual C++ 2013 Redistributable - x64",
            "Microsoft.VCRedist.2013.x64"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  127
  },
  {
    "ID":  "Microsoft.VCRedist.2013.x86",
    "Name":  "VC++ 2013 (x86)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ 2013 Redistributable (x86)",
            "Microsoft Visual C++ 2013 Redistributable - x86",
            "Microsoft.VCRedist.2013.x86"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  128
  },
  {
    "ID":  "Microsoft.VCRedist.2015+.x64",
    "Name":  "VC++ 2015-2026 (x64)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ v14 Redistributable (x64)",
            "Microsoft Visual C++ 2015-2022 Redistributable (x64)",
            "Microsoft.VCRedist.2015+.x64"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  129
  },
  {
    "ID":  "Microsoft.VCRedist.2015+.x86",
    "Name":  "VC++ 2015-2026 (x86)",
    "Domain":  "visualstudio.microsoft.com",
    "Aliases":  [
            "Microsoft Visual C++ v14 Redistributable (x86)",
            "Microsoft Visual C++ 2015-2022 Redistributable (x86)",
            "Microsoft.VCRedist.2015+.x86"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist",
    "IconUrl":  "https://img.icons8.com/fluency/96/visual-studio.png",
    "IDn":  130
  },
  {
    "ID":  "Microsoft.DirectX",
    "Name":  "DirectX End-User",
    "Domain":  "microsoft.com",
    "Aliases":  [
            "DirectX",
            "Microsoft DirectX",
            "DirectX End-User Runtimes",
            "Microsoft.DirectX"
          ],
    "Category":  "C++ \u0026 System Runtimes",
    "Url":  "https://www.microsoft.com/en-us/download/details.aspx?id=35",
    "IDn":  131
  },
  {
    "ID":  "7zip.7zip",
    "Name":  "7-Zip",
    "Domain":  "7-zip.org",
    "Aliases":  [
            "7-Zip",
            "7zip.7zip"
          ],
    "Category":  "System Utilities",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/7zip.png",
    "IDn":  132
  },
  {
    "ID":  "RARLab.WinRAR",
    "Name":  "WinRAR",
    "Domain":  "win-rar.com",
    "Aliases":  [
            "WinRAR",
            "RARLab.WinRAR"
          ],
    "Category":  "System Utilities",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=win-rar.com\u0026sz=128",
    "IDn":  133
  },
  {
    "ID":  "voidtools.Everything",
    "Name":  "Everything",
    "Domain":  "voidtools.com",
    "Aliases":  [
            "Everything",
            "voidtools.Everything"
          ],
    "Category":  "System Utilities",
    "IDn":  134
  },
  {
    "ID":  "Microsoft.PowerToys",
    "Name":  "PowerToys",
    "Domain":  "learn.microsoft.com",
    "Aliases":  [
            "PowerToys",
            "Microsoft PowerToys",
            "Microsoft.PowerToys"
          ],
    "IconUrl":  "https://raw.githubusercontent.com/microsoft/PowerToys/main/src/settings-ui/Settings.UI/Assets/Settings/logo44.png",
    "Category":  "System Utilities",
    "Url":  "https://learn.microsoft.com/en-us/windows/powertoys/",
    "IDn":  135
  },
  {
    "ID":  "Flow-Launcher.Flow-Launcher",
    "Name":  "Flow Launcher",
    "Domain":  "flowlauncher.com",
    "Aliases":  [
            "Flow Launcher",
            "Flow-Launcher.Flow-Launcher"
          ],
    "Category":  "System Utilities",
    "IconUrl":  "https://raw.githubusercontent.com/Flow-Launcher/Flow.Launcher/dev/Flow.Launcher/Images/app.png",
    "IDn":  136
  },
  {
    "ID":  "RevoUninstaller.RevoUninstaller",
    "Name":  "Revo Uninstaller",
    "Domain":  "revouninstaller.com",
    "Aliases":  [
            "Revo Uninstaller",
            "Revo Uninstaller Free",
            "RevoUninstaller.RevoUninstaller"
          ],
    "Category":  "System Utilities",
    "Url":  "https://www.revouninstaller.com/products/revo-uninstaller-free/",
    "IDn":  137
  },
  {
    "ID":  "JAMSoftware.TreeSize.Free",
    "Name":  "TreeSize Free",
    "Domain":  "jam-software.com",
    "Aliases":  [
            "TreeSize Free",
            "JAMSoftware.TreeSize.Free"
          ],
    "Category":  "System Utilities",
    "Url":  "https://www.jam-software.com/treesize-free",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/treesize.png",
    "IDn":  138
  },
  {
    "ID":  "BleachBit.BleachBit",
    "Name":  "BleachBit",
    "Domain":  "bleachbit.org",
    "Aliases":  [
            "BleachBit",
            "BleachBit.BleachBit"
          ],
    "Category":  "System Utilities",
    "IDn":  139
  },
  {
    "ID":  "UniKey.UniKey",
    "Name":  "UniKey",
    "Domain":  "unikey.org",
    "Aliases":  [
            "UniKey",
            "UniKey.UniKey"
          ],
    "Category":  "System Utilities",
    "Url":  "https://www.unikey.org/",
    "IconUrl":  "https://img.icons8.com/fluency/96/keyboard.png",
    "IDn":  140
  },
  {
    "ID":  "M2Team.NanaZip",
    "Name":  "NanaZip",
    "Domain":  "github.com/M2Team/NanaZip",
    "Aliases":  [
            "NanaZip",
            "M2Team.NanaZip"
          ],
    "Category":  "System Utilities",
    "Url":  "https://github.com/M2Team/NanaZip",
    "IconUrl":  "https://avatars.githubusercontent.com/u/86552972?s=128\u0026v=4",
    "IDn":  141
  },
  {
    "ID":  "AntibodySoftware.WizTree",
    "Name":  "WizTree",
    "Domain":  "diskanalyzer.com",
    "Aliases":  [
            "WizTree",
            "AntibodySoftware.WizTree"
          ],
    "Category":  "System Utilities",
    "Url":  "https://diskanalyzer.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=diskanalyzer.com\u0026sz=128",
    "IDn":  142
  },
  {
    "ID":  "Klocman.BulkCrapUninstaller",
    "Name":  "BCUninstaller",
    "Domain":  "bcuninstaller.com",
    "Aliases":  [
            "BCUninstaller",
            "Bulk Crap Uninstaller",
            "Klocman.BulkCrapUninstaller"
          ],
    "Category":  "System Utilities",
    "Url":  "https://www.bcuninstaller.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=bcuninstaller.com\u0026sz=128",
    "IDn":  143
  },
  {
    "ID":  "CharlesMilette.TranslucentTB",
    "Name":  "TranslucentTB",
    "Domain":  "github.com/TranslucentTB",
    "Aliases":  [
            "TranslucentTB",
            "CharlesMilette.TranslucentTB"
          ],
    "Category":  "System Utilities",
    "Url":  "https://github.com/TranslucentTB/TranslucentTB",
    "IconUrl":  "https://avatars.githubusercontent.com/u/25596512?s=128\u0026v=4",
    "IDn":  144
  },
  {
    "ID":  "RamenSoftware.Windhawk",
    "Name":  "Windhawk",
    "Domain":  "windhawk.net",
    "Aliases":  [
            "Windhawk",
            "RamenSoftware.Windhawk"
          ],
    "Category":  "System Utilities",
    "Url":  "https://windhawk.net/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=windhawk.net\u0026sz=128",
    "IDn":  145
  },
  {
    "ID":  "Rufus.Rufus",
    "Name":  "Rufus",
    "Domain":  "rufus.ie",
    "Aliases":  [
            "Rufus",
            "Rufus.Rufus"
          ],
    "Category":  "System Utilities",
    "Url":  "https://rufus.ie/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=rufus.ie\u0026sz=128",
    "IDn":  146
  },
  {
    "ID":  "WinsiderSS.SystemInformer",
    "Name":  "System Informer",
    "Domain":  "systeminformer.sourceforge.io",
    "Aliases":  [
            "System Informer",
            "Process Hacker",
            "WinsiderSS.SystemInformer"
          ],
    "Category":  "System Utilities",
    "Url":  "https://systeminformer.sourceforge.io/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=systeminformer.sourceforge.io\u0026sz=128",
    "IDn":  147
  },
  {
    "ID":  "Microsoft.Sysinternals.Autoruns",
    "Name":  "Autoruns (Sysinternals)",
    "Domain":  "learn.microsoft.com",
    "Aliases":  [
            "Sysinternals Autoruns",
            "Autoruns",
            "Microsoft.Sysinternals.Autoruns"
          ],
    "Category":  "System Utilities",
    "Url":  "https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=microsoft.com\u0026sz=128",
    "IDn":  148
  },
  {
    "ID":  "Microsoft.Sysinternals.ProcessExplorer",
    "Name":  "Process Explorer",
    "Domain":  "learn.microsoft.com",
    "Aliases":  [
            "Sysinternals Process Explorer",
            "Process Explorer",
            "Microsoft.Sysinternals.ProcessExplorer"
          ],
    "Category":  "System Utilities",
    "Url":  "https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=microsoft.com\u0026sz=128",
    "IDn":  149
  },
  {
    "ID":  "Ventoy.Ventoy",
    "Name":  "Ventoy (Multi-ISO USB)",
    "Domain":  "ventoy.net",
    "Aliases":  [
            "Ventoy",
            "Ventoy.Ventoy"
          ],
    "Category":  "System Utilities",
    "Url":  "https://www.ventoy.net/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=ventoy.net\u0026sz=128",
    "IDn":  150
  },
  {
    "ID":  "File-New-Project.EarTrumpet",
    "Name":  "EarTrumpet",
    "Domain":  "eartrumpet.app",
    "Aliases":  [
            "EarTrumpet",
            "File-New-Project.EarTrumpet"
          ],
    "Category":  "System Utilities",
    "Url":  "https://eartrumpet.app/",
    "IconUrl":  "https://avatars.githubusercontent.com/u/11562010?s=128\u0026v=4",
    "IDn":  151
  },
  {
    "ID":  "xanderfrangos.twinkletray",
    "Name":  "Twinkle Tray",
    "Domain":  "twinkletray.com",
    "Aliases":  [
            "Twinkle Tray",
            "xanderfrangos.twinkletray"
          ],
    "Category":  "System Utilities",
    "GitHubRepo":  "xanderfrangos/twinkle-tray",
    "AssetRegex":  "Twinkle\\.Tray\\.v[0-9.]+\\.exe$",
    "Url":  "https://twinkletray.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=twinkletray.com\u0026sz=128",
    "IDn":  152
  },
  {
    "ID":  "AutoHotkey.AutoHotkey",
    "Name":  "AutoHotkey v2",
    "Domain":  "autohotkey.com",
    "Aliases":  [
            "AutoHotkey",
            "AutoHotkey.AutoHotkey"
          ],
    "Category":  "System Utilities",
    "GitHubRepo":  "AutoHotkey/AutoHotkey",
    "AssetRegex":  "AutoHotkey_[0-9.]+_setup\\.exe$",
    "Url":  "https://www.autohotkey.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=autohotkey.com\u0026sz=128",
    "IDn":  153
  },
  {
    "ID":  "Nilesoft.Shell",
    "Name":  "Nilesoft Shell",
    "Domain":  "nilesoft.org",
    "Aliases":  [
            "Nilesoft Shell",
            "Nilesoft.Shell"
          ],
    "Category":  "System Utilities",
    "Url":  "https://nilesoft.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=nilesoft.org\u0026sz=128",
    "IDn":  154
  },
  {
    "ID":  "FilesCommunity.Files",
    "Name":  "Files App",
    "Domain":  "files.community",
    "Aliases":  [
            "Files",
            "Files App",
            "FilesCommunity.Files"
          ],
    "Category":  "System Utilities",
    "Url":  "https://files.community/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=files.community\u0026sz=128",
    "IDn":  155
  },
  {
    "ID":  "srwi.EverythingToolbar.Launcher",
    "Name":  "EverythingToolbar",
    "Domain":  "github.com/srwi/EverythingToolbar",
    "Aliases":  [
            "EverythingToolbar",
            "srwi.EverythingToolbar.Launcher",
            "srwi.EverythingToolbar.Deskband"
          ],
    "Category":  "System Utilities",
    "GitHubRepo":  "srwi/EverythingToolbar",
    "AssetRegex":  "\\.msi$",
    "Url":  "https://github.com/srwi/EverythingToolbar",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=voidtools.com\u0026sz=128",
    "IDn":  156
  },
  {
    "ID":  "QL-Win.QuickLook",
    "Name":  "QuickLook (Space Preview)",
    "Domain":  "github.com/QL-Win/QuickLook",
    "Aliases":  [
            "QuickLook",
            "QL-Win.QuickLook"
          ],
    "Category":  "System Utilities",
    "GitHubRepo":  "QL-Win/QuickLook",
    "AssetRegex":  "QuickLook-[0-9.]+\\.msi$",
    "Url":  "https://github.com/QL-Win/QuickLook",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=github.com\u0026sz=128",
    "IDn":  157
  },
  {
    "ID":  "Ditto.Ditto",
    "Name":  "Ditto Clipboard",
    "Domain":  "ditto-cp.sourceforge.io",
    "Aliases":  [
            "Ditto",
            "Ditto Clipboard",
            "Ditto.Ditto"
          ],
    "Category":  "System Utilities",
    "Url":  "https://ditto-cp.sourceforge.io/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=sourceforge.net\u0026sz=128",
    "IDn":  158
  },
  {
    "ID":  "Henry++.MemReduct",
    "Name":  "Mem Reduct",
    "Domain":  "henrypp.org",
    "Aliases":  [
            "Mem Reduct",
            "Henry++.MemReduct"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://www.henrypp.org/product/memreduct",
    "IconUrl":  "https://avatars.githubusercontent.com/u/1976542?s=128\u0026v=4",
    "IDn":  159
  },
  {
    "ID":  "BitSum.ProcessLasso",
    "Name":  "Process Lasso",
    "Domain":  "bitsum.com",
    "Aliases":  [
            "Process Lasso",
            "BitSum.ProcessLasso"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://bitsum.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=bitsum.com\u0026sz=128",
    "IDn":  160
  },
  {
    "ID":  "BitSum.ParkControl",
    "Name":  "ParkControl (CPU Unpark)",
    "Domain":  "bitsum.com",
    "Aliases":  [
            "ParkControl",
            "BitSum.ParkControl"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://bitsum.com/parkcontrol/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=bitsum.com\u0026sz=128",
    "IDn":  161
  },
  {
    "ID":  "CoderBag.QuickCPUx64",
    "Name":  "Quick CPU",
    "Domain":  "coderbag.com",
    "Aliases":  [
            "Quick CPU",
            "QuickCPU",
            "CoderBag.QuickCPUx64"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://coderbag.com/product/quickcpu",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=coderbag.com\u0026sz=128",
    "IDn":  162
  },
  {
    "ID":  "TechPowerUp.ThrottleStop",
    "Name":  "ThrottleStop",
    "Domain":  "techpowerup.com",
    "Aliases":  [
            "ThrottleStop",
            "TechPowerUp.ThrottleStop"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://www.techpowerup.com/download/techpowerup-throttlestop/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=techpowerup.com\u0026sz=128",
    "IDn":  163
  },
  {
    "ID":  "JamesCJ60.Universalx86TuningUtility",
    "Name":  "Universal x86 Tuning (UXTU)",
    "Domain":  "amdaputuningutility.com",
    "Aliases":  [
            "Universal x86 Tuning Utility",
            "UXTU",
            "JamesCJ60.Universalx86TuningUtility"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://amdaputuningutility.com/",
    "IconUrl":  "https://avatars.githubusercontent.com/u/105427589?s=128\u0026v=4",
    "IDn":  164
  },
  {
    "ID":  "Microsoft.Sysinternals.RAMMap",
    "Name":  "RAMMap (Empty Standby)",
    "Domain":  "learn.microsoft.com",
    "Aliases":  [
            "RAMMap",
            "Microsoft.Sysinternals.RAMMap"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://learn.microsoft.com/en-us/sysinternals/downloads/rammap",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=learn.microsoft.com\u0026sz=128",
    "IDn":  165
  },
  {
    "ID":  "OO-Software.ShutUp10",
    "Name":  "O\u0026O ShutUp10++",
    "Domain":  "oo-software.com",
    "Aliases":  [
            "O\u0026O ShutUp10++",
            "O\u0026O ShutUp10",
            "OO-Software.ShutUp10"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://www.oo-software.com/en/shutup10",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=oo-software.com\u0026sz=128",
    "IDn":  166
  },
  {
    "ID":  "9PM860492SZD",
    "Name":  "Microsoft PC Manager",
    "Domain":  "pcmanager.microsoft.com",
    "Aliases":  [
            "Microsoft PC Manager",
            "PC Manager",
            "9PM860492SZD"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Source":  "msstore",
    "Url":  "https://pcmanager.microsoft.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=pcmanager.microsoft.com\u0026sz=128",
    "IDn":  167
  },
  {
    "ID":  "IridiumIO.CompactGUI",
    "Name":  "CompactGUI (Nén Game)",
    "Domain":  "github.com/IridiumIO/CompactGUI",
    "Aliases":  [
            "CompactGUI",
            "IridiumIO.CompactGUI"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://github.com/IridiumIO/CompactGUI",
    "IconUrl":  "https://avatars.githubusercontent.com/u/14960348?s=128\u0026v=4",
    "IDn":  168
  },
  {
    "ID":  "Blinue.Magpie",
    "Name":  "Magpie (FSR Upscaler)",
    "Domain":  "github.com/Blinue/Magpie",
    "Aliases":  [
            "Magpie",
            "Blinue.Magpie"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://github.com/Blinue/Magpie",
    "IconUrl":  "https://avatars.githubusercontent.com/u/34770031?s=128\u0026v=4",
    "IDn":  169
  },
  {
    "ID":  "Orbmu2k.nvidiaProfileInspector",
    "Name":  "NVIDIA Profile Inspector",
    "Domain":  "github.com/Orbmu2k/nvidiaProfileInspector",
    "Aliases":  [
            "NVIDIA Profile Inspector",
            "nvidiaProfileInspector",
            "Orbmu2k.nvidiaProfileInspector"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://github.com/Orbmu2k/nvidiaProfileInspector",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=nvidia.com\u0026sz=128",
    "IDn":  170
  },
  {
    "ID":  "seerge.g-helper",
    "Name":  "G-Helper (ASUS ROG/TUF)",
    "Domain":  "g-helper.com",
    "Aliases":  [
            "G-Helper",
            "g-helper",
            "seerge.g-helper"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://g-helper.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=g-helper.com\u0026sz=128",
    "IDn":  171
  },
  {
    "ID":  "LenovoLegionToolkitTeam.LenovoLegionToolkit",
    "Name":  "Lenovo Legion Toolkit",
    "Domain":  "github.com/BartoszCichecki/LenovoLegionToolkit",
    "Aliases":  [
            "Lenovo Legion Toolkit",
            "LenovoLegionToolkitTeam.LenovoLegionToolkit",
            "BartoszCichecki.LenovoLegionToolkit"
          ],
    "Category":  "Optimization \u0026 Tuning",
    "Url":  "https://github.com/BartoszCichecki/LenovoLegionToolkit",
    "IconUrl":  "https://avatars.githubusercontent.com/u/197661095?s=128\u0026v=4",
    "IDn":  172
  },
  {
    "ID":  "Guru3D.Afterburner",
    "Name":  "MSI Afterburner",
    "Domain":  "msi.com",
    "Aliases":  [
            "MSI Afterburner",
            "Afterburner",
            "Guru3D.Afterburner"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://www.msi.com/Landing/afterburner/graphics-cards",
    "IconUrl":  "https://img.icons8.com/fluency/96/msi-afterburner.png",
    "IDn":  173
  },
  {
    "ID":  "Rem0o.FanControl",
    "Name":  "FanControl",
    "Domain":  "getfancontrol.com",
    "Aliases":  [
            "FanControl",
            "Fan Control",
            "Rem0o.FanControl"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "IDn":  174
  },
  {
    "ID":  "CPUID.CPU-Z",
    "Name":  "CPU-Z",
    "Domain":  "cpuid.com",
    "Aliases":  [
            "CPUID CPU-Z",
            "CPU-Z",
            "CPUID.CPU-Z"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://www.cpuid.com/softwares/cpu-z.html",
    "IconUrl":  "https://www.cpuid.com/medias/images/softwares/cpu-z.png",
    "IDn":  175
  },
  {
    "ID":  "CPUID.HWMonitor",
    "Name":  "HWMonitor",
    "Domain":  "cpuid.com",
    "Aliases":  [
            "CPUID HWMonitor",
            "HWMonitor",
            "CPUID.HWMonitor"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://www.cpuid.com/softwares/hwmonitor.html",
    "IconUrl":  "https://www.cpuid.com/medias/images/softwares/hwmonitor.png",
    "IDn":  176
  },
  {
    "ID":  "TechPowerUp.GPU-Z",
    "Name":  "TechPowerUp GPU-Z",
    "Domain":  "techpowerup.com",
    "Aliases":  [
            "TechPowerUp GPU-Z",
            "GPU-Z",
            "TechPowerUp.GPU-Z"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://www.techpowerup.com/gpuz/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=techpowerup.com\u0026sz=128",
    "IDn":  177
  },
  {
    "ID":  "REALiX.HWiNFO",
    "Name":  "HWiNFO",
    "Domain":  "hwinfo.com",
    "Aliases":  [
            "HWiNFO",
            "HWiNFO64",
            "REALiX.HWiNFO"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://www.hwinfo.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=hwinfo.com\u0026sz=128",
    "IDn":  178
  },
  {
    "ID":  "CrystalDewWorld.CrystalDiskInfo",
    "Name":  "CrystalDiskInfo",
    "Domain":  "crystalmark.info",
    "Aliases":  [
            "CrystalDiskInfo",
            "CrystalDewWorld.CrystalDiskInfo"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://crystalmark.info/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=crystalmark.info\u0026sz=128",
    "IDn":  179
  },
  {
    "ID":  "TechPowerUp.NVCleanstall",
    "Name":  "NVCleanstall",
    "Domain":  "techpowerup.com",
    "Aliases":  [
            "NVCleanstall",
            "TechPowerUp.NVCleanstall"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://www.techpowerup.com/nvcleanstall/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=techpowerup.com\u0026sz=128",
    "IDn":  180
  },
  {
    "ID":  "Wagnardsoft.DisplayDriverUninstaller",
    "Name":  "Display Driver Uninstaller (DDU)",
    "Domain":  "wagnardsoft.com",
    "Aliases":  [
            "Display Driver Uninstaller",
            "DDU",
            "Wagnardsoft.DisplayDriverUninstaller"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://www.wagnardsoft.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=wagnardsoft.com\u0026sz=128",
    "IDn":  181
  },
  {
    "ID":  "OpenRGB.OpenRGB",
    "Name":  "OpenRGB",
    "Domain":  "openrgb.org",
    "Aliases":  [
            "OpenRGB",
            "OpenRGB.OpenRGB"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://openrgb.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=openrgb.org\u0026sz=128",
    "IDn":  182
  },
  {
    "ID":  "Logitech.GHUB",
    "Name":  "Logitech G HUB",
    "Domain":  "logitechg.com",
    "Aliases":  [
            "Logitech G HUB",
            "LGHUB",
            "Logitech.GHUB"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://www.logitechg.com/en-us/innovation/g-hub.html",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=logitechg.com\u0026sz=128",
    "IDn":  183
  },
  {
    "ID":  "Logitech.OptionsPlus",
    "Name":  "Logitech Options+",
    "Domain":  "logitech.com",
    "Aliases":  [
            "Logi Options+",
            "Logitech Options+",
            "Logitech.OptionsPlus"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://www.logitech.com/en-us/software/logi-options-plus.html",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=logitech.com\u0026sz=128",
    "IDn":  184
  },
  {
    "ID":  "Intel.IntelDriverAndSupportAssistant",
    "Name":  "Intel Driver \u0026 Support",
    "Domain":  "intel.com",
    "Aliases":  [
            "Intel Driver \u0026 Support Assistant",
            "Intel.IntelDriverAndSupportAssistant"
          ],
    "Category":  "Hardware \u0026 Monitoring",
    "Url":  "https://www.intel.com/content/www/us/en/support/detect.html",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=intel.com\u0026sz=128",
    "IDn":  185
  },
  {
    "ID":  "CrystalDewWorld.CrystalDiskMark",
    "Name":  "CrystalDiskMark",
    "Domain":  "crystalmark.info",
    "Aliases":  [
            "CrystalDiskMark",
            "CrystalDewWorld.CrystalDiskMark"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://crystalmark.info/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=crystalmark.info\u0026sz=128",
    "IDn":  186
  },
  {
    "ID":  "OCBase.OCCT.Personal",
    "Name":  "OCCT (Stress Test)",
    "Domain":  "ocbase.com",
    "Aliases":  [
            "OCCT",
            "OCBase.OCCT.Personal"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://www.ocbase.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=ocbase.com\u0026sz=128",
    "IDn":  187
  },
  {
    "ID":  "Geeks3D.FurMark.2",
    "Name":  "FurMark 2 (GPU Test)",
    "Domain":  "geeks3d.com",
    "Aliases":  [
            "FurMark 2",
            "FurMark",
            "Geeks3D.FurMark.2"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://geeks3d.com/furmark/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=geeks3d.com\u0026sz=128",
    "IDn":  188
  },
  {
    "ID":  "Maxon.CinebenchR23",
    "Name":  "Cinebench R23 (CPU Test)",
    "Domain":  "maxon.net",
    "Aliases":  [
            "Cinebench R23",
            "Cinebench",
            "Maxon.CinebenchR23"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://www.maxon.net/en/cinebench",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=maxon.net\u0026sz=128",
    "IDn":  189
  },
  {
    "ID":  "PrimateLabs.Geekbench.6",
    "Name":  "Geekbench 6 (CPU/GPU)",
    "Domain":  "geekbench.com",
    "Aliases":  [
            "Geekbench 6",
            "Geekbench",
            "PrimateLabs.Geekbench.6"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://www.geekbench.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=primatelabs.com\u0026sz=128",
    "IDn":  190
  },
  {
    "ID":  "Unigine.SuperpositionBenchmark",
    "Name":  "Unigine Superposition (GPU)",
    "Domain":  "benchmark.unigine.com",
    "Aliases":  [
            "Unigine Superposition Benchmark",
            "Superposition",
            "Unigine.SuperpositionBenchmark"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://benchmark.unigine.com/superposition",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=benchmark.unigine.com\u0026sz=128",
    "IDn":  191
  },
  {
    "ID":  "FinalWire.AIDA64.Extreme",
    "Name":  "AIDA64 Extreme",
    "Domain":  "aida64.com",
    "Aliases":  [
            "AIDA64 Extreme",
            "AIDA64",
            "FinalWire.AIDA64.Extreme"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://www.aida64.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=aida64.com\u0026sz=128",
    "IDn":  192
  },
  {
    "ID":  "Guru3D.RTSS",
    "Name":  "RivaTuner (RTSS OSD)",
    "Domain":  "guru3d.com",
    "Aliases":  [
            "Rivatuner Statistics Server",
            "RTSS",
            "Guru3D.RTSS"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://www.guru3d.com/download/rtss-rivatuner-statistics-server-download/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=guru3d.com\u0026sz=128",
    "IDn":  193
  },
  {
    "ID":  "CXWorld.CapFrameX",
    "Name":  "CapFrameX (FPS Benchmark)",
    "Domain":  "capframex.com",
    "Aliases":  [
            "CapFrameX",
            "CapFrameX Capture and Analysis Tool",
            "CXWorld.CapFrameX"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://www.capframex.com/",
    "IconUrl":  "https://avatars.githubusercontent.com/u/47972546?s=128\u0026v=4",
    "IDn":  194
  },
  {
    "ID":  "Resplendence.LatencyMon",
    "Name":  "LatencyMon (DPC Latency)",
    "Domain":  "resplendence.com",
    "Aliases":  [
            "LatencyMon",
            "Resplendence.LatencyMon"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://www.resplendence.com/latencymon",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=resplendence.com\u0026sz=128",
    "IDn":  195
  },
  {
    "ID":  "NirSoft.BlueScreenView",
    "Name":  "BlueScreenView (BSOD)",
    "Domain":  "nirsoft.net",
    "Aliases":  [
            "BlueScreenView",
            "NirSoft.BlueScreenView"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://www.nirsoft.net/utils/blue_screen_view.html",
    "IconUrl":  "https://img.icons8.com/fluency/96/system-report.png",
    "IDn":  196
  },
  {
    "ID":  "Resplendence.WhoCrashed",
    "Name":  "WhoCrashed (Crash Test)",
    "Domain":  "resplendence.com",
    "Aliases":  [
            "WhoCrashed",
            "WhoCrashed Home Edition",
            "Resplendence.WhoCrashed"
          ],
    "Category":  "Benchmark \u0026 Stress Test",
    "Url":  "https://www.resplendence.com/whocrashed",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=resplendence.com\u0026sz=128",
    "IDn":  197
  },
  {
    "ID":  "Bitwarden.Bitwarden",
    "Name":  "Bitwarden",
    "Domain":  "bitwarden.com",
    "Aliases":  [
            "Bitwarden",
            "Bitwarden.Bitwarden"
          ],
    "Category":  "Security \u0026 Network",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/bitwarden.png",
    "IDn":  198
  },
  {
    "ID":  "KeePassXCTeam.KeePassXC",
    "Name":  "KeePassXC",
    "Domain":  "keepassxc.org",
    "Aliases":  [
            "KeePassXC",
            "KeePassXCTeam.KeePassXC"
          ],
    "Category":  "Security \u0026 Network",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/keepassxc.png",
    "IDn":  199
  },
  {
    "ID":  "Cryptomator.Cryptomator",
    "Name":  "Cryptomator",
    "Domain":  "cryptomator.org",
    "Aliases":  [
            "Cryptomator",
            "Cryptomator.Cryptomator"
          ],
    "Category":  "Security \u0026 Network",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/cryptomator.png",
    "IDn":  200
  },
  {
    "ID":  "Proton.ProtonVPN",
    "Name":  "Proton VPN",
    "Domain":  "protonvpn.com",
    "Aliases":  [
            "Proton VPN",
            "ProtonVPN",
            "Proton.ProtonVPN"
          ],
    "Category":  "Security \u0026 Network",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/proton-vpn.png",
    "IDn":  201
  },
  {
    "ID":  "WiresharkFoundation.Wireshark",
    "Name":  "Wireshark",
    "Domain":  "wireshark.org",
    "Aliases":  [
            "Wireshark",
            "WiresharkFoundation.Wireshark"
          ],
    "Category":  "Security \u0026 Network",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/wireshark.png",
    "IDn":  202
  },
  {
    "ID":  "Cloudflare.Warp",
    "Name":  "Cloudflare WARP (1.1.1.1)",
    "Domain":  "one.one.one.one",
    "Aliases":  [
            "Cloudflare WARP",
            "Cloudflare One Client",
            "Cloudflare.Warp"
          ],
    "Category":  "Security \u0026 Network",
    "Url":  "https://one.one.one.one/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/cloudflare.png",
    "IDn":  203
  },
  {
    "ID":  "Tailscale.Tailscale",
    "Name":  "Tailscale",
    "Domain":  "tailscale.com",
    "Aliases":  [
            "Tailscale",
            "Tailscale.Tailscale"
          ],
    "Category":  "Security \u0026 Network",
    "Url":  "https://tailscale.com/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/tailscale-light.png",
    "IDn":  204
  },
  {
    "ID":  "WireGuard.WireGuard",
    "Name":  "WireGuard",
    "Domain":  "wireguard.com",
    "Aliases":  [
            "WireGuard",
            "WireGuard.WireGuard"
          ],
    "Category":  "Security \u0026 Network",
    "Url":  "https://www.wireguard.com/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/wireguard.png",
    "IDn":  205
  },
  {
    "ID":  "ZeroTier.ZeroTierOne",
    "Name":  "ZeroTier One",
    "Domain":  "zerotier.com",
    "Aliases":  [
            "ZeroTier One",
            "ZeroTier.ZeroTierOne"
          ],
    "Category":  "Security \u0026 Network",
    "Url":  "https://www.zerotier.com/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zerotier.png",
    "IDn":  206
  },
  {
    "ID":  "Famatech.RadminVPN",
    "Name":  "Radmin VPN",
    "Domain":  "radmin-vpn.com",
    "Aliases":  [
            "Radmin VPN",
            "Famatech.RadminVPN"
          ],
    "Category":  "Security \u0026 Network",
    "Url":  "https://www.radmin-vpn.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=radmin-vpn.com\u0026sz=128",
    "IDn":  207
  },
  {
    "ID":  "NextDNS.NextDNS",
    "Name":  "NextDNS",
    "Domain":  "nextdns.io",
    "Aliases":  [
            "NextDNS",
            "NextDNS.NextDNS"
          ],
    "Category":  "Security \u0026 Network",
    "Url":  "https://nextdns.io/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/nextdns.png",
    "IDn":  208
  },
  {
    "ID":  "IDRIX.VeraCrypt",
    "Name":  "VeraCrypt",
    "Domain":  "veracrypt.fr",
    "Aliases":  [
            "VeraCrypt",
            "IDRIX.VeraCrypt"
          ],
    "Category":  "Security \u0026 Network",
    "Url":  "https://www.veracrypt.fr/",
    "IconUrl":  "https://avatars.githubusercontent.com/u/8641615?s=128\u0026v=4",
    "IDn":  209
  },
  {
    "ID":  "MullvadVPN.MullvadVPN",
    "Name":  "Mullvad VPN",
    "Domain":  "mullvad.net",
    "Aliases":  [
            "Mullvad VPN",
            "MullvadVPN.MullvadVPN"
          ],
    "Category":  "Security \u0026 Network",
    "Url":  "https://mullvad.net/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/mullvad.png",
    "IDn":  210
  },
  {
    "ID":  "OpenVPNTechnologies.OpenVPNConnect",
    "Name":  "OpenVPN Connect",
    "Domain":  "openvpn.net",
    "Aliases":  [
            "OpenVPN Connect",
            "OpenVPNTechnologies.OpenVPNConnect"
          ],
    "Category":  "Security \u0026 Network",
    "Url":  "https://openvpn.net/client/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/openvpn.png",
    "IDn":  211
  },
  {
    "ID":  "angryziber.AngryIPScanner",
    "Name":  "Angry IP Scanner",
    "Domain":  "angryip.org",
    "Aliases":  [
            "Angry IP Scanner",
            "angryziber.AngryIPScanner"
          ],
    "Category":  "Security \u0026 Network",
    "GitHubRepo":  "angryip/ipscan",
    "AssetRegex":  "win64-[0-9.]+\\.exe$",
    "Url":  "https://angryip.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=angryip.org\u0026sz=128",
    "IDn":  212
  },
  {
    "ID":  "Insecure.Nmap",
    "Name":  "Nmap (Zenmap)",
    "Domain":  "nmap.org",
    "Aliases":  [
            "Nmap",
            "Insecure.Nmap"
          ],
    "Category":  "Security \u0026 Network",
    "Url":  "https://nmap.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=nmap.org\u0026sz=128",
    "IDn":  213
  },
  {
    "ID":  "VideoLAN.VLC",
    "Name":  "VLC media player",
    "Domain":  "videolan.org",
    "Aliases":  [
            "VLC media player",
            "VLC",
            "VideoLAN.VLC"
          ],
    "Category":  "Audio \u0026 Video",
    "Url":  "https://www.videolan.org/vlc/",
    "IconUrl":  "https://raw.githubusercontent.com/videolan/vlc/master/share/icons/128x128/vlc.png",
    "IDn":  214
  },
  {
    "ID":  "OBSProject.OBSStudio",
    "Name":  "OBS Studio",
    "Domain":  "obsproject.com",
    "Aliases":  [
            "OBS Studio",
            "OBS",
            "OBSProject.OBSStudio"
          ],
    "Category":  "Audio \u0026 Video",
    "IconUrl":  "https://img.icons8.com/fluency/96/obs-studio.png",
    "IDn":  215
  },
  {
    "ID":  "Spotify.Spotify",
    "Name":  "Spotify",
    "Domain":  "spotify.com",
    "Aliases":  [
            "Spotify",
            "Spotify.Spotify"
          ],
    "Category":  "Audio \u0026 Video",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/spotify.png",
    "IDn":  216
  },
  {
    "ID":  "Audacity.Audacity",
    "Name":  "Audacity",
    "Domain":  "audacityteam.org",
    "Aliases":  [
            "Audacity",
            "Audacity.Audacity"
          ],
    "Category":  "Audio \u0026 Video",
    "IconUrl":  "https://img.icons8.com/fluency/96/audacity.png",
    "IDn":  217
  },
  {
    "ID":  "HandBrake.HandBrake",
    "Name":  "HandBrake",
    "Domain":  "handbrake.fr",
    "Aliases":  [
            "HandBrake",
            "HandBrake.HandBrake"
          ],
    "Category":  "Audio \u0026 Video",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/handbrake.png",
    "IDn":  218
  },
  {
    "ID":  "CodecGuide.K-LiteCodecPack.Mega",
    "Name":  "K-Lite Codec Pack Mega",
    "Domain":  "codecguide.com",
    "Aliases":  [
            "K-Lite Mega Codec Pack",
            "K-Lite Codec Pack",
            "K-Lite Codec Pack Mega",
            "CodecGuide.K-LiteCodecPack.Mega"
          ],
    "Category":  "Audio \u0026 Video",
    "IconUrl":  "https://icons.duckduckgo.com/ip3/codecguide.com.ico",
    "Url":  "https://codecguide.com/download_k-lite_codec_pack_mega.htm",
    "IDn":  219
  },
  {
    "ID":  "Daum.PotPlayer",
    "Name":  "PotPlayer",
    "Domain":  "potplayer.tv",
    "Aliases":  [
            "PotPlayer",
            "PotPlayer-64 bit",
            "Daum.PotPlayer"
          ],
    "Category":  "Audio \u0026 Video",
    "Url":  "https://potplayer.tv/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=potplayer.tv\u0026sz=128",
    "IDn":  220
  },
  {
    "ID":  "ByteDance.CapCut",
    "Name":  "CapCut",
    "Domain":  "capcut.com",
    "Aliases":  [
            "CapCut",
            "ByteDance.CapCut"
          ],
    "Category":  "Audio \u0026 Video",
    "Url":  "https://www.capcut.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=capcut.com\u0026sz=128",
    "IDn":  221
  },
  {
    "ID":  "KDE.Kdenlive",
    "Name":  "Kdenlive",
    "Domain":  "kdenlive.org",
    "Aliases":  [
            "Kdenlive",
            "KDE.Kdenlive"
          ],
    "Category":  "Audio \u0026 Video",
    "Url":  "https://kdenlive.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=kdenlive.org\u0026sz=128",
    "IDn":  222
  },
  {
    "ID":  "Gyan.FFmpeg",
    "Name":  "FFmpeg",
    "Domain":  "ffmpeg.org",
    "Aliases":  [
            "FFmpeg",
            "Gyan.FFmpeg"
          ],
    "Category":  "Audio \u0026 Video",
    "Url":  "https://ffmpeg.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=ffmpeg.org\u0026sz=128",
    "IDn":  223
  },
  {
    "ID":  "BlackmagicDesign.DaVinciResolve",
    "Name":  "DaVinci Resolve",
    "Domain":  "blackmagicdesign.com",
    "Aliases":  [
            "DaVinci Resolve",
            "Blackmagic Design DaVinci Resolve",
            "BlackmagicDesign.DaVinciResolve"
          ],
    "Category":  "Audio \u0026 Video",
    "FallbackUrl":  "https://www.blackmagicdesign.com/products/davinciresolve",
    "Url":  "https://www.blackmagicdesign.com/products/davinciresolve",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=blackmagicdesign.com\u0026sz=128",
    "IDn":  224
  },
  {
    "ID":  "Meltytech.Shotcut",
    "Name":  "Shotcut",
    "Domain":  "shotcut.org",
    "Aliases":  [
            "Shotcut",
            "Meltytech.Shotcut"
          ],
    "Category":  "Audio \u0026 Video",
    "GitHubRepo":  "mltframework/shotcut",
    "AssetRegex":  "shotcut-win64-[0-9]+\\.exe$",
    "Url":  "https://www.shotcut.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=shotcut.org\u0026sz=128",
    "IDn":  225
  },
  {
    "ID":  "ch.LosslessCut",
    "Name":  "LosslessCut",
    "Domain":  "mifi.no/losslesscut",
    "Aliases":  [
            "LosslessCut",
            "ch.LosslessCut",
            "mifi.losslesscut"
          ],
    "Category":  "Audio \u0026 Video",
    "GitHubRepo":  "mifi/lossless-cut",
    "AssetRegex":  "LosslessCut-win-x64\\.7z$",
    "Url":  "https://mifi.no/losslesscut/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=mifi.no\u0026sz=128",
    "IDn":  226
  },
  {
    "ID":  "clsid2.mpc-hc",
    "Name":  "MPC-HC (Media Player)",
    "Domain":  "github.com/clsid2/mpc-hc",
    "Aliases":  [
            "MPC-HC",
            "MPC-HC (64-bit)",
            "clsid2.mpc-hc"
          ],
    "Category":  "Audio \u0026 Video",
    "GitHubRepo":  "clsid2/mpc-hc",
    "AssetRegex":  "MPC-HC\\.[0-9.]+\\.x64\\.exe$",
    "Url":  "https://github.com/clsid2/mpc-hc",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=mpc-hc.org\u0026sz=128",
    "IDn":  227
  },
  {
    "ID":  "MoritzBunkus.MKVToolNix",
    "Name":  "MKVToolNix",
    "Domain":  "mkvtoolnix.download",
    "Aliases":  [
            "MKVToolNix",
            "MoritzBunkus.MKVToolNix"
          ],
    "Category":  "Audio \u0026 Video",
    "Url":  "https://mkvtoolnix.download/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=mkvtoolnix.download\u0026sz=128",
    "IDn":  228
  },
  {
    "ID":  "PaulPacifico.ShutterEncoder",
    "Name":  "Shutter Encoder",
    "Domain":  "shutterencoder.com",
    "Aliases":  [
            "Shutter Encoder",
            "PaulPacifico.ShutterEncoder"
          ],
    "Category":  "Audio \u0026 Video",
    "Url":  "https://www.shutterencoder.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=shutterencoder.com\u0026sz=128",
    "IDn":  229
  },
  {
    "ID":  "PeterPawlowski.foobar2000",
    "Name":  "foobar2000",
    "Domain":  "foobar2000.org",
    "Aliases":  [
            "foobar2000",
            "PeterPawlowski.foobar2000"
          ],
    "Category":  "Audio \u0026 Video",
    "Url":  "https://www.foobar2000.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=foobar2000.org\u0026sz=128",
    "IDn":  230
  },
  {
    "ID":  "AIMP.AIMP",
    "Name":  "AIMP",
    "Domain":  "aimp.ru",
    "Aliases":  [
            "AIMP",
            "AIMP.AIMP"
          ],
    "Category":  "Audio \u0026 Video",
    "Url":  "https://www.aimp.ru/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=aimp.ru\u0026sz=128",
    "IDn":  231
  },
  {
    "ID":  "VB-Audio.Voicemeeter.Banana",
    "Name":  "VoiceMeeter Banana",
    "Domain":  "vb-audio.com",
    "Aliases":  [
            "Voicemeeter Banana",
            "VB-Audio Voicemeeter",
            "VB-Audio.Voicemeeter.Banana"
          ],
    "Category":  "Audio \u0026 Video",
    "Url":  "https://vb-audio.com/Voicemeeter/banana.htm",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=vb-audio.com\u0026sz=128",
    "IDn":  232
  },
  {
    "ID":  "ShareX.ShareX",
    "Name":  "ShareX",
    "Domain":  "getsharex.com",
    "Aliases":  [
            "ShareX",
            "ShareX.ShareX"
          ],
    "Category":  "Graphics \u0026 Design",
    "IconUrl":  "https://raw.githubusercontent.com/ShareX/ShareX/master/ShareX.HelpersLib/Resources/ShareX_Logo.png",
    "IDn":  233
  },
  {
    "ID":  "GIMP.GIMP",
    "Name":  "GIMP",
    "Domain":  "gimp.org",
    "Aliases":  [
            "GIMP",
            "GNU Image Manipulation Program",
            "GIMP.GIMP"
          ],
    "Category":  "Graphics \u0026 Design",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/selfhst/icons/png/gimp.png",
    "IDn":  234
  },
  {
    "ID":  "KDE.Krita",
    "Name":  "Krita",
    "Domain":  "krita.org",
    "Aliases":  [
            "Krita",
            "KDE.Krita"
          ],
    "Category":  "Graphics \u0026 Design",
    "IconUrl":  "https://img.icons8.com/color/96/krita.png",
    "IDn":  235
  },
  {
    "ID":  "BlenderFoundation.Blender",
    "Name":  "Blender",
    "Domain":  "blender.org",
    "Aliases":  [
            "Blender",
            "BlenderFoundation.Blender"
          ],
    "Category":  "Graphics \u0026 Design",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/blender.png",
    "IDn":  236
  },
  {
    "ID":  "Inkscape.Inkscape",
    "Name":  "Inkscape",
    "Domain":  "inkscape.org",
    "Aliases":  [
            "Inkscape",
            "Inkscape.Inkscape"
          ],
    "Category":  "Graphics \u0026 Design",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/selfhst/icons/png/inkscape-light.png",
    "IDn":  237
  },
  {
    "ID":  "Figma.Figma",
    "Name":  "Figma",
    "Domain":  "figma.com",
    "Aliases":  [
            "Figma",
            "Figma.Figma"
          ],
    "Category":  "Graphics \u0026 Design",
    "Url":  "https://www.figma.com/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/figma.png",
    "IDn":  238
  },
  {
    "ID":  "JannisX11.Blockbench",
    "Name":  "Blockbench",
    "Domain":  "blockbench.net",
    "Aliases":  [
            "Blockbench",
            "JannisX11.Blockbench"
          ],
    "Category":  "Graphics \u0026 Design",
    "Url":  "https://www.blockbench.net/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=blockbench.net\u0026sz=128",
    "IDn":  239
  },
  {
    "ID":  "dotPDN.PaintDotNet",
    "Name":  "paint.net",
    "Domain":  "getpaint.net",
    "Aliases":  [
            "paint.net",
            "dotPDN.PaintDotNet"
          ],
    "Category":  "Graphics \u0026 Design",
    "Url":  "https://www.getpaint.net/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=getpaint.net\u0026sz=128",
    "IDn":  240
  },
  {
    "ID":  "DuongDieuPhap.ImageGlass",
    "Name":  "ImageGlass",
    "Domain":  "imageglass.org",
    "Aliases":  [
            "ImageGlass",
            "DuongDieuPhap.ImageGlass"
          ],
    "Category":  "Graphics \u0026 Design",
    "Url":  "https://imageglass.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=imageglass.org\u0026sz=128",
    "IDn":  241
  },
  {
    "ID":  "Pinta.Pinta",
    "Name":  "Pinta",
    "Domain":  "pinta-project.com",
    "Aliases":  [
            "Pinta",
            "Pinta.Pinta"
          ],
    "Category":  "Graphics \u0026 Design",
    "GitHubRepo":  "PintaProject/Pinta",
    "AssetRegex":  "Pinta\\.exe$",
    "Url":  "https://www.pinta-project.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=pinta-project.com\u0026sz=128",
    "IDn":  242
  },
  {
    "ID":  "darktable.darktable",
    "Name":  "Darktable",
    "Domain":  "darktable.org",
    "Aliases":  [
            "darktable",
            "darktable.darktable"
          ],
    "Category":  "Graphics \u0026 Design",
    "GitHubRepo":  "darktable-org/darktable",
    "AssetRegex":  "win64\\.exe$",
    "Url":  "https://www.darktable.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=darktable.org\u0026sz=128",
    "IDn":  243
  },
  {
    "ID":  "RawTherapee.RawTherapee",
    "Name":  "RawTherapee",
    "Domain":  "rawtherapee.com",
    "Aliases":  [
            "RawTherapee",
            "RawTherapee.RawTherapee"
          ],
    "Category":  "Graphics \u0026 Design",
    "Url":  "https://www.rawtherapee.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=rawtherapee.com\u0026sz=128",
    "IDn":  244
  },
  {
    "ID":  "FastStone.Viewer",
    "Name":  "FastStone Image Viewer",
    "Domain":  "faststone.org",
    "Aliases":  [
            "FastStone Image Viewer",
            "FastStone.Viewer"
          ],
    "Category":  "Graphics \u0026 Design",
    "Url":  "https://www.faststone.org/FSViewerDetail.htm",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=faststone.org\u0026sz=128",
    "IDn":  245
  },
  {
    "ID":  "XnSoft.XnViewMP",
    "Name":  "XnView MP",
    "Domain":  "xnview.com",
    "Aliases":  [
            "XnView MP",
            "XnSoft.XnViewMP"
          ],
    "Category":  "Graphics \u0026 Design",
    "Url":  "https://www.xnview.com/en/xnviewmp/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=xnview.com\u0026sz=128",
    "IDn":  246
  },
  {
    "ID":  "Flameshot.Flameshot",
    "Name":  "Flameshot",
    "Domain":  "flameshot.org",
    "Aliases":  [
            "Flameshot",
            "Flameshot.Flameshot"
          ],
    "Category":  "Graphics \u0026 Design",
    "GitHubRepo":  "flameshot-org/flameshot",
    "AssetRegex":  "win64\\.msi$",
    "Url":  "https://flameshot.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=flameshot.org\u0026sz=128",
    "IDn":  247
  },
  {
    "ID":  "GodotEngine.GodotEngine",
    "Name":  "Godot Engine",
    "Domain":  "godotengine.org",
    "Aliases":  [
            "Godot Engine",
            "Godot",
            "GodotEngine.GodotEngine"
          ],
    "Category":  "Graphics \u0026 Design",
    "Url":  "https://godotengine.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=godotengine.org\u0026sz=128",
    "IDn":  248
  },
  {
    "ID":  "TheDocumentFoundation.LibreOffice",
    "Name":  "LibreOffice",
    "Domain":  "libreoffice.org",
    "Aliases":  [
            "LibreOffice",
            "TheDocumentFoundation.LibreOffice"
          ],
    "Category":  "Documents \u0026 Office",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/libreoffice-colibre-text.png",
    "IDn":  249
  },
  {
    "ID":  "Obsidian.Obsidian",
    "Name":  "Obsidian",
    "Domain":  "obsidian.md",
    "Aliases":  [
            "Obsidian",
            "Obsidian.Obsidian"
          ],
    "Category":  "Documents \u0026 Office",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/obsidian.png",
    "IDn":  250
  },
  {
    "ID":  "Notion.Notion",
    "Name":  "Notion",
    "Domain":  "notion.so",
    "Aliases":  [
            "Notion",
            "Notion.Notion"
          ],
    "Category":  "Documents \u0026 Office",
    "IconUrl":  "https://img.icons8.com/fluency/96/notion.png",
    "IDn":  251
  },
  {
    "ID":  "SumatraPDF.SumatraPDF",
    "Name":  "SumatraPDF",
    "Domain":  "sumatrapdfreader.org",
    "Aliases":  [
            "SumatraPDF",
            "SumatraPDF.SumatraPDF"
          ],
    "Category":  "Documents \u0026 Office",
    "Url":  "https://www.sumatrapdfreader.org/free-pdf-reader",
    "IDn":  252
  },
  {
    "ID":  "Foxit.FoxitReader",
    "Name":  "Foxit PDF Reader",
    "Domain":  "foxit.com",
    "Aliases":  [
            "Foxit PDF Reader",
            "Foxit Reader",
            "Foxit.FoxitReader"
          ],
    "Category":  "Documents \u0026 Office",
    "Url":  "https://www.foxit.com/pdf-reader/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/foxit-icon.png",
    "IDn":  253
  },
  {
    "ID":  "ONLYOFFICE.DesktopEditors",
    "Name":  "ONLYOFFICE Desktop",
    "Domain":  "onlyoffice.com",
    "Aliases":  [
            "ONLYOFFICE Desktop Editors",
            "ONLYOFFICE.DesktopEditors"
          ],
    "Category":  "Documents \u0026 Office",
    "Url":  "https://www.onlyoffice.com/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/onlyoffice.png",
    "IDn":  254
  },
  {
    "ID":  "geeksoftwareGmbH.PDF24Creator",
    "Name":  "PDF24 Creator",
    "Domain":  "pdf24.org",
    "Aliases":  [
            "PDF24 Creator",
            "geeksoftwareGmbH.PDF24Creator"
          ],
    "Category":  "Documents \u0026 Office",
    "Url":  "https://tools.pdf24.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=pdf24.org\u0026sz=128",
    "IDn":  255
  },
  {
    "ID":  "calibre.calibre",
    "Name":  "Calibre",
    "Domain":  "calibre-ebook.com",
    "Aliases":  [
            "calibre",
            "calibre - E-book management",
            "calibre.calibre"
          ],
    "Category":  "Documents \u0026 Office",
    "Url":  "https://calibre-ebook.com/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/calibre.png",
    "IDn":  256
  },
  {
    "ID":  "Adobe.Acrobat.Reader.64-bit",
    "Name":  "Adobe Acrobat Reader",
    "Domain":  "adobe.com",
    "Aliases":  [
            "Adobe Acrobat Reader",
            "Adobe Acrobat (64-bit)",
            "Adobe.Acrobat.Reader.64-bit"
          ],
    "Category":  "Documents \u0026 Office",
    "Url":  "https://get.adobe.com/reader/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=adobe.com\u0026sz=128",
    "IDn":  257
  },
  {
    "ID":  "KDE.Okular",
    "Name":  "Okular (PDF/EPUB)",
    "Domain":  "okular.kde.org",
    "Aliases":  [
            "Okular",
            "KDE.Okular"
          ],
    "Category":  "Documents \u0026 Office",
    "Url":  "https://okular.kde.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=okular.kde.org\u0026sz=128",
    "IDn":  258
  },
  {
    "ID":  "Logseq.Logseq",
    "Name":  "Logseq",
    "Domain":  "logseq.com",
    "Aliases":  [
            "Logseq",
            "Logseq.Logseq"
          ],
    "Category":  "Documents \u0026 Office",
    "GitHubRepo":  "logseq/logseq",
    "AssetRegex":  "win-x64-[0-9.]+\\.exe$",
    "Url":  "https://logseq.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=logseq.com\u0026sz=128",
    "IDn":  259
  },
  {
    "ID":  "AnyAssociation.Anytype",
    "Name":  "Anytype",
    "Domain":  "anytype.io",
    "Aliases":  [
            "Anytype",
            "AnyAssociation.Anytype"
          ],
    "Category":  "Documents \u0026 Office",
    "Url":  "https://anytype.io/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=anytype.io\u0026sz=128",
    "IDn":  260
  },
  {
    "ID":  "Anki.Anki",
    "Name":  "Anki (Flashcards)",
    "Domain":  "apps.ankiweb.net",
    "Aliases":  [
            "Anki",
            "Anki.Anki"
          ],
    "Category":  "Documents \u0026 Office",
    "GitHubRepo":  "ankitects/anki",
    "AssetRegex":  "windows-qt6\\.exe$",
    "Url":  "https://apps.ankiweb.net/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=ankiweb.net\u0026sz=128",
    "IDn":  261
  },
  {
    "ID":  "Mozilla.Thunderbird",
    "Name":  "Mozilla Thunderbird",
    "Domain":  "thunderbird.net",
    "Aliases":  [
            "Mozilla Thunderbird",
            "Thunderbird",
            "Mozilla.Thunderbird"
          ],
    "Category":  "Documents \u0026 Office",
    "Url":  "https://www.thunderbird.net/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/thunderbird.png",
    "IDn":  262
  },
  {
    "ID":  "PrismLauncher.PrismLauncher",
    "Name":  "Prism Launcher",
    "Domain":  "prismlauncher.org",
    "Aliases":  [
            "Prism Launcher",
            "PrismLauncher.PrismLauncher"
          ],
    "Category":  "Minecraft \u0026 Modding",
    "Url":  "https://prismlauncher.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=prismlauncher.org\u0026sz=128",
    "IDn":  263
  },
  {
    "ID":  "Mojang.MinecraftLauncher",
    "Name":  "Minecraft Launcher",
    "Domain":  "minecraft.net",
    "Aliases":  [
            "Minecraft Launcher",
            "Mojang.MinecraftLauncher"
          ],
    "Category":  "Minecraft \u0026 Modding",
    "Url":  "https://www.minecraft.net/en-us/download",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/minecraft.png",
    "IDn":  264
  },
  {
    "ID":  "Overwolf.CurseForge",
    "Name":  "CurseForge",
    "Domain":  "curseforge.com",
    "Aliases":  [
            "CurseForge",
            "Overwolf.CurseForge"
          ],
    "Category":  "Minecraft \u0026 Modding",
    "Url":  "https://www.curseforge.com/download/app",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=curseforge.com\u0026sz=128",
    "IDn":  265
  },
  {
    "ID":  "Overwolf.Overwolf",
    "Name":  "Overwolf",
    "Domain":  "overwolf.com",
    "Aliases":  [
            "Overwolf",
            "Overwolf.Overwolf"
          ],
    "Category":  "Minecraft \u0026 Modding",
    "FallbackUrl":  "https://www.overwolf.com/",
    "Url":  "https://www.overwolf.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=overwolf.com\u0026sz=128",
    "IDn":  266
  },
  {
    "ID":  "Modrinth.ModrinthApp",
    "Name":  "Modrinth App",
    "Domain":  "modrinth.com",
    "Aliases":  [
            "Modrinth App",
            "Modrinth",
            "Modrinth.ModrinthApp"
          ],
    "Category":  "Minecraft \u0026 Modding",
    "Url":  "https://modrinth.com/app",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=modrinth.com\u0026sz=128",
    "IDn":  267
  },
  {
    "ID":  "ATLauncher.ATLauncher",
    "Name":  "ATLauncher",
    "Domain":  "atlauncher.com",
    "Aliases":  [
            "ATLauncher",
            "ATLauncher.ATLauncher"
          ],
    "Category":  "Minecraft \u0026 Modding",
    "GitHubRepo":  "ATLauncher/ATLauncher",
    "AssetRegex":  "ATLauncher-[0-9.]+-setup\\.exe$",
    "Url":  "https://atlauncher.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=atlauncher.com\u0026sz=128",
    "IDn":  268
  },
  {
    "ID":  "HMCL.HMCL.Stable",
    "Name":  "HMCL (Hello Minecraft!)",
    "Domain":  "hmcl.huangyuhui.net",
    "Aliases":  [
            "Hello Minecraft! Launcher",
            "HMCL",
            "HMCL.HMCL.Stable"
          ],
    "Category":  "Minecraft \u0026 Modding",
    "GitHubRepo":  "HMCL-dev/HMCL",
    "AssetRegex":  "HMCL-[0-9.]+\\.exe$",
    "Url":  "https://hmcl.huangyuhui.net/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=hmcl.huangyuhui.net\u0026sz=128",
    "IDn":  269
  },
  {
    "ID":  "NexusMods.Vortex",
    "Name":  "Nexus Mods Vortex",
    "Domain":  "nexusmods.com",
    "Aliases":  [
            "Vortex",
            "Nexus Mods Vortex",
            "NexusMods.Vortex"
          ],
    "Category":  "Minecraft \u0026 Modding",
    "GitHubRepo":  "Nexus-Mods/Vortex",
    "AssetRegex":  "vortex-setup-[0-9.]+\\.exe$",
    "Url":  "https://www.nexusmods.com/about/vortex/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=nexusmods.com\u0026sz=128",
    "IDn":  270
  },
  {
    "ID":  "LegacyLauncher.LegacyLauncher",
    "Name":  "Legacy Launcher",
    "Domain":  "llaun.ch",
    "Aliases":  [
            "Legacy Launcher",
            "LegacyLauncher",
            "LLauncher"
          ],
    "Category":  "Minecraft \u0026 Modding",
    "Url":  "https://llaun.ch/en",
    "FallbackUrl":  "https://llaun.ch/exe",
    "BrowserDownload":  true,
    "IconUrl":  "https://www.google.com/s2/favicons?domain=llaun.ch\u0026sz=128",
    "IDn":  271
  },
  {
    "ID":  "Valve.Steam",
    "Name":  "Steam",
    "Domain":  "store.steampowered.com",
    "Aliases":  [
            "Steam",
            "Valve.Steam"
          ],
    "Category":  "Game Launchers",
    "Url":  "https://store.steampowered.com/",
    "IconUrl":  "https://img.icons8.com/fluency/96/steam.png",
    "IDn":  272
  },
  {
    "ID":  "EpicGames.EpicGamesLauncher",
    "Name":  "Epic Games Launcher",
    "Domain":  "store.epicgames.com",
    "Aliases":  [
            "Epic Games Launcher",
            "Epic Games",
            "EpicGames.EpicGamesLauncher"
          ],
    "Category":  "Game Launchers",
    "IconUrl":  "https://img.icons8.com/fluency/96/epic-games.png",
    "Url":  "https://store.epicgames.com/",
    "IDn":  273
  },
  {
    "ID":  "GOG.Galaxy",
    "Name":  "GOG Galaxy",
    "Domain":  "gog.com",
    "Aliases":  [
            "GOG Galaxy",
            "GOG.Galaxy"
          ],
    "Category":  "Game Launchers",
    "Url":  "https://www.gog.com/galaxy",
    "IconUrl":  "https://img.icons8.com/fluency/96/gog-galaxy.png",
    "IDn":  274
  },
  {
    "ID":  "Playnite.Playnite",
    "Name":  "Playnite",
    "Domain":  "playnite.link",
    "Aliases":  [
            "Playnite",
            "Playnite.Playnite"
          ],
    "Category":  "Game Launchers",
    "IconUrl":  "https://raw.githubusercontent.com/JosefNemec/Playnite/master/source/Playnite.DesktopApp/Themes/Desktop/Default/Images/applogo.png",
    "IDn":  275
  },
  {
    "ID":  "Blizzard.BattleNet",
    "Name":  "Battle.net",
    "Domain":  "battle.net",
    "Aliases":  [
            "Battle.net",
            "Battle.net Setup",
            "Blizzard.BattleNet"
          ],
    "Category":  "Game Launchers",
    "Url":  "https://www.blizzard.com/apps/battle.net/desktop",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=battle.net\u0026sz=128",
    "IDn":  276
  },
  {
    "ID":  "ElectronicArts.EADesktop",
    "Name":  "EA app",
    "Domain":  "ea.com",
    "Aliases":  [
            "EA app",
            "ElectronicArts.EADesktop"
          ],
    "Category":  "Game Launchers",
    "Url":  "https://www.ea.com/ea-app",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=ea.com\u0026sz=128",
    "IconBg":  "light",
    "IDn":  277
  },
  {
    "ID":  "Ubisoft.Connect",
    "Name":  "Ubisoft Connect",
    "Domain":  "ubisoft.com",
    "Aliases":  [
            "Ubisoft Connect",
            "Ubisoft.Connect"
          ],
    "Category":  "Game Launchers",
    "Url":  "https://ubisoftconnect.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=ubisoft.com\u0026sz=128",
    "IconBg":  "light",
    "IDn":  278
  },
  {
    "ID":  "HeroicGamesLauncher.HeroicGamesLauncher",
    "Name":  "Heroic Games Launcher",
    "Domain":  "heroicgameslauncher.com",
    "Aliases":  [
            "Heroic",
            "Heroic Games Launcher",
            "HeroicGamesLauncher.HeroicGamesLauncher"
          ],
    "Category":  "Game Launchers",
    "GitHubRepo":  "Heroic-Games-Launcher/HeroicGamesLauncher",
    "AssetRegex":  "Setup-x64\\.exe$",
    "Url":  "https://heroicgameslauncher.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=heroicgameslauncher.com\u0026sz=128",
    "IDn":  279
  },
  {
    "ID":  "ItchIo.Itch",
    "Name":  "Itch.io",
    "Domain":  "itch.io",
    "Aliases":  [
            "itch",
            "Itch.io",
            "ItchIo.Itch"
          ],
    "Category":  "Game Launchers",
    "Url":  "https://itch.io/app",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=itch.io\u0026sz=128",
    "IDn":  280
  },
  {
    "ID":  "Nvidia.GeForceNow",
    "Name":  "NVIDIA GeForce NOW",
    "Domain":  "nvidia.com/en-us/geforce-now",
    "Aliases":  [
            "NVIDIA GeForce NOW",
            "GeForce NOW",
            "Nvidia.GeForceNow"
          ],
    "Category":  "Game Launchers",
    "Url":  "https://www.nvidia.com/en-us/geforce-now/download/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/nvidia.png",
    "IDn":  281
  },
  {
    "ID":  "Wargaming.GameCenter",
    "Name":  "Wargaming Game Center",
    "Domain":  "wargaming.net",
    "Aliases":  [
            "Wargaming.net Game Center",
            "Wargaming.GameCenter"
          ],
    "Category":  "Game Launchers",
    "Url":  "https://eu.wargaming.net/en/wgc",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=wargaming.net\u0026sz=128",
    "IDn":  282
  },
  {
    "ID":  "Tonec.InternetDownloadManager",
    "Name":  "Internet Download Manager (IDM)",
    "Domain":  "internetdownloadmanager.com",
    "Aliases":  [
            "Internet Download Manager",
            "Tonec.InternetDownloadManager"
          ],
    "Category":  "Download Managers",
    "Url":  "https://www.internetdownloadmanager.com/",
    "IconUrl":  "https://img.icons8.com/fluency/96/download-from-cloud.png",
    "IDn":  283
  },
  {
    "ID":  "SoftDeluxe.FreeDownloadManager",
    "Name":  "Free Download Manager (FDM)",
    "Domain":  "freedownloadmanager.org",
    "Aliases":  [
            "Free Download Manager",
            "SoftDeluxe.FreeDownloadManager"
          ],
    "Category":  "Download Managers",
    "Url":  "https://www.freedownloadmanager.org/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=freedownloadmanager.org\u0026sz=128",
    "IDn":  284
  },
  {
    "ID":  "JavadMotallebi.NeatDownloadManager",
    "Name":  "Neat Download Manager (NDM)",
    "Domain":  "neatdownloadmanager.com",
    "Aliases":  [
            "Neat Download Manager",
            "JavadMotallebi.NeatDownloadManager"
          ],
    "Category":  "Download Managers",
    "Url":  "https://www.neatdownloadmanager.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=neatdownloadmanager.com\u0026sz=128",
    "IDn":  285
  },
  {
    "ID":  "amir1376.ABDownloadManager",
    "Name":  "AB Download Manager",
    "Domain":  "abdownloadmanager.com",
    "Aliases":  [
            "AB Download Manager",
            "amir1376.ABDownloadManager"
          ],
    "Category":  "Download Managers",
    "GitHubRepo":  "amir1376/ab-download-manager",
    "AssetRegex":  "windows_x64\\.exe$",
    "Url":  "https://abdownloadmanager.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=abdownloadmanager.com\u0026sz=128",
    "IDn":  286
  },
  {
    "ID":  "subhra74.XtremeDownloadManager",
    "Name":  "Xtreme Download Manager (XDM)",
    "Domain":  "xtremedownloadmanager.com",
    "Aliases":  [
            "Xtreme Download Manager",
            "XDM",
            "subhra74.XtremeDownloadManager"
          ],
    "Category":  "Download Managers",
    "GitHubRepo":  "subhra74/xdm",
    "AssetRegex":  "xdmsetup-[0-9.]+\\.msi$",
    "Url":  "https://xtremedownloadmanager.com/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=xtremedownloadmanager.com\u0026sz=128",
    "IDn":  287
  },
  {
    "ID":  "agalwood.Motrix",
    "Name":  "Motrix Downloader (MDM)",
    "Domain":  "motrix.app",
    "Aliases":  [
            "Motrix",
            "agalwood.Motrix"
          ],
    "Category":  "Download Managers",
    "GitHubRepo":  "agalwood/Motrix",
    "AssetRegex":  "Setup-[0-9.]+\\.exe$",
    "Url":  "https://motrix.app/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=motrix.app\u0026sz=128",
    "IDn":  288
  },
  {
    "ID":  "aria2.aria2",
    "Name":  "aria2 (Multi-Protocol CLI)",
    "Domain":  "aria2.github.io",
    "Aliases":  [
            "aria2",
            "aria2.aria2"
          ],
    "Category":  "Download Managers",
    "GitHubRepo":  "aria2/aria2",
    "AssetRegex":  "win-64bit-build1\\.zip$",
    "Url":  "https://aria2.github.io/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=aria2.github.io\u0026sz=128",
    "IDn":  289
  },
  {
    "ID":  "yt-dlp.yt-dlp",
    "Name":  "yt-dlp (Video Downloader)",
    "Domain":  "github.com/yt-dlp/yt-dlp",
    "Aliases":  [
            "yt-dlp",
            "yt-dlp.yt-dlp"
          ],
    "Category":  "Download Managers",
    "GitHubRepo":  "yt-dlp/yt-dlp",
    "AssetRegex":  "^yt-dlp\\.exe$",
    "Url":  "https://github.com/yt-dlp/yt-dlp",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=youtube.com\u0026sz=128",
    "IDn":  290
  },
  {
    "ID":  "Nickvision.Parabolic",
    "Name":  "Parabolic (yt-dlp GUI)",
    "Domain":  "nickvision.org",
    "Aliases":  [
            "Nickvision Parabolic",
            "Parabolic",
            "Nickvision.Parabolic"
          ],
    "Category":  "Download Managers",
    "GitHubRepo":  "NickvisionApps/Parabolic",
    "AssetRegex":  "NickvisionParabolicSetup\\.exe$",
    "Url":  "https://github.com/NickvisionApps/Parabolic",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=github.com\u0026sz=128",
    "IDn":  291
  },
  {
    "ID":  "yt-dlg.yt-dlg",
    "Name":  "yt-dlg (YouTube-DL GUI)",
    "Domain":  "oleksis.github.io/youtube-dl-gui",
    "Aliases":  [
            "yt-dlg",
            "yt-dlg.yt-dlg"
          ],
    "Category":  "Download Managers",
    "GitHubRepo":  "oleksis/youtube-dl-gui",
    "AssetRegex":  "yt-dlg-[0-9.]+\\.exe$",
    "Url":  "https://oleksis.github.io/youtube-dl-gui/",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=youtube.com\u0026sz=128",
    "IDn":  292
  },
  {
    "ID":  "qBittorrent.qBittorrent",
    "Name":  "qBittorrent",
    "Domain":  "qbittorrent.org",
    "Aliases":  [
            "qBittorrent",
            "qBittorrent.qBittorrent"
          ],
    "Category":  "Download Managers",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/qbittorrent.png",
    "IDn":  293
  },
  {
    "ID":  "Transmission.Transmission",
    "Name":  "Transmission (BitTorrent)",
    "Domain":  "transmissionbt.com",
    "Aliases":  [
            "Transmission",
            "Transmission.Transmission"
          ],
    "Category":  "Download Managers",
    "GitHubRepo":  "transmission/transmission",
    "AssetRegex":  "x64\\.msi$",
    "Url":  "https://transmissionbt.com/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/transmission.png",
    "IDn":  294
  },
  {
    "ID":  "DelugeTeam.Deluge",
    "Name":  "Deluge (BitTorrent)",
    "Domain":  "deluge-torrent.org",
    "Aliases":  [
            "Deluge",
            "Deluge BitTorrent Client",
            "DelugeTeam.Deluge"
          ],
    "Category":  "Download Managers",
    "Url":  "https://deluge-torrent.org/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/deluge.png",
    "IDn":  295
  },
  {
    "ID":  "LocalSend.LocalSend",
    "Name":  "LocalSend",
    "Domain":  "localsend.org",
    "Aliases":  [
            "LocalSend",
            "LocalSend.LocalSend"
          ],
    "Category":  "File Transfer \u0026 Cloud",
    "IconUrl":  "https://raw.githubusercontent.com/localsend/localsend/main/app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png",
    "IDn":  296
  },
  {
    "ID":  "WinSCP.WinSCP",
    "Name":  "WinSCP",
    "Domain":  "winscp.net",
    "Aliases":  [
            "WinSCP",
            "WinSCP.WinSCP"
          ],
    "Category":  "File Transfer \u0026 Cloud",
    "IDn":  297
  },
  {
    "ID":  "TimKosse.FileZilla.Client",
    "Name":  "FileZilla",
    "Domain":  "filezilla-project.org",
    "Aliases":  [
            "FileZilla Client",
            "FileZilla",
            "TimKosse.FileZilla.Client"
          ],
    "Category":  "File Transfer \u0026 Cloud",
    "FallbackUrl":  "https://filezilla-project.org/download.php?platform=win64",
    "Url":  "https://filezilla-project.org/download.php?platform=win64",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/filezilla.png",
    "IDn":  298
  },
  {
    "ID":  "Rclone.Rclone",
    "Name":  "Rclone",
    "Domain":  "rclone.org",
    "Aliases":  [
            "Rclone",
            "Rclone.Rclone"
          ],
    "Category":  "File Transfer \u0026 Cloud",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/rclone.png",
    "IDn":  299
  },
  {
    "ID":  "Google.GoogleDrive",
    "Name":  "Google Drive",
    "Domain":  "google.com/drive",
    "Aliases":  [
            "Google Drive",
            "Google.GoogleDrive"
          ],
    "Category":  "File Transfer \u0026 Cloud",
    "Url":  "https://www.google.com/drive/download/",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/google-drive.png",
    "IDn":  300
  },
  {
    "ID":  "Dropbox.Dropbox",
    "Name":  "Dropbox",
    "Domain":  "dropbox.com",
    "Aliases":  [
            "Dropbox",
            "Dropbox.Dropbox"
          ],
    "Category":  "File Transfer \u0026 Cloud",
    "Url":  "https://www.dropbox.com/install",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/dropbox.png",
    "IDn":  301
  },
  {
    "ID":  "Mega.MEGASync",
    "Name":  "MEGA (MEGAsync)",
    "Domain":  "mega.io",
    "Aliases":  [
            "MEGAsync",
            "Mega.MEGASync"
          ],
    "Category":  "File Transfer \u0026 Cloud",
    "Url":  "https://mega.io/desktop",
    "IconUrl":  "https://www.google.com/s2/favicons?domain=mega.io\u0026sz=128",
    "IDn":  302
  },
  {
    "ID":  "Nextcloud.NextcloudDesktop",
    "Name":  "Nextcloud Desktop",
    "Domain":  "nextcloud.com",
    "Aliases":  [
            "Nextcloud",
            "Nextcloud.NextcloudDesktop"
          ],
    "Category":  "File Transfer \u0026 Cloud",
    "Url":  "https://nextcloud.com/install/#install-clients",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/nextcloud.png",
    "IDn":  303
  },
  {
    "ID":  "SyncTrayzor.SyncTrayzor",
    "Name":  "Syncthing (SyncTrayzor)",
    "Domain":  "syncthing.net",
    "Aliases":  [
            "SyncTrayzor",
            "Syncthing",
            "SyncTrayzor.SyncTrayzor"
          ],
    "Category":  "File Transfer \u0026 Cloud",
    "GitHubRepo":  "canton7/SyncTrayzor",
    "AssetRegex":  "SyncTrayzorSetup-x64\\.exe$",
    "Url":  "https://github.com/canton7/SyncTrayzor",
    "IconUrl":  "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/syncthing.png",
    "IDn":  304
  }
]
'@
$AppCatalog = ConvertFrom-Json $appsRawJson

[xml]$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="App-Driver — Windows Software &amp; Driver Suite"
    Width="1260" Height="780"
    MinWidth="980" MinHeight="620"
    WindowStartupLocation="CenterScreen"
    Background="#0C1018"
    Foreground="#E2E8F0"
    FontFamily="Segoe UI Variable Display, Segoe UI, -apple-system, sans-serif"
    TextOptions.TextFormattingMode="Display"
    TextOptions.TextRenderingMode="ClearType"
    UseLayoutRounding="True"
    SnapsToDevicePixels="True">

    <Window.Resources>
        <Style TargetType="{x:Type CheckBox}">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type CheckBox}">
                        <Grid Background="Transparent" Width="16" Height="16">
                            <Border x:Name="box" Width="15" Height="15" CornerRadius="4"
                                    Background="#131B29" BorderBrush="#334155" BorderThickness="1.2"
                                    HorizontalAlignment="Center" VerticalAlignment="Center">
                                <Path x:Name="checkMark" Visibility="Collapsed"
                                      Data="M 2.2,6.2 L 5.2,9.2 L 10.8,3.2"
                                      Stroke="#FFFFFF" StrokeThickness="1.8"
                                      StrokeStartLineCap="Round" StrokeEndLineCap="Round"
                                      StrokeLineJoin="Round" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="box" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter TargetName="box" Property="Background" Value="#192335"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="box" Property="Background" Value="#0284C7"/>
                                <Setter TargetName="box" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter TargetName="checkMark" Property="Visibility" Value="Visible"/>
                            </Trigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsChecked" Value="True"/>
                                    <Condition Property="IsMouseOver" Value="True"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="box" Property="Background" Value="#0EA5E9"/>
                            </MultiTrigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="box" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ModernScrollThumb" TargetType="{x:Type Thumb}">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="IsTabStop" Value="False"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type Thumb}">
                        <Border Name="thumbBorder" Background="#253147" CornerRadius="3" Margin="2,0"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="thumbBorder" Property="Background" Value="#38BDF8"/>
                            </Trigger>
                            <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="thumbBorder" Property="Background" Value="#0EA5E9"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ScrollBarPageButton" TargetType="{x:Type RepeatButton}">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="IsTabStop" Value="False"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type RepeatButton}">
                        <Border Background="Transparent"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="{x:Type ScrollBar}">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Vertical">
                    <Setter Property="Width" Value="7"/>
                    <Setter Property="Height" Value="Auto"/>
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="{x:Type ScrollBar}">
                                <Grid Background="Transparent">
                                    <Track Name="PART_Track" IsDirectionReversed="True">
                                        <Track.DecreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageUpCommand"/>
                                        </Track.DecreaseRepeatButton>
                                        <Track.Thumb>
                                            <Thumb Style="{StaticResource ModernScrollThumb}"/>
                                        </Track.Thumb>
                                        <Track.IncreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageDownCommand"/>
                                        </Track.IncreaseRepeatButton>
                                    </Track>
                                </Grid>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Trigger>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Width" Value="Auto"/>
                    <Setter Property="Height" Value="7"/>
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="{x:Type ScrollBar}">
                                <Grid Background="Transparent">
                                    <Track Name="PART_Track" IsDirectionReversed="False">
                                        <Track.DecreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageLeftCommand"/>
                                        </Track.DecreaseRepeatButton>
                                        <Track.Thumb>
                                            <Thumb Style="{StaticResource ModernScrollThumb}">
                                                <Thumb.Template>
                                                    <ControlTemplate TargetType="{x:Type Thumb}">
                                                        <Border Name="hThumbBorder" Background="#253147" CornerRadius="3" Margin="0,2"/>
                                                        <ControlTemplate.Triggers>
                                                            <Trigger Property="IsMouseOver" Value="True">
                                                                <Setter TargetName="hThumbBorder" Property="Background" Value="#38BDF8"/>
                                                            </Trigger>
                                                            <Trigger Property="IsDragging" Value="True">
                                                                <Setter TargetName="hThumbBorder" Property="Background" Value="#0EA5E9"/>
                                                            </Trigger>
                                                        </ControlTemplate.Triggers>
                                                    </ControlTemplate>
                                                </Thumb.Template>
                                            </Thumb>
                                        </Track.Thumb>
                                        <Track.IncreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageRightCommand"/>
                                        </Track.IncreaseRepeatButton>
                                    </Track>
                                </Grid>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,7"/>
            <Setter Property="Margin" Value="0,0,6,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#24FFFFFF"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="btnBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.90"/>
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#55FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.72"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="#141B29"/>
            <Setter Property="Foreground" Value="#CBD5E1"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="13,7"/>
            <Setter Property="Margin" Value="0,0,6,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderBrush" Value="#212B3F"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="btnBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#1B2538"/>
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="#161E2E"/>
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#0EA5E9"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="NavTabButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#64748B"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="18,10"/>
            <Setter Property="Margin" Value="0,0,4,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0,0,0,2"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="navBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#E2E8F0"/>
                                <Setter TargetName="navBorder" Property="Background" Value="#121825"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.48"/>
                                <Setter Property="Foreground" Value="#64748B"/>
                                <Setter Property="Cursor" Value="No"/>
                                <Setter TargetName="navBorder" Property="Background" Value="Transparent"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="FilterTabButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#64748B"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="12,5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="filterBorder" Background="{TemplateBinding Background}"
                                CornerRadius="4" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#F8FAFC"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> 
            <RowDefinition Height="*"/>    
            <RowDefinition Height="Auto"/> 
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#0A0E15" Padding="14,0" BorderBrush="#192130" BorderThickness="0,0,0,1">
            <Grid>
                <StackPanel Orientation="Horizontal">
                    <Button Name="navBtnApps" Content="Ứng dụng" Style="{StaticResource NavTabButton}"
                            BorderBrush="#38BDF8" Foreground="#38BDF8"/>
                    <Button Name="navBtnUninstaller" Content="Gỡ cài đặt" Style="{StaticResource NavTabButton}"/>
                    <Button Name="navBtnRepair" Content="&#x1F512; Gỡ lỗi &amp; Hệ thống (Đang khóa)" Style="{StaticResource NavTabButton}"
                            IsEnabled="False" ToolTip="Tính năng Gỡ lỗi &amp; Hệ thống đang được tạm khóa." ToolTipService.ShowOnDisabled="True"/>
                    <Button Name="navBtnDrivers" Content="&#x1F512; Quản lý Driver (Đang khóa)" Style="{StaticResource NavTabButton}"
                            IsEnabled="False" ToolTip="Tính năng Quản lý Driver đang được tạm khóa." ToolTipService.ShowOnDisabled="True"/>
                </StackPanel>
                <TextBlock Text="App-Driver" HorizontalAlignment="Right" VerticalAlignment="Center"
                           Foreground="#475569" FontSize="11.5" FontWeight="SemiBold" Margin="0,0,4,0"/>
            </Grid>
        </Border>

        <TabControl Grid.Row="1" Name="MainTabControl" Background="Transparent" BorderThickness="0" Padding="0">
            <TabControl.ItemContainerStyle>
                <Style TargetType="TabItem">
                    <Setter Property="Visibility" Value="Collapsed"/>
                </Style>
            </TabControl.ItemContainerStyle>

            <TabItem>
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="#0E131D" Padding="16,9" BorderBrush="#192130" BorderThickness="0,0,0,1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>

                            <Grid Grid.Row="0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Column="0" Orientation="Horizontal">
                                    <Button Name="btnInstall" Content="Install Selected" Style="{StaticResource ActionButton}"
                                            Background="#059669" Padding="15,7"/>
                                    <Button Name="btnUpgradeSelected" Content="Upgrade Selected" Style="{StaticResource SecondaryButton}"
                                            Foreground="#A78BFA" BorderBrush="#2E234E"/>
                                    <Button Name="btnUpgradeAll" Content="Upgrade All" Style="{StaticResource SecondaryButton}"
                                            Foreground="#FBBF24" BorderBrush="#3B311B"/>
                                    <Button Name="btnScanInstalled" Content="Get Installed" Style="{StaticResource SecondaryButton}"
                                            Foreground="#38BDF8" BorderBrush="#1D3652"/>
                                </StackPanel>

                                <StackPanel Grid.Column="2" Orientation="Horizontal">
                                    <Button Name="btnSelectAll" Content="Select All" Style="{StaticResource SecondaryButton}" Margin="0,0,6,0"/>
                                    <Button Name="btnDeselectAll" Content="Clear Selection" Style="{StaticResource SecondaryButton}" Margin="0"/>
                                </StackPanel>
                            </Grid>

                            <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="1,7,0,0" VerticalAlignment="Center">
                                <TextBlock Text="Trạng thái:" FontSize="11" Foreground="#64748B" Margin="0,0,12,0" FontWeight="SemiBold"/>
                                <StackPanel Orientation="Horizontal" Margin="0,0,14,0" VerticalAlignment="Center">
                                    <Ellipse Width="7" Height="7" Fill="#F1F5F9" Margin="0,0,5,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="Chưa cài đặt" FontSize="11" Foreground="#CBD5E1"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,14,0" VerticalAlignment="Center">
                                    <Ellipse Width="7" Height="7" Fill="#34D399" Margin="0,0,5,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="Đã cài (Mới nhất)" FontSize="11" Foreground="#34D399"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <Ellipse Width="7" Height="7" Fill="#F87171" Margin="0,0,5,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="Bản cũ (Có cập nhật)" FontSize="11" Foreground="#F87171"/>
                                </StackPanel>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <ScrollViewer Name="AppsScrollViewer" Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                                  CanContentScroll="False" PanningMode="VerticalOnly" Padding="10,10">
                        <Grid Name="CardsContainer">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" Name="CardsCol0" Margin="4,0"/>
                            <StackPanel Grid.Column="1" Name="CardsCol1" Margin="4,0"/>
                            <StackPanel Grid.Column="2" Name="CardsCol2" Margin="4,0"/>
                            <StackPanel Grid.Column="3" Name="CardsCol3" Margin="4,0"/>
                        </Grid>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <TabItem>
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="#0D121B" Padding="16,9" BorderBrush="#192130" BorderThickness="0,0,0,1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                                <Button Name="btnDeepUninstall" Content="Gỡ Tận Gốc (0)" Style="{StaticResource ActionButton}"
                                        Background="#991B1B" Foreground="#FEE2E2" Padding="14,8"/>
                                <Button Name="btnScanOrphans" Content="Quét App Xóa Sai Cách" Style="{StaticResource ActionButton}"
                                        Background="#0284C7" Foreground="#E0F2FE" Padding="14,8"/>
                                <Button Name="btnRefreshUninstaller" Content="Làm mới" Style="{StaticResource SecondaryButton}"
                                        Background="#1E293B" Foreground="#93C5FD" Padding="12,8"/>
                            </StackPanel>

                            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                                <Border Background="#101623" BorderBrush="#1C2638" BorderThickness="1" CornerRadius="6" Padding="2">
                                    <StackPanel Orientation="Horizontal">
                                        <Button Name="btnFilterUninstAll" Content="Tất cả" Style="{StaticResource FilterTabButton}"
                                                Background="#1E293B" Foreground="#38BDF8"/>
                                        <Button Name="btnFilterUninstBroken" Content="Xóa sai cách / Lỗi" Style="{StaticResource FilterTabButton}"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                                <Border Background="#101520" CornerRadius="6" BorderBrush="#1E283A" BorderThickness="1" Padding="8,4" Margin="0,0,8,0">
                                    <Grid Width="220">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock Text="🔍" Foreground="#475569" VerticalAlignment="Center" Margin="0,0,6,0" FontSize="11"/>
                                        <TextBox Grid.Column="1" Name="txtUninstallSearch" Background="Transparent" Foreground="#F8FAFC"
                                                 BorderThickness="0" FontSize="12" VerticalAlignment="Center" CaretBrush="#38BDF8"
                                                 ToolTip="Tìm kiếm theo tên ứng dụng, nhà phát hành hoặc phiên bản..."/>
                                        <Button Grid.Column="2" Name="btnClearUninstallSearch" Content="✕" Background="Transparent" Foreground="#64748B"
                                                BorderThickness="0" FontSize="10" Cursor="Hand" Padding="2,0" ToolTip="Xóa bộ lọc"/>
                                    </Grid>
                                </Border>
                                <Button Name="btnUninstallSelectAll" Content="Select All" Style="{StaticResource SecondaryButton}" Padding="10,6"/>
                                <Button Name="btnUninstallDeselectAll" Content="Clear" Style="{StaticResource SecondaryButton}" Padding="10,6"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <Border Grid.Row="1" Background="#090D14" Padding="16,7" BorderBrush="#141B26" BorderThickness="0,0,0,1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <TextBlock Grid.Column="0" Name="txtUninstallerSummary" Text="Chưa tải danh sách"
                                       Foreground="#64748B" FontSize="11.5" FontWeight="SemiBold" VerticalAlignment="Center"/>

                            <Grid Grid.Column="1" Margin="14,0,14,0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="36"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="120"/>
                                    <ColumnDefinition Width="180"/>
                                    <ColumnDefinition Width="95"/>
                                    <ColumnDefinition Width="110"/>
                                    <ColumnDefinition Width="44"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="1" Text="TÊN ỨNG DỤNG" Foreground="#475569" FontSize="10.5" FontWeight="Bold" Margin="6,0,0,0"/>
                                <TextBlock Grid.Column="2" Text="PHIÊN BẢN" Foreground="#475569" FontSize="10.5" FontWeight="Bold" Margin="6,0,0,0"/>
                                <TextBlock Grid.Column="3" Text="NHÀ PHÁT HÀNH" Foreground="#475569" FontSize="10.5" FontWeight="Bold" Margin="6,0,0,0"/>
                                <TextBlock Grid.Column="4" Text="DUNG LƯỢNG" Foreground="#475569" FontSize="10.5" FontWeight="Bold" TextAlignment="Right" Margin="0,0,8,0"/>
                                <TextBlock Grid.Column="5" Text="TRẠNG THÁI" Foreground="#475569" FontSize="10.5" FontWeight="Bold" TextAlignment="Center"/>
                                <TextBlock Grid.Column="6" Text="THƯ MỤC" Foreground="#475569" FontSize="10.5" FontWeight="Bold" TextAlignment="Center"/>
                            </Grid>
                        </Grid>
                    </Border>

                    <ScrollViewer Grid.Row="2" Name="UninstallerScrollViewer" VerticalScrollBarVisibility="Auto"
                                  HorizontalScrollBarVisibility="Disabled" CanContentScroll="False" PanningMode="VerticalOnly">
                        <StackPanel Name="UninstallerRowsPanel" Margin="14,6,14,14"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <TabItem>
                <DockPanel>
                    <Border DockPanel.Dock="Top" Background="#1A1512" BorderBrush="#92400E" BorderThickness="1" CornerRadius="6" Margin="16,14,16,0" Padding="14,10">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock Text="&#x1F512; TÍNH NĂNG ĐANG TẠM KHÓA" Foreground="#FBBF24" FontWeight="Bold" FontSize="11.5" Margin="0,0,10,0" VerticalAlignment="Center"/>
                            <TextBlock Text="Module Gỡ lỗi &amp; Hệ thống hiện đang được khóa để tập trung ổn định trình cài đặt và cập nhật ứng dụng." Foreground="#CBD5E1" FontSize="11.5" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Border>
                    <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16,12,16,14" IsEnabled="False" Opacity="0.45">
                        <UniformGrid Columns="2" VerticalAlignment="Top">
                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#12263A" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="CORE FIX" FontSize="9.5" FontWeight="Bold" Foreground="#38BDF8"/>
                                    </Border>
                                    <TextBlock Text="Sửa chữa file hệ thống" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Quét và tự động sửa các file hệ thống Windows bị hỏng hoặc mất qua SFC và DISM."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnSfcScan" Content="SFC Scan (sfc /scannow)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnDismRestore" Content="DISM RestoreHealth (Phục hồi linh kiện)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnDismCleanup" Content="Dọn Kho Linh Kiện (Component Cleanup)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>

                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#2A1F12" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="UPDATE" FontSize="9.5" FontWeight="Bold" Foreground="#FBBF24"/>
                                    </Border>
                                    <TextBlock Text="Gỡ lỗi Windows Update" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Khắc phục triệt để lỗi kẹt tải 0%, mã lỗi 0x80070002, 0x8024... khi cập nhật Windows."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnFixWindowsUpdate" Content="Reset Toàn Bộ Cache Update (Triệt để)" Style="{StaticResource ActionButton}" Background="#B45309" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnRestartUpdateServices" Content="Khởi Động Lại Dịch Vụ BITS &amp; Wuauserv" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnTriggerScanUpdate" Content="Kích Hoạt Tìm Bản Cập Nhật Mới (USOClient)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>

                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#0E2920" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="NETWORK" FontSize="9.5" FontWeight="Bold" Foreground="#34D399"/>
                                    </Border>
                                    <TextBlock Text="Sửa lỗi Mạng &amp; Kết nối" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Khắc phục sự cố mất kết nối mạng, gián đoạn truy cập web, lỗi DNS và sự cố bộ giao thức."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnFlushDnsWinsock" Content="Flush DNS &amp; Reset Winsock (Làm mới mạng)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnResetTcpIp" Content="Reset Toàn Bộ Ngăn Xếp TCP/IP Stack" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>

                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#1F1936" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="MAINTAIN" FontSize="9.5" FontWeight="Bold" Foreground="#A78BFA"/>
                                    </Border>
                                    <TextBlock Text="Bảo trì &amp; Dọn dẹp hệ thống" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Giải phóng dung lượng ổ C bị chiếm dụng bởi tệp tạm, nhật ký sự kiện và nạp lại thanh Taskbar khi bị treo."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnClearTemp" Content="Dọn Sạch Thư Mục Temp &amp; Cache Rác" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnCleanEventLogs" Content="Dọn Dẹp Windows Event Logs" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnRestartExplorer" Content="Khởi Động Lại Windows Explorer (Fix đơ taskbar)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>
                        </UniformGrid>
                    </ScrollViewer>
                </DockPanel>
            </TabItem>

            <TabItem>
                <DockPanel>
                    <Border DockPanel.Dock="Top" Background="#1A1512" BorderBrush="#92400E" BorderThickness="1" CornerRadius="6" Margin="16,14,16,0" Padding="14,10">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock Text="&#x1F512; TÍNH NĂNG ĐANG TẠM KHÓA" Foreground="#FBBF24" FontWeight="Bold" FontSize="11.5" Margin="0,0,10,0" VerticalAlignment="Center"/>
                            <TextBlock Text="Module Quản lý Driver hiện đang được khóa để đảm bảo an toàn hệ thống và tập trung quản lý ứng dụng." Foreground="#CBD5E1" FontSize="11.5" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Border>
                    <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16,12,16,14" IsEnabled="False" Opacity="0.45">
                        <UniformGrid Columns="3" VerticalAlignment="Top">
                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#2D141D" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="HARDWARE" FontSize="9.5" FontWeight="Bold" Foreground="#FB7185"/>
                                    </Border>
                                    <TextBlock Text="Chẩn đoán phần cứng" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Rà soát các thiết bị bị chấm than vàng, thiếu driver hoặc driver bị xung đột crash."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnScanFaultyDrivers" Content="Quét Thiết Bị &amp; Driver Bị Lỗi" Style="{StaticResource ActionButton}" Background="#BE123C" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnPnpRescan" Content="Buộc Windows Quét Lại Phần Cứng (PnP Scan)" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnOpenDeviceManager" Content="Mở Trình Quản Lý Device Manager" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>

                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#2A1F12" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="RESOLVE" FontSize="9.5" FontWeight="Bold" Foreground="#FBBF24"/>
                                    </Border>
                                    <TextBlock Text="Gỡ lỗi cập nhật Driver" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Sửa lỗi Windows Update bị kẹt khi đang cài driver màn hình, âm thanh, touchpad."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnFixDriverUpdate" Content="Sửa Lỗi Kẹt Cập Nhật Driver (Xóa Queue)" Style="{StaticResource ActionButton}" Background="#B45309" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnScanWindowsUpdateDrivers" Content="Kích Hoạt Quét Driver Mới Từ Microsoft" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnCleanDriverStore" Content="Dọn Dẹp Driver Cũ Trong DriverStore" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>

                        <Border Background="#111722" BorderBrush="#1C2536" BorderThickness="1" CornerRadius="8" Margin="6" Padding="18">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                    <Border Background="#0E2920" CornerRadius="4" Padding="6,2" Margin="0,0,8,0" VerticalAlignment="Center">
                                        <TextBlock Text="BACKUP" FontSize="9.5" FontWeight="Bold" Foreground="#34D399"/>
                                    </Border>
                                    <TextBlock Text="Sao lưu &amp; Bảo vệ Driver" FontWeight="SemiBold" FontSize="13.5" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBlock Text="Trích xuất toàn bộ driver bên thứ ba để phòng khi cài lại Windows không sợ mất mạng/wifi."
                                           FontSize="11.5" Foreground="#64748B" Margin="0,0,0,12" TextWrapping="Wrap"/>
                                <Button Name="btnBackupDrivers" Content="Sao Lưu Toàn Bộ Driver (Ra C:\Backup_Drivers)" Style="{StaticResource ActionButton}" Background="#059669" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                                <Button Name="btnOpenBackupFolder" Content="Mở Thư Mục Chứa Driver Đã Sao Lưu" Style="{StaticResource SecondaryButton}" Margin="0,3" HorizontalContentAlignment="Left" Padding="14,9"/>
                            </StackPanel>
                        </Border>
                        </UniformGrid>
                    </ScrollViewer>
                </DockPanel>
            </TabItem>
        </TabControl>

        <Border Grid.Row="2" Background="#0A0E15" Padding="16,6" BorderBrush="#192130" BorderThickness="0,1,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <StackPanel Grid.Column="0" Grid.Row="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <Ellipse Fill="#10B981" Width="7" Height="7" Margin="0,0,8,0" VerticalAlignment="Center"/>
                    <TextBlock Name="txtStatus" Text="Sẵn sàng"
                               Foreground="#93C5FD" FontSize="11.5" FontWeight="SemiBold"/>
                </StackPanel>

                <TextBlock Grid.Column="1" Grid.Row="0" Name="txtSelectionCount" Text="0 app được chọn"
                           Foreground="#64748B" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>

                <ProgressBar Grid.Column="0" Grid.ColumnSpan="2" Grid.Row="1"
                             Name="progressBar" Height="2" Margin="0,5,0,1"
                             Background="#141C2B" Foreground="#0EA5E9" BorderThickness="0" Value="0"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

if (-not ("DuckUtil.SmoothScrollController" -as [type])) {
    try {
        $wpfSmoothRefs = @(
            [System.Windows.Controls.ScrollViewer].Assembly.Location,
            [System.Windows.UIElement].Assembly.Location,
            [System.Windows.DependencyObject].Assembly.Location,
            [System.Windows.Markup.IQueryAmbient].Assembly.Location,
            [System.Diagnostics.Stopwatch].Assembly.Location,
            [System.Object].Assembly.Location
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
        $smoothScrollCs = @'
using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace DuckUtil {
    public sealed class SmoothScrollController {
        private readonly ScrollViewer _sv;
        private double _currentOffset;
        private double _targetOffset;
        private double _lastAppliedOffset;
        private bool _isAnimating;
        private readonly Stopwatch _sw = new Stopwatch();
        private double _lastTimeSec;

        private SmoothScrollController(ScrollViewer sv) {
            _sv = sv;
            _currentOffset = sv.VerticalOffset;
            _targetOffset = sv.VerticalOffset;
            _lastAppliedOffset = sv.VerticalOffset;
            _sv.PreviewMouseWheel += OnPreviewMouseWheel;
        }

        public static SmoothScrollController Attach(ScrollViewer sv) {
            if (sv == null) return null;
            return new SmoothScrollController(sv);
        }

        private void OnPreviewMouseWheel(object sender, MouseWheelEventArgs e) {
            if (e == null || e.Handled) return;
            if (Keyboard.Modifiers != ModifierKeys.None) return;

            double maxScroll = _sv.ScrollableHeight;
            if (maxScroll <= 0) return;

            if (!_isAnimating || Math.Abs(_sv.VerticalOffset - _lastAppliedOffset) > 2.5) {
                _currentOffset = _sv.VerticalOffset;
                _targetOffset = _sv.VerticalOffset;
            }

            double step = -e.Delta * 0.85;
            _targetOffset = Math.Max(0.0, Math.Min(maxScroll, _targetOffset + step));
            e.Handled = true;

            if (!_isAnimating) {
                _isAnimating = true;
                _sw.Restart();
                _lastTimeSec = 0.0;
                CompositionTarget.Rendering += OnRendering;
            }
        }

        private void OnRendering(object sender, EventArgs e) {
            if (!_sv.IsLoaded) {
                StopAnimation();
                return;
            }

            if (Math.Abs(_sv.VerticalOffset - _lastAppliedOffset) > 2.5) {
                _currentOffset = _sv.VerticalOffset;
                _targetOffset = _sv.VerticalOffset;
                StopAnimation();
                return;
            }

            double nowSec = _sw.Elapsed.TotalSeconds;
            double dt = nowSec - _lastTimeSec;
            _lastTimeSec = nowSec;
            if (dt <= 0.0 || dt > 0.1) dt = 0.016;

            double maxScroll = _sv.ScrollableHeight;
            if (_targetOffset > maxScroll) _targetOffset = maxScroll;
            if (_targetOffset < 0.0) _targetOffset = 0.0;

            double diff = _targetOffset - _currentOffset;
            if (Math.Abs(diff) < 0.25) {
                _currentOffset = _targetOffset;
                _lastAppliedOffset = _currentOffset;
                _sv.ScrollToVerticalOffset(_currentOffset);
                StopAnimation();
                return;
            }

            double factor = 1.0 - Math.Exp(-17.0 * dt);
            _currentOffset += diff * factor;
            _lastAppliedOffset = _currentOffset;
            _sv.ScrollToVerticalOffset(_currentOffset);
        }

        private void StopAnimation() {
            if (_isAnimating) {
                _isAnimating = false;
                CompositionTarget.Rendering -= OnRendering;
                _sw.Stop();
            }
        }
    }
}
'@
        Add-Type -TypeDefinition $smoothScrollCs -ReferencedAssemblies $wpfSmoothRefs -ErrorAction SilentlyContinue
    } catch {}
}

if (-not ("DuckUtil.DeepUninstallerEngine" -as [type])) {
    try {
        $deepUninstCs = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;
using Microsoft.Win32;

namespace DuckUtil
{
    public class InstalledAppInfo
    {
        public string Id { get; set; }
        public string DisplayName { get; set; }
        public string DisplayVersion { get; set; }
        public string Publisher { get; set; }
        public string InstallDate { get; set; }
        public string InstallLocation { get; set; }
        public string UninstallString { get; set; }
        public string QuietUninstallString { get; set; }
        public string RegistryPath { get; set; }
        public string RawRegPath { get; set; }
        public string Scope { get; set; }
        public long SizeBytes { get; set; }
        public bool IsBrokenOrphan { get; set; }
    }

    public struct ScanTarget
    {
        public RegistryHive Hive;
        public RegistryView View;
        public string SubKey;
        public string Scope;
        public ScanTarget(RegistryHive h, RegistryView v, string k, string s)
        {
            Hive = h;
            View = v;
            SubKey = k;
            Scope = s;
        }
    }

    public static class DeepUninstallerEngine
    {
        private const int MOVEFILE_DELAY_UNTIL_REBOOT = 0x00000004;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);

        [DllImport("ntdll.dll", SetLastError = true)]
        private static extern int NtSuspendProcess(IntPtr processHandle);

        public static List<InstalledAppInfo> GetInstalledApps()
        {
            var list = new List<InstalledAppInfo>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            var targets = new ScanTarget[]
            {
                new ScanTarget(RegistryHive.LocalMachine, RegistryView.Registry64, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "System"),
                new ScanTarget(RegistryHive.LocalMachine, RegistryView.Registry32, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "System"),
                new ScanTarget(RegistryHive.CurrentUser, RegistryView.Default, @"Software\Microsoft\Windows\CurrentVersion\Uninstall", "User"),
                new ScanTarget(RegistryHive.CurrentUser, RegistryView.Registry32, @"Software\Microsoft\Windows\CurrentVersion\Uninstall", "User")
            };

            foreach (var target in targets)
            {
                try
                {
                    using (var baseKey = RegistryKey.OpenBaseKey(target.Hive, target.View))
                    using (var uninstallKey = baseKey.OpenSubKey(target.SubKey))
                    {
                        if (uninstallKey == null) continue;
                        foreach (var subKeyName in uninstallKey.GetSubKeyNames())
                        {
                            try
                            {
                                using (var appKey = uninstallKey.OpenSubKey(subKeyName))
                                {
                                    if (appKey == null) continue;

                                    var sysComp = appKey.GetValue("SystemComponent");
                                    if (sysComp != null && (sysComp.ToString() == "1" || ((sysComp is int) && ((int)sysComp == 1))))
                                        continue;

                                    var parentKey = appKey.GetValue("ParentKeyName") as string;
                                    if (!string.IsNullOrEmpty(parentKey)) continue;

                                    var releaseType = appKey.GetValue("ReleaseType") as string;
                                    if (!string.IsNullOrEmpty(releaseType) && (releaseType.IndexOf("Update", StringComparison.OrdinalIgnoreCase) >= 0 || releaseType.IndexOf("Hotfix", StringComparison.OrdinalIgnoreCase) >= 0))
                                        continue;

                                    var displayName = appKey.GetValue("DisplayName") as string;
                                    if (string.IsNullOrWhiteSpace(displayName)) continue;
                                    displayName = displayName.Trim();

                                    string dedupKey = displayName + "|" + (appKey.GetValue("DisplayVersion") as string ?? "");
                                    if (seen.Contains(dedupKey)) continue;
                                    seen.Add(dedupKey);

                                    var info = new InstalledAppInfo();
                                    info.Id = subKeyName;
                                    info.DisplayName = displayName;
                                    info.DisplayVersion = (appKey.GetValue("DisplayVersion") as string ?? "").Trim();
                                    info.Publisher = (appKey.GetValue("Publisher") as string ?? "").Trim();
                                    info.InstallDate = (appKey.GetValue("InstallDate") as string ?? "").Trim();
                                    string rawLoc = (appKey.GetValue("InstallLocation") as string ?? "").Trim().Trim('\"');
                                    info.UninstallString = (appKey.GetValue("UninstallString") as string ?? "").Trim();
                                    info.QuietUninstallString = (appKey.GetValue("QuietUninstallString") as string ?? "").Trim();
                                    string displayIcon = (appKey.GetValue("DisplayIcon") as string ?? "").Trim();
                                    info.InstallLocation = InferInstallLocation(rawLoc, info.UninstallString, displayIcon);
                                    info.Scope = target.Scope;

                                    string hivePrefix = target.Hive == RegistryHive.LocalMachine ? @"HKLM:\" : @"HKCU:\";
                                    string fullSub = target.SubKey + @"\" + subKeyName;
                                    info.RegistryPath = hivePrefix + fullSub;
                                    info.RawRegPath = (target.Hive == RegistryHive.LocalMachine ? "HKEY_LOCAL_MACHINE\\" : "HKEY_CURRENT_USER\\") + fullSub;

                                    long size = 0;
                                    var estSize = appKey.GetValue("EstimatedSize");
                                    if (estSize != null)
                                    {
                                        long esVal;
                                        if (long.TryParse(estSize.ToString(), out esVal))
                                        {
                                            size = esVal * 1024L;
                                        }
                                    }
                                    if (size == 0 && !string.IsNullOrEmpty(info.InstallLocation))
                                    {
                                        try
                                        {
                                            if (Directory.Exists(info.InstallLocation))
                                            {
                                                var dirInfo = new DirectoryInfo(info.InstallLocation);
                                                foreach (var fi in dirInfo.GetFiles("*", SearchOption.TopDirectoryOnly))
                                                {
                                                    size += fi.Length;
                                                }
                                            }
                                        }
                                        catch {}
                                    }
                                    info.SizeBytes = size;

                                    info.IsBrokenOrphan = CheckIsBrokenOrphan(info.UninstallString, info.InstallLocation);

                                    list.Add(info);
                                }
                            }
                            catch {}
                        }
                    }
                }
                catch {}
            }

            return list;
        }

        private static string InferInstallLocation(string installLocation, string uninstallString, string displayIcon)
        {
            if (!string.IsNullOrWhiteSpace(installLocation))
            {
                return installLocation.Trim().TrimEnd('\\');
            }

            string[] candidates = new string[] { uninstallString, displayIcon };
            foreach (string cand in candidates)
            {
                if (string.IsNullOrWhiteSpace(cand)) continue;
                if (cand.IndexOf("msiexec", StringComparison.OrdinalIgnoreCase) >= 0) continue;

                string exePath = ExtractExePath(cand);
                if (string.IsNullOrWhiteSpace(exePath)) continue;
                if (exePath.IndexOf("\\Windows\\", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    exePath.IndexOf("\\Package Cache\\", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    exePath.IndexOf("\\Temp\\", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    continue;
                }

                try
                {
                    string dir = Path.GetDirectoryName(exePath);
                    if (!string.IsNullOrWhiteSpace(dir) && dir.Length > 3)
                    {
                        return dir.TrimEnd('\\');
                    }
                }
                catch {}
            }

            return "";
        }

        private static bool CheckIsBrokenOrphan(string uninstallString, string installLocation)
        {
            if (string.IsNullOrWhiteSpace(uninstallString)) return false;
            string u = uninstallString.Trim();
            if (u.IndexOf("msiexec", StringComparison.OrdinalIgnoreCase) >= 0) return false;

            string exePath = ExtractExePath(u);
            if (string.IsNullOrEmpty(exePath)) return false;

            bool exeExists = false;
            try { exeExists = File.Exists(exePath); } catch {}

            if (!exeExists)
            {
                bool locExists = false;
                try
                {
                    if (!string.IsNullOrEmpty(installLocation) && Directory.Exists(installLocation))
                    {
                        locExists = true;
                    }
                }
                catch {}

                if (!locExists) return true;
            }

            return false;
        }

        private static string ExtractExePath(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return null;
            raw = raw.Trim();
            if (raw.StartsWith("\""))
            {
                int nextQuote = raw.IndexOf('\"', 1);
                if (nextQuote > 1)
                {
                    return raw.Substring(1, nextQuote - 1).Trim();
                }
            }

            int exeIdx = raw.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
            if (exeIdx > 0)
            {
                return raw.Substring(0, exeIdx + 4).Trim('\"', ' ');
            }

            int spaceIdx = raw.IndexOf(' ');
            if (spaceIdx > 0)
            {
                return raw.Substring(0, spaceIdx).Trim('\"', ' ');
            }

            return raw.Trim('\"', ' ');
        }

        public static long GetHollowDirectorySize(string rootPath, int maxDepth, long maxSizeLimit)
        {
            if (string.IsNullOrEmpty(rootPath)) return -1L;
            try
            {
                if (!Directory.Exists(rootPath)) return -1L;
            }
            catch { return -1L; }

            long totalSize = 0L;
            var currentLevel = new List<string> { rootPath };

            for (int depth = 0; depth <= maxDepth; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var file in Directory.EnumerateFiles(dir))
                        {
                            string ext = Path.GetExtension(file);
                            if (string.Equals(ext, ".exe", StringComparison.OrdinalIgnoreCase) ||
                                string.Equals(ext, ".dll", StringComparison.OrdinalIgnoreCase) ||
                                string.Equals(ext, ".sys", StringComparison.OrdinalIgnoreCase))
                            {
                                return -1L;
                            }
                            try
                            {
                                var fi = new FileInfo(file);
                                totalSize += fi.Length;
                                if (totalSize >= maxSizeLimit) return -1L;
                            }
                            catch {}
                        }

                        if (depth < maxDepth)
                        {
                            foreach (var sub in Directory.EnumerateDirectories(dir))
                            {
                                nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return totalSize < maxSizeLimit ? totalSize : -1L;
        }

        public static long GetDirectorySizeFast(string rootPath, int maxDepth)
        {
            if (string.IsNullOrEmpty(rootPath)) return 0L;
            try
            {
                if (!Directory.Exists(rootPath)) return 0L;
            }
            catch { return 0L; }

            long totalSize = 0L;
            var currentLevel = new List<string> { rootPath };

            for (int depth = 0; depth <= maxDepth; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var file in Directory.EnumerateFiles(dir))
                        {
                            try
                            {
                                var fi = new FileInfo(file);
                                totalSize += fi.Length;
                            }
                            catch {}
                        }

                        if (depth < maxDepth)
                        {
                            foreach (var sub in Directory.EnumerateDirectories(dir))
                            {
                                nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return totalSize;
        }

        private static List<string> EnumerateFilesSafe(string rootDir, string pattern, int maxDepth)
        {
            var results = new List<string>();
            if (string.IsNullOrEmpty(rootDir)) return results;
            try
            {
                if (!Directory.Exists(rootDir)) return results;
            }
            catch { return results; }

            var currentLevel = new List<string> { rootDir };

            for (int depth = 0; depth <= maxDepth; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var file in Directory.EnumerateFiles(dir, pattern))
                        {
                            results.Add(file);
                        }

                        if (depth < maxDepth)
                        {
                            foreach (var sub in Directory.EnumerateDirectories(dir))
                            {
                                nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return results;
        }

        private static List<string> EnumerateDirectoriesSafe(string rootDir, int maxDepth)
        {
            var results = new List<string>();
            if (string.IsNullOrEmpty(rootDir)) return results;
            try
            {
                if (!Directory.Exists(rootDir)) return results;
            }
            catch { return results; }

            var currentLevel = new List<string> { rootDir };

            for (int depth = 0; depth <= maxDepth; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var sub in Directory.EnumerateDirectories(dir))
                        {
                            results.Add(sub);
                            if (depth < maxDepth)
                            {
                                nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return results;
        }

        private static string GetSignerSubject(string filePath)
        {
            if (string.IsNullOrEmpty(filePath)) return "";
            try
            {
                MethodInfo method = typeof(X509Certificate).GetMethod("CreateFromSignedFile", new Type[] { typeof(string) });
                if (method != null)
                {
                    object cert = method.Invoke(null, new object[] { filePath });
                    if (cert != null)
                    {
                        PropertyInfo prop = cert.GetType().GetProperty("Subject");
                        if (prop != null)
                        {
                            return prop.GetValue(cert, null) as string ?? "";
                        }
                    }
                }
            }
            catch {}
            return "";
        }

        public static int StopProcessesInDirectory(string targetDir)
        {
            if (string.IsNullOrWhiteSpace(targetDir)) return 0;
            string prefix = targetDir.Trim().TrimEnd('\\') + "\\";
            if (prefix.Length <= 4) return 0;

            Process[] procs = null;
            try { procs = Process.GetProcesses(); } catch { return 0; }

            var matched = new List<Process>();
            foreach (Process p in procs)
            {
                try
                {
                    if (p.Id <= 4) { p.Dispose(); continue; }
                    string fileName = null;
                    try
                    {
                        if (p.MainModule != null) fileName = p.MainModule.FileName;
                    }
                    catch {}

                    if (!string.IsNullOrEmpty(fileName) &&
                        fileName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    {
                        try
                        {
                            IntPtr h = p.Handle;
                            NtSuspendProcess(h);
                        }
                        catch {}
                        matched.Add(p);
                    }
                    else
                    {
                        p.Dispose();
                    }
                }
                catch
                {
                    try { p.Dispose(); } catch {}
                }
            }

            int killed = 0;
            foreach (Process mp in matched)
            {
                try
                {
                    mp.Kill();
                    mp.WaitForExit(1500);
                    killed++;
                }
                catch {}
                finally
                {
                    try { mp.Dispose(); } catch {}
                }
            }
            return killed;
        }

        public static int DisableAndRemoveServicesInDirectory(string targetDir)
        {
            if (string.IsNullOrWhiteSpace(targetDir)) return 0;
            string prefix = targetDir.Trim().TrimEnd('\\') + "\\";
            if (prefix.Length <= 4) return 0;

            int neutralized = 0;
            try
            {
                using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (var svcRoot = baseKey.OpenSubKey(@"SYSTEM\CurrentControlSet\Services", true))
                {
                    if (svcRoot == null) return 0;
                    foreach (string svcName in svcRoot.GetSubKeyNames())
                    {
                        try
                        {
                            bool matches = false;
                            using (var sk = svcRoot.OpenSubKey(svcName, true))
                            {
                                if (sk == null) continue;
                                string imgPath = (sk.GetValue("ImagePath") as string ?? "").Trim('\"', ' ');
                                if (string.IsNullOrEmpty(imgPath)) continue;
                                if (imgPath.StartsWith(@"\??\", StringComparison.OrdinalIgnoreCase))
                                {
                                    imgPath = imgPath.Substring(4);
                                }
                                if (imgPath.IndexOf(prefix, StringComparison.OrdinalIgnoreCase) >= 0)
                                {
                                    matches = true;
                                    try { sk.SetValue("Start", 4, RegistryValueKind.DWord); } catch {}
                                    try { sk.DeleteValue("FailureActions", false); } catch {}
                                }
                            }

                            if (matches)
                            {
                                neutralized++;
                                RunHiddenSc("stop \"" + svcName + "\"");
                                RunHiddenSc("delete \"" + svcName + "\"");
                            }
                        }
                        catch {}
                    }
                }
            }
            catch {}
            return neutralized;
        }

        public static int RemoveScheduledTasksInDirectory(string targetDir)
        {
            if (string.IsNullOrWhiteSpace(targetDir)) return 0;
            string prefix = targetDir.Trim().TrimEnd('\\') + "\\";
            if (prefix.Length <= 4) return 0;

            int removed = 0;
            string tasksRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "Tasks");
            if (!Directory.Exists(tasksRoot)) return 0;

            try
            {
                foreach (string taskFile in EnumerateFilesSafe(tasksRoot, "*", 6))
                {
                    try
                    {
                        if (taskFile.IndexOf(@"\Tasks\Microsoft\Windows\", StringComparison.OrdinalIgnoreCase) >= 0)
                            continue;

                        string xml = File.ReadAllText(taskFile);
                        if (xml.IndexOf(prefix, StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            string relTaskName = taskFile.Substring(tasksRoot.Length);
                            try
                            {
                                var psi = new ProcessStartInfo("schtasks.exe", "/Delete /TN \"" + relTaskName + "\" /F");
                                psi.CreateNoWindow = true;
                                psi.UseShellExecute = false;
                                using (var p = Process.Start(psi))
                                {
                                    if (p != null) p.WaitForExit(2000);
                                }
                            }
                            catch {}
                            try
                            {
                                File.SetAttributes(taskFile, FileAttributes.Normal);
                                File.Delete(taskFile);
                            }
                            catch {}
                            removed++;
                        }
                    }
                    catch {}
                }
            }
            catch {}
            return removed;
        }

        private static void RunHiddenSc(string args)
        {
            try
            {
                var psi = new ProcessStartInfo("sc.exe", args);
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                using (var p = Process.Start(psi))
                {
                    if (p != null) p.WaitForExit(2000);
                }
            }
            catch {}
        }

        public static bool VerifyDirectoryExeOwnership(string targetDir, string[] expectedKeywords)
        {
            if (string.IsNullOrWhiteSpace(targetDir) || expectedKeywords == null || expectedKeywords.Length == 0)
                return false;
            try
            {
                if (!Directory.Exists(targetDir)) return false;
                int checkedCount = 0;
                foreach (string file in EnumerateFilesSafe(targetDir, "*", 4))
                {
                    string ext = Path.GetExtension(file);
                    if (!string.Equals(ext, ".exe", StringComparison.OrdinalIgnoreCase) &&
                        !string.Equals(ext, ".dll", StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    checkedCount++;
                    if (checkedCount > 15) break;

                    try
                    {
                        FileVersionInfo fvi = FileVersionInfo.GetVersionInfo(file);
                        string certSubj = GetSignerSubject(file);

                        string combined = (fvi.ProductName ?? "") + " | " + (fvi.CompanyName ?? "") + " | " + (fvi.FileDescription ?? "") + " | " + (fvi.InternalName ?? "") + " | " + (fvi.OriginalFilename ?? "") + " | " + certSubj;
                        foreach (string kw in expectedKeywords)
                        {
                            if (string.IsNullOrWhiteSpace(kw) || kw.Length < 2) continue;
                            if (combined.IndexOf(kw, StringComparison.OrdinalIgnoreCase) >= 0)
                            {
                                return true;
                            }
                        }
                    }
                    catch {}
                }
            }
            catch {}
            return false;
        }

        public static string[] ExtractBinaryAndCertTokens(string targetDir, string uninstallString, string displayIcon)
        {
            var results = new List<string>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var ignoreWords = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "uninstall", "uninst", "unins000", "unins001", "setup", "install", "installer",
                "update", "updater", "helper", "launcher", "client", "app", "application",
                "main", "bin", "x64", "x86", "win32", "win64", "release", "debug", "program files",
                "program files (x86)", "common files", "programs", "appdata", "local", "roaming",
                "windows", "system32", "temp", "microsoft", "corporation", "company", "limited",
                "ltd", "inc", "llc", "corp", "co", "technology", "software", "network", "beijing",
                "shenzhen", "guangzhou", "shanghai", "hangzhou", "china"
            };

            string[] exeSources = new string[] { uninstallString, displayIcon };
            foreach (string src in exeSources)
            {
                string exe = ExtractExePath(src);
                if (!string.IsNullOrWhiteSpace(exe))
                {
                    try
                    {
                        string baseName = Path.GetFileNameWithoutExtension(exe);
                        if (!string.IsNullOrWhiteSpace(baseName) && baseName.Length >= 3 && !ignoreWords.Contains(baseName))
                        {
                            if (seen.Add(baseName)) results.Add(baseName);
                        }
                    }
                    catch {}
                }
            }

            if (!string.IsNullOrWhiteSpace(targetDir) && Directory.Exists(targetDir))
            {
                try
                {
                    int count = 0;
                    foreach (string file in EnumerateFilesSafe(targetDir, "*.exe", 4))
                    {
                        count++;
                        if (count > 8) break;
                        string fn = Path.GetFileNameWithoutExtension(file);
                        if (!string.IsNullOrWhiteSpace(fn) && fn.Length >= 3 && !ignoreWords.Contains(fn))
                        {
                            if (seen.Add(fn)) results.Add(fn);
                        }

                        try
                        {
                            FileVersionInfo fvi = FileVersionInfo.GetVersionInfo(file);
                            string[] fields = new string[] { fvi.ProductName, fvi.CompanyName, fvi.InternalName };
                            foreach (string f in fields)
                            {
                                if (string.IsNullOrWhiteSpace(f)) continue;
                                string clean = f.Replace(".exe", "").Replace(".dll", "").Trim();
                                if (clean.Length >= 3 && clean.Length <= 30 && !ignoreWords.Contains(clean))
                                {
                                    if (seen.Add(clean)) results.Add(clean);
                                }
                            }
                        }
                        catch {}

                        try
                        {
                            string certSubj = GetSignerSubject(file);
                            if (!string.IsNullOrWhiteSpace(certSubj))
                            {
                                string[] parts = certSubj.Split(',');
                                foreach (string part in parts)
                                {
                                    string p = part.Trim();
                                    if (p.StartsWith("CN=", StringComparison.OrdinalIgnoreCase) ||
                                        p.StartsWith("O=", StringComparison.OrdinalIgnoreCase))
                                    {
                                        string val = p.Substring(p.IndexOf('=') + 1).Trim('\"', ' ');
                                        string[] words = val.Split(new char[] { ' ', '(', ')', '.', ',', '-' }, StringSplitOptions.RemoveEmptyEntries);
                                        foreach (string w in words)
                                        {
                                            if (w.Length >= 4 && !ignoreWords.Contains(w))
                                            {
                                                if (seen.Add(w)) results.Add(w);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        catch {}
                    }
                }
                catch {}
            }

            return results.ToArray();
        }

        public static bool ForceDeleteDirectory(string targetDir, out int rebootScheduledCount)
        {
            rebootScheduledCount = 0;
            if (string.IsNullOrWhiteSpace(targetDir)) return false;
            string norm = targetDir.Trim().TrimEnd('\\');
            if (norm.Length <= 3) return false;

            if (File.Exists(norm))
            {
                try
                {
                    File.SetAttributes(norm, FileAttributes.Normal);
                    File.Delete(norm);
                    return true;
                }
                catch
                {
                    if (MoveFileEx(norm, null, MOVEFILE_DELAY_UNTIL_REBOOT))
                    {
                        rebootScheduledCount++;
                        return true;
                    }
                    return false;
                }
            }

            if (!Directory.Exists(norm)) return true;

            DisableAndRemoveServicesInDirectory(norm);
            RemoveScheduledTasksInDirectory(norm);
            StopProcessesInDirectory(norm);

            try
            {
                foreach (string file in EnumerateFilesSafe(norm, "*", 10))
                {
                    try
                    {
                        File.SetAttributes(file, FileAttributes.Normal);
                        File.Delete(file);
                    }
                    catch
                    {
                        string deadPath = file + ".dead_" + Guid.NewGuid().ToString("N").Substring(0, 6);
                        try
                        {
                            File.Move(file, deadPath);
                            if (MoveFileEx(deadPath, null, MOVEFILE_DELAY_UNTIL_REBOOT))
                            {
                                rebootScheduledCount++;
                            }
                        }
                        catch
                        {
                            if (MoveFileEx(file, null, MOVEFILE_DELAY_UNTIL_REBOOT))
                            {
                                rebootScheduledCount++;
                            }
                        }
                    }
                }
            }
            catch {}

            try
            {
                List<string> subDirs = EnumerateDirectoriesSafe(norm, 10);
                subDirs.Sort(delegate(string a, string b) { return b.Length.CompareTo(a.Length); });
                foreach (string sd in subDirs)
                {
                    try
                    {
                        File.SetAttributes(sd, FileAttributes.Normal);
                        Directory.Delete(sd, true);
                    }
                    catch
                    {
                        MoveFileEx(sd, null, MOVEFILE_DELAY_UNTIL_REBOOT);
                    }
                }
            }
            catch {}

            try
            {
                File.SetAttributes(norm, FileAttributes.Normal);
                Directory.Delete(norm, true);
                return true;
            }
            catch
            {
                if (MoveFileEx(norm, null, MOVEFILE_DELAY_UNTIL_REBOOT))
                {
                    rebootScheduledCount++;
                    return true;
                }
                return false;
            }
        }

        public static long BackupDirectorySnapshot(string sourceDir, string backupDir, long maxTotalBytes)
        {
            if (string.IsNullOrWhiteSpace(sourceDir) || string.IsNullOrWhiteSpace(backupDir))
                return 0L;
            try
            {
                if (!Directory.Exists(sourceDir)) return 0L;
            }
            catch { return 0L; }

            if (maxTotalBytes <= 0) maxTotalBytes = 104857600L;

            var skipExts = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                ".exe", ".dll", ".sys", ".pdb", ".pak", ".node", ".obj", ".iso", ".vmdk"
            };

            long totalBytes = 0L;
            int srcLen = sourceDir.TrimEnd('\\').Length;

            var currentLevel = new List<string> { sourceDir };
            for (int depth = 0; depth <= 8; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var file in Directory.EnumerateFiles(dir))
                        {
                            try
                            {
                                string ext = Path.GetExtension(file);
                                if (!string.IsNullOrEmpty(ext) && skipExts.Contains(ext))
                                    continue;

                                var fi = new FileInfo(file);
                                if (fi.Length > 20971520L) continue;
                                if (totalBytes + fi.Length > maxTotalBytes) continue;

                                string relPath = file.Substring(srcLen).TrimStart('\\');
                                string destFile = Path.Combine(backupDir, relPath);
                                string destDir = Path.GetDirectoryName(destFile);
                                if (!string.IsNullOrEmpty(destDir) && !Directory.Exists(destDir))
                                {
                                    Directory.CreateDirectory(destDir);
                                }

                                File.Copy(file, destFile, true);
                                totalBytes += fi.Length;
                            }
                            catch {}
                        }

                        if (depth < 8)
                        {
                            foreach (var sub in Directory.EnumerateDirectories(dir))
                            {
                                nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return totalBytes;
        }

        public static int RestoreDirectorySnapshot(string backupDir, string targetDir)
        {
            if (string.IsNullOrWhiteSpace(backupDir) || string.IsNullOrWhiteSpace(targetDir))
                return 0;
            try
            {
                if (!Directory.Exists(backupDir)) return 0;
            }
            catch { return 0; }

            int restoredCount = 0;
            int bkpLen = backupDir.TrimEnd('\\').Length;

            var currentLevel = new List<string> { backupDir };
            for (int depth = 0; depth <= 8; depth++)
            {
                var nextLevel = new List<string>();
                foreach (var dir in currentLevel)
                {
                    try
                    {
                        foreach (var file in Directory.EnumerateFiles(dir))
                        {
                            try
                            {
                                string relPath = file.Substring(bkpLen).TrimStart('\\');
                                string destFile = Path.Combine(targetDir, relPath);
                                string destDir = Path.GetDirectoryName(destFile);
                                if (!string.IsNullOrEmpty(destDir) && !Directory.Exists(destDir))
                                {
                                    Directory.CreateDirectory(destDir);
                                }

                                File.Copy(file, destFile, true);
                                restoredCount++;
                            }
                            catch {}
                        }

                        if (depth < 8)
                        {
                            foreach (var sub in Directory.EnumerateDirectories(dir))
                            {
                                nextLevel.Add(sub);
                            }
                        }
                    }
                    catch {}
                }
                if (nextLevel.Count == 0) break;
                currentLevel = nextLevel;
            }

            return restoredCount;
        }
    }
}
'@
        Add-Type -TypeDefinition $deepUninstCs -ErrorAction SilentlyContinue
    } catch {}
}

$script:activeChildProcess = $null
$script:isWindowClosing    = $false

function Stop-ActiveChildProcess {
    try {
        if ($script:activeChildProcess -and -not $script:activeChildProcess.HasExited) {
            $pidToKill = $script:activeChildProcess.Id
            try {
                Start-Process "taskkill.exe" -ArgumentList "/F /T /PID $pidToKill" -NoNewWindow -Wait -ErrorAction SilentlyContinue
            } catch {}
            try {
                $script:activeChildProcess.Kill()
            } catch {}
        }
    } catch {}
}

function Log-Text {
    param([string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    $clean = $text -replace '\x1B\[[0-9;]*[a-zA-Z]', ''
    if ($clean.Contains("`r")) {
        $parts = $clean -split "`r"
        $clean = $parts[-1]
    }
    $trimmed = $clean.TrimEnd("`r", "`n")
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return }

    $trimmed = $trimmed.Replace("[✓]", "[OK]").Replace("[✓ ", "[OK - ").Replace("✓", "OK")
    $trimmed = $trimmed.Replace("[❌]", "[ERR]").Replace("[❌ ", "[ERR - ").Replace("❌", "ERR")
    $trimmed = $trimmed.Replace("[⚠️]", "[WARN]").Replace("[⚠️ ", "[WARN - ").Replace("⚠️", "WARN")
    $trimmed = $trimmed.Replace("[🔍]", "[SCAN]").Replace("🔍 ", "").Replace("🔍", "")
    $trimmed = $trimmed.Replace("[↗]", "[WEB]").Replace("↗", "->")
    $trimmed = $trimmed.Replace("🟢 ", "").Replace("🔴 ", "").Replace("🚀 ", "").Replace("⚡ ", "").Replace("🗑️ ", "")
    $trimmed = $trimmed.Replace("•", "-").Replace("─", "-")

    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $color = [System.ConsoleColor]::Gray

    if ($trimmed -match '^={4,}|^-{4,}|^\s*-{4,}') {
        $color = [System.ConsoleColor]::DarkCyan
    } elseif ($trimmed -match '\[OK|HOÀN THÀNH|THÀNH CÔNG') {
        $color = [System.ConsoleColor]::Green
    } elseif ($trimmed -match '\[ERR|\[x\]|LỖI') {
        $color = [System.ConsoleColor]::Red
    } elseif ($trimmed -match '\[!\]|\[WARN|\[LOCK\]') {
        $color = [System.ConsoleColor]::Yellow
    } elseif ($trimmed -match '\[SCAN\]|BẮT ĐẦU|ĐANG QUÉT') {
        $color = [System.ConsoleColor]::Cyan
    } elseif ($trimmed -match '\[CLEAN\]') {
        $color = [System.ConsoleColor]::Magenta
    } elseif ($trimmed -match '^\[\d+/\d+\]') {
        $color = [System.ConsoleColor]::White
    }

    try {
        Write-Host "[$timestamp] $trimmed" -ForegroundColor $color
    } catch {
        [Console]::WriteLine("[$timestamp] $trimmed")
    }
}

function Run-CliStream {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        [Parameter(Mandatory = $false)]
        [string]$Args = ""
    )

    try {
        $timestamp = (Get-Date).ToString("HH:mm:ss")
        try {
            Write-Host "[$timestamp] > $FileName $Args" -ForegroundColor DarkGray
        } catch {}

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $FileName
        $pinfo.Arguments = $Args
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $false
        $pinfo.RedirectStandardOutput = $false
        $pinfo.RedirectStandardError = $false

        $p = [System.Diagnostics.Process]::Start($pinfo)
        if ($null -eq $p) {
            Log-Text "[!] Không thể khởi động tiến trình: $FileName"
            return -1
        }

        $script:activeChildProcess = $p
        try {
            while (-not $p.HasExited) {
                if ($script:isWindowClosing) {
                    Stop-ActiveChildProcess
                    break
                }
                try { [System.Windows.Forms.Application]::DoEvents() } catch {}
                Start-Sleep -Milliseconds 25
            }

            try { [void]$p.WaitForExit(1000) } catch {}
            try { [System.Windows.Forms.Application]::DoEvents() } catch {}
            $exitCode = try { $p.ExitCode } catch { -1 }
            return $exitCode
        } finally {
            $script:activeChildProcess = $null
            try { $p.Dispose() } catch {}
        }
    } catch {
        Log-Text "[!] Lỗi khi thực thi lệnh [$FileName $Args]: $($_.Exception.Message)"
        return -1
    }
}

$script:brushOutdatedFg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF8, 0x71, 0x71))
$script:brushLatestFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x34, 0xD3, 0x99))
$script:brushNoneBg     = [System.Windows.Media.Brushes]::Transparent
$script:brushNoneFg     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF1, 0xF5, 0xF9))

$script:brushOutdatedFg.Freeze()
$script:brushLatestFg.Freeze()
$script:brushNoneFg.Freeze()

function Get-CleanAppName {
    param([string]$RawName)
    if ([string]::IsNullOrWhiteSpace($RawName)) { return "" }
    $clean = ($RawName -replace '\((?!x64|x86|arm64).*?\)', '').Replace('(', '').Replace(')', '').Trim().ToLowerInvariant()
    $terms = @(" browser", " desktop", " lts", " client", " free", " ce", " community", " end-user")
    foreach ($term in $terms) {
        $clean = $clean.Replace($term, "")
    }
    return $clean.Trim()
}

function Get-CharDisplayWidth {
    param([int]$Code)
    if (
        ($Code -ge 0x1100 -and $Code -le 0x115F) -or
        ($Code -eq 0x2329 -or $Code -eq 0x232A) -or
        ($Code -ge 0x2E80 -and $Code -le 0x303E) -or
        ($Code -ge 0x3041 -and $Code -le 0x33FF) -or
        ($Code -ge 0x3400 -and $Code -le 0x4DBF) -or
        ($Code -ge 0x4E00 -and $Code -le 0xA4CF) -or
        ($Code -ge 0xA960 -and $Code -le 0xA97F) -or
        ($Code -ge 0xAC00 -and $Code -le 0xD7AF) -or
        ($Code -ge 0xF900 -and $Code -le 0xFAFF) -or
        ($Code -ge 0xFE10 -and $Code -le 0xFE19) -or
        ($Code -ge 0xFE30 -and $Code -le 0xFE6F) -or
        ($Code -ge 0xFF01 -and $Code -le 0xFF60) -or
        ($Code -ge 0xFFE0 -and $Code -le 0xFFE6) -or
        ($Code -ge 0x1F300 -and $Code -le 0x1FAFF)
    ) { return 2 }
    return 1
}

function Get-SliceByDisplayWidth {
    param([string]$Line, [int[]]$Offsets)
    $idIdx    = if ($Offsets.Count -ge 2) { $Offsets[1] } else { -1 }
    $verIdx   = if ($Offsets.Count -ge 3) { $Offsets[2] } else { -1 }
    $availIdx = if ($Offsets.Count -ge 4) { $Offsets[3] } else { -1 }
    $srcIdx   = if ($Offsets.Count -ge 5) { $Offsets[4] } else { -1 }

    $targets = @($idIdx, $verIdx, $availIdx, $srcIdx)
    $charPos = @(-1, -1, -1, -1)
    $w = 0
    for ($i = 0; $i -lt $Line.Length; $i++) {
        for ($t = 0; $t -lt 4; $t++) {
            if ($charPos[$t] -lt 0 -and $targets[$t] -ge 0 -and $w -ge $targets[$t]) {
                $charPos[$t] = $i
            }
        }
        $ch = $Line[$i]
        if ([char]::IsHighSurrogate($ch) -and ($i + 1) -lt $Line.Length -and [char]::IsLowSurrogate($Line[$i + 1])) {
            $cp = [char]::ConvertToUtf32($ch, $Line[$i + 1])
            $w += Get-CharDisplayWidth $cp
            $i++
        } else {
            $w += Get-CharDisplayWidth ([int]$ch)
        }
    }

    $cId    = $charPos[0]
    $cVer   = $charPos[1]
    $cAvail = $charPos[2]
    $cSrc   = $charPos[3]

    $appName = ""; $appId = ""; $version = ""; $avail = ""
    if ($cId -gt 0 -and $Line.Length -gt $cId) {
        $appName = $Line.Substring(0, $cId).Trim()
        if ($cVer -gt $cId -and $Line.Length -gt $cVer) {
            $appId = $Line.Substring($cId, $cVer - $cId).Trim()
            if ($cAvail -gt $cVer -and $Line.Length -gt $cAvail) {
                $version = $Line.Substring($cVer, $cAvail - $cVer).Trim()
                if ($cSrc -gt $cAvail -and $Line.Length -gt $cSrc) {
                    $avail = $Line.Substring($cAvail, $cSrc - $cAvail).Trim()
                } else {
                    $avail = $Line.Substring($cAvail).Trim()
                }
            } else {
                $version = $Line.Substring($cVer).Trim()
            }
        } else {
            $appId = $Line.Substring($cId).Trim()
        }
    }
    return @($appName, $appId, $version, $avail)
}

function Set-PreferredMapEntry {
    param($Map, [string]$Key, $Candidate)
    if ([string]::IsNullOrWhiteSpace($Key)) { return }
    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = $Candidate
        return
    }
    $cur = $Map[$Key]
    $preferUpdate = (-not $cur.HasUpdate -and $Candidate.HasUpdate)
    $preferNativeId = ($cur.HasUpdate -eq $Candidate.HasUpdate -and $cur.ID -match '^(ARP|MSIX)\\' -and $Candidate.ID -notmatch '^(ARP|MSIX)\\')
    if ($preferUpdate -or $preferNativeId) {
        $Map[$Key] = $Candidate
    }
}

function Test-MatchCompatible {
    param($TargetApp, $Item)
    if (-not $TargetApp -or -not $Item) { return $false }

    $tName = [string]$TargetApp.Name
    $tId   = [string]$TargetApp.ID
    $iName = [string]$Item.Name
    $iId   = [string]$Item.ID

    $tPrev = ($tName -match 'Preview') -or ($tId -match 'Preview')
    $iPrev = ($iName -match 'Preview') -or ($iId -match 'Preview')
    if ($tPrev -ne $iPrev) { return $false }

    if (($tId -match 'VCRedist' -or $tName -match 'VC\+\+') -and ($iName -match '\bUWP\b' -or $iId -match 'VCLibs')) {
        return $false
    }

    $tComm = ($tName -match '\bCommunity\b') -or ($tId -match '\.Community\b')
    $tPro  = ($tName -match '\b(Ultimate|Professional)\b') -or ($tId -match '\.(Ultimate|Professional)\b')
    $iComm = ($iName -match '\bCommunity\b') -or ($iId -match '\.Community\b')
    $iPro  = ($iName -match '\b(Ultimate|Professional)\b') -or ($iId -match '\.(Ultimate|Professional)\b')
    if (($tComm -and $iPro) -or ($tPro -and $iComm)) { return $false }

    $tIde = ($tName -match '\bIDE\b') -or ($tId -match 'IDE$')
    $iIde = ($iName -match '\bIDE\b') -or ($iId -match 'IDE$')
    if ($tIde -ne $iIde -and ($tId -match 'Antigravity' -or $iId -match 'Antigravity')) { return $false }

    $tCli = ($tName -match '\bCLI\b') -or ($tId -match '(\.cli|CLI)$')
    $iCli = ($iName -match '\bCLI\b') -or ($iId -match '(\.cli|CLI)$')
    if ($tCli -ne $iCli) { return $false }

    $tBt = ($tName -match 'Build Tools') -or ($tId -match 'BuildTools')
    $iBt = ($iName -match 'Build Tools') -or ($iId -match 'BuildTools')
    if ($tBt -ne $iBt) { return $false }

    $tVsc = ($tId -match 'VisualStudioCode') -or ($tName -match 'VS Code|Visual Studio Code')
    $iVsc = ($iId -match 'VisualStudioCode') -or ($iName -match 'VS Code|Visual Studio Code')
    if ($tVsc -ne $iVsc -and ($tId -match 'VisualStudio' -or $iId -match 'VisualStudio')) { return $false }

    $tEtb = ($tId -match 'EverythingToolbar') -or ($tName -match 'EverythingToolbar')
    $iEtb = ($iId -match 'EverythingToolbar') -or ($iName -match 'EverythingToolbar')
    if ($tEtb -ne $iEtb) { return $false }

    if ($tId -match 'Temurin' -and ($iId -match 'Oracle|Corretto' -or $iName -match 'Corretto|^Java \d+ Update')) { return $false }
    if ($tId -match 'Oracle\.Java' -and ($iId -match 'Temurin|Corretto' -or $iName -match 'Temurin|Corretto')) { return $false }
    if ($tId -match 'Corretto' -and ($iId -match 'Temurin|Oracle' -or $iName -match 'Temurin|^Java \d+ Update')) { return $false }

    $tArch = if ($tName -match '\(x64\)|\.x64' -or $tId -match '\.x64$') { "x64" }
             elseif ($tName -match '\(x86\)|\.x86' -or $tId -match '\.x86$') { "x86" }
             elseif ($tName -match '\(arm64\)|\.arm64' -or $tId -match '\.arm64$') { "arm64" }
             else { "" }

    if ($tArch) {
        $idForArch = if ($iId -match '^(ARP|MSIX)\\') { "" } else { $iId }
        $iArch = if ($iName -match '(?<![a-zA-Z0-9])(x64|64-bit)(?![a-zA-Z0-9])' -or $idForArch -match '\.x64$') { "x64" }
                 elseif ($iName -match '(?<![a-zA-Z0-9])(x86|32-bit)(?![a-zA-Z0-9])' -or $idForArch -match '\.x86$') { "x86" }
                 elseif ($iName -match '(?<![a-zA-Z0-9])arm64(?![a-zA-Z0-9])' -or $idForArch -match '\.arm64$') { "arm64" }
                 else { "" }
        if ($iArch -and $iArch -ne $tArch) { return $false }
    }

    return $true
}

$script:isScanningApps = $false
$script:hasCompletedAppScan = $false

function Invoke-WingetListCapture {
    param(
        [string]$Arguments = "list --disable-interactivity --accept-source-agreements",
        [int]$TimeoutSeconds = 35
    )

    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{
            Available = $false
            TimedOut  = $false
            ExitCode  = -1
            StdOut    = ""
            StdErr    = ""
        }
    }

    $rawList = ""
    $errList = ""
    $timedOut = $false
    $exitCode = -1

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "winget"
    $pinfo.Arguments = $Arguments
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $pinfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($pinfo)
    if ($null -eq $p) {
        throw "Không thể khởi động tiến trình winget."
    }

    $readTask = $p.StandardOutput.ReadToEndAsync()
    $errTask  = $p.StandardError.ReadToEndAsync()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $readTask.IsCompleted -or -not $errTask.IsCompleted) {
        if ($sw.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
            $timedOut = $true
            try { if (-not $p.HasExited) { $p.Kill() } } catch {}
            break
        }
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
        Start-Sleep -Milliseconds 30
    }

    try { if (-not $p.HasExited) { $p.WaitForExit(1000) | Out-Null } } catch {}
    if ($readTask.IsCompleted) { $rawList = $readTask.Result }
    if ($errTask.IsCompleted)  { $errList = $errTask.Result }
    if ($p.HasExited) { $exitCode = $p.ExitCode }

    return [PSCustomObject]@{
        Available = $true
        TimedOut  = $timedOut
        ExitCode  = $exitCode
        StdOut    = $rawList
        StdErr    = $errList
    }
}

function ConvertFrom-WingetListOutput {
    param(
        [string]$RawText,
        [bool]$AllowHeaderless = $false
    )

    $parsed = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($RawText)) {
        return [PSCustomObject]@{ HasTable = $false; Items = $parsed }
    }

    $rawLines = $RawText -split "`n"
    $lines = [System.Collections.Generic.List[string]]::new($rawLines.Count)
    foreach ($rl in $rawLines) {
        $cleanLine = $rl.TrimEnd("`r")
        if ($cleanLine.Contains("`r")) { $cleanLine = ($cleanLine -split "`r")[-1] }
        if ($cleanLine.Contains([char]0x1B)) {
            $cleanLine = [System.Text.RegularExpressions.Regex]::Replace($cleanLine, '\x1B\[[0-9;?]*[A-Za-z]', '')
        }
        $lines.Add($cleanLine)
    }

    $separatorIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^---+(\s+---+)*\s*$') {
            $separatorIndex = $i
            break
        }
    }

    if ($separatorIndex -gt 0) {
        $separatorLine = $lines[$separatorIndex]
        $headerLine    = $lines[$separatorIndex - 1]

        $colOffsets = @()
        if ($separatorLine -match '---+\s+---+') {
            $dashMatches = [System.Text.RegularExpressions.Regex]::Matches($separatorLine, '-+')
            foreach ($dm in $dashMatches) { $colOffsets += $dm.Index }
        } elseif ($headerLine) {
            $headerMatches = [System.Text.RegularExpressions.Regex]::Matches($headerLine, '[^\s]+(?:\s[^\s]+)*(?=\s{2,}|\s*$)')
            foreach ($hm in $headerMatches) { $colOffsets += $hm.Index }
        }

        $idIdx    = if ($colOffsets.Count -ge 2) { $colOffsets[1] } else { -1 }
        $verIdx   = if ($colOffsets.Count -ge 3) { $colOffsets[2] } else { -1 }
        $availIdx = if ($colOffsets.Count -ge 4) { $colOffsets[3] } else { -1 }
        $srcIdx   = if ($colOffsets.Count -ge 5) { $colOffsets[4] } else { -1 }

        for ($j = $separatorIndex + 1; $j -lt $lines.Count; $j++) {
            $line = $lines[$j]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $appName = ""; $appId = ""; $version = ""; $avail = ""

            if ($idIdx -gt 0 -and $line -match '[^\x00-\xFF]') {
                $sliced = Get-SliceByDisplayWidth -Line $line -Offsets $colOffsets
                $appName = $sliced[0]; $appId = $sliced[1]; $version = $sliced[2]; $avail = $sliced[3]
            } elseif ($idIdx -gt 0 -and $line.Length -gt $idIdx) {
                $appName = $line.Substring(0, $idIdx).Trim()
                if ($verIdx -gt $idIdx -and $line.Length -gt $verIdx) {
                    $appId = $line.Substring($idIdx, $verIdx - $idIdx).Trim()
                    if ($availIdx -gt $verIdx -and $line.Length -gt $availIdx) {
                        $version = $line.Substring($verIdx, $availIdx - $verIdx).Trim()
                        if ($srcIdx -gt $availIdx -and $line.Length -gt $srcIdx) {
                            $avail = $line.Substring($availIdx, $srcIdx - $availIdx).Trim()
                        } else {
                            $avail = $line.Substring($availIdx).Trim()
                        }
                    } else {
                        $version = $line.Substring($verIdx).Trim()
                    }
                } else {
                    $appId = $line.Substring($idIdx).Trim()
                }
            } else {
                $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                if ($cols.Count -ge 2) {
                    $appName = $cols[0].Trim()
                    $appId   = $cols[1].Trim()
                    $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    $avail   = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($appId)) {
                $hasUpdate = (-not [string]::IsNullOrWhiteSpace($avail)) -and ($avail -ne "winget") -and ($avail -ne "msstore")
                $clean = Get-CleanAppName $appName
                $parsed.Add([PSCustomObject]@{
                    Name      = $appName
                    ID        = $appId
                    Version   = $version
                    Available = $avail
                    HasUpdate = $hasUpdate
                    CleanName = $clean
                })
            }
        }
    } elseif ($AllowHeaderless) {
        foreach ($line in $lines) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and -not ($line -like "---*")) {
                $cols = [System.Text.RegularExpressions.Regex]::Split($line.Trim(), '\s{2,}')
                if ($cols.Count -ge 2) {
                    $appName = $cols[0].Trim()
                    $appId   = $cols[1].Trim()
                    if ($appId -notmatch '^(ARP|MSIX)\\|\S+\.\S+') { continue }
                    $version = if ($cols.Count -ge 3) { $cols[2].Trim() } else { "" }
                    $avail   = if ($cols.Count -ge 4) { $cols[3].Trim() } else { "" }
                    $hasUpdate = ($cols.Count -ge 5 -or ($cols.Count -eq 4 -and $avail -ne "winget" -and $avail -ne "msstore" -and $avail -ne ""))
                    $clean = Get-CleanAppName $appName

                    $parsed.Add([PSCustomObject]@{
                        Name      = $appName
                        ID        = $appId
                        Version   = $version
                        Available = $avail
                        HasUpdate = $hasUpdate
                        CleanName = $clean
                    })
                }
            }
        }
    }

    return [PSCustomObject]@{ HasTable = ($separatorIndex -gt 0); Items = $parsed }
}

function Get-LocalInstalledEntries {
    $localItems = [System.Collections.Generic.List[object]]::new()
    $regConfigs = @(
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; SubKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';             Prefix = 'ARP\Machine\X64\' },
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; SubKey = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Prefix = 'ARP\Machine\X86\' },
        @{ Hive = [Microsoft.Win32.Registry]::CurrentUser;  SubKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';             Prefix = 'ARP\User\X64\' },
        @{ Hive = [Microsoft.Win32.Registry]::CurrentUser;  SubKey = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Prefix = 'ARP\User\X86\' }
    )

    foreach ($cfg in $regConfigs) {
        $baseKey = $null
        try {
            $baseKey = $cfg.Hive.OpenSubKey($cfg.SubKey, $false)
            if ($null -eq $baseKey) { continue }
            foreach ($subName in $baseKey.GetSubKeyNames()) {
                $subKey = $null
                try {
                    $subKey = $baseKey.OpenSubKey($subName, $false)
                    if ($null -eq $subKey) { continue }
                    $dispName = [string]$subKey.GetValue('DisplayName', '')
                    if ([string]::IsNullOrWhiteSpace($dispName)) { continue }
                    $sysComp = $subKey.GetValue('SystemComponent', 0)
                    if ($sysComp -eq 1) { continue }
                    $relType = [string]$subKey.GetValue('ReleaseType', '')
                    if (-not [string]::IsNullOrWhiteSpace($relType)) { continue }
                    if ($dispName -match 'Additional Runtime|Minimum Runtime|Debug Runtime|IntelliSense|Language Pack') { continue }

                    $dispVer = [string]$subKey.GetValue('DisplayVersion', '')
                    $localItems.Add([PSCustomObject]@{
                        Name      = $dispName.Trim()
                        ID        = ($cfg.Prefix + $subName)
                        Version   = $dispVer
                        Available = ""
                        HasUpdate = $false
                        CleanName = (Get-CleanAppName $dispName)
                    })
                } catch {} finally {
                    if ($null -ne $subKey) { $subKey.Dispose() }
                }
            }
        } catch {} finally {
            if ($null -ne $baseKey) { $baseKey.Dispose() }
        }
    }

    try { [System.Windows.Forms.Application]::DoEvents() } catch {}
    try {
        foreach ($pkg in (Get-AppxPackage -ErrorAction SilentlyContinue)) {
            if ($pkg.IsFramework -or [string]::IsNullOrWhiteSpace($pkg.Name)) { continue }
            $pkgName = [string]$pkg.Name
            $localItems.Add([PSCustomObject]@{
                Name      = $pkgName
                ID        = "MSIX\" + [string]$pkg.PackageFullName
                Version   = [string]$pkg.Version
                Available = ""
                HasUpdate = $false
                CleanName = (Get-CleanAppName $pkgName)
            })
        }
    } catch {}

    return $localItems
}

function Scan-And-ColorizeApps {
    if ($script:isScanningApps) {
        Log-Text "[!] Tiến trình quét ứng dụng đang chạy, bỏ qua yêu cầu trùng lặp."
        return
    }

    $script:isScanningApps = $true
    try {
        Log-Text "[SCAN] Đang quét nhận diện ứng dụng & kiểm tra cập nhật..."
        if ($txtStatus) { $txtStatus.Text = "Đang kiểm tra phiên bản app..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}

        $wingetItems = [System.Collections.Generic.List[object]]::new()
        $wingetOk = $false
        $wingetMissing = $false

        try {
            $primary = Invoke-WingetListCapture -Arguments "list --disable-interactivity --accept-source-agreements" -TimeoutSeconds 35
            if (-not $primary.Available) {
                $wingetMissing = $true
                Log-Text "[WARN] Chưa có WinGet; chuyển sang quét cục bộ qua Registry & Appx."
            } else {
                $parsedPrimary = ConvertFrom-WingetListOutput -RawText $primary.StdOut -AllowHeaderless ($primary.ExitCode -eq 0 -and -not $primary.TimedOut)
                if (-not $primary.TimedOut -and $primary.ExitCode -eq 0 -and $parsedPrimary.Items.Count -gt 0) {
                    $wingetItems = $parsedPrimary.Items
                    $wingetOk = $true
                } else {
                    if ($primary.TimedOut) {
                        Log-Text "[WARN] WinGet (tất cả nguồn) quá thời gian chờ (35s); đang thử lại với nguồn --source winget..."
                    } else {
                        Log-Text "[WARN] WinGet (tất cả nguồn) trả về mã $($primary.ExitCode) ($($parsedPrimary.Items.Count) dòng); đang thử lại --source winget..."
                        if (-not [string]::IsNullOrWhiteSpace($primary.StdErr)) {
                            Log-Text "[stderr] $($primary.StdErr.Trim())"
                        }
                    }

                    $fallbackWg = Invoke-WingetListCapture -Arguments "list --source winget --disable-interactivity --accept-source-agreements" -TimeoutSeconds 20
                    $parsedFallback = ConvertFrom-WingetListOutput -RawText $fallbackWg.StdOut -AllowHeaderless ($fallbackWg.ExitCode -eq 0 -and -not $fallbackWg.TimedOut)

                    if (-not $fallbackWg.TimedOut -and $fallbackWg.ExitCode -eq 0 -and $parsedFallback.Items.Count -gt 0) {
                        $wingetItems = $parsedFallback.Items
                        $wingetOk = $true
                    } elseif ($parsedPrimary.HasTable -and $parsedPrimary.Items.Count -gt $parsedFallback.Items.Count) {
                        $wingetItems = $parsedPrimary.Items
                        $wingetOk = $true
                    } elseif ($parsedFallback.HasTable -and $parsedFallback.Items.Count -gt 0) {
                        $wingetItems = $parsedFallback.Items
                        $wingetOk = $true
                    }
                }
            }
        } catch {
            Log-Text "[!] Lỗi khi gọi WinGet: $($_.Exception.Message)"
        }

        $idMap         = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $nameMap       = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $cleanNameMap  = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $installedList = [System.Collections.Generic.List[object]]::new()

        foreach ($itemObj in $wingetItems) {
            $installedList.Add($itemObj)
            Set-PreferredMapEntry $idMap $itemObj.ID $itemObj
            Set-PreferredMapEntry $nameMap $itemObj.Name $itemObj
            if ($itemObj.CleanName.Length -ge 3) { Set-PreferredMapEntry $cleanNameMap $itemObj.CleanName $itemObj }
        }

        if (-not $idMap.ContainsKey("LegacyLauncher.LegacyLauncher")) {
            $llPaths = @(
                (Join-Path $env:APPDATA ".tlauncher\legacy\Minecraft\TL.exe"),
                (Join-Path $env:APPDATA ".tlauncher\legacy"),
                (Join-Path $env:APPDATA ".minecraft\LLauncher.exe"),
                (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Legacy Launcher.lnk")
            )
            foreach ($lp in $llPaths) {
                if ($lp -and [System.IO.File]::Exists($lp) -or ($lp -and [System.IO.Directory]::Exists($lp))) {
                    $llObj = [PSCustomObject]@{
                        ID        = "LegacyLauncher.LegacyLauncher"
                        Name      = "Legacy Launcher"
                        CleanName = "legacylauncher"
                        Version   = "Installed"
                        Available = ""
                        HasUpdate = $false
                        Source    = "local"
                    }
                    $installedList.Add($llObj)
                    Set-PreferredMapEntry $idMap $llObj.ID $llObj
                    Set-PreferredMapEntry $nameMap $llObj.Name $llObj
                    break
                }
            }
        }

        if (-not $wingetOk -or $wingetItems.Count -lt 5) {
            $localItems = Get-LocalInstalledEntries
            foreach ($locObj in $localItems) {
                $installedList.Add($locObj)
                Set-PreferredMapEntry $idMap $locObj.ID $locObj
                Set-PreferredMapEntry $nameMap $locObj.Name $locObj
                if ($locObj.CleanName.Length -ge 3) { Set-PreferredMapEntry $cleanNameMap $locObj.CleanName $locObj }
            }
        }

        if ($installedList.Count -eq 0 -and -not $wingetOk) {
            Log-Text "[!] Không nhận được danh sách ứng dụng từ cả WinGet lẫn cục bộ. Giữ nguyên trạng thái hiện tại."
            if ($txtStatus -and -not $script:hasCompletedAppScan) {
                $txtStatus.Text = if ($wingetMissing) { "Thiếu WinGet | Quét thất bại" } else { "Lỗi quét WinGet | Hãy thử Get Installed lại" }
            }
            return
        }

    $lookupCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Find-InstalledAppFast {
        param($targetApp)

        $targetId = $targetApp.ID
        $cachedMatch = $null
        if ($lookupCache.TryGetValue($targetId, [ref]$cachedMatch)) {
            return $cachedMatch
        }

        $match = $null
        if ($idMap.TryGetValue($targetId, [ref]$match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        if ($targetApp.Name -and $nameMap.TryGetValue($targetApp.Name, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        if ($targetApp.Aliases) {
            foreach ($alias in $targetApp.Aliases) {
                if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                if ($idMap.TryGetValue($alias, [ref]$match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
                if ($nameMap.TryGetValue($alias, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
                $cleanAlias = Get-CleanAppName $alias
                if ($cleanAlias.Length -ge 3 -and $cleanNameMap.TryGetValue($cleanAlias, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
                    $lookupCache[$targetId] = $match
                    return $match
                }
            }
        }

        $cleanTarget = Get-CleanAppName $targetApp.Name
        if ($cleanTarget.Length -ge 3 -and $cleanNameMap.TryGetValue($cleanTarget, [ref]$match) -and (Test-MatchCompatible $targetApp $match)) {
            $lookupCache[$targetId] = $match
            return $match
        }

        if ($targetApp.Aliases) {
            foreach ($alias in $targetApp.Aliases) {
                if ([string]::IsNullOrWhiteSpace($alias) -or $alias.Length -lt 4) { continue }
                $pattern = "(?<![a-zA-Z0-9])" + [System.Text.RegularExpressions.Regex]::Escape($alias) + "(?![a-zA-Z0-9])"
                foreach ($item in $installedList) {
                    if (($item.ID -match $pattern -or $item.Name -match $pattern) -and (Test-MatchCompatible $targetApp $item)) {
                        $lookupCache[$targetId] = $item
                        return $item
                    }
                }
            }
        }

        if ($cleanTarget.Length -ge 4) {
            $patternClean = "(?<![a-zA-Z0-9])" + [System.Text.RegularExpressions.Regex]::Escape($cleanTarget) + "(?![a-zA-Z0-9])"
            foreach ($item in $installedList) {
                if ($item.CleanName -match $patternClean -and (Test-MatchCompatible $targetApp $item)) {
                    $lookupCache[$targetId] = $item
                    return $item
                }
            }
        }

        $lookupCache[$targetId] = $null
        return $null
    }

    if ($progressBar) { $progressBar.IsIndeterminate = $false }
    $countInstalled = 0
    $countLatest = 0
    $countOutdated = 0

    foreach ($row in $allItemBorders) {
        $app = $row.Tag.App
        $grid = $row.Child
        $tb = if ($row.Tag.NameText) { $row.Tag.NameText } elseif ($grid -and $grid.Children.Count -gt 2) { $grid.Children[2] } else { $null }
        $updateBadge = $row.Tag.UpdateBadge
        $updateText  = $row.Tag.UpdateText
        $idnPrefix = if ($app.IDn) { "[#$($app.IDn)] " } else { "" }

        $info = Find-InstalledAppFast $app

        if ($info) {
            $countInstalled++
            $row.Tag.DetectedId = $info.ID
            $row.Tag.InstalledVersion = $info.Version

            if ($info.HasUpdate -eq $true) {
                $countOutdated++
                $row.Tag.Status = "OUTDATED"
                $tb.Foreground = $script:brushOutdatedFg
                $tb.Text = $app.Name
                $tb.TextDecorations = $null
                if ($updateBadge -and $updateText) {
                    $updateText.Text = if ($info.Available) { "↑ $($info.Available)" } else { "↑ Mới" }
                    $updateBadge.Visibility = [System.Windows.Visibility]::Visible
                }
                $tip = "$idnPrefix$($app.Name)`nĐang cài: $($info.Version)`nCó bản mới: $($info.Available)`nID phát hiện: $($info.ID)"
                $tb.ToolTip = $tip
                $row.ToolTip = $tip
            } else {
                $countLatest++
                $row.Tag.Status = "LATEST"
                $tb.Foreground = $script:brushLatestFg
                $tb.Text = $app.Name
                $tb.TextDecorations = $null
                if ($updateBadge) { $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed }
                $tip = "$idnPrefix$($app.Name)`nPhiên bản: $($info.Version) (Mới nhất)`nID phát hiện: $($info.ID)"
                $tb.ToolTip = $tip
                $row.ToolTip = $tip
            }
        } else {
            $row.Tag.Status = "NONE"
            $row.Tag.DetectedId = $null
            $row.Tag.InstalledVersion = $null
            $tb.Foreground = $script:brushNoneFg
            $tb.Text = $app.Name
            $tb.TextDecorations = $null
            if ($updateBadge) { $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed }
            $tip = "$idnPrefix$($app.Name)`nTrạng thái: Chưa cài đặt`nID: $($app.ID)"
            $tb.ToolTip = $tip
            $row.ToolTip = $tip
        }
    }

        $script:hasCompletedAppScan = $true
        $modeTag = if (-not $wingetOk) { " [Chế độ dự phòng Registry/Appx]" } else { "" }
        $summary = "Đã quét xong: $countInstalled app đã cài ($countLatest bản mới nhất [XANH], $countOutdated bản cũ [ĐỎ])$modeTag"
        Log-Text "[OK] $summary"
        if ($txtStatus) {
            $txtStatus.Text = "$countInstalled app đã cài ($countLatest mới / $countOutdated cũ)" + $(if (-not $wingetOk) { " [Dự phòng]" } else { "" })
        }
    } finally {
        $script:isScanningApps = $false
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if (Get-Command "Flush-PendingIconCache" -ErrorAction SilentlyContinue) {
            Flush-PendingIconCache
        }
    }
}

Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

if (-not ("DuckUtil.DeepUninstallerEngine" -as [type])) {
    try {
        $csCandidates = @(
            (Join-Path $PSScriptRoot "..\..\csharp\DeepUninstallerEngine.cs"),
            (Join-Path $PSScriptRoot "..\csharp\DeepUninstallerEngine.cs"),
            (Join-Path $PSScriptRoot "csharp\DeepUninstallerEngine.cs")
        )
        foreach ($cand in $csCandidates) {
            if (Test-Path -LiteralPath $cand) {
                $deepUninstCs = Get-Content -Raw -Encoding utf8 $cand
                Add-Type -TypeDefinition $deepUninstCs -ErrorAction SilentlyContinue
                break
            }
        }
    } catch {}
}

function Get-SystemInstalledAppsFast {
    $apps = [DuckUtil.DeepUninstallerEngine]::GetInstalledApps()
    return @($apps | Sort-Object -Property @{ Expression = { $_.IsBrokenOrphan }; Descending = $true }, @{ Expression = { $_.DisplayName }; Descending = $false })
}

function Test-SafeAppDirectoryForCleanup {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$AppEntry,
        [Parameter(Mandatory = $false)][string[]]$Keywords = @(),
        [Parameter(Mandatory = $false)]$AllInstalledApps = $null
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $norm = $Path.Trim().TrimEnd('\')
    if ($norm -match '^[A-Za-z]:$') { return $false }

    $parts = @($norm -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -lt 2) { return $false }

    $genericContainers = @(
        'Windows', 'System32', 'SysWOW64', 'Program Files', 'Program Files (x86)',
        'ProgramData', 'Programs', 'Users', 'AppData', 'Local', 'Roaming', 'LocalLow',
        'Common Files', 'WindowsApps', 'ModifiableWindowsApps', 'Package Cache', 'Packages',
        'Temp', 'Apps', 'Applications', 'Games', 'Game', 'Software', 'Softwares', 'Tools',
        'Downloads', 'Desktop', 'Documents', 'Pictures', 'Music', 'Videos', 'OneDrive',
        'Steam', 'SteamLibrary', 'steamapps', 'common', 'Epic Games', 'GOG Galaxy', 'Riot Games'
    )

    $leafName = $parts[$parts.Count - 1]
    foreach ($gc in $genericContainers) {
        if ($leafName.Equals($gc, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    if ($Keywords -and $Keywords.Count -gt 0) {
        $parentName = if ($parts.Count -ge 3) { $parts[$parts.Count - 2] } else { "" }
        $matchedOwner = $false
        foreach ($kw in $Keywords) {
            if ([string]::IsNullOrWhiteSpace($kw)) { continue }
            $isCjk = $kw -match '[\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]'
            if ((-not $isCjk) -and $kw.Length -lt 3) { continue }
            if ($isCjk -and $kw.Length -lt 2) { continue }
            if ($leafName.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                ($parentName -and $parentName.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)) {
                $matchedOwner = $true
                break
            }
        }
        if (-not $matchedOwner) {
            $matchedOwner = [DuckUtil.DeepUninstallerEngine]::VerifyDirectoryExeOwnership($norm, $Keywords)
        }
        if (-not $matchedOwner -and $AppEntry.InstallLocation) {
            $regLoc = $AppEntry.InstallLocation.Trim().TrimEnd('\')
            if ($regLoc.Equals($norm, [System.StringComparison]::OrdinalIgnoreCase) -and $parts.Count -ge 3) {
                $matchedOwner = $true
            }
        }
        if (-not $matchedOwner) { return $false }
    }

    if ($AllInstalledApps) {
        $normWithSlash = $norm + "\"
        foreach ($other in $AllInstalledApps) {
            if ($null -eq $other -or $other.Id -eq $AppEntry.Id) { continue }
            if ($other.IsBrokenOrphan) { continue }
            $otherLoc = if ($other.InstallLocation) { $other.InstallLocation.Trim().TrimEnd('\') } else { "" }
            if ($otherLoc) {
                if ($otherLoc.Equals($norm, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $otherLoc.StartsWith($normWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $false
                }
            }
        }
    }

    return $true
}

function Find-AppLeftovers {
    param(
        [Parameter(Mandatory = $true)]$AppEntry,
        [Parameter(Mandatory = $false)]$AllInstalledApps = $null
    )

    $leftovers = [System.Collections.Generic.List[object]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $exclusions = @(
        'Microsoft', 'Windows', 'Intel', 'AMD', 'NVIDIA', 'Google', 'Common Files',
        'WindowsApps', 'Package Cache', 'Packages', 'Temp', 'System32', 'Explorer', 'Internet Explorer'
    )

    $rawName = $AppEntry.DisplayName
    if ([string]::IsNullOrWhiteSpace($rawName)) { return @() }

    $cleanName = ($rawName -replace '\(.*?\)', '').Trim()
    $cleanName = ($cleanName -replace '[0-9]+(\.[0-9]+)+', '').Trim()

    $cnAliasMap = @{
        "$([char]0x817E)$([char]0x8BAF)" = @("Tencent", "QQ")
        "$([char]0x5FAE)$([char]0x4FE1)" = @("WeChat", "Tencent")
        "$([char]0x767E)$([char]0x5EA6)" = @("Baidu", "BaiduNetdisk")
        "$([char]0x7F51)$([char]0x6613)" = @("NetEase", "CloudMusic")
        "$([char]0x8FC5)$([char]0x96F7)" = @("Thunder", "Xunlei", "Thunder Network")
        "$([char]0x5947)$([char]0x864E)" = @("Qihoo360", "360Safe", "360se6")
        "360"                            = @("360Safe", "Qihoo360", "360se6")
        "$([char]0x91D1)$([char]0x5C71)" = @("Kingsoft", "WPS Office", "kingsoft")
        "$([char]0x641C)$([char]0x72D7)" = @("Sogou", "SogouInput", "SogouPY")
        "$([char]0x54D4)$([char]0x54E9)" = @("Bilibili", "Bililive")
        "$([char]0x6296)$([char]0x97F3)" = @("Douyin", "ByteDance")
        "$([char]0x5B57)$([char]0x8282)" = @("ByteDance", "Douyin")
        "$([char]0x9489)$([char]0x9489)" = @("DingTalk", "Alibaba", "AliWorkbench")
        "$([char]0x963F)$([char]0x91CC)" = @("Alibaba", "AliWorkbench", "DingTalk")
        "$([char]0x7231)$([char]0x5947)$([char]0x827A)" = @("IQIYI", "QyClient")
        "$([char]0x4F18)$([char]0x9177)" = @("Youku", "YoukuClient")
        "$([char]0x9177)$([char]0x72D7)" = @("KuGou", "KuGouMusic")
        "$([char]0x9177)$([char]0x6211)" = @("Kuwo", "kwmusic")
        "$([char]0x9C81)$([char]0x5927)$([char]0x5E08)" = @("LuDaShi", "ComputerZ")
        "$([char]0x96F7)$([char]0x7535)" = @("LDPlayer", "XuanZhi", "leidian", "dnplayer")
        "$([char]0x84DD)$([char]0x53E0)" = @("BlueStacks", "BlueStacks_nxt")
        "2345"                           = @("2345Soft", "2345Pic", "2345Explorer")
        "$([char]0x864E)$([char]0x7259)" = @("Huya", "HuyaClient")
        "$([char]0x6597)$([char]0x9C7C)" = @("Douyu", "DouyuClient")
    }

    $candidateTokens = [System.Collections.Generic.List[string]]::new()
    foreach ($tk in ($cleanName -split '\s+')) {
        $isCjk = $tk -match '[\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]'
        if (($isCjk -and $tk.Length -ge 2) -or ((-not $isCjk) -and $tk.Length -ge 4)) {
            if ($exclusions -notcontains $tk) { $candidateTokens.Add($tk) }
        }
    }
    $isFullCjk = $cleanName -match '[\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]'
    if (($isFullCjk -and $cleanName.Length -ge 2) -or ((-not $isFullCjk) -and $cleanName.Length -ge 4)) {
        if ($exclusions -notcontains $cleanName) { $candidateTokens.Add($cleanName) }
    }

    if ($AppEntry.Id -and $AppEntry.Id -notmatch '^\{?[0-9A-Fa-f\-]{12,}\}?$' -and $AppEntry.Id -notmatch '^MSI') {
        $cleanId = ($AppEntry.Id -replace '_is1$', '').Trim()
        if ($cleanId.Length -ge 3 -and $exclusions -notcontains $cleanId) {
            $candidateTokens.Add($cleanId)
        }
    }

    if ($AppEntry.InstallLocation) {
        $locTrim = $AppEntry.InstallLocation.Trim().TrimEnd('\')
        $locLeaf = [System.IO.Path]::GetFileName($locTrim)
        $genericFolders = @('Program Files', 'Program Files (x86)', 'Programs', 'Apps', 'Games', 'Software', 'Tools', 'Common Files', 'bin', 'Client')
        if ($locLeaf -and $locLeaf.Length -ge 3 -and $genericFolders -notcontains $locLeaf -and $exclusions -notcontains $locLeaf) {
            $candidateTokens.Add($locLeaf)
        }
    }

    $binTokens = [DuckUtil.DeepUninstallerEngine]::ExtractBinaryAndCertTokens($AppEntry.InstallLocation, $AppEntry.UninstallString, "")
    if ($binTokens) {
        foreach ($bt in $binTokens) {
            if ($bt -and $bt.Length -ge 3 -and $exclusions -notcontains $bt) {
                $candidateTokens.Add($bt)
            }
        }
    }

    $combinedSource = "$rawName | $($AppEntry.Publisher) | $($AppEntry.InstallLocation) | $($AppEntry.UninstallString)"
    $vendorFolders = [System.Collections.Generic.List[string]]::new()
    foreach ($cnKey in $cnAliasMap.Keys) {
        if ($combinedSource.IndexOf($cnKey, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            foreach ($mapped in $cnAliasMap[$cnKey]) {
                $candidateTokens.Add($mapped)
                $vendorFolders.Add($mapped)
            }
        }
    }

    $nameKeywords = @($candidateTokens | Select-Object -Unique)
    if ($nameKeywords.Count -eq 0) { return @() }

    $ownerKeywords = [System.Collections.Generic.List[string]]::new()
    foreach ($nk in $nameKeywords) { $ownerKeywords.Add($nk) }
    if (-not [string]::IsNullOrWhiteSpace($AppEntry.Publisher)) {
        $pubClean = ($AppEntry.Publisher -replace '\(.*?\)', '').Trim()
        foreach ($pk in ($pubClean -split '\s+')) {
            $isPkCjk = $pk -match '[\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]'
            if ((($isPkCjk -and $pk.Length -ge 2) -or ($pk.Length -ge 3)) -and $exclusions -notcontains $pk) {
                $ownerKeywords.Add($pk)
            }
        }
    }

    if ($AppEntry.InstallLocation -and (Test-Path -LiteralPath $AppEntry.InstallLocation)) {
        $loc = try { (Resolve-Path -LiteralPath $AppEntry.InstallLocation).Path.TrimEnd('\') } catch { $AppEntry.InstallLocation.Trim().TrimEnd('\') }
        $isSafe = $true
        foreach ($ex in $exclusions) {
            if ($loc -like "*\$ex\*" -or $loc -like "*\$ex") { $isSafe = $false; break }
        }
        if ($isSafe -and (Test-SafeAppDirectoryForCleanup -Path $loc -AppEntry $AppEntry -Keywords $ownerKeywords.ToArray() -AllInstalledApps $AllInstalledApps)) {
            if ($seenPaths.Add($loc)) {
                $dirSize = [DuckUtil.DeepUninstallerEngine]::GetDirectorySizeFast($loc, 4)
                $leftovers.Add([PSCustomObject]@{
                    Type              = "Th$([char]0x01B0) m$([char]0x1EE5)c c$([char]0x00E0)i $([char]0x0111)$([char]0x1EB7)t"
                    Confidence        = "An to$([char]0x00E0)n 100%"
                    AppName           = $AppEntry.DisplayName
                    Path              = $loc
                    SizeBytes         = [long]$dirSize
                    SizeMB            = [math]::Round($dirSize / 1MB, 2)
                    IsRegistry        = $false
                    RegistryValueName = ""
                })
            }
        }
    }

    $folderRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($baseRoot in @($env:APPDATA, $env:LOCALAPPDATA, (Join-Path $env:LOCALAPPDATA "Programs"), "C:\ProgramData")) {
        if ($baseRoot -and (Test-Path -LiteralPath $baseRoot)) {
            $folderRoots.Add($baseRoot)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($AppEntry.Publisher)) {
        $pubClean = ($AppEntry.Publisher -replace '\(.*?\)', '' -replace '(?i)\b(Inc\.?|LLC|Ltd\.?|Corp\.?|Corporation|GmbH|Co\.?)\b', '').Trim(' ', ',', '.')
        if ($pubClean.Length -ge 2 -and $exclusions -notcontains $pubClean) {
            $vendorFolders.Add($pubClean)
        }
    }
    foreach ($vf in ($vendorFolders | Select-Object -Unique)) {
        foreach ($baseRoot in @($env:APPDATA, $env:LOCALAPPDATA, "C:\ProgramData")) {
            if ($baseRoot) {
                $pubSub = Join-Path $baseRoot $vf
                if (Test-Path -LiteralPath $pubSub) { $folderRoots.Add($pubSub) }
            }
        }
    }

    foreach ($root in $folderRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($kw in $nameKeywords) {
            $candidatePath = Join-Path $root $kw
            if (Test-Path -LiteralPath $candidatePath) {
                $fullPath = (Resolve-Path -LiteralPath $candidatePath).Path.TrimEnd('\')
                $isSafe = $true
                foreach ($ex in $exclusions) {
                    if ($fullPath -like "*\$ex\*" -or $fullPath -like "*\$ex") { $isSafe = $false; break }
                }
                if ($isSafe -and $seenPaths.Add($fullPath)) {
                    $dirSize = [DuckUtil.DeepUninstallerEngine]::GetDirectorySizeFast($fullPath, 4)
                    $leftovers.Add([PSCustomObject]@{
                        Type              = "Th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x00E1)c AppData"
                        Confidence        = "An to$([char]0x00E0)n 100%"
                        AppName           = $AppEntry.DisplayName
                        Path              = $fullPath
                        SizeBytes         = [long]$dirSize
                        SizeMB            = [math]::Round($dirSize / 1MB, 2)
                        IsRegistry        = $false
                        RegistryValueName = ""
                    })
                }
            }
        }
    }

    $crashDumpDir = Join-Path $env:LOCALAPPDATA "CrashDumps"
    if (Test-Path -LiteralPath $crashDumpDir) {
        foreach ($kw in $nameKeywords) {
            try {
                $dumps = [System.IO.Directory]::GetFiles($crashDumpDir, "*$kw*.dmp", [System.IO.SearchOption]::TopDirectoryOnly)
                foreach ($dmp in $dumps) {
                    if ($seenPaths.Add($dmp)) {
                        $dmpSize = (Get-Item -LiteralPath $dmp -ErrorAction SilentlyContinue).Length
                        $leftovers.Add([PSCustomObject]@{
                            Type              = "Crash Dump r$([char]0x00E1)c"
                            Confidence        = "An to$([char]0x00E0)n 100%"
                            AppName           = $AppEntry.DisplayName
                            Path              = $dmp
                            SizeBytes         = [long]$dmpSize
                            SizeMB            = [math]::Round($dmpSize / 1MB, 2)
                            IsRegistry        = $false
                            RegistryValueName = ""
                        })
                    }
                }
            } catch {}
        }
    }

    $shortcutDirs = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('Programs'),
        [Environment]::GetFolderPath('CommonPrograms')
    )
    $wsh = $null
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $targetLocPrefix = if ($AppEntry.InstallLocation) { $AppEntry.InstallLocation.Trim().TrimEnd('\') + "\" } else { "" }
        foreach ($sDir in $shortcutDirs) {
            if (-not $sDir -or -not (Test-Path -LiteralPath $sDir)) { continue }
            $lnks = [System.IO.Directory]::GetFiles($sDir, "*.lnk", [System.IO.SearchOption]::AllDirectories)
            foreach ($lnk in $lnks) {
                try {
                    $lnkName = [System.IO.Path]::GetFileNameWithoutExtension($lnk)
                    $sc = $wsh.CreateShortcut($lnk)
                    $tPath = $sc.TargetPath
                    $matchesApp = $false
                    if ($targetLocPrefix -and $tPath -and $tPath.StartsWith($targetLocPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $matchesApp = $true
                    } elseif ($lnkName.Equals($cleanName, [System.StringComparison]::OrdinalIgnoreCase) -and $tPath -and -not (Test-Path -LiteralPath $tPath)) {
                        $matchesApp = $true
                    }
                    if ($matchesApp -and $seenPaths.Add($lnk)) {
                        $leftovers.Add([PSCustomObject]@{
                            Type              = "Shortcut ch$([char]0x1EBF)t"
                            Confidence        = "An to$([char]0x00E0)n 100%"
                            AppName           = $AppEntry.DisplayName
                            Path              = $lnk
                            SizeBytes         = 0L
                            SizeMB            = 0.0
                            IsRegistry        = $false
                            RegistryValueName = ""
                        })
                    }
                } catch {}
            }
        }
    } catch {} finally {
        if ($null -ne $wsh) {
            try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null } catch {}
            $wsh = $null
        }
    }

    $runKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    $locPrefixForRun = if ($AppEntry.InstallLocation) { $AppEntry.InstallLocation.Trim().TrimEnd('\') + "\" } else { "" }
    foreach ($rk in $runKeys) {
        if (-not (Test-Path -LiteralPath $rk)) { continue }
        try {
            $props = Get-ItemProperty -LiteralPath $rk -ErrorAction SilentlyContinue
            if ($null -eq $props) { continue }
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { continue }
                $valStr = [string]$p.Value
                if ([string]::IsNullOrWhiteSpace($valStr)) { continue }
                $isAppRun = $false
                if ($locPrefixForRun -and $valStr.IndexOf($locPrefixForRun, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $isAppRun = $true
                } elseif ($p.Name.Equals($cleanName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isAppRun = $true
                }
                if ($isAppRun) {
                    $runDisplayPath = "$rk -> [$($p.Name)]"
                    if ($seenPaths.Add($runDisplayPath)) {
                        $leftovers.Add([PSCustomObject]@{
                            Type              = "Startup m$([char]0x1ED3) c$([char]0x00F4)i"
                            Confidence        = "An to$([char]0x00E0)n 100%"
                            AppName           = $AppEntry.DisplayName
                            Path              = $rk
                            SizeBytes         = 0L
                            SizeMB            = 0.0
                            IsRegistry        = $true
                            RegistryValueName = $p.Name
                        })
                    }
                }
            }
        } catch {}
    }

    $regRoots = @(
        "HKCU:\Software",
        "HKLM:\SOFTWARE",
        "HKLM:\SOFTWARE\WOW6432Node"
    )

    foreach ($regRoot in $regRoots) {
        if (-not (Test-Path -LiteralPath $regRoot)) { continue }
        foreach ($kw in $nameKeywords) {
            $regPath = Join-Path $regRoot $kw
            if (Test-Path -LiteralPath $regPath) {
                $isSafe = $true
                foreach ($ex in $exclusions) {
                    if ($kw -eq $ex) { $isSafe = $false; break }
                }
                if ($isSafe -and $seenPaths.Add($regPath)) {
                    $leftovers.Add([PSCustomObject]@{
                        Type              = "Registry m$([char]0x1ED3) c$([char]0x00F4)i"
                        Confidence        = "An to$([char]0x00E0)n 100%"
                        AppName           = $AppEntry.DisplayName
                        Path              = $regPath
                        SizeBytes         = 0L
                        SizeMB            = 0.0
                        IsRegistry        = $true
                        RegistryValueName = ""
                    })
                }
            }
        }
    }

    if ($AppEntry.RegistryPath -and (Test-Path -LiteralPath $AppEntry.RegistryPath)) {
        if ($seenPaths.Add($AppEntry.RegistryPath)) {
            $leftovers.Add([PSCustomObject]@{
                Type              = "Registry g$([char]0x1EE1) b$([char]0x1ECF) h$([char]0x1ECF)ng"
                Confidence        = "An to$([char]0x00E0)n 100%"
                AppName           = $AppEntry.DisplayName
                Path              = $AppEntry.RegistryPath
                SizeBytes         = 0L
                SizeMB            = 0.0
                IsRegistry        = $true
                RegistryValueName = ""
            })
        }
    }

    return @($leftovers)
}

function Find-SystemOrphanLeftovers {
    param(
        [Parameter(Mandatory = $false)]$InstalledApps,
        [Parameter(Mandatory = $false)]$CatalogApps
    )

    if ($null -eq $InstalledApps) {
        $InstalledApps = Get-SystemInstalledAppsFast
    }

    $orphans = [System.Collections.Generic.List[object]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $exclusions = @(
        'Microsoft', 'Windows', 'Intel', 'AMD', 'NVIDIA', 'Google', 'Common Files',
        'WindowsApps', 'ModifiableWindowsApps', 'Internet Explorer', 'Windows Defender',
        'Windows Mail', 'Windows Media Player', 'Windows NT', 'Windows Photo Viewer',
        'Windows Portable Devices', 'Windows Security', 'Windows Sidebar', 'WindowsPowerShell',
        'PowerShell', 'dotnet', 'Reference Assemblies', 'MSBuild', 'Package Cache',
        'Packages', 'Temp', 'System32', 'Uninstall Information'
    )

    foreach ($app in $InstalledApps) {
        if ($app.IsBrokenOrphan) {
            if ($app.RegistryPath -and (Test-Path -LiteralPath $app.RegistryPath)) {
                if ($seenPaths.Add($app.RegistryPath)) {
                    $orphans.Add([PSCustomObject]@{
                        Type              = "[Registry m$([char]0x1ED3) c$([char]0x00F4)i]"
                        Confidence        = "An to$([char]0x00E0)n 100%"
                        AppName           = $app.DisplayName
                        Path              = $app.RegistryPath
                        SizeBytes         = 0L
                        SizeMB            = 0.0
                        IsRegistry        = $true
                        RegistryValueName = ""
                    })
                }
            }

            $appLeftovers = Find-AppLeftovers -AppEntry $app -AllInstalledApps $InstalledApps
            foreach ($lo in $appLeftovers) {
                $dedupKey = if ($lo.RegistryValueName) { "$($lo.Path)->$($lo.RegistryValueName)" } else { $lo.Path }
                if ($seenPaths.Add($dedupKey)) {
                    $badgeType = if ($lo.IsRegistry) { "[Registry m$([char]0x1ED3) c$([char]0x00F4)i]" } else { "[Th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x00E1)c AppData]" }
                    $orphans.Add([PSCustomObject]@{
                        Type              = $badgeType
                        Confidence        = if ($lo.Confidence) { $lo.Confidence } else { "An to$([char]0x00E0)n 100%" }
                        AppName           = $app.DisplayName
                        Path              = $lo.Path
                        SizeBytes         = [long]$lo.SizeBytes
                        SizeMB            = [double]$lo.SizeMB
                        IsRegistry        = [bool]$lo.IsRegistry
                        RegistryValueName = [string]$lo.RegistryValueName
                    })
                }
            }
        }
    }

    $programRoots = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($drv in [System.IO.DriveInfo]::GetDrives()) {
            if ($drv.DriveType -eq [System.IO.DriveType]::Fixed -and $drv.IsReady) {
                $pf1 = Join-Path $drv.RootDirectory.FullName "Program Files"
                $pf2 = Join-Path $drv.RootDirectory.FullName "Program Files (x86)"
                if (Test-Path -LiteralPath $pf1) { $programRoots.Add($pf1) }
                if (Test-Path -LiteralPath $pf2) { $programRoots.Add($pf2) }
            }
        }
    } catch {
        $programRoots.Add("C:\Program Files")
        $programRoots.Add("C:\Program Files (x86)")
    }
    $localProgs = Join-Path $env:LOCALAPPDATA "Programs"
    if (Test-Path -LiteralPath $localProgs) { $programRoots.Add($localProgs) }

    $activeInstallLocs = [System.Collections.Generic.List[string]]::new()
    foreach ($ia in $InstalledApps) {
        if (-not $ia.IsBrokenOrphan -and -not [string]::IsNullOrWhiteSpace($ia.InstallLocation)) {
            $activeInstallLocs.Add($ia.InstallLocation.Trim().TrimEnd('\'))
        }
    }

    foreach ($pRoot in $programRoots) {
        if (-not (Test-Path -LiteralPath $pRoot)) { continue }
        $subDirs = [System.IO.Directory]::GetDirectories($pRoot)
        foreach ($sd in $subDirs) {
            $dirName = [System.IO.Path]::GetFileName($sd)
            $isExcluded = $false
            foreach ($ex in $exclusions) {
                if ($dirName -like "$ex*" -or $dirName -eq $ex) { $isExcluded = $true; break }
            }
            if ($isExcluded) { continue }

            $sdNorm = $sd.Trim().TrimEnd('\')
            $isUsedByActiveApp = $false
            foreach ($actLoc in $activeInstallLocs) {
                if ($actLoc.Equals($sdNorm, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $actLoc.StartsWith($sdNorm + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isUsedByActiveApp = $true
                    break
                }
            }
            if ($isUsedByActiveApp) { continue }

            $hollowSize = [DuckUtil.DeepUninstallerEngine]::GetHollowDirectorySize($sd, 3, 52428800L)
            if ($hollowSize -ge 0L) {
                if ($seenPaths.Add($sd)) {
                    $orphans.Add([PSCustomObject]@{
                        Type              = "[V$([char]0x1ECF) th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x1ED7)ng]"
                        Confidence        = "An to$([char]0x00E0)n 100%"
                        AppName           = $dirName
                        Path              = $sd
                        SizeBytes         = [long]$hollowSize
                        SizeMB            = [math]::Round($hollowSize / 1MB, 2)
                        IsRegistry        = $false
                        RegistryValueName = ""
                    })
                }
            }
        }
    }

    if ($CatalogApps) {
        $installedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($ia in $InstalledApps) {
            $installedNames.Add($ia.DisplayName) | Out-Null
        }

        $appDataRoots = @($env:APPDATA, $env:LOCALAPPDATA)
        foreach ($catApp in $CatalogApps) {
            $catName = ($catApp.Name -replace '\(.*?\)', '').Trim()
            if ($catName.Length -lt 5) { continue }
            $isInstalled = $false
            foreach ($inName in $installedNames) {
                if ($inName.IndexOf($catName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $isInstalled = $true
                    break
                }
            }
            if (-not $isInstalled) {
                foreach ($ar in $appDataRoots) {
                    $cand = Join-Path $ar $catName
                    if (Test-Path -LiteralPath $cand) {
                        $full = (Resolve-Path -LiteralPath $cand).Path
                        if ($seenPaths.Add($full)) {
                            $dirSize = [DuckUtil.DeepUninstallerEngine]::GetDirectorySizeFast($full, 3)
                            $orphans.Add([PSCustomObject]@{
                                Type              = "[Th$([char]0x01B0) m$([char]0x1EE5)c r$([char]0x00E1)c AppData]"
                                Confidence        = "An to$([char]0x00E0)n 100%"
                                AppName           = $catApp.Name
                                Path              = $full
                                SizeBytes         = [long]$dirSize
                                SizeMB            = [math]::Round($dirSize / 1MB, 2)
                                IsRegistry        = $false
                                RegistryValueName = ""
                            })
                        }
                    }
                }
            }
        }
    }

    $desktopPaths = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('Programs'),
        [Environment]::GetFolderPath('CommonPrograms')
    )

    $wsh = $null
    try {
        $wsh = New-Object -ComObject WScript.Shell
        foreach ($dp in $desktopPaths) {
            if (-not (Test-Path -LiteralPath $dp)) { continue }
            $lnks = [System.IO.Directory]::GetFiles($dp, "*.lnk", [System.IO.SearchOption]::AllDirectories)
            foreach ($lnk in $lnks) {
                try {
                    $sc = $wsh.CreateShortcut($lnk)
                    $target = $sc.TargetPath
                    if ($target -and $target -match '^[A-Za-z]:\\' -and $target.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
                        if (-not (Test-Path -LiteralPath $target)) {
                            if ($seenPaths.Add($lnk)) {
                                $orphans.Add([PSCustomObject]@{
                                    Type              = "[Shortcut ch$([char]0x1EBF)t]"
                                    Confidence        = "An to$([char]0x00E0)n 100%"
                                    AppName           = [System.IO.Path]::GetFileNameWithoutExtension($lnk)
                                    Path              = $lnk
                                    SizeBytes         = 0L
                                    SizeMB            = 0.0
                                    IsRegistry        = $false
                                    RegistryValueName = ""
                                })
                            }
                        }
                    }
                } catch {}
            }
        }
    } catch {} finally {
        if ($null -ne $wsh) {
            try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null } catch {}
            $wsh = $null
        }
    }

    return @($orphans)
}

function Show-LeftoverReviewDialog {
    param(
        [Parameter(Mandatory = $false)]$OwnerWindow,
        [Parameter(Mandatory = $true)][object[]]$Items,
        [Parameter(Mandatory = $false)][string]$Title = "Duy$([char]0x1EC7)t & D$([char]0x1ECD)n S$([char]0x1EA1)ch R$([char]0x00E1)c T$([char]0x1ED3)n D$([char]0x01B0)"
    )

    if ($null -eq $Items -or $Items.Count -eq 0) {
        return [PSCustomObject]@{ Confirmed = $false; RemovedCount = 0; FreedBytes = 0L }
    }

    $dialog = New-Object System.Windows.Window
    $dialog.Title = $Title
    $dialog.Width = 920
    $dialog.Height = 580
    $dialog.MinWidth = 760
    $dialog.MinHeight = 440
    if ($OwnerWindow -and ($OwnerWindow -is [System.Windows.Window]) -and $OwnerWindow.IsLoaded) {
        $dialog.Owner = $OwnerWindow
        $dialog.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    } else {
        $dialog.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    }
    $dialog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E15")
    $dialog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F1F5F9")
    $dialog.WindowStyle = [System.Windows.WindowStyle]::SingleBorderWindow
    $dialog.UseLayoutRounding = $true
    $dialog.SnapsToDevicePixels = $true

    $rootGrid = New-Object System.Windows.Controls.Grid
    $rowTop = New-Object System.Windows.Controls.RowDefinition; $rowTop.Height = [System.Windows.GridLength]::Auto
    $rowList = New-Object System.Windows.Controls.RowDefinition; $rowList.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $rowBottom = New-Object System.Windows.Controls.RowDefinition; $rowBottom.Height = [System.Windows.GridLength]::Auto
    $rootGrid.RowDefinitions.Add($rowTop) | Out-Null
    $rootGrid.RowDefinitions.Add($rowList) | Out-Null
    $rootGrid.RowDefinitions.Add($rowBottom) | Out-Null

    $headerPanel = New-Object System.Windows.Controls.DockPanel
    $headerPanel.Margin = New-Object System.Windows.Thickness(18, 14, 18, 10)
    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = $Title
    $titleBlock.FontSize = 15
    $titleBlock.FontWeight = [System.Windows.FontWeights]::Bold
    $titleBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    $headerPanel.Children.Add($titleBlock) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($headerPanel, 0)
    $rootGrid.Children.Add($headerPanel) | Out-Null

    $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
    $scrollViewer.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $scrollViewer.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Disabled
    $scrollViewer.Margin = New-Object System.Windows.Thickness(18, 0, 18, 10)

    $itemsStack = New-Object System.Windows.Controls.StackPanel
    $itemCheckBoxes = [System.Collections.Generic.List[System.Windows.Controls.CheckBox]]::new()

    foreach ($item in $Items) {
        $itemBorder = New-Object System.Windows.Controls.Border
        $itemBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#101520")
        $itemBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $itemBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $itemBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $itemBorder.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
        $itemBorder.Padding = New-Object System.Windows.Thickness(10, 8, 10, 8)

        $itemGrid = New-Object System.Windows.Controls.Grid
        $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
        $c4 = New-Object System.Windows.Controls.ColumnDefinition; $c4.Width = [System.Windows.GridLength]::Auto
        $itemGrid.ColumnDefinitions.Add($c0) | Out-Null
        $itemGrid.ColumnDefinitions.Add($c1) | Out-Null
        $itemGrid.ColumnDefinitions.Add($c2) | Out-Null
        $itemGrid.ColumnDefinitions.Add($c3) | Out-Null
        $itemGrid.ColumnDefinitions.Add($c4) | Out-Null

        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.IsChecked = $true
        $cb.Tag = $item
        $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cb.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $itemGrid.Children.Add($cb) | Out-Null
        $itemCheckBoxes.Add($cb)

        $badgeStack = New-Object System.Windows.Controls.StackPanel
        $badgeStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $badgeStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $badgeStack.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)

        $badgeBorder = New-Object System.Windows.Controls.Border
        $badgeColor = switch -Wildcard ($item.Type) {
            "*Registry*" { "#DC2626" }
            "*Startup*" { "#E11D48" }
            "*R$([char]0x00E1)c AppData*" { "#D97706" }
            "*V$([char]0x1ECF) th$([char]0x01B0) m$([char]0x1EE5)c*" { "#2563EB" }
            "*Shortcut*" { "#7C3AED" }
            "*Crash Dump*" { "#9333EA" }
            default { "#0D9488" }
        }
        $badgeBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($badgeColor)
        $badgeBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $badgeBorder.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)

        $badgeText = New-Object System.Windows.Controls.TextBlock
        $badgeText.Text = $item.Type
        $badgeText.FontSize = 10.5
        $badgeText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $badgeText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        $badgeBorder.Child = $badgeText
        $badgeStack.Children.Add($badgeBorder) | Out-Null

        $confBorder = New-Object System.Windows.Controls.Border
        $confBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#064E3B")
        $confBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")
        $confBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $confBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $confBorder.Padding = New-Object System.Windows.Thickness(5, 1, 5, 1)
        $confBorder.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
        $confText = New-Object System.Windows.Controls.TextBlock
        $confText.Text = if ($item.Confidence) { $item.Confidence } else { "An to$([char]0x00E0)n 100%" }
        $confText.FontSize = 9.5
        $confText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#6EE7B7")
        $confBorder.Child = $confText
        $badgeStack.Children.Add($confBorder) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($badgeStack, 1)
        $itemGrid.Children.Add($badgeStack) | Out-Null

        $infoPanel = New-Object System.Windows.Controls.StackPanel
        $infoPanel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $appBlock = New-Object System.Windows.Controls.TextBlock
        $appBlock.Text = $item.AppName
        $appBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
        $appBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
        $infoPanel.Children.Add($appBlock) | Out-Null

        $displayPathText = if ($item.RegistryValueName) { "$($item.Path) [Value: $($item.RegistryValueName)]" } else { $item.Path }
        $pathBlock = New-Object System.Windows.Controls.TextBlock
        $pathBlock.Text = $displayPathText
        $pathBlock.FontSize = 11
        $pathBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        $pathBlock.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $pathBlock.ToolTip = $displayPathText
        $infoPanel.Children.Add($pathBlock) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($infoPanel, 2)
        $itemGrid.Children.Add($infoPanel) | Out-Null

        $sizeBlock = New-Object System.Windows.Controls.TextBlock
        $sizeBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $sizeBlock.FontSize = 11.5
        $sizeBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
        $sizeBlock.Margin = New-Object System.Windows.Thickness(10, 0, 8, 0)
        if ($item.IsRegistry) {
            $sizeBlock.Text = "Registry"
            $sizeBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        } else {
            $sizeBlock.Text = "$([string]::Format('{0:N2}', $item.SizeMB)) MB"
            $sizeBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        }
        [System.Windows.Controls.Grid]::SetColumn($sizeBlock, 3)
        $itemGrid.Children.Add($sizeBlock) | Out-Null

        $btnOpenLoc = New-Object System.Windows.Controls.Button
        $btnOpenLoc.Content = "M$([char]0x1EDF) v$([char]0x1ECB) tr$([char]0x00ED)"
        $btnOpenLoc.FontSize = 10.5
        $btnOpenLoc.Padding = New-Object System.Windows.Thickness(8, 3, 8, 3)
        $btnOpenLoc.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $btnOpenLoc.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $btnOpenLoc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
        $btnOpenLoc.Tag = $item
        $btnOpenLoc.Add_Click({
            param($sender, $e)
            $tg = $sender.Tag
            if ($null -eq $tg) { return }
            try {
                if ($tg.IsRegistry) {
                    $rawKey = $tg.Path -replace '^HKCU:\\', 'HKEY_CURRENT_USER\' -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
                    $regApplet = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit"
                    if (-not (Test-Path -LiteralPath $regApplet)) {
                        New-Item -Path $regApplet -Force | Out-Null
                    }
                    Set-ItemProperty -LiteralPath $regApplet -Name "LastKey" -Value "Computer\$rawKey" -ErrorAction SilentlyContinue
                    Start-Process "regedit.exe"
                } else {
                    if (Test-Path -LiteralPath $tg.Path) {
                        Start-Process "explorer.exe" -ArgumentList "/select,`"$($tg.Path)`""
                    }
                }
            } catch {}
        })
        [System.Windows.Controls.Grid]::SetColumn($btnOpenLoc, 4)
        $itemGrid.Children.Add($btnOpenLoc) | Out-Null

        $itemBorder.Child = $itemGrid
        $itemsStack.Children.Add($itemBorder) | Out-Null
    }

    $scrollViewer.Content = $itemsStack
    [System.Windows.Controls.Grid]::SetRow($scrollViewer, 1)
    $rootGrid.Children.Add($scrollViewer) | Out-Null

    $bottomBar = New-Object System.Windows.Controls.Border
    $bottomBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0D121B")
    $bottomBar.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
    $bottomBar.BorderThickness = New-Object System.Windows.Thickness(0, 1, 0, 0)
    $bottomBar.Padding = New-Object System.Windows.Thickness(18, 10, 18, 10)

    $bottomGrid = New-Object System.Windows.Controls.Grid
    $bgCol0 = New-Object System.Windows.Controls.ColumnDefinition; $bgCol0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $bgCol1 = New-Object System.Windows.Controls.ColumnDefinition; $bgCol1.Width = [System.Windows.GridLength]::Auto
    $bottomGrid.ColumnDefinitions.Add($bgCol0) | Out-Null
    $bottomGrid.ColumnDefinitions.Add($bgCol1) | Out-Null

    $leftBottomStack = New-Object System.Windows.Controls.StackPanel
    $leftBottomStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $summaryText = New-Object System.Windows.Controls.TextBlock
    $summaryText.FontSize = 12
    $summaryText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $summaryText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")

    $chkRecycleBin = New-Object System.Windows.Controls.CheckBox
    $chkRecycleBin.IsChecked = $true
    $chkRecycleBin.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    $chkRecycleBin.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
    $chkRecycleBin.Content = "Chuy$([char]0x1EC3)n file/th$([char]0x01B0) m$([char]0x1EE5)c v$([char]0x00E0)o Th$([char]0x00F9)ng r$([char]0x00E1)c Windows (An to$([char]0x00E0)n, kh$([char]0x00F4)i ph$([char]0x1EE5)c $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c n$([char]0x1EBF)u c$([char]0x1EA7)n)"

    $leftBottomStack.Children.Add($summaryText) | Out-Null
    $leftBottomStack.Children.Add($chkRecycleBin) | Out-Null

    $updateSummary = {
        $selCount = 0
        $selBytes = 0L
        foreach ($c in $itemCheckBoxes) {
            if ($c.IsChecked) {
                $selCount++
                $selBytes += $c.Tag.SizeBytes
            }
        }
        $mb = [math]::Round($selBytes / 1MB, 2)
        $summaryText.Text = "$([char]0x0110)$([char]0x00E3) ch$([char]0x1ECD)n: $selCount / $($itemCheckBoxes.Count) m$([char]0x1EE5)c (~$mb MB)"
    }
    & $updateSummary

    foreach ($c in $itemCheckBoxes) {
        $c.Add_Checked($updateSummary)
        $c.Add_Unchecked($updateSummary)
    }

    [System.Windows.Controls.Grid]::SetColumn($leftBottomStack, 0)
    $bottomGrid.Children.Add($leftBottomStack) | Out-Null

    $btnStack = New-Object System.Windows.Controls.StackPanel
    $btnStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $btnStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $btnSelectAll = New-Object System.Windows.Controls.Button
    $btnSelectAll.Content = "Ch$([char]0x1ECD)n t$([char]0x1EA5)t c$([char]0x1EA3)"
    $btnSelectAll.Padding = New-Object System.Windows.Thickness(10, 6, 10, 6)
    $btnSelectAll.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $btnSelectAll.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
    $btnSelectAll.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
    $btnSelectAll.Add_Click({
        foreach ($c in $itemCheckBoxes) { $c.IsChecked = $true }
    })
    $btnStack.Children.Add($btnSelectAll) | Out-Null

    $btnDeselectAll = New-Object System.Windows.Controls.Button
    $btnDeselectAll.Content = "B$([char]0x1ECF) ch$([char]0x1ECD)n"
    $btnDeselectAll.Padding = New-Object System.Windows.Thickness(10, 6, 10, 6)
    $btnDeselectAll.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $btnDeselectAll.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
    $btnDeselectAll.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
    $btnDeselectAll.Add_Click({
        foreach ($c in $itemCheckBoxes) { $c.IsChecked = $false }
    })
    $btnStack.Children.Add($btnDeselectAll) | Out-Null

    $btnCancel = New-Object System.Windows.Controls.Button
    $btnCancel.Content = "H$([char]0x1EE7)y b$([char]0x1ECF)"
    $btnCancel.Padding = New-Object System.Windows.Thickness(12, 6, 12, 6)
    $btnCancel.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $btnCancel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
    $btnCancel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
    $btnCancel.Add_Click({ $dialog.Close() })
    $btnStack.Children.Add($btnCancel) | Out-Null

    $dialogResult = [PSCustomObject]@{ Confirmed = $false; RemovedCount = 0; FreedBytes = 0L; RebootScheduled = 0 }

    $btnDelete = New-Object System.Windows.Controls.Button
    $btnDelete.Content = "X$([char]0x00F3)a S$([char]0x1EA1)ch M$([char]0x1EE5)c $([char]0x0110)$([char]0x00E3) Ch$([char]0x1ECD)n"
    $btnDelete.Padding = New-Object System.Windows.Thickness(14, 6, 14, 6)
    $btnDelete.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#991B1B")
    $btnDelete.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEE2E2")
    $btnDelete.FontWeight = [System.Windows.FontWeights]::Bold
    $btnDelete.Add_Click({
        $checkedItems = @($itemCheckBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        if ($checkedItems.Count -eq 0) {
            [System.Windows.MessageBox]::Show($dialog, "B$([char]0x1EA1)n ch$([char]0x01B0)a ch$([char]0x1ECD)n m$([char]0x1EE5)c n$([char]0x00E0)o $([char]0x0111)$([char]0x1EC3) d$([char]0x1ECD)n s$([char]0x1EA1)ch.", "Th$([char]0x00F4)ng b$([char]0x00E1)o", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            return
        }

        $useRecycle = [bool]$chkRecycleBin.IsChecked
        $removed = 0
        $freed = 0L
        $rebootTotal = 0

        foreach ($ci in $checkedItems) {
            try {
                if ($ci.IsRegistry) {
                    if ($ci.RegistryValueName) {
                        if (Test-Path -LiteralPath $ci.Path) {
                            Remove-ItemProperty -LiteralPath $ci.Path -Name $ci.RegistryValueName -Force -ErrorAction Stop
                            $removed++
                            if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                                Log-Text "[D$([char]0x1ECC)N R$([char]0x00C1)C] $([char]0x0110)$([char]0x00E3) x$([char]0x00F3)a Startup Registry: $($ci.Path) [$($ci.RegistryValueName)]"
                            }
                        }
                    } elseif (Test-Path -LiteralPath $ci.Path) {
                        Remove-Item -LiteralPath $ci.Path -Recurse -Force -ErrorAction Stop
                        $removed++
                        if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                            Log-Text "[D$([char]0x1ECC)N R$([char]0x00C1)C] $([char]0x0110)$([char]0x00E3) x$([char]0x00F3)a Registry: $($ci.Path)"
                        }
                    }
                } elseif (Test-Path -LiteralPath $ci.Path) {
                    $deletedOk = $false
                    if ($useRecycle) {
                        try {
                            $itemObj = Get-Item -LiteralPath $ci.Path -Force -ErrorAction Stop
                            if ($itemObj.PSIsContainer) {
                                [DuckUtil.DeepUninstallerEngine]::StopProcessesInDirectory($ci.Path) | Out-Null
                                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($ci.Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                            } else {
                                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($ci.Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                            }
                            $deletedOk = $true
                        } catch {
                            $deletedOk = $false
                        }
                    }

                    if (-not $deletedOk) {
                        $rbCount = 0
                        $deletedOk = [DuckUtil.DeepUninstallerEngine]::ForceDeleteDirectory($ci.Path, [ref]$rbCount)
                        $rebootTotal += $rbCount
                    }

                    if ($deletedOk) {
                        $removed++
                        $freed += $ci.SizeBytes
                        if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                            Log-Text "[D$([char]0x1ECC)N R$([char]0x00C1)C] $([char]0x0110)$([char]0x00E3) d$([char]0x1ECD)n s$([char]0x1EA1)ch: $($ci.Type) - $($ci.Path)"
                        }
                    }
                }
            } catch {
                if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                    Log-Text "[!] L$([char]0x1ED7)i khi x$([char]0x00F3)a $($ci.Path): $($_.Exception.Message)"
                }
            }
        }

        if ($rebootTotal -gt 0 -and (Get-Command Log-Text -ErrorAction SilentlyContinue)) {
            Log-Text "[*] $([char]0x0110)$([char]0x00E3) $([char]0x0111)$([char]0x1EB7)t l$([char]0x1ECB)ch x$([char]0x00F3)a $rebootTotal file $([char]0x0111)ang b$([char]0x1ECB) kh$([char]0x00F3)a ngay khi Windows kh$([char]0x1EDF)i $([char]0x0111)$([char]0x1ED9)ng l$([char]0x1EA1)i (MoveFileEx)."
        }

        $dialogResult.Confirmed = $true
        $dialogResult.RemovedCount = $removed
        $dialogResult.FreedBytes = $freed
        $dialogResult.RebootScheduled = $rebootTotal
        $dialog.Close()
    })
    $btnStack.Children.Add($btnDelete) | Out-Null

    [System.Windows.Controls.Grid]::SetColumn($btnStack, 1)
    $bottomGrid.Children.Add($btnStack) | Out-Null

    $bottomBar.Child = $bottomGrid
    [System.Windows.Controls.Grid]::SetRow($bottomBar, 2)
    $rootGrid.Children.Add($bottomBar) | Out-Null

    $dialog.Content = $rootGrid
    $null = $dialog.ShowDialog()

    return $dialogResult
}

function Invoke-DeepAppUninstall {
    param(
        [Parameter(Mandatory = $true)]$AppEntry,
        [Parameter(Mandatory = $false)]$OwnerWindow
    )

    if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
        Log-Text "=========================================================="
        Log-Text "B$([char]0x1EAE)T $([char]0x0110)$([char]0x1EA6)U G$([char]0x1EE0) C$([char]0x00C0)I $([char]0x0110)$([char]0x1EB6)T T$([char]0x1EAC)N G$([char]0x1ED0)C: $($AppEntry.DisplayName)"
        Log-Text "=========================================================="
    }

    $allInstalledNow = Get-SystemInstalledAppsFast

    $safeLoc = ""
    if ($AppEntry.InstallLocation -and (Test-Path -LiteralPath $AppEntry.InstallLocation)) {
        $loc = try { (Resolve-Path -LiteralPath $AppEntry.InstallLocation).Path.TrimEnd('\') } catch { $AppEntry.InstallLocation.Trim().TrimEnd('\') }
        if (Test-SafeAppDirectoryForCleanup -Path $loc -AppEntry $AppEntry -AllInstalledApps $allInstalledNow) {
            $safeLoc = $loc
            $svcCount = [DuckUtil.DeepUninstallerEngine]::DisableAndRemoveServicesInDirectory($loc)
            if ($svcCount -gt 0 -and (Get-Command Log-Text -ErrorAction SilentlyContinue)) {
                Log-Text "[*] $([char]0x0110)$([char]0x00E3) v$([char]0x00F4) hi$([char]0x1EC7)u h$([char]0x00F3)a & g$([char]0x1EE1) $svcCount Service / Kernel Driver ng$([char]0x1EA7)m trong: $loc"
            }
            $taskCount = [DuckUtil.DeepUninstallerEngine]::RemoveScheduledTasksInDirectory($loc)
            if ($taskCount -gt 0 -and (Get-Command Log-Text -ErrorAction SilentlyContinue)) {
                Log-Text "[*] $([char]0x0110)$([char]0x00E3) x$([char]0x00F3)a $taskCount Scheduled Task t$([char]0x1EF1) kh$([char]0x1EDF)i $([char]0x0111)$([char]0x1ED9)ng l$([char]0x1EA1)i trong: $loc"
            }
            $killedCount = [DuckUtil.DeepUninstallerEngine]::StopProcessesInDirectory($loc)
            if ($killedCount -gt 0 -and (Get-Command Log-Text -ErrorAction SilentlyContinue)) {
                Log-Text "[*] $([char]0x0110)$([char]0x00E3) $([char]0x0111)$([char]0x00F3)ng b$([char]0x0103)ng (NtSuspendProcess) & t$([char]0x1EAF)t $killedCount ti$([char]0x1EBF)n tr$([char]0x00EC)nh trong: $loc"
            }
        }
    }

    if (-not $AppEntry.IsBrokenOrphan) {
        $uninstCmd = if (-not [string]::IsNullOrWhiteSpace($AppEntry.QuietUninstallString)) {
            $AppEntry.QuietUninstallString
        } else {
            $AppEntry.UninstallString
        }

        if (-not [string]::IsNullOrWhiteSpace($uninstCmd)) {
            $uninstCmd = $uninstCmd.Trim()
            if ($uninstCmd.IndexOf("msiexec", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                    Log-Text "[*] $([char]0x0110)ang g$([char]0x1ECD)i Windows Installer g$([char]0x1EE1) b$([char]0x1ECF) g$([char]0x00F3)i MSI: $($AppEntry.DisplayName)..."
                }
                if (Get-Command Run-CliStream -ErrorAction SilentlyContinue) {
                    Run-CliStream "msiexec.exe" "/x `"$($AppEntry.Id)`" /qn /norestart"
                } else {
                    Start-Process "msiexec.exe" -ArgumentList "/x `"$($AppEntry.Id)`" /qn /norestart" -Wait -NoNewWindow
                }
            } else {
                $exe = ""
                $args = ""
                if ($uninstCmd.StartsWith('"')) {
                    $nextQ = $uninstCmd.IndexOf('"', 1)
                    if ($nextQ -gt 1) {
                        $exe = $uninstCmd.Substring(1, $nextQ - 1)
                        $args = $uninstCmd.Substring($nextQ + 1).Trim()
                    } else {
                        $exe = $uninstCmd.Trim('"')
                    }
                } else {
                    $parts = $uninstCmd -split '\s+', 2
                    $exe = $parts[0]
                    if ($parts.Count -gt 1) { $args = $parts[1] }
                }

                if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                    Log-Text "[*] $([char]0x0110)ang th$([char]0x1EF1)c thi tr$([char]0x00EC)nh g$([char]0x1EE1) b$([char]0x1ECF) ch$([char]0x00ED)nh th$([char]0x1EE9)c: $exe $args"
                }
                if (Get-Command Run-CliStream -ErrorAction SilentlyContinue) {
                    Run-CliStream $exe $args
                } else {
                    Start-Process $exe -ArgumentList $args -Wait -NoNewWindow
                }
            }
        }
    }

    Start-Sleep -Milliseconds 800

    if ($safeLoc -and (Test-Path -LiteralPath $safeLoc)) {
        [DuckUtil.DeepUninstallerEngine]::DisableAndRemoveServicesInDirectory($safeLoc) | Out-Null
        [DuckUtil.DeepUninstallerEngine]::RemoveScheduledTasksInDirectory($safeLoc) | Out-Null
        [DuckUtil.DeepUninstallerEngine]::StopProcessesInDirectory($safeLoc) | Out-Null
    }

    $leftovers = Find-AppLeftovers -AppEntry $AppEntry -AllInstalledApps $allInstalledNow
    if ($leftovers.Count -gt 0) {
        if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
            Log-Text "[*] Ph$([char]0x00E1)t hi$([char]0x1EC7)n $($leftovers.Count) m$([char]0x1EE5)c r$([char]0x00E1)c / Registry c$([char]0x00F2)n s$([char]0x00F3)t l$([char]0x1EA1)i sau khi g$([char]0x1EE1) b$([char]0x1ECF)."
        }
        $dialogTitle = "D$([char]0x1ECD)n r$([char]0x00E1)c t$([char]0x1ED3)n d$([char]0x01B0) sau khi g$([char]0x1EE1): $($AppEntry.DisplayName)"
        $res = Show-LeftoverReviewDialog -OwnerWindow $OwnerWindow -Items $leftovers -Title $dialogTitle
        if ($res.Confirmed) {
            if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
                $freedMb = [math]::Round($res.FreedBytes / 1MB, 2)
                Log-Text "[OK] $([char]0x0110)$([char]0x00E3) d$([char]0x1ECD)n s$([char]0x1EA1)ch $($res.RemovedCount) m$([char]0x1EE5)c t$([char]0x1ED3)n d$([char]0x01B0) (~$freedMb MB)."
            }
        }
    } else {
        if (Get-Command Log-Text -ErrorAction SilentlyContinue) {
            Log-Text "[OK] Tr$([char]0x00EC)nh g$([char]0x1EE1) b$([char]0x1ECF) $([char]0x0111)$([char]0x00E3) d$([char]0x1ECD)n d$([char]0x1EB9)p s$([char]0x1EA1)ch s$([char]0x1EBD), kh$([char]0x00F4)ng ph$([char]0x00E1)t hi$([char]0x1EC7)n r$([char]0x00E1)c t$([char]0x1ED3)n d$([char]0x01B0)."
        }
    }
}

function Find-FaultyPnpDevices {
    try {
        return @(Get-PnpDevice -ErrorAction Stop | Where-Object {
            $_.Present -eq $true -and ($_.Status -ne 'OK' -or ($null -ne $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0))
        })
    } catch {
        Log-Text "[!] Lỗi khi quét danh sách PnpDevice: $($_.Exception.Message)"
        return @()
    }
}

function Invoke-PnpDeviceRescan {
    $code = Run-CliStream "pnputil.exe" "/scan-devices"
    if ($code -eq 0) {
        Log-Text "[OK] Quét lại thiết bị phần cứng PnP thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] Quét thiết bị phần cứng PnP thất bại hoặc gặp lỗi (ExitCode: $code)."
    }
    return $code
}

function Invoke-PnpDriverStoreCleanup {
    Log-Text "[*] Đang phân tích danh sách gói Driver OEM bên thứ ba (pnputil /enum-drivers)..."
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "pnputil.exe"
        $pinfo.Arguments = "/enum-drivers"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($pinfo)
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        $raw = $outTask.Result

        $matches = [System.Text.RegularExpressions.Regex]::Matches($raw, '(?i)(?:Published Name|Tên đã phát hành):\s*(oem\d+\.inf)')
        $oemList = @($matches | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Select-Object -Unique)

        if ($oemList.Count -eq 0) {
            Log-Text "[OK] Không tìm thấy gói driver OEM nào trong DriverStore."
            return
        }

        Log-Text "[*] Tìm thấy $($oemList.Count) gói driver OEM. Bắt đầu dọn dẹp an toàn (không xóa driver đang sử dụng)..."
        $deletedCount = 0
        $inUseCount = 0
        $errorCount = 0

        foreach ($inf in $oemList) {
            try {
                $delPinfo = New-Object System.Diagnostics.ProcessStartInfo
                $delPinfo.FileName = "pnputil.exe"
                $delPinfo.Arguments = "/delete-driver $inf"
                $delPinfo.RedirectStandardOutput = $true
                $delPinfo.RedirectStandardError = $true
                $delPinfo.UseShellExecute = $false
                $delPinfo.CreateNoWindow = $true
                $delP = [System.Diagnostics.Process]::Start($delPinfo)

                $delOutTask = $delP.StandardOutput.ReadToEndAsync()
                $delErrTask = $delP.StandardError.ReadToEndAsync()
                $delP.WaitForExit()

                $delOut = $delOutTask.Result
                $delErr = $delErrTask.Result
                $combined = ($delOut + "`n" + $delErr).Trim()

                if ($delP.ExitCode -eq 0 -or $combined -match 'deleted successfully|đã xóa thành công') {
                    $deletedCount++
                    Log-Text "   [OK - Đã dọn] $inf"
                } elseif ($combined -match 'installed using the specified INF|đang được sử dụng|in use|bị từ chối') {
                    $inUseCount++
                } else {
                    $errorCount++
                    $errDetail = ($combined -split "`r?`n" | Where-Object { $_ -match 'failed|lỗi|error' } | Select-Object -First 1)
                    if (-not $errDetail) { $errDetail = "ExitCode $($delP.ExitCode)" }
                    Log-Text "   [WARN - Lỗi gói $inf] $errDetail"
                }
            } catch {
                $errorCount++
                Log-Text "   [!] Lỗi ngoại lệ khi xử lý ${inf}: $($_.Exception.Message)"
            }
            [System.Windows.Forms.Application]::DoEvents()
        }

        if ($deletedCount -gt 0) {
            Log-Text "[OK] Hoàn tất! Đã giải phóng $deletedCount gói driver OEM cũ không còn sử dụng ($inUseCount gói đang được phần cứng sử dụng an toàn)."
        } else {
            Log-Text "[OK] Toàn bộ $($oemList.Count) gói driver OEM đều đang được các thiết bị phần cứng sử dụng an toàn."
        }
        if ($errorCount -gt 0) {
            Log-Text "[!] Có $errorCount gói driver gặp lỗi trong quá trình xử lý."
        }
    } catch {
        Log-Text "[!] Lỗi khi dọn dẹp DriverStore: $($_.Exception.Message)"
    }
}

function Invoke-DismComponentCleanup {
    Log-Text "[WARN] CẢNH BÁO: Tùy chọn /ResetBase sẽ xóa vĩnh viễn các bản cập nhật cũ đã bị thay thế trong WinSxS."
    Log-Text "[*] Sau khi hoàn tất thao tác này, bạn SẼ KHÔNG THỂ gỡ cài đặt (rollback) các bản Windows Update hiện tại."
    Log-Text "[*] Đang tiến hành dọn dẹp và nén kho linh kiện WinSxS qua DISM..."
    $code = Run-CliStream "dism.exe" "/Online /Cleanup-Image /StartComponentCleanup /ResetBase"
    if ($code -eq 0) {
        Log-Text "[OK] Dọn dẹp kho linh kiện WinSxS hoàn tất thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] Dọn dẹp kho linh kiện WinSxS thất bại hoặc bị gián đoạn (ExitCode: $code)."
    }
    return $code
}

function Export-SystemDriversBackup {
    param([string]$Destination = "C:\Backup_Drivers")

    if (-not (Test-Path -LiteralPath $Destination)) {
        try {
            New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null
        } catch {
            Log-Text "[!] Không thể tạo thư mục sao lưu '$Destination': $($_.Exception.Message)"
            return $false
        }
    }

    try {
        Export-WindowsDriver -Online -Destination $Destination -ErrorAction Stop | Out-Null
        Log-Text "[OK] Sao lưu toàn bộ driver thành công qua Export-WindowsDriver."
        return $true
    } catch {
        Log-Text "[*] Export-WindowsDriver không khả dụng hoặc bị từ chối, chuyển sang pnputil.exe..."
        $exitCode = Run-CliStream "pnputil.exe" "/export-driver * `"$Destination`""
        if ($exitCode -eq 0) {
            Log-Text "[OK] Sao lưu toàn bộ driver thành công qua pnputil.exe (ExitCode: 0)."
            return $true
        } else {
            Log-Text "[!] Sao lưu driver qua pnputil.exe thất bại (ExitCode: $exitCode)."
            return $false
        }
    }
}

function Reset-WindowsUpdateEngine {
    Log-Text "[*] Đang dừng các dịch vụ Windows Update, BITS, DoSvc & TrustedInstaller..."
    $services = @("wuauserv", "bits", "cryptsvc", "dosvc", "trustedinstaller")
    foreach ($s in $services) {
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Milliseconds 1500

    Log-Text "[*] Đang làm mới bộ nhớ đệm SoftwareDistribution và Catroot2..."
    $sdPath = "C:\Windows\SoftwareDistribution"
    $sdRenamed = $true
    if (Test-Path -LiteralPath $sdPath) {
        $backupSD = "SoftwareDistribution.bak_$(Get-Random)"
        Rename-Item -LiteralPath $sdPath -NewName $backupSD -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $sdPath) {
            $sdRenamed = $false
            Log-Text "[WARN] Không thể đổi tên SoftwareDistribution (tệp đang bị khóa bởi tiến trình khác)."
        }
    }

    $crPath = "C:\Windows\System32\catroot2"
    $crRenamed = $true
    if (Test-Path -LiteralPath $crPath) {
        $backupCR = "catroot2.bak_$(Get-Random)"
        Rename-Item -LiteralPath $crPath -NewName $backupCR -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $crPath) {
            $crRenamed = $false
            Log-Text "[WARN] Không thể đổi tên catroot2 (tệp đang bị khóa)."
        }
    }

    Log-Text "[*] Khởi động lại các dịch vụ hệ thống..."
    Start-Service -Name "cryptsvc" -ErrorAction SilentlyContinue
    Start-Service -Name "bits" -ErrorAction SilentlyContinue
    Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    Start-Service -Name "dosvc" -ErrorAction SilentlyContinue

    if ($sdRenamed -and $crRenamed) {
        Log-Text "[OK] Đã khởi tạo lại dịch vụ Windows Update và xóa sạch cache thành công!"
    } else {
        Log-Text "[*] Đã đặt lại dịch vụ Windows Update (một số thư mục cache đang được hệ thống bảo vệ)."
    }
}

function Invoke-WindowsUpdateScan {
    Log-Text "[*] Đang gửi tín hiệu yêu cầu Windows tìm kiếm bản cập nhật mới..."
    try {
        $au = New-Object -ComObject Microsoft.Update.AutoUpdate
        $au.DetectNow()
        Log-Text "[OK] Đã kích hoạt Microsoft.Update.AutoUpdate.DetectNow() thành công."
    } catch {
        Log-Text "[*] COM AutoUpdate không phản hồi, mở trang cập nhật hệ thống..."
    }

    try {
        Start-Process "ms-settings:windowsupdate-action" -ErrorAction SilentlyContinue
    } catch {}
}

function Invoke-SystemFileCheck {
    Log-Text "[*] Đang khởi chạy System File Checker (sfc /scannow)..."
    $code = Run-CliStream "sfc.exe" "/scannow"
    if ($code -eq 0) {
        Log-Text "[OK] SFC Scan hoàn tất: Toàn vẹn tệp hệ thống đạt chuẩn (ExitCode: 0)."
    } else {
        Log-Text "[!] SFC Scan phát hiện lỗi hoặc không thể sửa chữa toàn bộ tệp hệ thống (ExitCode: $code)."
    }
    return $code
}

function Invoke-DismRestoreHealth {
    Log-Text "[*] Đang khởi chạy DISM RestoreHealth khôi phục kho linh kiện hệ thống..."
    $code = Run-CliStream "dism.exe" "/Online /Cleanup-Image /RestoreHealth"
    if ($code -eq 0) {
        Log-Text "[OK] DISM RestoreHealth hoàn tất thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] DISM RestoreHealth thất bại hoặc gặp sự cố (ExitCode: $code). Hãy kiểm tra kết nối mạng hoặc nguồn tệp hệ thống."
    }
    return $code
}

function Clear-DnsResolverCache {
    $code = Run-CliStream "ipconfig.exe" "/flushdns"
    if ($code -eq 0) {
        Log-Text "[OK] Làm mới bộ nhớ đệm DNS thành công (ExitCode: 0)."
    } else {
        Log-Text "[!] Làm mới bộ nhớ đệm DNS thất bại (ExitCode: $code)."
    }
    return $code
}

function Reset-NetworkInterfaceStack {
    $codeWinsock = Run-CliStream "netsh.exe" "winsock reset"
    $codeTcpIp = Run-CliStream "netsh.exe" "int ip reset"
    if ($codeWinsock -eq 0 -and $codeTcpIp -eq 0) {
        Log-Text "[OK] Đặt lại Winsock Catalog và TCP/IP Stack thành công (ExitCode: 0). Khuyên bạn nên khởi động lại máy."
    } else {
        Log-Text "[!] Đặt lại mạng gặp lỗi (Winsock ExitCode: $codeWinsock, TCP/IP ExitCode: $codeTcpIp)."
    }
    return ($codeWinsock -eq 0 -and $codeTcpIp -eq 0)
}

function Clear-SystemTempFiles {
    $tempPaths = @($env:TEMP, "C:\Windows\Temp")
    foreach ($p in $tempPaths) {
        if (Test-Path -LiteralPath $p) {
            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Clear-SystemEventLogs {
    Log-Text "[*] Đang quét và dọn sạch nhật ký sự kiện Windows Event Logs..."
    Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)
        } catch {}
    }
    Log-Text "[OK] Toàn bộ Windows Event Logs đã được làm sạch."
}

$reader = New-Object System.Xml.XmlNodeReader $XAML
$window = [Windows.Markup.XamlReader]::Load($reader)

try {
    $wa = [System.Windows.SystemParameters]::WorkArea
    if ($wa.Width -gt 0 -and $window.Width -gt ($wa.Width - 24)) {
        $window.Width = [math]::Max($window.MinWidth, $wa.Width - 24)
    }
    if ($wa.Height -gt 0 -and $window.Height -gt ($wa.Height - 24)) {
        $window.Height = [math]::Max(560, $wa.Height - 24)
        $window.MinHeight = [math]::Min($window.MinHeight, $window.Height)
    }
} catch {}

$MainTabControl    = $window.FindName("MainTabControl")
$txtStatus         = $window.FindName("txtStatus")
$progressBar       = $window.FindName("progressBar")
$txtSelectionCount = $window.FindName("txtSelectionCount")
$cardsContainer    = $window.FindName("CardsContainer")

$script:brushNavActive   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushNavActive.Freeze()
$script:brushNavInactive = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x64, 0x74, 0x8B)); $script:brushNavInactive.Freeze()
$script:brushTransparent = [System.Windows.Media.Brushes]::Transparent

$script:brushCardBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x11, 0x17, 0x22)); $script:brushCardBg.Freeze()
$script:brushCardBorder  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1C, 0x25, 0x36)); $script:brushCardBorder.Freeze()
$script:brushHeaderFg    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x7D, 0xD3, 0xFC)); $script:brushHeaderFg.Freeze()
$script:brushHeaderCntBg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x16, 0x1E, 0x2E)); $script:brushHeaderCntBg.Freeze()
$script:brushHeaderCntFg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x64, 0x74, 0x8B)); $script:brushHeaderCntFg.Freeze()
$script:brushSeparator   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1A, 0x22, 0x32)); $script:brushSeparator.Freeze()

$script:brushRowHover    = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x19, 0x22, 0x34)); $script:brushRowHover.Freeze()
$script:brushTextWhite   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xF1, 0xF5, 0xF9)); $script:brushTextWhite.Freeze()
$script:fontSegoeEmoji   = New-Object System.Windows.Media.FontFamily("Segoe UI Emoji, Segoe UI Symbol, Arial")
$script:fontSegoeUI      = New-Object System.Windows.Media.FontFamily("Segoe UI Variable Text, Segoe UI, Arial")

$script:brushLinkBtnBg        = [System.Windows.Media.Brushes]::Transparent
$script:brushLinkBtnBorder    = [System.Windows.Media.Brushes]::Transparent
$script:brushLinkBtnFg        = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x52, 0x60, 0x76)); $script:brushLinkBtnFg.Freeze()
$script:brushLinkBtnRowHover  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x94, 0xA3, 0xB8)); $script:brushLinkBtnRowHover.Freeze()

$script:brushLinkBtnHoverBg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x1E, 0x29, 0x3B)); $script:brushLinkBtnHoverBg.Freeze()
$script:brushLinkBtnHoverBdr  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushLinkBtnHoverBdr.Freeze()
$script:brushLinkBtnHoverFg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x38, 0xBD, 0xF8)); $script:brushLinkBtnHoverFg.Freeze()

$script:brushIconBadgeBg        = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(14, 255, 255, 255)); $script:brushIconBadgeBg.Freeze()
$script:brushIconBadgeLightBg   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(245, 255, 255, 255)); $script:brushIconBadgeLightBg.Freeze()
$script:brushIconBadgeBorder    = [System.Windows.Media.Brushes]::Transparent

$script:styleAppRow = New-Object System.Windows.Style([System.Windows.Controls.Border])
$script:styleAppRow.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushTransparent)))
$trigRowHover = New-Object System.Windows.Trigger
$trigRowHover.Property = [System.Windows.UIElement]::IsMouseOverProperty
$trigRowHover.Value = $true
$trigRowHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushRowHover)))
$script:styleAppRow.Triggers.Add($trigRowHover)
$script:styleAppRow.Seal()

$script:styleLinkBtn = New-Object System.Windows.Style([System.Windows.Controls.Border])
$script:styleLinkBtn.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushLinkBtnBg)))
$script:styleLinkBtn.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushLinkBtnBorder)))
$trigLinkHover = New-Object System.Windows.Trigger
$trigLinkHover.Property = [System.Windows.UIElement]::IsMouseOverProperty
$trigLinkHover.Value = $true
$trigLinkHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $script:brushLinkBtnHoverBg)))
$trigLinkHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushLinkBtnHoverBdr)))
$script:styleLinkBtn.Triggers.Add($trigLinkHover)
$script:styleLinkBtn.Seal()

$script:brushCardHoverBorder = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0x2B, 0x45, 0x68)); $script:brushCardHoverBorder.Freeze()
$script:styleCategoryCard = New-Object System.Windows.Style([System.Windows.Controls.Border])
$script:styleCategoryCard.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushCardBorder)))
$trigCardHover = New-Object System.Windows.Trigger
$trigCardHover.Property = [System.Windows.UIElement]::IsMouseOverProperty
$trigCardHover.Value = $true
$trigCardHover.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $script:brushCardHoverBorder)))
$script:styleCategoryCard.Triggers.Add($trigCardHover)
$script:styleCategoryCard.Seal()

if (-not ("DuckUtil.SmoothScrollController" -as [type])) {
    try {
        $csCandidates = @(
            (Join-Path $PSScriptRoot "..\csharp\SmoothScrollController.cs"),
            (Join-Path $PSScriptRoot "csharp\SmoothScrollController.cs")
        )
        foreach ($cand in $csCandidates) {
            if (Test-Path -LiteralPath $cand) {
                $wpfSmoothRefs = @(
                    [System.Windows.Controls.ScrollViewer].Assembly.Location,
                    [System.Windows.UIElement].Assembly.Location,
                    [System.Windows.DependencyObject].Assembly.Location,
                    [System.Windows.Markup.IQueryAmbient].Assembly.Location,
                    [System.Diagnostics.Stopwatch].Assembly.Location,
                    [System.Object].Assembly.Location
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
                $smoothScrollCs = Get-Content -Raw -Encoding utf8 $cand
                Add-Type -TypeDefinition $smoothScrollCs -ReferencedAssemblies $wpfSmoothRefs -ErrorAction SilentlyContinue
                break
            }
        }
    } catch {}
}

$appsScrollViewer = $window.FindName("AppsScrollViewer")
if ($appsScrollViewer -and ("DuckUtil.SmoothScrollController" -as [type])) {
    $script:smoothScrollCtrl = [DuckUtil.SmoothScrollController]::Attach($appsScrollViewer)
}
$uninstallerScrollViewer = $window.FindName("UninstallerScrollViewer")
if ($uninstallerScrollViewer -and ("DuckUtil.SmoothScrollController" -as [type])) {
    $script:uninstallerSmoothScrollCtrl = [DuckUtil.SmoothScrollController]::Attach($uninstallerScrollViewer)
}

try {
    [System.Net.ServicePointManager]::DefaultConnectionLimit = 24
    [System.Net.ServicePointManager]::Expect100Continue = $false
} catch {}

function Import-LocalIconBitmap {
    param(
        [string]$Path,
        [string]$CacheKey = ""
    )
    if (-not [string]::IsNullOrWhiteSpace($CacheKey)) {
        $cached = $null
        if ($script:remoteBmpCache -and $script:remoteBmpCache.TryGetValue($CacheKey, [ref]$cached)) {
            return $cached
        }
    }
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.File]::Exists($Path)) { return $null }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if (-not $bytes -or $bytes.Length -le 64) { return $null }
        $ms = [System.IO.MemoryStream]::new($bytes)
        try {
            $bmp = [System.Windows.Media.Imaging.BitmapImage]::new()
            $bmp.BeginInit()
            $bmp.StreamSource = $ms
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.DecodePixelWidth = 36
            $bmp.EndInit()
            $bmp.Freeze()
            if (-not [string]::IsNullOrWhiteSpace($CacheKey) -and $script:remoteBmpCache) {
                $script:remoteBmpCache[$CacheKey] = $bmp
            }
            return $bmp
        } finally {
            $ms.Dispose()
        }
    } catch {
        try { [System.IO.File]::Delete($Path) } catch {}
        return $null
    }
}

$script:pendingIconSaves = [System.Collections.Generic.List[hashtable]]::new()
$script:inFlightIconTasks = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Start-BackgroundIconDownload {
    param(
        [string]$Url,
        [string]$DestPath
    )
    if ([string]::IsNullOrWhiteSpace($Url) -or [string]::IsNullOrWhiteSpace($DestPath)) { return $null }
    $existing = $null
    if ($script:inFlightIconTasks.TryGetValue($Url, [ref]$existing)) {
        return $existing
    }
    try {
        $wc = [System.Net.WebClient]::new()
        $wc.Proxy = $null
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) DuckUtil/3.5")
        $task = $wc.DownloadDataTaskAsync([uri]$Url)
        $info = @{
            Url      = $Url
            DestPath = $DestPath
            Client   = $wc
            Task     = $task
            Saved    = $false
        }
        $script:inFlightIconTasks[$Url] = $info
        return $info
    } catch {
        return $null
    }
}

function Flush-PendingIconCache {
    if (-not $script:pendingIconSaves -or $script:pendingIconSaves.Count -eq 0) { return }
    if ($script:isScanningApps -or $script:isActionRunning) { return }
    $inFlightCount = 0
    $decodedCount  = 0
    for ($idx = $script:pendingIconSaves.Count - 1; $idx -ge 0; $idx--) {
        $entry = $script:pendingIconSaves[$idx]
        if (-not $entry.DownloadInfo -and $entry.Url) {
            if ($inFlightCount -ge 10 -and -not $script:inFlightIconTasks.ContainsKey($entry.Url)) {
                continue
            }
            $entry.DownloadInfo = Start-BackgroundIconDownload -Url $entry.Url -DestPath $entry.DestPath
        }
        $dlInfo = $entry.DownloadInfo
        if ($dlInfo -and $dlInfo.Task) {
            if (-not $dlInfo.Task.IsCompleted) {
                $inFlightCount++
                continue
            }
            if (-not $dlInfo.Saved) {
                $dlInfo.Saved = $true
                if ($dlInfo.Task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                    try {
                        $data = $dlInfo.Task.Result
                        if ($data -and $data.Length -gt 64 -and -not [System.IO.File]::Exists($entry.DestPath)) {
                            $tmpFile = "$($entry.DestPath).$([guid]::NewGuid().ToString('N')).tmp"
                            [System.IO.File]::WriteAllBytes($tmpFile, $data)
                            Move-Item -LiteralPath $tmpFile -Destination $entry.DestPath -Force -ErrorAction SilentlyContinue
                        }
                    } catch {}
                }
                try { if ($dlInfo.Client) { $dlInfo.Client.Dispose() } } catch {}
            }
        }
        if ([System.IO.File]::Exists($entry.DestPath) -or ($script:remoteBmpCache -and $script:remoteBmpCache.ContainsKey($entry.CacheKey))) {
            if ($decodedCount -ge 20) { continue }
            $bmp = Import-LocalIconBitmap -Path $entry.DestPath -CacheKey $entry.CacheKey
            if ($bmp -and $bmp.PixelWidth -gt 0) {
                $decodedCount++
                if (-not [System.IO.File]::Exists($entry.DestPath)) {
                    Save-BitmapToCacheAtomic -BitmapSource $bmp -DestPath $entry.DestPath
                }
                if ($entry.Img) {
                    $entry.Img.Source = $bmp
                    $entry.Img.Visibility = [System.Windows.Visibility]::Visible
                }
                if ($entry.Fallback) {
                    $entry.Fallback.Visibility = [System.Windows.Visibility]::Collapsed
                }
            }
        }
        $script:pendingIconSaves.RemoveAt($idx)
    }
}
$script:cornerIconBadge         = New-Object System.Windows.CornerRadius(5)
$script:brushUpdateBadgeBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(28, 0xF8, 0x71, 0x71)); $script:brushUpdateBadgeBg.Freeze()
$script:brushUpdateBadgeBorder  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(85, 0xF8, 0x71, 0x71)); $script:brushUpdateBadgeBorder.Freeze()
$script:brushUpdateBadgeFg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 0xFC, 0xA5, 0xA5)); $script:brushUpdateBadgeFg.Freeze()

$marginCardBorder = New-Object System.Windows.Thickness(4)
$paddingCard      = New-Object System.Windows.Thickness(10, 8, 10, 10)
$marginHeaderGrid = New-Object System.Windows.Thickness(2, 0, 2, 6)
$marginSeparator  = New-Object System.Windows.Thickness(0, 1, 0, 5)
$marginRowBorder  = New-Object System.Windows.Thickness(0, 1, 0, 1)
$paddingRow       = New-Object System.Windows.Thickness(5, 0, 4, 0)
$marginIcon       = New-Object System.Windows.Thickness(7, 0, 8, 0)
$cornerCard       = New-Object System.Windows.CornerRadius(8)
$cornerRow        = New-Object System.Windows.CornerRadius(5)
$thicknessZero    = New-Object System.Windows.Thickness(0)
$thicknessOne     = New-Object System.Windows.Thickness(1)

$iconsCacheDir = Join-Path $env:LOCALAPPDATA "DuckUtil\Icons"
if (-not (Test-Path -LiteralPath $iconsCacheDir)) {
    try { New-Item -ItemType Directory -Path $iconsCacheDir -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
} else {
    try {
        Get-ChildItem -Path $iconsCacheDir -Filter "*.png" -ErrorAction SilentlyContinue | Where-Object {
            $_.Length -le 230 -or $_.Length -eq 588
        } | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}

    try {
        $mapFile = Join-Path $iconsCacheDir "cache.icons.map.txt"
        $oldMap = @{}
        if (Test-Path -LiteralPath $mapFile) {
            foreach ($line in [System.IO.File]::ReadAllLines($mapFile)) {
                $sepIdx = $line.IndexOf('=')
                if ($sepIdx -gt 0) {
                    $oldMap[$line.Substring(0, $sepIdx)] = $line.Substring($sepIdx + 1)
                }
            }
        }
        $newLines = [System.Collections.Generic.List[string]]::new()
        $mapChanged = $false
        if ($AppCatalog) {
            foreach ($appItem in $AppCatalog) {
                $appKey = "$($appItem.ID)"
                $appVal = "$($appItem.IconUrl)|$($appItem.Domain)"
                $newLines.Add("$appKey=$appVal")
                if ($oldMap.ContainsKey($appKey)) {
                    if ($oldMap[$appKey] -ne $appVal) {
                        $staleIcon = Join-Path $iconsCacheDir "$appKey.png"
                        if (Test-Path -LiteralPath $staleIcon) {
                            Remove-Item -LiteralPath $staleIcon -Force -ErrorAction SilentlyContinue
                        }
                        $mapChanged = $true
                    }
                } else {
                    $mapChanged = $true
                }
            }
        }
        if ($mapChanged -or -not (Test-Path -LiteralPath $mapFile)) {
            [System.IO.File]::WriteAllLines($mapFile, $newLines, [System.Text.Encoding]::UTF8)
        }
    } catch {}
}

function Save-BitmapToCacheAtomic {
    param($BitmapSource, [string]$DestPath)
    if (-not $BitmapSource -or [string]::IsNullOrWhiteSpace($DestPath) -or (Test-Path -LiteralPath $DestPath)) { return }
    try {
        if ($BitmapSource.PixelWidth -le 0 -or $BitmapSource.PixelHeight -le 0) { return }
        $tmpPath = "$DestPath.$([guid]::NewGuid().ToString('N')).tmp"
        $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($BitmapSource))
        $fs = $null
        try {
            $fs = [System.IO.File]::OpenWrite($tmpPath)
            $encoder.Save($fs)
        } finally {
            if ($fs) { $fs.Dispose() }
        }
        if ((Test-Path -LiteralPath $tmpPath) -and (Get-Item -LiteralPath $tmpPath).Length -gt 64) {
            Move-Item -LiteralPath $tmpPath -Destination $DestPath -Force -ErrorAction SilentlyContinue
        } elseif (Test-Path -LiteralPath $tmpPath) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
    } catch {
        if ($tmpPath -and (Test-Path -LiteralPath $tmpPath)) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
    }
}

$script:isActionRunning = $false

function Invoke-GuardedAction {
    param(
        [string]$ActionName,
        [scriptblock]$Action,
        [switch]$DeferExpand
    )
    if ($script:isActionRunning) {
        Log-Text "[WARN] Đang có một tác vụ khác đang thực thi ($ActionName). Vui lòng đợi!"
        return
    }
    if (-not $DeferExpand) {
        Expand-TerminalLog
    }
    $script:isActionRunning = $true
    try {
        & $Action
    } catch {
        Log-Text "[!] Lỗi khi thực hiện '$ActionName': $($_.Exception.Message)"
    } finally {
        $script:isActionRunning = $false
        try { Flush-PendingIconCache } catch {}
        [System.Windows.Forms.Application]::DoEvents()
    }
}

$script:LockMaintenanceTabs = $true
$script:LockedButtonActions = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Test-MaintenanceFeatureLocked {
    param([string]$FeatureName)
    if ($script:LockMaintenanceTabs) {
        Log-Text "[LOCK] Tính năng '$FeatureName' hiện đang được tạm khóa."
        if ($txtStatus) { $txtStatus.Text = "Tính năng '$FeatureName' đang tạm khóa" }
        return $true
    }
    return $false
}

function Register-Click {
    param(
        [string]$ButtonName,
        [scriptblock]$Action,
        [string]$LockGroup = ""
    )
    $btn = $window.FindName($ButtonName)
    if ($btn) {
        if (-not [string]::IsNullOrWhiteSpace($LockGroup)) {
            $script:LockedButtonActions[$ButtonName] = @{
                Group  = $LockGroup
                Action = $Action
            }
            if ($script:LockMaintenanceTabs) {
                $btn.IsEnabled = $false
            }
            $btn.Add_Click({
                param($sender, $e)
                $entry = $script:LockedButtonActions[$sender.Name]
                if ($entry -and (Test-MaintenanceFeatureLocked $entry.Group)) { return }
                if ($entry -and $entry.Action) { & $entry.Action }
            })
        } else {
            $btn.Add_Click($Action)
        }
    } else {
        Write-Warning "Không tìm thấy nút trong XAML: $ButtonName"
    }
}

$navBtnApps        = $window.FindName("navBtnApps")
$navBtnUninstaller = $window.FindName("navBtnUninstaller")
$navBtnRepair      = $window.FindName("navBtnRepair")
$navBtnDrivers     = $window.FindName("navBtnDrivers")

$script:uninstallerLoadedOnce = $false

function Set-ActiveTab {
    param([int]$index, $activeBtn)
    if ($script:LockMaintenanceTabs -and ($index -eq 2 -or $index -eq 3)) {
        $feature = if ($index -eq 2) { "Gỡ lỗi & Hệ thống" } else { "Quản lý Driver" }
        Test-MaintenanceFeatureLocked $feature | Out-Null
        return
    }
    if ($MainTabControl) {
        $MainTabControl.SelectedIndex = $index
    }

    if ($index -eq 1 -and -not $script:uninstallerLoadedOnce) {
        $script:uninstallerLoadedOnce = $true
        Update-UninstallerList
    }

    $buttons = @($navBtnApps, $navBtnUninstaller, $navBtnRepair, $navBtnDrivers)
    foreach ($btn in $buttons) {
        if ($btn) {
            $btn.Foreground  = $script:brushNavInactive
            $btn.BorderBrush = $script:brushTransparent
        }
    }

    if ($activeBtn) {
        $activeBtn.Foreground  = $script:brushNavActive
        $activeBtn.BorderBrush = $script:brushNavActive
    }
}

Register-Click "navBtnApps"        { Set-ActiveTab 0 $navBtnApps }
Register-Click "navBtnUninstaller" { Set-ActiveTab 1 $navBtnUninstaller }
Register-Click "navBtnRepair"      -LockGroup "Gỡ lỗi & Hệ thống" { Set-ActiveTab 2 $navBtnRepair }
Register-Click "navBtnDrivers"     -LockGroup "Quản lý Driver"    { Set-ActiveTab 3 $navBtnDrivers }

Set-ActiveTab 0 $navBtnApps

$btnDeepUninstall        = $window.FindName("btnDeepUninstall")
$btnScanOrphans          = $window.FindName("btnScanOrphans")
$btnRefreshUninstaller   = $window.FindName("btnRefreshUninstaller")
$btnFilterUninstAll      = $window.FindName("btnFilterUninstAll")
$btnFilterUninstBroken   = $window.FindName("btnFilterUninstBroken")
$txtUninstallSearch      = $window.FindName("txtUninstallSearch")
$btnClearUninstallSearch = $window.FindName("btnClearUninstallSearch")
$btnUninstallSelectAll   = $window.FindName("btnUninstallSelectAll")
$btnUninstallDeselectAll = $window.FindName("btnUninstallDeselectAll")
$txtUninstallerSummary   = $window.FindName("txtUninstallerSummary")
$uninstallerRowsPanel    = $window.FindName("UninstallerRowsPanel")

$script:cachedUninstallerApps = @()
$script:uninstallerRowEntries = [System.Collections.Generic.List[object]]::new()
$script:uninstallerFilterMode = "All"

function Update-UninstallerSelectionCount {
    $count = 0
    foreach ($entry in $script:uninstallerRowEntries) {
        if ($entry.CheckBox -and $entry.CheckBox.IsChecked -eq $true) {
            $count++
        }
    }
    if ($btnDeepUninstall) {
        $btnDeepUninstall.Content = "Gỡ Tận Gốc ($count)"
        $btnDeepUninstall.IsEnabled = ($count -gt 0)
    }
}

function Apply-UninstallerFilter {
    $q = if ($txtUninstallSearch) { $txtUninstallSearch.Text.Trim().ToLowerInvariant() } else { "" }
    $visibleCount = 0
    $brokenCount = 0

    foreach ($entry in $script:uninstallerRowEntries) {
        $app = $entry.App
        if ($app.IsBrokenOrphan) { $brokenCount++ }

        $matchSearch = [string]::IsNullOrEmpty($q) -or $entry.SearchText.Contains($q)
        $matchFilter = if ($script:uninstallerFilterMode -eq "Broken") { [bool]$app.IsBrokenOrphan } else { $true }

        if ($matchSearch -and $matchFilter) {
            $entry.Row.Visibility = [System.Windows.Visibility]::Visible
            $visibleCount++
        } else {
            $entry.Row.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }

    if ($txtUninstallerSummary) {
        $total = $script:cachedUninstallerApps.Count
        $txtUninstallerSummary.Text = "Đang hiển thị $visibleCount / $total ứng dụng ($brokenCount ứng dụng lỗi/mồ côi)"
    }
    Update-UninstallerSelectionCount
}

function Update-UninstallerList {
    if (-not $uninstallerRowsPanel) { return }
    if ($txtUninstallerSummary) { $txtUninstallerSummary.Text = "Đang quét danh sách ứng dụng đã cài..." }
    [System.Windows.Forms.Application]::DoEvents()

    if (Get-Command "Get-SystemInstalledAppsFast" -ErrorAction SilentlyContinue) {
        $script:cachedUninstallerApps = @(Get-SystemInstalledAppsFast)
    } else {
        $script:cachedUninstallerApps = @()
    }

    $uninstallerRowsPanel.Children.Clear()
    $script:uninstallerRowEntries.Clear()

    foreach ($app in $script:cachedUninstallerApps) {
        $rowBorder = New-Object System.Windows.Controls.Border
        $rowBorder.Height = 34
        $rowBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $rowBorder.Padding = New-Object System.Windows.Thickness(8, 0, 8, 0)
        $rowBorder.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
        $rowBorder.Background = $script:brushTransparent
        $rowBorder.Cursor = [System.Windows.Input.Cursors]::Hand

        $rowGrid = New-Object System.Windows.Controls.Grid
        $rowGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = New-Object System.Windows.GridLength(36, [System.Windows.GridUnitType]::Pixel)
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(120, [System.Windows.GridUnitType]::Pixel)
        $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = New-Object System.Windows.GridLength(180, [System.Windows.GridUnitType]::Pixel)
        $c4 = New-Object System.Windows.Controls.ColumnDefinition; $c4.Width = New-Object System.Windows.GridLength(95, [System.Windows.GridUnitType]::Pixel)
        $c5 = New-Object System.Windows.Controls.ColumnDefinition; $c5.Width = New-Object System.Windows.GridLength(110, [System.Windows.GridUnitType]::Pixel)
        $c6 = New-Object System.Windows.Controls.ColumnDefinition; $c6.Width = New-Object System.Windows.GridLength(44, [System.Windows.GridUnitType]::Pixel)

        $rowGrid.ColumnDefinitions.Add($c0) | Out-Null
        $rowGrid.ColumnDefinitions.Add($c1) | Out-Null
        $rowGrid.ColumnDefinitions.Add($c2) | Out-Null
        $rowGrid.ColumnDefinitions.Add($c3) | Out-Null
        $rowGrid.ColumnDefinitions.Add($c4) | Out-Null
        $rowGrid.ColumnDefinitions.Add($c5) | Out-Null
        $rowGrid.ColumnDefinitions.Add($c6) | Out-Null

        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cb.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $cb.Margin = New-Object System.Windows.Thickness(2, 0, 0, 0)
        $cb.Add_Checked({ Update-UninstallerSelectionCount })
        $cb.Add_Unchecked({ Update-UninstallerSelectionCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $rowGrid.Children.Add($cb) | Out-Null

        $namePanel = New-Object System.Windows.Controls.StackPanel
        $namePanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $namePanel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $glyphTb = New-Object System.Windows.Controls.TextBlock
        $glyphTb.Text = if ($app.IsBrokenOrphan) { [char]::ConvertFromUtf32(0x26A0) } else { [char]::ConvertFromUtf32(0x1F4E6) }
        $glyphTb.FontSize = 11
        $glyphTb.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        $glyphTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $namePanel.Children.Add($glyphTb) | Out-Null

        $nameTb = New-Object System.Windows.Controls.TextBlock
        $nameTb.Text = $app.DisplayName
        $nameTb.FontSize = 12
        $nameTb.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameTb.Foreground = if ($app.IsBrokenOrphan) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FCA5A5") } else { $script:brushTextWhite }
        $nameTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $nameTb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $namePanel.Children.Add($nameTb) | Out-Null

        $rowTooltip = "$($app.DisplayName)`nPhiên bản: $($app.DisplayVersion)`nNhà phát hành: $($app.Publisher)`nĐường dẫn: $($app.InstallLocation)`nLệnh gỡ: $($app.UninstallString)"
        $rowBorder.ToolTip = $rowTooltip

        [System.Windows.Controls.Grid]::SetColumn($namePanel, 1)
        $rowGrid.Children.Add($namePanel) | Out-Null

        $verTb = New-Object System.Windows.Controls.TextBlock
        $verTb.Text = if ($app.DisplayVersion) { $app.DisplayVersion } else { "--" }
        $verTb.FontSize = 11.5
        $verTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        $verTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $verTb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $verTb.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
        [System.Windows.Controls.Grid]::SetColumn($verTb, 2)
        $rowGrid.Children.Add($verTb) | Out-Null

        $pubTb = New-Object System.Windows.Controls.TextBlock
        $pubTb.Text = if ($app.Publisher) { $app.Publisher } else { "--" }
        $pubTb.FontSize = 11.5
        $pubTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        $pubTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $pubTb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $pubTb.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
        [System.Windows.Controls.Grid]::SetColumn($pubTb, 3)
        $rowGrid.Children.Add($pubTb) | Out-Null

        $sizeText = if ($app.SizeBytes -and $app.SizeBytes -gt 0) {
            $mb = [double]$app.SizeBytes / 1MB
            if ($mb -ge 1024) { "{0:N2} GB" -f ($mb / 1024.0) } else { "{0:N1} MB" -f $mb }
        } else {
            "--"
        }
        $sizeTb = New-Object System.Windows.Controls.TextBlock
        $sizeTb.Text = $sizeText
        $sizeTb.FontSize = 11.5
        $sizeTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
        $sizeTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $sizeTb.TextAlignment = [System.Windows.TextAlignment]::Right
        $sizeTb.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        [System.Windows.Controls.Grid]::SetColumn($sizeTb, 4)
        $rowGrid.Children.Add($sizeTb) | Out-Null

        $statusBorder = New-Object System.Windows.Controls.Border
        $statusBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $statusBorder.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)
        $statusBorder.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $statusBorder.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $statusTb = New-Object System.Windows.Controls.TextBlock
        $statusTb.FontSize = 10.5
        $statusTb.FontWeight = [System.Windows.FontWeights]::SemiBold

        if ($app.IsBrokenOrphan) {
            $statusBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D1215")
            $statusBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E11D48")
            $statusBorder.BorderThickness = New-Object System.Windows.Thickness(1)
            $statusTb.Text = "Xóa sai cách"
            $statusTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
        } else {
            $statusBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0C2518")
            $statusBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981")
            $statusBorder.BorderThickness = New-Object System.Windows.Thickness(1)
            $statusTb.Text = "Bình thường"
            $statusTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
        }
        $statusBorder.Child = $statusTb
        [System.Windows.Controls.Grid]::SetColumn($statusBorder, 5)
        $rowGrid.Children.Add($statusBorder) | Out-Null

        $folderBtn = New-Object System.Windows.Controls.Border
        $folderBtn.Width = 24
        $folderBtn.Height = 20
        $folderBtn.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $folderBtn.Background = $script:brushLinkBtnBg
        $folderBtn.BorderBrush = $script:brushLinkBtnBorder
        $folderBtn.BorderThickness = New-Object System.Windows.Thickness(1)
        $folderBtn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $folderBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $folderBtn.Cursor = [System.Windows.Input.Cursors]::Hand

        $folderIcon = New-Object System.Windows.Controls.TextBlock
        $folderIcon.Text = [char]::ConvertFromUtf32(0x1F4C1)
        $folderIcon.FontSize = 10
        $folderIcon.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $folderIcon.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $folderBtn.Child = $folderIcon

        $hasLoc = (-not [string]::IsNullOrWhiteSpace($app.InstallLocation)) -and (Test-Path -LiteralPath $app.InstallLocation)
        if ($hasLoc) {
            $loc = $app.InstallLocation
            $folderBtn.ToolTip = "Mở thư mục cài đặt: $loc"
            $folderBtn.Add_MouseDown({
                param($s, $e)
                $e.Handled = $true
                try { Start-Process "explorer.exe" "`"$loc`"" } catch {}
            }.GetNewClosure())
        } else {
            $folderBtn.Opacity = 0.25
            $folderBtn.Cursor = [System.Windows.Input.Cursors]::Arrow
            $folderBtn.ToolTip = "Không tìm thấy thư mục cài đặt"
        }
        [System.Windows.Controls.Grid]::SetColumn($folderBtn, 6)
        $rowGrid.Children.Add($folderBtn) | Out-Null

        $rowBorder.Child = $rowGrid

        $rowBorder.Add_MouseEnter({
            param($sender, $e)
            $sender.Background = $script:brushRowHover
        })
        $rowBorder.Add_MouseLeave({
            param($sender, $e)
            $sender.Background = $script:brushTransparent
        })
        $rowBorder.Add_MouseLeftButtonUp({
            param($sender, $e)
            $cbRef = $sender.Tag.CheckBox
            if ($cbRef) {
                $cbRef.IsChecked = -not $cbRef.IsChecked
            }
        })

        $entry = @{
            Row = $rowBorder
            App = $app
            CheckBox = $cb
            SearchText = "$($app.DisplayName) $($app.Publisher) $($app.DisplayVersion)".ToLowerInvariant()
        }
        $rowBorder.Tag = $entry
        $script:uninstallerRowEntries.Add($entry)
        $uninstallerRowsPanel.Children.Add($rowBorder) | Out-Null
    }

    Apply-UninstallerFilter
}

if ($btnFilterUninstAll) {
    $btnFilterUninstAll.Add_Click({
        $script:uninstallerFilterMode = "All"
        $btnFilterUninstAll.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $btnFilterUninstAll.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        $btnFilterUninstBroken.Background = $script:brushTransparent
        $btnFilterUninstBroken.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        Apply-UninstallerFilter
    })
}

if ($btnFilterUninstBroken) {
    $btnFilterUninstBroken.Add_Click({
        $script:uninstallerFilterMode = "Broken"
        $btnFilterUninstBroken.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D1215")
        $btnFilterUninstBroken.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
        $btnFilterUninstAll.Background = $script:brushTransparent
        $btnFilterUninstAll.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        Apply-UninstallerFilter
    })
}

if ($txtUninstallSearch) {
    $txtUninstallSearch.Add_TextChanged({
        Apply-UninstallerFilter
    })
}

if ($btnClearUninstallSearch) {
    $btnClearUninstallSearch.Add_Click({
        if ($txtUninstallSearch) { $txtUninstallSearch.Text = "" }
        Apply-UninstallerFilter
    })
}

if ($btnUninstallSelectAll) {
    $btnUninstallSelectAll.Add_Click({
        foreach ($entry in $script:uninstallerRowEntries) {
            if ($entry.Row.Visibility -eq [System.Windows.Visibility]::Visible) {
                $entry.CheckBox.IsChecked = $true
            }
        }
        Update-UninstallerSelectionCount
    })
}

if ($btnUninstallDeselectAll) {
    $btnUninstallDeselectAll.Add_Click({
        foreach ($entry in $script:uninstallerRowEntries) {
            $entry.CheckBox.IsChecked = $false
        }
        Update-UninstallerSelectionCount
    })
}

if ($btnRefreshUninstaller) {
    $btnRefreshUninstaller.Add_Click({
        Update-UninstallerList
    })
}

if ($btnDeepUninstall) {
    $btnDeepUninstall.Add_Click({
        $selectedItems = @($script:uninstallerRowEntries | Where-Object { $_.CheckBox.IsChecked -eq $true } | ForEach-Object { $_.App })
        if ($selectedItems.Count -eq 0) { return }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Bạn có chắc chắn muốn gỡ tận gốc $($selectedItems.Count) ứng dụng đã chọn?",
            "Xác nhận Gỡ Tận Gốc",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        foreach ($item in $selectedItems) {
            if (Get-Command "Invoke-DeepAppUninstall" -ErrorAction SilentlyContinue) {
                Invoke-DeepAppUninstall -AppEntry $item -OwnerWindow $window
            }
        }
        Update-UninstallerList
    })
}

if ($btnScanOrphans) {
    $btnScanOrphans.Add_Click({
        if (Get-Command "Find-SystemOrphanLeftovers" -ErrorAction SilentlyContinue) {
            $orphans = @(Find-SystemOrphanLeftovers -InstalledApps $script:cachedUninstallerApps -CatalogApps $AppCatalog)
            if ($orphans.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Không phát hiện tệp tin rác hoặc ứng dụng nào bị xóa sai cách trên hệ thống!",
                    "Quét Rác Tồn Dư",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            } else {
                if (Get-Command "Show-LeftoverReviewDialog" -ErrorAction SilentlyContinue) {
                    Show-LeftoverReviewDialog -OwnerWindow $window -Items $orphans -Title "Quét Rác Tồn Dư & App Xóa Sai Cách"
                }
                Update-UninstallerList
            }
        }
    })
}

function Expand-TerminalLog {
}

function Get-AppFallbackGlyph {
    param([string]$AppName, [string]$Category)
    $nameLower = if ($AppName) { $AppName.ToLowerInvariant() } else { "" }
    if ($nameLower -match 'chrome') { return [char]::ConvertFromUtf32(0x1F310) }
    if ($nameLower -match 'firefox') { return [char]::ConvertFromUtf32(0x1F98A) }
    if ($nameLower -match 'brave') { return [char]::ConvertFromUtf32(0x1F981) }
    if ($nameLower -match 'tor') { return [char]::ConvertFromUtf32(0x1F9C5) }
    if ($nameLower -match 'opera') { return [char]::ConvertFromUtf32(0x1F534) }
    if ($nameLower -match 'vivaldi') { return [char]::ConvertFromUtf32(0x1F3AD) }
    if ($nameLower -match 'librewolf') { return [char]::ConvertFromUtf32(0x1F43A) }
    if ($nameLower -match 'discord') { return [char]::ConvertFromUtf32(0x1F4AC) }
    if ($nameLower -match 'telegram') { return [char]::ConvertFromUtf32(0x2708) }
    if ($nameLower -match 'zalo') { return [char]::ConvertFromUtf32(0x1F4AC) }
    if ($nameLower -match 'slack') { return [char]::ConvertFromUtf32(0x1F4BC) }
    if ($nameLower -match 'teams') { return [char]::ConvertFromUtf32(0x1F465) }
    if ($nameLower -match 'whatsapp') { return [char]::ConvertFromUtf32(0x1F4F1) }
    if ($nameLower -match 'zoom') { return [char]::ConvertFromUtf32(0x1F4F9) }
    if ($nameLower -match 'vs code|visual studio') { return [char]::ConvertFromUtf32(0x1F4BB) }
    if ($nameLower -match 'git') { return [char]::ConvertFromUtf32(0x1F419) }
    if ($nameLower -match 'terminal') { return [char]::ConvertFromUtf32(0x1F4DF) }
    if ($nameLower -match 'python') { return [char]::ConvertFromUtf32(0x1F40D) }
    if ($nameLower -match 'node') { return [char]::ConvertFromUtf32(0x1F7E2) }
    if ($nameLower -match 'docker') { return [char]::ConvertFromUtf32(0x1F433) }
    if ($nameLower -match 'notepad\+\+') { return [char]::ConvertFromUtf32(0x1F4DD) }
    if ($nameLower -match 'postman') { return [char]::ConvertFromUtf32(0x1F680) }
    if ($nameLower -match 'dbeaver') { return [char]::ConvertFromUtf32(0x1F9AB) }
    if ($nameLower -match 'rustup|\brust\b') { return [char]::ConvertFromUtf32(0x1F980) }
    if ($nameLower -match 'go lang|golang') { return [char]::ConvertFromUtf32(0x1F439) }
    if ($nameLower -match '7-zip') { return [char]::ConvertFromUtf32(0x1F5DC) }
    if ($nameLower -match 'winrar') { return [char]::ConvertFromUtf32(0x1F4E6) }
    if ($nameLower -match 'everything') { return [char]::ConvertFromUtf32(0x1F50D) }
    if ($nameLower -match 'powertoys') { return [char]::ConvertFromUtf32(0x26A1) }
    if ($nameLower -match 'flow launcher') { return [char]::ConvertFromUtf32(0x1F680) }
    if ($nameLower -match 'revo') { return [char]::ConvertFromUtf32(0x1F9F9) }
    if ($nameLower -match 'treesize') { return [char]::ConvertFromUtf32(0x1F4CA) }
    if ($nameLower -match 'sharex') { return [char]::ConvertFromUtf32(0x1F4F8) }
    if ($nameLower -match 'bleachbit') { return [char]::ConvertFromUtf32(0x1F9FC) }
    if ($nameLower -match 'fancontrol') { return [char]::ConvertFromUtf32(0x1F300) }
    if ($nameLower -match 'spotify') { return [char]::ConvertFromUtf32(0x1F3B5) }
    if ($nameLower -match 'vlc') { return [char]::ConvertFromUtf32(0x1F538) }
    if ($nameLower -match 'obs') { return [char]::ConvertFromUtf32(0x1F3AC) }
    if ($nameLower -match 'steam') { return [char]::ConvertFromUtf32(0x1F579) }
    if ($nameLower -match 'epic') { return [char]::ConvertFromUtf32(0x1F3AE) }
    if ($nameLower -match 'onedrive|gdrive|drive|dropbox') { return [char]::ConvertFromUtf32(0x2601) }
    if ($nameLower -match 'rustdesk|anydesk|ultraviewer|teamviewer') { return [char]::ConvertFromUtf32(0x1F5A5) }
    if ($nameLower -match 'afterburner') { return [char]::ConvertFromUtf32(0x26A1) }
    if ($nameLower -match 'gimp|krita') { return [char]::ConvertFromUtf32(0x1F3A8) }
    if ($nameLower -match 'blender') { return [char]::ConvertFromUtf32(0x1F3A8) }
    if ($nameLower -match 'inkscape') { return [char]::ConvertFromUtf32(0x2712) }
    if ($nameLower -match 'java|openjdk|temurin') { return [char]::ConvertFromUtf32(0x2615) }
    if ($nameLower -match '\.net|desktopruntime') { return [char]::ConvertFromUtf32(0x1F7E3) }
    if ($nameLower -match 'vc\+\+|visual c\+\+') { return [char]::ConvertFromUtf32(0x2699) }
    if ($nameLower -match 'directx') { return [char]::ConvertFromUtf32(0x1F3AE) }
    if ($nameLower -match 'cpu-z|hwmonitor') { return [char]::ConvertFromUtf32(0x1F39B) }

    if ($Category -match 'Antigravity') { return [char]::ConvertFromUtf32(0x1F680) }
    if ($Category -match 'JetBrains') { return [char]::ConvertFromUtf32(0x1F9E9) }
    if ($Category -match 'AI|Assistant') { return [char]::ConvertFromUtf32(0x1F916) }
    if ($Category -match 'Database|DevOps') { return [char]::ConvertFromUtf32(0x1F5C4) }
    if ($Category -match 'Minecraft|Modding') { return [char]::ConvertFromUtf32(0x26CF) }
    if ($Category -match 'Download') { return [char]::ConvertFromUtf32(0x2B07) }
    if ($Category -match 'Web|Browser') { return [char]::ConvertFromUtf32(0x1F310) }
    if ($Category -match 'Chat|Liên|Communication') { return [char]::ConvertFromUtf32(0x1F4AC) }
    if ($Category -match 'Remote') { return [char]::ConvertFromUtf32(0x1F5A5) }
    if ($Category -match 'Dev|Triển|Development') { return [char]::ConvertFromUtf32(0x1F4BB) }
    if ($Category -match 'Java') { return [char]::ConvertFromUtf32(0x2615) }
    if ($Category -match '\.NET') { return [char]::ConvertFromUtf32(0x1F7E3) }
    if ($Category -match 'Hardware|Monitoring') { return [char]::ConvertFromUtf32(0x1F39B) }
    if ($Category -match 'C\+\+|System Runtimes') { return [char]::ConvertFromUtf32(0x2699) }
    if ($Category -match 'Tiện|Thống|Utilities|Utility') { return [char]::ConvertFromUtf32(0x1F6E0) }
    if ($Category -match 'Graphic|Design') { return [char]::ConvertFromUtf32(0x1F3A8) }
    if ($Category -match 'Audio|Video|Media') { return [char]::ConvertFromUtf32(0x1F3AC) }
    if ($Category -match 'Phòng|Liệu|Documents|Office') { return [char]::ConvertFromUtf32(0x1F4C4) }
    if ($Category -match 'Chơi|Game|Launcher') { return [char]::ConvertFromUtf32(0x1F3AE) }
    if ($Category -match 'Trữ|Tệp|Storage|File|Transfer') { return [char]::ConvertFromUtf32(0x2601) }
    if ($Category -match 'Security|Bảo Mật|Network|Mạng') { return [char]::ConvertFromUtf32(0x1F6E1) }
    if ($Category -match 'Core|Runtimes|Thư Viện') { return [char]::ConvertFromUtf32(0x2699) }

    return [char]::ConvertFromUtf32(0x1F4E6)
}

$script:colHeights = @(0, 0, 0, 0)

$allCheckBoxes   = [System.Collections.Generic.List[object]]::new()
$allItemBorders  = [System.Collections.Generic.List[object]]::new()

$categories = $AppCatalog | Select-Object -ExpandProperty Category -Unique

$script:suppressSelectionCount = $false

function Update-SelectionCount {
    if ($script:suppressSelectionCount) { return }
    $selectedCount = 0
    foreach ($cb in $allCheckBoxes) {
        if ($cb.IsChecked -eq $true) {
            $selectedCount++
        }
    }
    if ($txtSelectionCount) {
        $txtSelectionCount.Text = "$selectedCount app được chọn"
    }
}

$cardCols = @(
    $window.FindName("CardsCol0"),
    $window.FindName("CardsCol1"),
    $window.FindName("CardsCol2"),
    $window.FindName("CardsCol3")
)

$script:remoteBmpCache = [System.Collections.Generic.Dictionary[string, System.Windows.Media.Imaging.BitmapImage]]::new([System.StringComparer]::OrdinalIgnoreCase)

$glCol0             = [System.Windows.GridLength]::new(20, [System.Windows.GridUnitType]::Pixel)
$glCol1             = [System.Windows.GridLength]::new(23, [System.Windows.GridUnitType]::Pixel)
$glCol2             = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
$glCol3             = [System.Windows.GridLength]::new(22, [System.Windows.GridUnitType]::Pixel)
$glAuto             = [System.Windows.GridLength]::Auto
$marginCardBottom   = [System.Windows.Thickness]::new(0, 0, 0, 10)
$paddingHeaderCnt   = [System.Windows.Thickness]::new(6, 1, 6, 1)
$marginNameText     = [System.Windows.Thickness]::new(5, 0, 4, 0)
$paddingUpdateBadge = [System.Windows.Thickness]::new(5, 1, 5, 1)
$marginUpdateBadge  = [System.Windows.Thickness]::new(2, 0, 4, 0)
$marginLinkIcon     = [System.Windows.Thickness]::new(0, -1, 0, 0)
$cornerFour         = [System.Windows.CornerRadius]::new(4)
$strOpenLinkGlyph   = [string][char]0x2197

$script:cbChangedHandler = [System.Windows.RoutedEventHandler]{ Update-SelectionCount }
$script:linkClickHandler = [System.Windows.Input.MouseButtonEventHandler]{
    param($s, $e)
    $e.Handled = $true
    if ($script:isScanningApps -or $script:isActionRunning) { return }
    $domain = if ($s.Tag -and $s.Tag.Url) { $s.Tag.Url } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($domain)) {
        $targetUrl = if ($domain.StartsWith("http")) { $domain } else { "https://$domain" }
        try {
            Start-Process $targetUrl
        } catch {
            Log-Text "[!] Không thể mở trang web: $targetUrl"
        }
    }
}
$script:rowClickHandler = [System.Windows.Input.MouseButtonEventHandler]{
    param($sender, $e)
    if ($e.Handled) { return }
    if ($script:isScanningApps -or $script:isActionRunning) { return }

    $src = $e.OriginalSource
    $isCb = $false
    $node = $src
    while ($node -ne $null -and $node -ne $sender) {
        if ($node -is [System.Windows.Controls.CheckBox]) {
            $isCb = $true
            break
        }
        if ($node -is [System.Windows.Media.Visual]) {
            $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
        } else {
            break
        }
    }
    if ($isCb) { return }

    if ($sender.Tag -and $sender.Tag.CheckBox) {
        $targetCb = $sender.Tag.CheckBox
        $targetCb.IsChecked = -not $targetCb.IsChecked
    }
}

$appsByCategory = @{}
foreach ($item in $AppCatalog) {
    if (-not $appsByCategory.ContainsKey($item.Category)) {
        $appsByCategory[$item.Category] = [System.Collections.Generic.List[object]]::new()
    }
    $appsByCategory[$item.Category].Add($item)
}

foreach ($cat in $categories) {
    $cardBorder = [System.Windows.Controls.Border]::new()
    $cardBorder.Background = $script:brushCardBg
    $cardBorder.Style = $script:styleCategoryCard
    $cardBorder.BorderThickness = $thicknessOne
    $cardBorder.CornerRadius = $cornerCard
    $cardBorder.Margin = $marginCardBottom
    $cardBorder.Padding = $paddingCard
    $cardBorder.Height = [double]::NaN
    $cardBorder.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch

    $cardStack = [System.Windows.Controls.StackPanel]::new()
    $appsInCat = $appsByCategory[$cat]

    $headerGrid = [System.Windows.Controls.Grid]::new()
    $headerGrid.Margin = $marginHeaderGrid

    $headerText = [System.Windows.Controls.TextBlock]::new()
    $headerText.Text = $cat
    $headerText.FontSize = 12
    $headerText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $headerText.Foreground = $script:brushHeaderFg
    $headerText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $headerText.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    [void]$headerGrid.Children.Add($headerText)

    $headerCountBadge = [System.Windows.Controls.Border]::new()
    $headerCountBadge.Background = $script:brushHeaderCntBg
    $headerCountBadge.CornerRadius = $cornerFour
    $headerCountBadge.Padding = $paddingHeaderCnt
    $headerCountBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $headerCountBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $headerCountText = [System.Windows.Controls.TextBlock]::new()
    $headerCountText.Text = "$($appsInCat.Count)"
    $headerCountText.FontSize = 10
    $headerCountText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $headerCountText.Foreground = $script:brushHeaderCntFg
    $headerCountBadge.Child = $headerCountText
    [void]$headerGrid.Children.Add($headerCountBadge)

    $separator = [System.Windows.Controls.Border]::new()
    $separator.Height = 1
    $separator.Background = $script:brushSeparator
    $separator.Margin = $marginSeparator

    [void]$cardStack.Children.Add($headerGrid)
    [void]$cardStack.Children.Add($separator)

    foreach ($app in $appsInCat) {
        $rowBorder = [System.Windows.Controls.Border]::new()
        $rowBorder.Height = 27
        $rowBorder.CornerRadius = $cornerRow
        $rowBorder.Padding = $paddingRow
        $rowBorder.Margin = $marginRowBorder
        $rowBorder.Style = $script:styleAppRow
        $rowBorder.Cursor = [System.Windows.Input.Cursors]::Hand

        $rowBorder.Tag = @{
            App              = $app
            Status           = "NONE"
            DetectedId       = $null
            InstalledVersion = $null
            CardBorder       = $cardBorder
        }

        $rowGrid = [System.Windows.Controls.Grid]::new()
        $rowGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $col0 = [System.Windows.Controls.ColumnDefinition]::new(); $col0.Width = $glCol0
        $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = $glCol1
        $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = $glCol2
        $col3 = [System.Windows.Controls.ColumnDefinition]::new(); $col3.Width = $glCol3
        [void]$rowGrid.ColumnDefinitions.Add($col0)
        [void]$rowGrid.ColumnDefinitions.Add($col1)
        [void]$rowGrid.ColumnDefinitions.Add($col2)
        [void]$rowGrid.ColumnDefinitions.Add($col3)

        $cb = [System.Windows.Controls.CheckBox]::new()
        $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cb.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $cb.Margin = $thicknessZero
        $cb.Tag = $rowBorder.Tag
        $cb.Add_Checked($script:cbChangedHandler)
        $cb.Add_Unchecked($script:cbChangedHandler)
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        [void]$rowGrid.Children.Add($cb)
        $allCheckBoxes.Add($cb)
        $rowBorder.Tag["CheckBox"] = $cb

        $useLightBadge = ($app.IconBg -eq "light") -or ($cat -eq "Java Runtimes")
        $iconBadge = [System.Windows.Controls.Border]::new()
        $iconBadge.Width = 20
        $iconBadge.Height = 20
        $iconBadge.CornerRadius = $script:cornerIconBadge
        $iconBadge.Background = if ($useLightBadge) { $script:brushIconBadgeLightBg } else { $script:brushIconBadgeBg }
        $iconBadge.BorderBrush = $script:brushIconBadgeBorder
        $iconBadge.BorderThickness = $thicknessZero
        $iconBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $iconBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $iconInnerGrid = [System.Windows.Controls.Grid]::new()
        $iconInnerGrid.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $iconInnerGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $fallbackGlyph = [System.Windows.Controls.TextBlock]::new()
        $fallbackGlyph.Text = Get-AppFallbackGlyph -AppName $app.Name -Category $cat
        $fallbackGlyph.FontFamily = $script:fontSegoeEmoji
        $fallbackGlyph.FontSize = 10
        $fallbackGlyph.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $fallbackGlyph.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [void]$iconInnerGrid.Children.Add($fallbackGlyph)

        $img = [System.Windows.Controls.Image]::new()
        $imgDim = if ($useLightBadge) { 15 } else { 17 }
        $img.Width = $imgDim; $img.Height = $imgDim
        $img.Stretch = [System.Windows.Media.Stretch]::Uniform
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)
        $img.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $img.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $img.Visibility = [System.Windows.Visibility]::Collapsed

        [void]$iconInnerGrid.Children.Add($img)
        $iconBadge.Child = $iconInnerGrid

        $remoteIconTarget = if (-not [string]::IsNullOrWhiteSpace($app.IconUrl)) {
            $app.IconUrl
        } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
            "https://www.google.com/s2/favicons?domain=$($app.Domain)&sz=128"
        } else {
            $null
        }
        $iconCacheKey = if ($remoteIconTarget) { $remoteIconTarget } else { "$($app.ID)" }
        $localIconPath = Join-Path $iconsCacheDir "$($app.ID).png"

        $loadedBmp = Import-LocalIconBitmap -Path $localIconPath -CacheKey $iconCacheKey
        if ($loadedBmp -and $loadedBmp.PixelWidth -gt 0) {
            $img.Source = $loadedBmp
            $fallbackGlyph.Visibility = [System.Windows.Visibility]::Collapsed
            $img.Visibility = [System.Windows.Visibility]::Visible
            if (-not [System.IO.File]::Exists($localIconPath)) {
                Save-BitmapToCacheAtomic -BitmapSource $loadedBmp -DestPath $localIconPath
            }
        } elseif ($remoteIconTarget) {
            $script:pendingIconSaves.Add(@{
                Url          = $remoteIconTarget
                CacheKey     = $iconCacheKey
                DestPath     = $localIconPath
                DownloadInfo = $null
                Img          = $img
                Fallback     = $fallbackGlyph
            })
        }
        [System.Windows.Controls.Grid]::SetColumn($iconBadge, 1)
        [void]$rowGrid.Children.Add($iconBadge)

        $nameAreaGrid = [System.Windows.Controls.Grid]::new()
        $nameCol0 = [System.Windows.Controls.ColumnDefinition]::new(); $nameCol0.Width = $glCol2
        $nameCol1 = [System.Windows.Controls.ColumnDefinition]::new(); $nameCol1.Width = $glAuto
        [void]$nameAreaGrid.ColumnDefinitions.Add($nameCol0)
        [void]$nameAreaGrid.ColumnDefinitions.Add($nameCol1)

        $nameText = [System.Windows.Controls.TextBlock]::new()
        $nameText.Text = $app.Name
        $nameText.Foreground = $script:brushTextWhite
        $nameText.FontSize = 12
        $nameText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $nameText.Margin = $marginNameText
        $nameText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $idnPrefix = if ($app.IDn) { "[#$($app.IDn)] " } else { "" }
        $nameText.ToolTip = "$idnPrefix$($app.Name)`nID: $($app.ID)"
        $rowBorder.ToolTip = $nameText.ToolTip
        [System.Windows.Controls.Grid]::SetColumn($nameText, 0)
        [void]$nameAreaGrid.Children.Add($nameText)

        $updateBadge = [System.Windows.Controls.Border]::new()
        $updateBadge.Background = $script:brushUpdateBadgeBg
        $updateBadge.BorderBrush = $script:brushUpdateBadgeBorder
        $updateBadge.BorderThickness = $thicknessOne
        $updateBadge.CornerRadius = $script:cornerIconBadge
        $updateBadge.Padding = $paddingUpdateBadge
        $updateBadge.Margin = $marginUpdateBadge
        $updateBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $updateBadge.Visibility = [System.Windows.Visibility]::Collapsed
        $updateBadge.MaxWidth = 86

        $updateText = [System.Windows.Controls.TextBlock]::new()
        $updateText.FontSize = 9.5
        $updateText.FontWeight = [System.Windows.FontWeights]::Bold
        $updateText.Foreground = $script:brushUpdateBadgeFg
        $updateText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $updateBadge.Child = $updateText
        [System.Windows.Controls.Grid]::SetColumn($updateBadge, 1)
        [void]$nameAreaGrid.Children.Add($updateBadge)

        $rowBorder.Tag["NameText"]    = $nameText
        $rowBorder.Tag["UpdateBadge"] = $updateBadge
        $rowBorder.Tag["UpdateText"]  = $updateText

        [System.Windows.Controls.Grid]::SetColumn($nameAreaGrid, 2)
        [void]$rowGrid.Children.Add($nameAreaGrid)

        $targetPageUrl = if (-not [string]::IsNullOrWhiteSpace($app.Url)) {
            $app.Url
        } elseif (-not [string]::IsNullOrWhiteSpace($app.Domain)) {
            if ($app.Domain.StartsWith("http")) { $app.Domain } else { "https://$($app.Domain)" }
        } else { "" }

        $linkBtn = [System.Windows.Controls.Border]::new()
        $linkBtn.Width = 20
        $linkBtn.Height = 19
        $linkBtn.CornerRadius = $cornerFour
        $linkBtn.Style = $script:styleLinkBtn
        $linkBtn.BorderThickness = $thicknessOne
        $linkBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $linkBtn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
        $linkBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $linkBtn.Margin = $thicknessZero
        $linkBtn.ToolTip = "Mở trang chính thức: $targetPageUrl"
        $linkBtn.Tag = @{ Url = $targetPageUrl; Row = $rowBorder }

        $linkIcon = [System.Windows.Controls.TextBlock]::new()
        $linkIcon.Text = $strOpenLinkGlyph
        $linkIcon.FontFamily = $script:fontSegoeUI
        $linkIcon.FontSize = 11.5
        $linkIcon.FontWeight = [System.Windows.FontWeights]::Bold
        $linkIcon.Foreground = $script:brushLinkBtnRowHover
        $linkIcon.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $linkIcon.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $linkIcon.Margin = $marginLinkIcon
        $linkBtn.Child = $linkIcon
        $rowBorder.Tag["LinkBtn"]  = $linkBtn
        $rowBorder.Tag["LinkIcon"] = $linkIcon

        $linkBtn.Add_MouseLeftButtonUp($script:linkClickHandler)
        [System.Windows.Controls.Grid]::SetColumn($linkBtn, 3)
        [void]$rowGrid.Children.Add($linkBtn)

        $rowBorder.Add_MouseLeftButtonUp($script:rowClickHandler)

        $rowBorder.Child = $rowGrid
        $cardStack.Children.Add($rowBorder) | Out-Null
        $allItemBorders.Add($rowBorder)
    }

    $cardBorder.Child = $cardStack

    $cardEstimatedHeight = 56 + ($appsInCat.Count * 29)

    $targetColIndex = 0
    $minHeight = $script:colHeights[0]
    for ($i = 1; $i -lt 4; $i++) {
        if ($script:colHeights[$i] -lt $minHeight) {
            $minHeight = $script:colHeights[$i]
            $targetColIndex = $i
        }
    }

    $targetColPanel = if ($cardCols[0] -and $cardCols[$targetColIndex]) { $cardCols[$targetColIndex] } else { $cardsContainer }
    if ($targetColPanel) {
        $targetColPanel.Children.Add($cardBorder) | Out-Null
    }

    $script:colHeights[$targetColIndex] += $cardEstimatedHeight
}

Register-Click "btnScanInstalled" {
    Invoke-GuardedAction "Quét ứng dụng" {
        Scan-And-ColorizeApps
    }
}

function Clear-AllCheckBoxes {
    $script:suppressSelectionCount = $true
    try {
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -ne $false) {
                $cb.IsChecked = $false
            }
        }
    } finally {
        $script:suppressSelectionCount = $false
    }
    Update-SelectionCount
}

function Invoke-GitHubAssetInstall {
    param($App)
    try {
        Log-Text "   -> Đang tìm bản phát hành mới nhất từ GitHub ($($App.GitHubRepo))..."
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$($App.GitHubRepo)/releases/latest" -Headers @{ "User-Agent" = "DuckUtil" } -TimeoutSec 15
        $asset = $rel.assets | Where-Object { $_.name -match $App.AssetRegex } | Select-Object -First 1
        if (-not $asset) {
            Log-Text "   [!] Không tìm thấy bộ cài phù hợp trên GitHub Release."
            return -1
        }
        $dlPath = Join-Path $env:TEMP $asset.name
        Log-Text "   -> Đang tải $($asset.name)..."
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dlPath -UseBasicParsing -Headers @{ "User-Agent" = "DuckUtil" } -TimeoutSec 120
        try {
            if ($dlPath -match '\.msi$') {
                return (Run-CliStream "msiexec.exe" "/i `"$dlPath`" /qn /norestart")
            } else {
                return (Run-CliStream $dlPath "--silent-install")
            }
        } finally {
            if (Test-Path -LiteralPath $dlPath) { Remove-Item -LiteralPath $dlPath -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Log-Text "   [!] Lỗi tải/cài từ GitHub: $($_.Exception.Message)"
        return -1
    }
}

function Clear-WinGetTempInstallers {
    param([string[]]$RootPaths)
    if (-not $RootPaths -or $RootPaths.Count -eq 0) {
        $rawCandidates = @(
            (Join-Path ([System.IO.Path]::GetTempPath()) "WinGet"),
            $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Temp\WinGet" })
        )
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $RootPaths = foreach ($cand in $rawCandidates) {
            if ([string]::IsNullOrWhiteSpace($cand)) { continue }
            $full = [System.IO.Path]::GetFullPath($cand).TrimEnd('\')
            if ($seen.Add($full)) { $full }
        }
    }

    $removedCount = 0
    $freedBytes = [long]0
    foreach ($wingetTemp in $RootPaths) {
        if ([string]::IsNullOrWhiteSpace($wingetTemp) -or -not (Test-Path -LiteralPath $wingetTemp)) { continue }

        $entries = Get-ChildItem -LiteralPath $wingetTemp -Force -ErrorAction SilentlyContinue
        foreach ($entry in $entries) {
            if ($entry.Name -ieq "cache") { continue }

            $entryBytes = [long]0
            if ($entry.PSIsContainer) {
                $measure = Get-ChildItem -LiteralPath $entry.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
                if ($measure -and $null -ne $measure.Sum) { $entryBytes = [long]$measure.Sum }
            } else {
                $entryBytes = [long]$entry.Length
            }

            try {
                Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop
                $removedCount++
                $freedBytes += $entryBytes
            } catch {
            }
        }
    }

    if ($removedCount -gt 0) {
        $freedMB = [math]::Round($freedBytes / 1MB, 1)
        Log-Text "[CLEAN] Đã tự động dọn $removedCount thư mục/tệp bộ cài WinGet tồn dư ($freedMB MB)."
    }
}

function Invoke-SmartAppUpgrade {
    param($Tag)
    if (-not $Tag) { return 1 }
    $app = $Tag.App
    if (-not $app) { return 1 }

    $upgradeId = if ($Tag.DetectedId -and -not ($Tag.DetectedId.StartsWith("ARP\") -or $Tag.DetectedId.StartsWith("MSIX\"))) {
        $Tag.DetectedId
    } else {
        $app.ID
    }

    $instApps = if ("DuckUtil.DeepUninstallerEngine" -as [type]) {
        [DuckUtil.DeepUninstallerEngine]::GetInstalledApps()
    } else {
        @()
    }

    $regMatch = $null
    foreach ($inst in $instApps) {
        if (($inst.Id -and ($inst.Id -eq $app.ID -or $inst.Id -eq $Tag.DetectedId)) -or
            ($inst.DisplayName -and ($inst.DisplayName -eq $app.Name -or $inst.DisplayName -eq $app.ID))) {
            $regMatch = $inst
            break
        }
    }

    $existingLoc = $null
    if ($regMatch -and -not [string]::IsNullOrWhiteSpace($regMatch.InstallLocation) -and (Test-Path -LiteralPath $regMatch.InstallLocation)) {
        $existingLoc = $regMatch.InstallLocation.Trim().TrimEnd('\')
    }

    if (-not $existingLoc -and $regMatch) {
        $uCmd = if ($regMatch.QuietUninstallString) { $regMatch.QuietUninstallString } else { $regMatch.UninstallString }
        if ($uCmd) {
            $uExe = if ($uCmd.StartsWith('"')) {
                $q2 = $uCmd.IndexOf('"', 1)
                if ($q2 -gt 1) { $uCmd.Substring(1, $q2 - 1) } else { $uCmd.Trim('"') }
            } else {
                ($uCmd -split '\s+')[0]
            }
            if ($uExe -and (Test-Path -LiteralPath $uExe)) {
                $pDir = [System.IO.Path]::GetDirectoryName($uExe)
                if ($pDir -and (Test-Path -LiteralPath $pDir)) {
                    $existingLoc = $pDir
                }
            }
        }
    }

    if (-not $existingLoc) {
        $stdCandidates = @(
            (Join-Path $env:LOCALAPPDATA "Programs\$($app.Name)"),
            (Join-Path $env:ProgramFiles $app.Name),
            (Join-Path ${env:ProgramFiles(x86)} $app.Name)
        )
        foreach ($sc in $stdCandidates) {
            if ($sc -and (Test-Path -LiteralPath $sc)) {
                $existingLoc = $sc
                break
            }
        }
    }

    $scope = ""
    if ($regMatch -and $regMatch.Scope -eq "User") {
        $scope = "user"
    } elseif ($existingLoc -and $existingLoc.StartsWith($env:USERPROFILE, [System.StringComparison]::OrdinalIgnoreCase)) {
        $scope = "user"
    }

    $nameVariations = [System.Collections.Generic.List[string]]::new()
    $nameVariations.Add($app.Name)
    $nameVariations.Add($app.ID)
    if ($app.Aliases) {
        foreach ($al in $app.Aliases) {
            if (-not [string]::IsNullOrWhiteSpace($al) -and -not $nameVariations.Contains($al)) {
                $nameVariations.Add($al)
            }
        }
    }
    if ($regMatch -and $regMatch.Publisher) {
        $pub = $regMatch.Publisher.Trim()
        if ($pub -and -not ($pub -match 'Microsoft|Windows|Corporation')) {
            $nameVariations.Add((Join-Path $pub $app.Name))
        }
    }

    $targetAppDataDirs = [System.Collections.Generic.List[string]]::new()
    foreach ($nv in $nameVariations) {
        if ([string]::IsNullOrWhiteSpace($nv)) { continue }
        $rPath = Join-Path $env:APPDATA $nv
        if ((Test-Path -LiteralPath $rPath) -and -not $targetAppDataDirs.Contains($rPath)) {
            $targetAppDataDirs.Add($rPath)
        }
        $lPath = Join-Path $env:LOCALAPPDATA $nv
        if ((Test-Path -LiteralPath $lPath) -and -not $targetAppDataDirs.Contains($lPath)) {
            $targetAppDataDirs.Add($lPath)
        }
    }

    $hkcuKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($nv in $nameVariations) {
        if ([string]::IsNullOrWhiteSpace($nv)) { continue }
        $rk = "HKCU:\Software\$nv"
        if ((Test-Path -LiteralPath $rk) -and -not $hkcuKeys.Contains($rk)) {
            $hkcuKeys.Add($rk)
        }
    }

    $backupRoot = Join-Path $env:TEMP "AppDriver_UpgradeGuard\$($app.ID)"
    if (Test-Path -LiteralPath $backupRoot) {
        Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $hasSnapshots = $false
    $locBkp = Join-Path $backupRoot "InstallLocation"
    if ($existingLoc -and (Test-Path -LiteralPath $existingLoc) -and ("DuckUtil.DeepUninstallerEngine" -as [type])) {
        $bytes = [DuckUtil.DeepUninstallerEngine]::BackupDirectorySnapshot($existingLoc, $locBkp, 104857600L)
        if ($bytes -gt 0) { $hasSnapshots = $true }
    }

    $appDataBkps = [System.Collections.Generic.List[object]]::new()
    $adIdx = 0
    if ("DuckUtil.DeepUninstallerEngine" -as [type]) {
        foreach ($adDir in $targetAppDataDirs) {
            $adIdx++
            $adBkpDir = Join-Path $backupRoot "AppData_$adIdx"
            $b = [DuckUtil.DeepUninstallerEngine]::BackupDirectorySnapshot($adDir, $adBkpDir, 104857600L)
            if ($b -gt 0) {
                $hasSnapshots = $true
                $appDataBkps.Add([PSCustomObject]@{ Source = $adDir; Backup = $adBkpDir })
            }
        }
    }

    $regFiles = [System.Collections.Generic.List[object]]::new()
    $rkIdx = 0
    foreach ($rk in $hkcuKeys) {
        $rkIdx++
        $rf = Join-Path $backupRoot "hkcu_reg_$rkIdx.reg"
        $rawHkcu = $rk -replace '^HKCU:\\', 'HKEY_CURRENT_USER\'
        try {
            $pReg = Start-Process "reg.exe" -ArgumentList "export `"$rawHkcu`" `"$rf`" /y" -Wait -NoNewWindow -PassThru -ErrorAction SilentlyContinue
            if ($pReg.ExitCode -eq 0 -and (Test-Path -LiteralPath $rf)) {
                $hasSnapshots = $true
                $regFiles.Add([PSCustomObject]@{ Key = $rawHkcu; File = $rf })
            }
        } catch {}
    }

    if ($hasSnapshots) {
        Log-Text "[*] Đã kích hoạt UpgradeDataGuard: Chụp snapshot dữ liệu cá nhân & cấu hình trước khi nâng cấp."
    }

    $upArgs = "upgrade --id `"$upgradeId`" --exact --silent --accept-package-agreements --accept-source-agreements"
    if ($existingLoc) {
        $upArgs += " --location `"$existingLoc`""
    }
    if ($scope) {
        $upArgs += " --scope $scope"
    }

    $code = Run-CliStream "winget" $upArgs
    if ($code -ne 0 -and $scope) {
        Log-Text "[!] Nâng cấp theo scope '$scope' không thành công (Code: $code), đang thử lại chế độ tự do..."
        $upArgsRetry = "upgrade --id `"$upgradeId`" --exact --silent --accept-package-agreements --accept-source-agreements"
        if ($existingLoc) {
            $upArgsRetry += " --location `"$existingLoc`""
        }
        $code = Run-CliStream "winget" $upArgsRetry
    }

    if ($hasSnapshots) {
        if ($existingLoc -and (Test-Path -LiteralPath $locBkp) -and ("DuckUtil.DeepUninstallerEngine" -as [type])) {
            $restoredLoc = [DuckUtil.DeepUninstallerEngine]::RestoreDirectorySnapshot($locBkp, $existingLoc)
            if ($restoredLoc -gt 0) {
                Log-Text "[OK] UpgradeDataGuard: Đã bảo toàn $restoredLoc tệp dữ liệu cá nhân trong thư mục cài đặt."
            }
        }

        if ("DuckUtil.DeepUninstallerEngine" -as [type]) {
            foreach ($item in $appDataBkps) {
                if (Test-Path -LiteralPath $item.Backup) {
                    $resAd = [DuckUtil.DeepUninstallerEngine]::RestoreDirectorySnapshot($item.Backup, $item.Source)
                    if ($resAd -gt 0) {
                        Log-Text "[OK] UpgradeDataGuard: Đã bảo toàn $resAd tệp dữ liệu/profile trong: $($item.Source)"
                    }
                }
            }
        }

        foreach ($rfItem in $regFiles) {
            if (Test-Path -LiteralPath $rfItem.File) {
                try {
                    Start-Process "reg.exe" -ArgumentList "import `"$($rfItem.File)`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                    Log-Text "[OK] UpgradeDataGuard: Đã khôi phục Registry cấu hình: $($rfItem.Key)"
                } catch {}
            }
        }

        try {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    return $code
}

Register-Click "btnInstall" {
    Invoke-GuardedAction "Cài đặt ứng dụng" {
        $selectedTags = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selectedTags.Add($cb.Tag)
            }
        }

        if ($selectedTags.Count -eq 0) {
            Log-Text "[!] Bạn chưa tick chọn ứng dụng nào để cài đặt!"
            return
        }

        $total = $selectedTags.Count
        $idx = 0
        Log-Text "=========================================================="
        Log-Text "[INSTALL] BẮT ĐẦU CÀI ĐẶT $total ỨNG DỤNG ĐÃ ĐÁNH DẤU"
        Log-Text "=========================================================="

        try {
            foreach ($tag in $selectedTags) {
                $idx++
                $app = $tag.App
                if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
                if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang cài đặt: $($app.Name)..." }

                if ($tag.Status -eq "LATEST") {
                    Log-Text "[OK] $($app.Name) đã ở phiên bản mới nhất ($($tag.InstalledVersion)), bỏ qua cài đè để bảo toàn dữ liệu."
                    if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                    continue
                }

                if ($tag.Status -eq "OUTDATED") {
                    Log-Text "[$idx/$total] Phát hiện bản cũ ($($tag.InstalledVersion)) -> Chuyển sang Nâng cấp giữ nguyên dữ liệu: $($app.Name)..."
                    $code = Invoke-SmartAppUpgrade -Tag $tag
                    if ($code -eq 0) {
                        Log-Text "   [OK - HOÀN THÀNH] $($app.Name)"
                        if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                    } else {
                        Log-Text "   [ERR - LỖI] $($app.Name) (Exit Code: $code)"
                    }
                    continue
                }

                Log-Text "[$idx/$total] Đang cài: $($app.Name) (ID: $($app.ID))..."

                if ($app.BrowserDownload -eq $true -and -not [string]::IsNullOrWhiteSpace($app.FallbackUrl)) {
                    Log-Text "   [WEB] Đang mở liên kết tải bộ cài chính thức: $($app.FallbackUrl)"
                    try {
                        Start-Process $app.FallbackUrl
                        if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                    } catch {
                        Log-Text "   [ERR - LỖI] Không thể mở trình duyệt cho $($app.Name)"
                    }
                    continue
                }

                if (-not [string]::IsNullOrWhiteSpace($app.GitHubRepo) -and -not [string]::IsNullOrWhiteSpace($app.AssetRegex)) {
                    $code = Invoke-GitHubAssetInstall -App $app
                } else {
                    $wgArgs = "install --id `"$($app.ID)`" --exact --silent --accept-package-agreements --accept-source-agreements"
                    if ($app.Source -eq "msstore") { $wgArgs += " --source msstore" }
                    $code = Run-CliStream "winget" $wgArgs
                }

                if ($code -eq 0) {
                    Log-Text "   [OK - HOÀN THÀNH] $($app.Name)"
                    if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                } else {
                    Log-Text "   [ERR - LỖI] $($app.Name) (Exit Code: $code)"
                    if (-not [string]::IsNullOrWhiteSpace($app.FallbackUrl)) {
                        Log-Text "   [WEB] Gói này hiện không khả dụng tự động qua WinGet. Đang mở trang tải chính thức: $($app.FallbackUrl)"
                        try { Start-Process $app.FallbackUrl } catch {}
                    }
                }
            }
        } finally {
            Clear-WinGetTempInstallers
        }
        Update-SelectionCount
        if ($txtStatus) { $txtStatus.Text = "Cài đặt hoàn tất!" }
        if ($progressBar) { $progressBar.Value = 100 }
        Scan-And-ColorizeApps
    }
}

Register-Click "btnUpgradeSelected" {
    Invoke-GuardedAction "Nâng cấp đã chọn" -DeferExpand {
        $selectedTags = [System.Collections.Generic.List[object]]::new()
        foreach ($cb in $allCheckBoxes) {
            if ($cb.IsChecked -eq $true) {
                $selectedTags.Add($cb.Tag)
            }
        }

        if ($selectedTags.Count -eq 0) {
            Expand-TerminalLog
            Log-Text "[!] Bạn chưa chọn ứng dụng nào để nâng cấp!"
            return
        }

        Expand-TerminalLog
        $total = $selectedTags.Count
        $idx = 0
        Log-Text "=========================================================="
        Log-Text "[UPGRADE] BẮT ĐẦU NÂNG CẤP $total ỨNG DỤNG ĐÃ CHỌN"
        Log-Text "=========================================================="

        try {
            foreach ($tag in $selectedTags) {
                $idx++
                $app = $tag.App

                if ($progressBar) { $progressBar.Value = [math]::Round(($idx / $total) * 100) }
                if ($txtStatus) { $txtStatus.Text = "[$idx/$total] Đang nâng cấp: $($app.Name)..." }

                if ($tag.Status -eq "LATEST") {
                    Log-Text "[OK] $($app.Name) đã là bản mới nhất, bỏ qua."
                    if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                    continue
                }

                Log-Text "[$idx/$total] Đang nâng cấp: $($app.Name)..."
                $code = Invoke-SmartAppUpgrade -Tag $tag
                if ($code -eq 0) {
                    Log-Text "   [OK - ĐÃ NÂNG CẤP THÀNH CÔNG] $($app.Name)"
                    if ($tag.CheckBox) { $tag.CheckBox.IsChecked = $false }
                } else {
                    Log-Text "   [ERR - LỖI NÂNG CẤP HOẶC ĐÃ MỚI NHẤT] $($app.Name) (Exit Code: $code)"
                }
            }
        } finally {
            Clear-WinGetTempInstallers
        }
        Update-SelectionCount
        if ($txtStatus) { $txtStatus.Text = "Nâng cấp hoàn tất!" }
        if ($progressBar) { $progressBar.Value = 100 }
        Scan-And-ColorizeApps
    }
}

Register-Click "btnUpgradeAll" {
    Invoke-GuardedAction "Nâng cấp toàn bộ" {
        Log-Text "=========================================================="
        Log-Text "[UPGRADE] BẮT ĐẦU NÂNG CẤP TOÀN BỘ PHẦN MỀM TRÊN MÁY"
        Log-Text "=========================================================="
        if ($txtStatus) { $txtStatus.Text = "Đang nâng cấp tất cả ứng dụng..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }

        try {
            $outdatedRows = @($allItemBorders | Where-Object { $_.Tag -and $_.Tag.Status -eq "OUTDATED" })
            if ($outdatedRows.Count -gt 0) {
                $totalOut = $outdatedRows.Count
                $idxOut = 0
                foreach ($row in $outdatedRows) {
                    $idxOut++
                    $tagOut = $row.Tag
                    if ($progressBar) { $progressBar.Value = [math]::Round(($idxOut / $totalOut) * 100) }
                    if ($txtStatus) { $txtStatus.Text = "[$idxOut/$totalOut] Đang nâng cấp an toàn: $($tagOut.App.Name)..." }
                    Log-Text "[$idxOut/$totalOut] Đang nâng cấp bảo toàn dữ liệu: $($tagOut.App.Name)..."
                    $codeOut = Invoke-SmartAppUpgrade -Tag $tagOut
                    if ($codeOut -eq 0) {
                        Log-Text "   [OK - ĐÃ NÂNG CẤP THÀNH CÔNG] $($tagOut.App.Name)"
                        if ($tagOut.CheckBox) { $tagOut.CheckBox.IsChecked = $false }
                    } else {
                        Log-Text "   [ERR - LỖI NÂNG CẤP HOẶC ĐÃ MỚI NHẤT] $($tagOut.App.Name) (Exit Code: $codeOut)"
                    }
                }
            } else {
                Run-CliStream "winget" "upgrade --all --silent --accept-package-agreements --accept-source-agreements"
            }
        } finally {
            Clear-WinGetTempInstallers
        }

        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Nâng cấp hoàn tất!" }
        Log-Text "[OK] Toàn bộ ứng dụng đã được nâng cấp lên bản mới nhất."
        Scan-And-ColorizeApps
    }
}

Register-Click "btnSelectAll" {
    $script:suppressSelectionCount = $true
    try {
        foreach ($row in $allItemBorders) {
            if ($row.Visibility -eq [System.Windows.Visibility]::Visible -and $row.Tag -and $row.Tag.CheckBox) {
                $cb = $row.Tag.CheckBox
                if ($cb.IsChecked -ne $true) {
                    $cb.IsChecked = $true
                }
            }
        }
    } finally {
        $script:suppressSelectionCount = $false
    }
    Update-SelectionCount
}

Register-Click "btnDeselectAll" {
    Clear-AllCheckBoxes
}

Register-Click "btnSfcScan" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "SFC Scan" {
        Log-Text "[*] Đang bắt đầu quét kiểm tra tính toàn vẹn hệ thống (sfc /scannow)..."
        if ($txtStatus) { $txtStatus.Text = "Đang chạy SFC Scan..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-SystemFileCheck
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Quét SFC hoàn tất" }
        Log-Text "[OK] Quá trình SFC đã kết thúc."
    }
}

Register-Click "btnDismRestore" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "DISM RestoreHealth" {
        Log-Text "[*] Đang khôi phục kho ảnh hệ thống Windows qua DISM RestoreHealth..."
        if ($txtStatus) { $txtStatus.Text = "Đang chạy DISM RestoreHealth..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-DismRestoreHealth
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "DISM hoàn tất" }
        Log-Text "[OK] DISM RestoreHealth hoàn thành xuất sắc."
    }
}

Register-Click "btnDismCleanup" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "DISM Component Cleanup" -DeferExpand {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Lệnh DISM /StartComponentCleanup /ResetBase sẽ nén kho WinSxS và KHÔNG THỂ gỡ cài đặt (rollback) các bản Windows Update hiện tại về sau.`n`nBạn có chắc chắn muốn tiếp tục?",
            "Xác nhận dọn kho linh kiện (WinSxS)",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Expand-TerminalLog
        Log-Text "[*] Đang dọn dẹp kho linh kiện hệ thống (DISM Component Cleanup)..."
        if ($txtStatus) { $txtStatus.Text = "Đang dọn kho linh kiện..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-DismComponentCleanup
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn kho linh kiện hoàn tất" }
        Log-Text "[OK] Đã giải phóng dung lượng kho linh kiện."
    }
}

Register-Click "btnFixWindowsUpdate" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Khởi tạo lại Windows Update" {
        Log-Text "[*] Bắt đầu khởi tạo và xóa sạch cache lỗi Windows Update..."
        if ($txtStatus) { $txtStatus.Text = "Đang sửa lỗi Windows Update..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Reset-WindowsUpdateEngine
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Đã đặt lại Windows Update" }
    }
}

Register-Click "btnRestartUpdateServices" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Khởi động lại Update Services" {
        Log-Text "[*] Đang khởi động lại dịch vụ Windows Update & BITS..."
        Restart-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        Restart-Service -Name "bits" -Force -ErrorAction SilentlyContinue
        Log-Text "[OK] Đã khởi động lại dịch vụ cập nhật."
    }
}

Register-Click "btnTriggerScanUpdate" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Kích hoạt quét cập nhật" {
        Invoke-WindowsUpdateScan
    }
}

Register-Click "btnFlushDnsWinsock" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Flush DNS & Reset Winsock" {
        Log-Text "[*] Đang xóa sạch cache DNS và reset Winsock Catalog..."
        Clear-DnsResolverCache
        Run-CliStream "netsh.exe" "winsock reset"
        Log-Text "[OK] Đã làm mới mạng và DNS cache."
    }
}

Register-Click "btnResetTcpIp" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Reset TCP/IP Stack" {
        Log-Text "[*] Đang đặt lại toàn bộ ngăn xếp giao thức mạng TCP/IP..."
        Reset-NetworkInterfaceStack
        Log-Text "[OK] Đã reset TCP/IP Stack. Khuyên bạn nên khởi động lại máy."
    }
}

Register-Click "btnClearTemp" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Dọn dẹp Temp" {
        Log-Text "[*] Đang dọn dẹp các tệp tạm thời trong User Temp và Windows Temp..."
        if ($txtStatus) { $txtStatus.Text = "Đang dọn tệp rác Temp..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Clear-SystemTempFiles
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn tệp tạm hoàn tất" }
        Log-Text "[OK] Dọn dẹp bộ nhớ tạm thành công!"
    }
}

Register-Click "btnCleanEventLogs" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Dọn dẹp Windows Event Logs" -DeferExpand {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Hành động này sẽ xóa toàn bộ nhật ký sự kiện Windows (Application, System, Security...). Bạn có chắc chắn muốn tiếp tục?",
            "Xác nhận dọn dẹp Event Logs",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Expand-TerminalLog
        if ($txtStatus) { $txtStatus.Text = "Đang dọn Event Logs..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Clear-SystemEventLogs
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn Event Logs hoàn tất" }
    }
}

Register-Click "btnRestartExplorer" -LockGroup "Gỡ lỗi & Hệ thống" {
    Invoke-GuardedAction "Khởi động lại Windows Explorer" {
        Log-Text "[*] Đang khởi động lại tiến trình Windows Explorer (explorer.exe)..."
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
            Start-Process "explorer.exe"
        }
        Log-Text "[OK] Đã nạp lại Windows Explorer thành công."
    }
}

Register-Click "btnScanFaultyDrivers" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Quét Driver lỗi" {
        Log-Text "=========================================================="
        Log-Text "[SCAN] ĐANG QUÉT TOÀN BỘ THIẾT BỊ PHẦN CỨNG & DRIVER BỊ LỖI..."
        Log-Text "=========================================================="
        if ($txtStatus) { $txtStatus.Text = "Đang quét thiết bị lỗi..." }

        $faulty = Find-FaultyPnpDevices

        if ($faulty.Count -eq 0) {
            Log-Text "[OK] Tuyệt vời! Không phát hiện thiết bị nào bị lỗi hoặc thiếu driver trên máy bạn."
            if ($txtStatus) { $txtStatus.Text = "Tất cả Driver đều hoạt động tốt" }
        } else {
            Log-Text "[WARN] PHÁT HIỆN $($faulty.Count) THIẾT BỊ ĐANG BỊ LỖI / THIẾU DRIVER:"
            foreach ($d in $faulty) {
                Log-Text "   - Tên thiết bị: $($d.FriendlyName)"
                Log-Text "     Mã phần cứng: $($d.InstanceId)"
                Log-Text "     Trạng thái: $($d.Status) | ErrorCode: $($d.ConfigManagerErrorCode)"
                Log-Text "   ------------------------------------------------"
            }
            if ($txtStatus) { $txtStatus.Text = "Phát hiện $($faulty.Count) thiết bị lỗi" }
        }
    }
}

Register-Click "btnPnpRescan" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Quét lại thiết bị PnP" {
        Log-Text "[*] Đang gửi lệnh quét phần cứng Plug and Play (pnputil /scan-devices)..."
        Invoke-PnpDeviceRescan
        Log-Text "[OK] Windows đã hoàn tất quét và phát hiện lại các thiết bị phần cứng."
    }
}

Register-Click "btnOpenDeviceManager" -LockGroup "Quản lý Driver" {
    Log-Text "[*] Đang mở Trình quản lý thiết bị (devmgmt.msc)..."
    Start-Process "devmgmt.msc"
}

Register-Click "btnFixDriverUpdate" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Gỡ lỗi kẹt driver update" {
        Log-Text "[*] Đang giải phóng hàng đợi tải driver bị kẹt trong Windows Update..."
        if ($txtStatus) { $txtStatus.Text = "Đang sửa lỗi kẹt cập nhật driver..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }

        Reset-WindowsUpdateEngine

        Log-Text "   - Đang buộc nhận diện lại các thiết bị phần cứng..."
        Invoke-PnpDeviceRescan

        Log-Text "   - Yêu cầu Windows Update quét tìm driver thay thế mới..."
        Invoke-WindowsUpdateScan

        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Đã gỡ lỗi kẹt driver update" }
        Log-Text "[OK] Hoàn thành! Lỗi kẹt tải driver đã được dọn sạch."
    }
}

Register-Click "btnScanWindowsUpdateDrivers" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Quét driver từ Windows Update" {
        Invoke-WindowsUpdateScan
    }
}

Register-Click "btnCleanDriverStore" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Dọn dẹp DriverStore" -DeferExpand {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Hành động này sẽ xóa các gói driver OEM cũ không còn thiết bị sử dụng trong DriverStore.`nBạn có chắc chắn muốn tiếp tục?",
            "Xác nhận dọn dẹp DriverStore",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Expand-TerminalLog
        if ($txtStatus) { $txtStatus.Text = "Đang dọn dẹp DriverStore..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }
        Invoke-PnpDriverStoreCleanup
        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($txtStatus) { $txtStatus.Text = "Dọn dẹp DriverStore hoàn tất" }
    }
}

Register-Click "btnBackupDrivers" -LockGroup "Quản lý Driver" {
    Invoke-GuardedAction "Sao lưu Driver" {
        $dest = "C:\Backup_Drivers"
        Log-Text "[*] Đang sao lưu toàn bộ Driver của máy ra thư mục: '$dest'..."
        if ($txtStatus) { $txtStatus.Text = "Đang sao lưu driver..." }
        if ($progressBar) { $progressBar.IsIndeterminate = $true }

        $res = Export-SystemDriversBackup -Destination $dest

        if ($progressBar) { $progressBar.IsIndeterminate = $false }
        if ($res) {
            if ($txtStatus) { $txtStatus.Text = "Sao lưu driver hoàn tất" }
            Log-Text "[OK] THÀNH CÔNG! Đã sao lưu toàn bộ driver vào: $dest"
        } else {
            if ($txtStatus) { $txtStatus.Text = "Sao lưu driver thất bại" }
            Log-Text "[ERR] Lỗi trong quá trình sao lưu driver."
        }
    }
}

Register-Click "btnOpenBackupFolder" -LockGroup "Quản lý Driver" {
    $dest = "C:\Backup_Drivers"
    if (Test-Path -LiteralPath $dest) {
        Start-Process explorer.exe "`"$dest`""
    } else {
        Log-Text "[!] Thư mục $dest chưa tồn tại. Hãy bấm nút 'Sao Lưu Toàn Bộ Driver' trước."
    }
}

$script:iconSyncTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:iconSyncTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$script:iconSyncTimer.Add_Tick({
    if ($script:isScanningApps -or $script:isActionRunning) { return }
    Flush-PendingIconCache
    if (-not $script:pendingIconSaves -or $script:pendingIconSaves.Count -eq 0) {
        $script:iconSyncTimer.Stop()
    }
})

$script:autoScannedOnStartup = $false
$window.Add_ContentRendered({
    if (-not $script:autoScannedOnStartup) {
        $script:autoScannedOnStartup = $true
        Log-Text "[OK] Giao diện App-Driver đã sẵn sàng ($($allItemBorders.Count) ứng dụng / $($categories.Count) danh mục)."
        if ($script:pendingIconSaves -and $script:pendingIconSaves.Count -gt 0) {
            $script:iconSyncTimer.Start()
        }
        $window.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
            [Action]{
                Invoke-GuardedAction "Quét ứng dụng khởi động" -DeferExpand {
                    Scan-And-ColorizeApps
                }
            }
        ) | Out-Null
    }
})
$window.Add_Closed({
    $script:isWindowClosing = $true
    try {
        if ($script:iconSyncTimer) { $script:iconSyncTimer.Stop() }
        Stop-ActiveChildProcess
        Flush-PendingIconCache
    } catch {}
})

$window.ShowDialog() | Out-Null
if (-not $script:SkipHostExit) {
    Stop-ActiveChildProcess
    [Environment]::Exit(0)
}
