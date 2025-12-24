param(
    [string]$WatchFolder = "F:\Games\Grand Theft Auto  San Andreas\",
    [string]$DockerContainer = "n8n-video",
    [string]$DockerPath = "/home/node/yt/",
    [int]$WaitSeconds = 300
)

# Function to get container status
function Get-DockerContainerStatus {
    param([string]$ContainerName)
    
    try {
        $container = docker ps -a --filter "name=^/${ContainerName}$" --format "{{.Names}}|{{.Status}}|{{.ID}}" 2>$null
        if ($container) {
            $parts = $container -split '\|'
            return @{
                Name = $parts[0]
                Status = $parts[1]
                ID = $parts[2]
                Exists = $true
            }
        }
        
        $container = docker ps -a --filter "name=${ContainerName}" --format "{{.Names}}|{{.Status}}|{{.ID}}" 2>$null | Select-Object -First 1
        if ($container) {
            $parts = $container -split '\|'
            return @{
                Name = $parts[0]
                Status = $parts[1]
                ID = $parts[2]
                Exists = $true
            }
        }
        
        return @{Exists = $false}
    } catch {
        return @{Exists = $false; Error = $_}
    }
}

# Function to test Docker
function Test-Docker {
    Write-Host "`nTesting Docker installation..." -ForegroundColor Cyan
    
    $dockerExists = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerExists) {
        Write-Host "   [X] Docker CLI not found in PATH" -ForegroundColor Red
        Write-Host "   Make sure Docker Desktop is installed and running" -ForegroundColor Yellow
        return $false
    }
    
    Write-Host "   [OK] Docker CLI found" -ForegroundColor Green
    
    try {
        $dockerInfo = docker info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   [X] Docker daemon not running" -ForegroundColor Red
            Write-Host "   Error: $dockerInfo" -ForegroundColor Red
            return $false
        }
        Write-Host "   [OK] Docker daemon is running" -ForegroundColor Green
    } catch {
        Write-Host "   [X] Cannot connect to Docker daemon" -ForegroundColor Red
        return $false
    }
    
    return $true
}

# Function to find correct container name
function Find-DockerContainer {
    param([string]$RequestedName)
    
    Write-Host "`nLooking for container: $RequestedName" -ForegroundColor Cyan
    
    Write-Host "Available containers:" -ForegroundColor Gray
    $containers = docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.ID}}" 2>$null
    
    if (-not $containers) {
        Write-Host "   No containers found" -ForegroundColor Yellow
        return $null
    }
    
    Write-Host $containers -ForegroundColor Gray
    
    $exactMatch = $containers | Where-Object { $_ -match "^$RequestedName\s" }
    if ($exactMatch) {
        Write-Host "   [OK] Found exact match: $RequestedName" -ForegroundColor Green
        return $RequestedName
    }
    
    $partialMatches = $containers | Where-Object { $_ -match $RequestedName }
    if ($partialMatches) {
        $firstMatch = ($partialMatches[0] -split '\s+')[0]
        Write-Host "   Found partial match: $firstMatch" -ForegroundColor Yellow
        return $firstMatch
    }
    
    Write-Host "`nContainer '$RequestedName' not found." -ForegroundColor Yellow
    $containerNames = $containers | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ -notlike "NAMES*" }
    
    if ($containerNames) {
        Write-Host "Available container names:" -ForegroundColor Gray
        for ($i = 0; $i -lt $containerNames.Count; $i++) {
            Write-Host "  [$i] $($containerNames[$i])" -ForegroundColor Gray
        }
        
        $choice = Read-Host "`nEnter number to select container (or leave empty to use default)"
        if ($choice -match '^\d+$' -and [int]$choice -lt $containerNames.Count) {
            $selected = $containerNames[$choice]
            Write-Host "   Selected container: $selected" -ForegroundColor Green
            return $selected
        }
    }
    
    return $null
}

# Function to test container access
function Test-ContainerAccess {
    param([string]$ContainerName, [string]$DestPath)
    
    Write-Host "`nTesting access to container: $ContainerName" -ForegroundColor Cyan
    
    $status = Get-DockerContainerStatus -ContainerName $ContainerName
    if (-not $status.Exists) {
        Write-Host "   [X] Container '$ContainerName' does not exist" -ForegroundColor Red
        return $false
    }
    
    Write-Host "   Container status: $($status.Status)" -ForegroundColor Gray
    
    if ($status.Status -notmatch "Up") {
        Write-Host "   [!] Container is not running" -ForegroundColor Yellow
        
        $startChoice = Read-Host "   Start container now? (y/n)"
        if ($startChoice -eq 'y') {
            Write-Host "   Starting container..." -ForegroundColor Gray
            docker start $ContainerName 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "   [OK] Container started" -ForegroundColor Green
                Start-Sleep -Seconds 2
            } else {
                Write-Host "   [X] Failed to start container" -ForegroundColor Red
                return $false
            }
        } else {
            return $false
        }
    }
    
    try {
        $testResult = docker exec $ContainerName echo "test" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   [X] Cannot execute commands in container: $testResult" -ForegroundColor Red
            return $false
        }
        
        $pathCheck = docker exec $ContainerName sh -c "if [ -d '$DestPath' ]; then echo 'exists'; fi" 2>&1
        if ($pathCheck -notmatch "exists") {
            Write-Host "   [!] Path '$DestPath' might not exist in container" -ForegroundColor Yellow
            
            $createChoice = Read-Host "   Create directory in container? (y/n)"
            if ($createChoice -eq 'y') {
                docker exec $ContainerName mkdir -p $DestPath 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "   [OK] Directory created" -ForegroundColor Green
                } else {
                    Write-Host "   [X] Failed to create directory" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "   [OK] Destination path exists: $DestPath" -ForegroundColor Green
        }
        
        Write-Host "   [OK] Container access verified" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "   [X] Error testing container: $_" -ForegroundColor Red
        return $false
    }
}

# Main script starts here
Write-Host "=== Docker Video Monitor ===" -ForegroundColor Cyan
Write-Host "Watch Folder: $WatchFolder" -ForegroundColor Yellow
Write-Host "Docker Path: $DockerPath" -ForegroundColor Yellow
Write-Host "Wait Time: $WaitSeconds seconds" -ForegroundColor Yellow

if (-not (Test-Path $WatchFolder)) {
    Write-Host "`n[!] Watch folder does not exist: $WatchFolder" -ForegroundColor Yellow
    $createChoice = Read-Host "Create folder? (y/n)"
    if ($createChoice -eq 'y') {
        New-Item -ItemType Directory -Path $WatchFolder -Force | Out-Null
        Write-Host "   [OK] Folder created" -ForegroundColor Green
    } else {
        Write-Host "   Exiting..." -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Docker)) {
    Write-Host "`n[X] Docker is not available. Please:" -ForegroundColor Red
    Write-Host "1. Install Docker Desktop for Windows" -ForegroundColor Gray
    Write-Host "2. Start Docker Desktop" -ForegroundColor Gray
    Write-Host "3. Make sure Docker is running (you should see the whale icon in system tray)" -ForegroundColor Gray
    exit 1
}

$actualContainer = Find-DockerContainer -RequestedName $DockerContainer
if (-not $actualContainer) {
    Write-Host "`n[X] No container selected. Exiting." -ForegroundColor Red
    exit 1
}

$DockerContainer = $actualContainer

if (-not (Test-ContainerAccess -ContainerName $DockerContainer -DestPath $DockerPath)) {
    Write-Host "`n[X] Cannot access container '$DockerContainer'. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "`nTesting Docker copy operation..." -ForegroundColor Cyan
$testFile = Join-Path $env:TEMP "docker_test.txt"
"Test file for Docker copy" | Out-File $testFile

$testResult = docker cp $testFile "${DockerContainer}:${DockerPath}/test.txt" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   [OK] Docker copy test successful" -ForegroundColor Green
    docker exec $DockerContainer rm "${DockerPath}/test.txt" 2>&1 | Out-Null
} else {
    Write-Host "   [X] Docker copy test failed: $testResult" -ForegroundColor Red
    Write-Host "   This indicates a permission or path issue." -ForegroundColor Yellow
}

Remove-Item $testFile -ErrorAction SilentlyContinue

Write-Host "`n[OK] All checks passed! Starting monitor..." -ForegroundColor Green
Write-Host "`nWaiting for new MP4 files in: $WatchFolder" -ForegroundColor Green
Write-Host "Files will be renamed to: Grand_Theft_Auto_San_Andreas_Vehicle_<your_text>.mp4" -ForegroundColor Magenta
Write-Host "Files will be copied to: ${DockerContainer}:${DockerPath}" -ForegroundColor Gray
Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Yellow

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $WatchFolder
$watcher.Filter = "*.mp4"
$watcher.EnableRaisingEvents = $true

$action = {
    param($sender, $e)
    
    $path = $e.FullPath
    $originalName = Split-Path $path -Leaf
    
    $containerName = $Event.MessageData.Container
    $destPath = $Event.MessageData.DockerPath
    $maxWait = $Event.MessageData.WaitSeconds
    
    try {
        $size = [math]::Round((Get-Item $path).Length / 1MB, 2)
    } catch {
        Write-Host "`n[!] Cannot access file: $originalName" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n[VIDEO] New video detected: $originalName ($size MB)" -ForegroundColor Cyan
    
    $checkInterval = 30
    $stableChecks = 2
    $currentStable = 0
    $lastSize = 0
    $waitStartTime = Get-Date
    
    Write-Host "   Waiting for file to stabilize..." -ForegroundColor Yellow
    
    while (((Get-Date) - $waitStartTime).TotalSeconds -lt $maxWait) {
        if (-not (Test-Path $path)) {
            Write-Host "   [!] File was deleted, skipping..." -ForegroundColor Yellow
            return
        }
        
        try {
            $currentSize = (Get-Item $path).Length
        } catch {
            Write-Host "   [!] Cannot access file, waiting..." -ForegroundColor Yellow
            Start-Sleep -Seconds $checkInterval
            continue
        }
        
        if ($currentSize -eq $lastSize -and $currentSize -gt 0) {
            $currentStable++
            if ($currentStable -ge $stableChecks) {
                $elapsed = [math]::Round(((Get-Date) - $waitStartTime).TotalSeconds, 1)
                Write-Host "   [OK] File stabilized after $elapsed seconds" -ForegroundColor Green
                break
            }
        } elseif ($currentSize -ne $lastSize) {
            $currentStable = 0
        }
        
        $lastSize = $currentSize
        Start-Sleep -Seconds $checkInterval
    }
    
    Write-Host "`n[INPUT] Enter additional text for filename:" -ForegroundColor Cyan
    Write-Host "   Final name will be: Grand_Theft_Auto_San_Andreas_Vehicle_<your_text>.mp4" -ForegroundColor Gray
    Write-Host -NoNewline "   Your text: " -ForegroundColor Yellow
    
    $userText = Read-Host
    
    $invalidChars = [IO.Path]::GetInvalidFileNameChars()
    $cleanText = $userText
    foreach ($char in $invalidChars) {
        $cleanText = $cleanText.Replace($char.ToString(), '')
    }
    $cleanText = $cleanText -replace ' ', '_'
    
    if ([string]::IsNullOrWhiteSpace($cleanText)) {
        Write-Host "   [!] No text provided, using timestamp instead" -ForegroundColor Yellow
        $cleanText = (Get-Date -Format "yyyyMMdd_HHmmss")
    }
    
    $newName = "Grand_Theft_Auto_San_Andreas_Vehicle_${cleanText}.mp4"
    
    Write-Host "   New filename: $newName" -ForegroundColor Magenta
    
    $containerCheck = docker ps --filter "name=$containerName" --format "{{.Names}}" 2>$null
    if (-not $containerCheck) {
        Write-Host "   [X] Container '$containerName' is not running" -ForegroundColor Red
        return
    }
    
    Write-Host "   Copying to Docker container..." -ForegroundColor Yellow
    
    try {
        $dockerCommand = "docker cp `"$path`" `"${containerName}:${destPath}/$newName`""
        Write-Host "   Executing: $dockerCommand" -ForegroundColor Gray
        
        $result = docker cp "$path" "${containerName}:${destPath}/$newName" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   [OK] Successfully copied to Docker as: $newName" -ForegroundColor Green
            
            $verify = docker exec $containerName ls -la "${destPath}/$newName" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $fileSizeInContainer = ($verify -split '\s+')[4]
                Write-Host "   Verified: $([math]::Round($fileSizeInContainer/1MB, 2)) MB in container" -ForegroundColor Gray
            }
        } else {
            Write-Host "   [X] Docker copy failed with exit code: $LASTEXITCODE" -ForegroundColor Red
            Write-Host "   Error: $result" -ForegroundColor Red
        }
    } catch {
        Write-Host "   [X] Exception: $_" -ForegroundColor Red
    }
    
    Write-Host "`n[READY] Watching for next file..." -ForegroundColor Green
}

$messageData = @{
    Container = $DockerContainer
    DockerPath = $DockerPath
    WaitSeconds = $WaitSeconds
}

$job = Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action -MessageData $messageData

Write-Host "Monitor is now active. Event handler registered." -ForegroundColor Green

try {
    while ($true) { 
        Start-Sleep -Seconds 1
    }
}
finally {
    Unregister-Event -SourceIdentifier $job.Name
    Remove-Job -Job $job -Force
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
    Write-Host "`nMonitor stopped." -ForegroundColor Yellow
}
