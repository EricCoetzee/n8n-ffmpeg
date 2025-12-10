# Simple Docker Video Monitor with File Renaming
param(
    [string]$WatchFolder = "F:\Games\Ppsspp\",
    [string]$DockerContainer = "n8n-video",
    [string]$DockerPath = "/home/node/yt/",
    [int]$WaitSeconds = 20
)

# Function to get container status
function Get-DockerContainerStatus {
    param([string]$ContainerName)
    
    try {
        # Try to get container by name
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
        
        # Try partial match
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
    
    # Test if Docker command exists
    $dockerExists = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerExists) {
        Write-Host "   ❌ Docker CLI not found in PATH" -ForegroundColor Red
        Write-Host "   Make sure Docker Desktop is installed and running" -ForegroundColor Yellow
        return $false
    }
    
    Write-Host "   ✅ Docker CLI found" -ForegroundColor Green
    
    # Test Docker daemon
    try {
        $dockerInfo = docker info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   ❌ Docker daemon not running" -ForegroundColor Red
            Write-Host "   Error: $dockerInfo" -ForegroundColor Red
            return $false
        }
        Write-Host "   ✅ Docker daemon is running" -ForegroundColor Green
    } catch {
        Write-Host "   ❌ Cannot connect to Docker daemon" -ForegroundColor Red
        return $false
    }
    
    return $true
}

# Function to find correct container name
function Find-DockerContainer {
    param([string]$RequestedName)
    
    Write-Host "`nLooking for container: $RequestedName" -ForegroundColor Cyan
    
    # List all containers
    Write-Host "Available containers:" -ForegroundColor Gray
    $containers = docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.ID}}" 2>$null
    
    if (-not $containers) {
        Write-Host "   No containers found" -ForegroundColor Yellow
        return $null
    }
    
    Write-Host $containers -ForegroundColor Gray
    
    # Check for exact match
    $exactMatch = $containers | Where-Object { $_ -match "^$RequestedName\s" }
    if ($exactMatch) {
        Write-Host "   ✅ Found exact match: $RequestedName" -ForegroundColor Green
        return $RequestedName
    }
    
    # Check for partial match
    $partialMatches = $containers | Where-Object { $_ -match $RequestedName }
    if ($partialMatches) {
        $firstMatch = ($partialMatches[0] -split '\s+')[0]
        Write-Host "   Found partial match: $firstMatch" -ForegroundColor Yellow
        return $firstMatch
    }
    
    # Ask user to select
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
    
    # Check if container is running
    $status = Get-DockerContainerStatus -ContainerName $ContainerName
    if (-not $status.Exists) {
        Write-Host "   ❌ Container '$ContainerName' does not exist" -ForegroundColor Red
        return $false
    }
    
    Write-Host "   Container status: $($status.Status)" -ForegroundColor Gray
    
    if ($status.Status -notmatch "Up") {
        Write-Host "   ⚠️ Container is not running" -ForegroundColor Yellow
        
        $startChoice = Read-Host "   Start container now? (y/n)"
        if ($startChoice -eq 'y') {
            Write-Host "   Starting container..." -ForegroundColor Gray
            docker start $ContainerName 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "   ✅ Container started" -ForegroundColor Green
                Start-Sleep -Seconds 2
            } else {
                Write-Host "   ❌ Failed to start container" -ForegroundColor Red
                return $false
            }
        } else {
            return $false
        }
    }
    
    # Test container access with a simple command
    try {
        $testResult = docker exec $ContainerName echo "test" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   ❌ Cannot execute commands in container: $testResult" -ForegroundColor Red
            return $false
        }
        
        # Test if destination path exists in container
        $pathCheck = docker exec $ContainerName sh -c "if [ -d '$DestPath' ]; then echo 'exists'; fi" 2>&1
        if ($pathCheck -notmatch "exists") {
            Write-Host "   ⚠️ Path '$DestPath' might not exist in container" -ForegroundColor Yellow
            
            $createChoice = Read-Host "   Create directory in container? (y/n)"
            if ($createChoice -eq 'y') {
                docker exec $ContainerName mkdir -p $DestPath 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "   ✅ Directory created" -ForegroundColor Green
                } else {
                    Write-Host "   ❌ Failed to create directory" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "   ✅ Destination path exists: $DestPath" -ForegroundColor Green
        }
        
        Write-Host "   ✅ Container access verified" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "   ❌ Error testing container: $_" -ForegroundColor Red
        return $false
    }
}

# Main script starts here
Write-Host "=== Docker Video Monitor ===" -ForegroundColor Cyan
Write-Host "Watch Folder: $WatchFolder" -ForegroundColor Yellow
Write-Host "Docker Path: $DockerPath" -ForegroundColor Yellow
Write-Host "Wait Time: $WaitSeconds seconds" -ForegroundColor Yellow

# Create watch folder if it doesn't exist
if (-not (Test-Path $WatchFolder)) {
    Write-Host "`n⚠️ Watch folder does not exist: $WatchFolder" -ForegroundColor Yellow
    $createChoice = Read-Host "Create folder? (y/n)"
    if ($createChoice -eq 'y') {
        New-Item -ItemType Directory -Path $WatchFolder -Force | Out-Null
        Write-Host "   ✅ Folder created" -ForegroundColor Green
    } else {
        Write-Host "   Exiting..." -ForegroundColor Red
        exit 1
    }
}

# Test Docker
if (-not (Test-Docker)) {
    Write-Host "`n❌ Docker is not available. Please:" -ForegroundColor Red
    Write-Host "1. Install Docker Desktop for Windows" -ForegroundColor Gray
    Write-Host "2. Start Docker Desktop" -ForegroundColor Gray
    Write-Host "3. Make sure Docker is running (you should see the whale icon in system tray)" -ForegroundColor Gray
    exit 1
}

# Find and verify container
$actualContainer = Find-DockerContainer -RequestedName $DockerContainer
if (-not $actualContainer) {
    Write-Host "`n❌ No container selected. Exiting." -ForegroundColor Red
    exit 1
}

# Update container name to actual found name
$DockerContainer = $actualContainer

# Test container access
if (-not (Test-ContainerAccess -ContainerName $DockerContainer -DestPath $DockerPath)) {
    Write-Host "`n❌ Cannot access container '$DockerContainer'. Exiting." -ForegroundColor Red
    exit 1
}

# Test a simple copy operation
Write-Host "`nTesting Docker copy operation..." -ForegroundColor Cyan
$testFile = Join-Path $env:TEMP "docker_test.txt"
"Test file for Docker copy" | Out-File $testFile

$testResult = docker cp $testFile "${DockerContainer}:${DockerPath}/test.txt" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Docker copy test successful" -ForegroundColor Green
    
    # Clean up test file in container
    docker exec $DockerContainer rm "${DockerPath}/test.txt" 2>&1 | Out-Null
} else {
    Write-Host "   ❌ Docker copy test failed: $testResult" -ForegroundColor Red
    Write-Host "   This indicates a permission or path issue." -ForegroundColor Yellow
}

Remove-Item $testFile -ErrorAction SilentlyContinue

Write-Host "`n✅ All checks passed! Starting monitor..." -ForegroundColor Green
Write-Host "`nWaiting for new MP4 files in: $WatchFolder" -ForegroundColor Green
Write-Host "Files will be copied to: ${DockerContainer}:${DockerPath}" -ForegroundColor Gray
Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Yellow

# Now start the file watcher
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $WatchFolder
$watcher.Filter = "*.mp4"
$watcher.EnableRaisingEvents = $true

# Create the action script block with variables passed in
$action = {
    param($sender, $e)
    
    $path = $e.FullPath
    $originalName = Split-Path $path -Leaf
    
    # Get variables from event - these are passed from the parent scope
    $containerName = $Event.MessageData.Container
    $destPath = $Event.MessageData.DockerPath
    $maxWait = $Event.MessageData.WaitSeconds
    
    try {
        $size = [math]::Round((Get-Item $path).Length / 1MB, 2)
    } catch {
        Write-Host "`n⚠️ Cannot access file: $originalName" -ForegroundColor Yellow
        return
    }
    
    # Create new filename
    $newName = $originalName -replace ' ', '_'
    
    Write-Host "`n🎥 New video detected: $originalName ($size MB)" -ForegroundColor Cyan
    Write-Host "   Renaming to: $newName" -ForegroundColor Magenta
    
    # File stabilization check
    $checkInterval = 30
    $stableChecks = 2
    $currentStable = 0
    $lastSize = 0
    $waitStartTime = Get-Date
    
    Write-Host "   Waiting for file to stabilize..." -ForegroundColor Yellow
    
    while (((Get-Date) - $waitStartTime).TotalSeconds -lt $maxWait) {
        if (-not (Test-Path $path)) {
            Write-Host "   ⚠️ File was deleted, skipping..." -ForegroundColor Yellow
            return
        }
        
        try {
            $currentSize = (Get-Item $path).Length
        } catch {
            Write-Host "   ⚠️ Cannot access file, waiting..." -ForegroundColor Yellow
            Start-Sleep -Seconds $checkInterval
            continue
        }
        
        if ($currentSize -eq $lastSize -and $currentSize -gt 0) {
            $currentStable++
            if ($currentStable -ge $stableChecks) {
                $elapsed = [math]::Round(((Get-Date) - $waitStartTime).TotalSeconds, 1)
                Write-Host "   ✅ File stabilized after $elapsed seconds" -ForegroundColor Green
                break
            }
        } elseif ($currentSize -ne $lastSize) {
            $currentStable = 0
        }
        
        $lastSize = $currentSize
        Start-Sleep -Seconds $checkInterval
    }
    
    # Double-check container is still running
    $containerCheck = docker ps --filter "name=$containerName" --format "{{.Names}}" 2>$null
    if (-not $containerCheck) {
        Write-Host "   ❌ Container '$containerName' is not running" -ForegroundColor Red
        return
    }
    
    Write-Host "   Copying to Docker container..." -ForegroundColor Yellow
    
    # Simple direct copy with error handling
    try {
        $dockerCommand = "docker cp `"$path`" `"${containerName}:${destPath}/$newName`""
        Write-Host "   Executing: $dockerCommand" -ForegroundColor Gray
        
        # Execute docker copy
        $result = docker cp "$path" "${containerName}:${destPath}/$newName" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   ✅ Successfully copied to Docker" -ForegroundColor Green
            
            # Verify file exists in container
            $verify = docker exec $containerName ls -la "${destPath}/$newName" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $fileSizeInContainer = ($verify -split '\s+')[4]
                Write-Host "   Verified: $([math]::Round($fileSizeInContainer/1MB, 2)) MB in container" -ForegroundColor Gray
                
                # Optional: Remove original file after successful copy
                # Remove-Item $path -Force
                # Write-Host "   Removed original file" -ForegroundColor Cyan
            }
        } else {
            Write-Host "   ❌ Docker copy failed with exit code: $LASTEXITCODE" -ForegroundColor Red
            Write-Host "   Error: $result" -ForegroundColor Red
        }
    } catch {
        Write-Host "   ❌ Exception: $_" -ForegroundColor Red
    }
}

# Register the event with MessageData to pass variables
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