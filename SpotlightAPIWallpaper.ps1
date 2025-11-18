# Spotlight API Wallpaper Script
# 使用在线API获取Windows聚焦壁纸并设置为桌面背景

# Log function - defined first to be available everywhere
function Add-LogEntry($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] $message"
    Write-Host $logLine
    try {
        # Ensure log directory exists
        $logDir = Split-Path -Parent $logFile
        if (-not (Test-Path -Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $logLine | Add-Content -Path $logFile -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if logging fails
    }
}

# Hash cache management functions - defined before they are used
function Get-HashCache {
    param()
    
    try {
        if (Test-Path -Path $hashCacheFile) {
            Write-Host "Loading hash cache from $hashCacheFile..."
            $cacheContent = Get-Content -Path $hashCacheFile -Raw
            $jsonObject = ConvertFrom-Json -InputObject $cacheContent -ErrorAction SilentlyContinue
            
            if ($jsonObject -eq $null -or $jsonObject.FileHashes -eq $null) {
                # Cache file exists but is invalid, create new cache
                return @{
                    FileHashes = @{}
                    LastUpdated = [DateTime]::Now
                }
            }
            
            # Convert PSCustomObject to Hashtable
            $hashCache = @{
                FileHashes = @{}
                LastUpdated = [DateTime]::Now
            }
            
            # Copy LastUpdated
            $hashCache.LastUpdated = $jsonObject.LastUpdated
            
            # Copy FileHashes
            foreach ($key in $jsonObject.FileHashes.PSObject.Properties.Name) {
                $fileInfo = $jsonObject.FileHashes.$key
                $hashCache.FileHashes[$key] = @{
                    Hash = $fileInfo.Hash
                    LastAccessed = $fileInfo.LastAccessed
                    FileName = $fileInfo.FileName
                }
            }
            
            return $hashCache
        } else {
            Write-Host "Hash cache not found, creating new cache..."
            return @{
                FileHashes = @{}
                LastUpdated = [DateTime]::Now
            }
        }
    } catch {
        Write-Host "Error loading hash cache: $($_.Exception.Message)"
        Add-LogEntry -message "Error loading hash cache: $($_.Exception.Message)"
        return @{
            FileHashes = @{}
            LastUpdated = [DateTime]::Now
        }
    }
}

function Save-HashCache {
    param(
        [hashtable]$cache
    )
    
    try {
        # Update last modified time
        $cache.LastUpdated = [DateTime]::Now
        
        # Ensure cache directory exists
        $cacheDir = Split-Path -Parent $hashCacheFile
        if (-not (Test-Path -Path $cacheDir)) {
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
        }
        
        # Save cache to file
        $cacheJson = ConvertTo-Json -InputObject $cache -Compress
        Set-Content -Path $hashCacheFile -Value $cacheJson -Force
        Write-Host "Hash cache saved to $hashCacheFile"
        Add-LogEntry -message "Hash cache saved to $hashCacheFile"
    } catch {
        Write-Host "Error saving hash cache: $($_.Exception.Message)"
        Add-LogEntry -message "Error saving hash cache: $($_.Exception.Message)"
    }
}

function Update-HashCache {
    param(
        [hashtable]$cache,
        [string]$filePath,
        [string]$fileHash
    )
    
    # Normalize file path for consistent lookup
    $normalizedPath = $filePath.ToLower()
    $cache.FileHashes[$normalizedPath] = @{
        Hash = $fileHash
        LastAccessed = [DateTime]::Now
        FileName = (Split-Path -Leaf $filePath)
    }
    
    # Clean up cache entries for files that no longer exist
    $existingFiles = Get-ChildItem -Path $saveFolder -File -Recurse:$false | ForEach-Object { $_.FullName.ToLower() }
    $keysToRemove = @()
    
    foreach ($key in $cache.FileHashes.Keys) {
        if (-not ($existingFiles -contains $key)) {
            $keysToRemove += $key
        }
    }
    
    foreach ($key in $keysToRemove) {
        $cache.FileHashes.Remove($key)
    }
    
    return $cache
}

function Get-FileHashValue {
    param(
        [string]$filePath
    )
    
    try {
        if (-not (Test-Path -Path $filePath)) {
            return $null
        }
        
        $hashAlgo = [System.Security.Cryptography.MD5]::Create()
        $stream = [System.IO.File]::OpenRead($filePath)
        $hashBytes = $hashAlgo.ComputeHash($stream)
        $stream.Close()
        $stream.Dispose()
        
        $hashString = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
        return $hashString
    } catch {
        Write-Host "Error calculating file hash: $($_.Exception.Message)"
        Add-LogEntry -message "Error calculating hash for ${filePath}: $($_.Exception.Message)"
        return $null
    }
}

function Test-IsDuplicateWallpaper {
    param(
        [string]$newFilePath,
        [hashtable]$hashCache
    )
    
    try {
        Write-Host "Checking for duplicate wallpaper..."
        
        # Calculate hash of the new file
        $newFileHash = Get-FileHashValue -filePath $newFilePath
        if ($newFileHash -eq $null) {
            Write-Host "Could not calculate hash for the new file. Skipping duplicate check."
            return $false
        }
        
        Write-Host "New file hash: $newFileHash"
        
        # Check if hash exists in cache
        foreach ($filePath in $hashCache.FileHashes.Keys) {
            $cachedHash = $hashCache.FileHashes[$filePath].Hash
            if ($cachedHash -eq $newFileHash) {
                $duplicateFileName = $hashCache.FileHashes[$filePath].FileName
                Write-Host "Duplicate found! Same content as $duplicateFileName"
                Add-LogEntry -message "Duplicate image found: $newFilePath is same as $duplicateFileName"
                return $true
            }
        }
        
        # If not found in cache, perform a full scan for any missing files
        # This ensures we catch any files not yet in the cache
        $allImageFiles = Get-ChildItem -Path $saveFolder -File -Recurse:$false
        $totalFiles = $allImageFiles.Count
        $processedCount = 0
        
        foreach ($file in $allImageFiles) {
            # Skip the new file itself
            if ($file.FullName.ToLower() -eq $newFilePath.ToLower()) {
                continue
            }
            
            $processedCount++
            Write-Host "Scanning file ${processedCount}/${totalFiles}: $($file.Name)" -ForegroundColor Cyan
            
            # Check if this file's hash is already in cache
            $normalizedPath = $file.FullName.ToLower()
            if ($hashCache.FileHashes.ContainsKey($normalizedPath)) {
                $cachedHash = $hashCache.FileHashes[$normalizedPath].Hash
                if ($cachedHash -eq $newFileHash) {
                    Write-Host "Duplicate found in cache! Same content as $($file.Name)"
                    Add-LogEntry -message "Duplicate image found: $newFilePath is same as $($file.Name)"
                    return $true
                }
            } else {
                # Calculate hash for files not in cache and add to cache
                $existingFileHash = Get-FileHashValue -filePath $file.FullName
                if ($existingFileHash -eq $newFileHash) {
                    Write-Host "Duplicate found during full scan! Same content as $($file.Name)"
                    Add-LogEntry -message "Duplicate image found: $newFilePath is same as $($file.Name)"
                    return $true
                } else {
                    # Update cache with this file's hash for future checks
                    $hashCache = Update-HashCache -cache $hashCache -filePath $file.FullName -fileHash $existingFileHash
                }
            }
        }
        
        # If no duplicates found, add this file's hash to the cache
        $hashCache = Update-HashCache -cache $hashCache -filePath $newFilePath -fileHash $newFileHash
        
        return $false
    } catch {
        Write-Host "Error during duplicate check: $($_.Exception.Message)"
        Add-LogEntry -message "Error during duplicate check: $($_.Exception.Message)"
        return $false
    }
}

# Function to clean up existing duplicate wallpapers
function Cleanup-DuplicateWallpapers {
    param(
        [hashtable]$hashCache
    )
    
    try {
        Write-Host "Starting duplicate wallpaper cleanup..."
        Add-LogEntry -message "Starting duplicate wallpaper cleanup"
        
        # Get all image files in the save folder
        $allImageFiles = Get-ChildItem -Path $saveFolder -File -Recurse:$false
        $totalFiles = $allImageFiles.Count
        $processedCount = 0
        $duplicatesRemoved = 0
        $hashToFiles = @{}
        
        Write-Host "Scanning $totalFiles files for duplicates..."
        
        # First pass: build a map of hash to list of files
        foreach ($file in $allImageFiles) {
            $processedCount++
            Write-Host "Processing file ${processedCount}/${totalFiles}: $($file.Name)" -ForegroundColor Yellow
            
            # Normalize file path
            $normalizedPath = $file.FullName.ToLower()
            
            # Try to get hash from cache first
            $fileHash = $null
            if ($hashCache.FileHashes.ContainsKey($normalizedPath)) {
                $fileHash = $hashCache.FileHashes[$normalizedPath].Hash
                Write-Host "Using cached hash for $($file.Name)"
            } else {
                # Calculate hash if not in cache
                $fileHash = Get-FileHashValue -filePath $file.FullName
                if ($fileHash -eq $null) {
                    Write-Host "Could not calculate hash for $($file.Name). Skipping."
                    continue
                }
                
                # Update cache
                $hashCache = Update-HashCache -cache $hashCache -filePath $file.FullName -fileHash $fileHash
            }
            
            # Add file to hash map
            if (-not $hashToFiles.ContainsKey($fileHash)) {
                $hashToFiles[$fileHash] = @()
            }
            $hashToFiles[$fileHash] += @{
                Path = $file.FullName
                Name = $file.Name
                LastWriteTime = $file.LastWriteTime
            }
        }
        
        # Second pass: identify and remove duplicates
        foreach ($hash in $hashToFiles.Keys) {
            $filesWithSameHash = $hashToFiles[$hash]
            
            # If there's only one file with this hash, no duplicates
            if ($filesWithSameHash.Count -le 1) {
                continue
            }
            
            # Sort files by LastWriteTime (newest first)
            $sortedFiles = $filesWithSameHash | Sort-Object -Property LastWriteTime -Descending
            
            # Keep the newest file, remove the rest
            $fileToKeep = $sortedFiles[0]
            Write-Host "Found $($sortedFiles.Count) files with the same content. Keeping $($fileToKeep.Name) and removing others." -ForegroundColor Magenta
            Add-LogEntry -message "Found $($sortedFiles.Count) duplicates with hash $hash. Keeping $($fileToKeep.Name)."
            
            # Remove duplicate files (all except the first one)
            for ($i = 1; $i -lt $sortedFiles.Count; $i++) {
                $fileToRemove = $sortedFiles[$i]
                try {
                    Write-Host "Removing duplicate file: $($fileToRemove.Name)"
                    Remove-Item -Path $fileToRemove.Path -Force
                    $duplicatesRemoved++
                    
                    # Remove from hash cache
                    $normalizedPathToRemove = $fileToRemove.Path.ToLower()
                    if ($hashCache.FileHashes.ContainsKey($normalizedPathToRemove)) {
                        $hashCache.FileHashes.Remove($normalizedPathToRemove)
                    }
                    
                    Add-LogEntry -message "Removed duplicate file: $($fileToRemove.Name)"
                } catch {
                    Write-Host "Error removing $($fileToRemove.Name): $($_.Exception.Message)"
                    Add-LogEntry -message "Error removing $($fileToRemove.Name): $($_.Exception.Message)"
                }
            }
        }
        
        Write-Host "Duplicate cleanup completed. Removed $duplicatesRemoved duplicate files." -ForegroundColor Green
        Add-LogEntry -message "Duplicate cleanup completed. Removed $duplicatesRemoved duplicate files."
        
        return $hashCache
    } catch {
        Write-Host "Error during duplicate cleanup: $($_.Exception.Message)"
        Add-LogEntry -message "Error during duplicate cleanup: $($_.Exception.Message)"
        return $hashCache
    }
}

Write-Host "Starting Spotlight API Wallpaper Script..."
Add-LogEntry -message "Script started"

# Configuration
$saveFolder = "D:\TD\Pictures\SpotlightWallpapers"
$today = Get-Date -Format "yyyyMMdd"
$imageNameBase = "spot_api_"
$logFile = "$PSScriptRoot\spotlight_api_wallpaper_log.txt"
$apiUrl = "https://api.qzink.me/spotlight"
$maxRetries = 3
$retryDelay = 10 # seconds
$minFileSize = 1MB # Minimum file size to consider valid
$retentionDays = 30 # Days to keep old wallpapers
$hashCacheFile = "$PSScriptRoot\wallpaper_hash_cache.json" # File to cache image hashes for performance

# Ensure save folder exists
if (-not (Test-Path -Path $saveFolder)) {
    try {
        New-Item -Path $saveFolder -ItemType Directory -Force | Out-Null
        Write-Host "Created wallpaper save directory: $saveFolder"
        Add-LogEntry -message "Created wallpaper save directory: $saveFolder"
    } catch {
        Write-Host "Error creating directory: $($_.Exception.Message)"
        Add-LogEntry -message "Error creating directory: $($_.Exception.Message)"
    }
}

# Function to clean up old wallpapers
function Cleanup-OldWallpapers {
    try {
        $cutoffDate = (Get-Date).AddDays(-$retentionDays)
        $oldFiles = Get-ChildItem -Path $saveFolder -File -Recurse:$false | Where-Object { $_.LastWriteTime -lt $cutoffDate }
        
        if ($oldFiles.Count -gt 0) {
            Write-Host "Cleaning up $($oldFiles.Count) old wallpapers..."
            Add-LogEntry -message "Cleaning up $($oldFiles.Count) wallpapers older than $retentionDays days"
            
            foreach ($file in $oldFiles) {
                try {
                    Remove-Item -Path $file.FullName -Force
                } catch {
                    Add-LogEntry -message "Error deleting $($file.FullName): $($_.Exception.Message)"
                }
            }
        } else {
            Write-Host "No wallpapers to clean up."
        }
    } catch {
        Write-Host "Error during cleanup: $($_.Exception.Message)"
        Add-LogEntry -message "Error during cleanup: $($_.Exception.Message)"
    }
}

# Function to download image with retry mechanism
function Download-ImageWithRetry {
    param(
        [string]$url,
        [string]$outputPath,
        [int]$maxRetries = 3,
        [int]$retryDelay = 10
    )
    
    $retryCount = 0
    $success = $false
    
    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            Write-Host "Downloading image from $url (Attempt $($retryCount + 1))..."
            
            # Use WebClient for better error handling
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($url, $outputPath)
            $webClient.Dispose()
            
            # Verify the file was downloaded successfully
            if (Test-Path -Path $outputPath) {
                $fileInfo = Get-Item -Path $outputPath
                if ($fileInfo.Length -gt 0) {
                    $success = $true
                    Write-Host "Successfully downloaded image to $outputPath (Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB)"
                    Add-LogEntry -message "Successfully downloaded image to $outputPath"
                    return $true
                } else {
                    Write-Host "Downloaded file is empty. Retrying..."
                    Add-LogEntry -message "Downloaded file is empty"
                    Remove-Item -Path $outputPath -Force -ErrorAction SilentlyContinue
                }
            } else {
                Write-Host "File was not created. Retrying..."
                Add-LogEntry -message "File was not created after download attempt"
            }
        } catch {
            Write-Host "Error downloading image: $($_.Exception.Message). Retrying in $retryDelay seconds..."
            Add-LogEntry -message "Error downloading image: $($_.Exception.Message)"
        }
        
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Start-Sleep -Seconds $retryDelay
        }
    }
    
    if (-not $success) {
        Write-Host "Failed to download image after $maxRetries attempts"
        Add-LogEntry -message "Failed to download image after $maxRetries attempts"
        return $false
    }
}

# Function to set Windows desktop wallpaper
function Set-Wallpaper {
    param(
        [string]$imagePath
    )
    
    try {
        # Check if image exists
        if (-not (Test-Path -Path $imagePath)) {
            Write-Host "Error: Image file not found at $imagePath"
            Add-LogEntry -message "Error: Image file not found at $imagePath"
            return $false
        }
        
        # Set wallpaper using Windows API
        $wallpaperStyle = 10  # 10 = Fill
        $tileWallpaper = 0    # 0 = No tiling
        
        # Update registry to set wallpaper
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value $wallpaperStyle
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value $tileWallpaper
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -Value $imagePath
        
        # Set wallpaper using user32.dll
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class Wallpaper {
            [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
            public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
        }
"@
        
        # Call the Win32 API to update the desktop
        [Wallpaper]::SystemParametersInfo(20, 0, $imagePath, 3)
        
        # Force desktop refresh to ensure wallpaper changes are visible
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.SendKeys]::SendWait("{F5}")
        
        return $true
    } catch {
        Write-Host "Error setting wallpaper: $($_.Exception.Message)"
        Add-LogEntry -message "Error setting wallpaper: $($_.Exception.Message)"
        return $false
    }
}

# Function to get Spotlight wallpaper from API
function Get-SpotlightWallpaperFromAPI {
    param(
        [hashtable]$hashCache
    )
    
    try {
        Write-Host "Fetching Spotlight wallpaper from API: $apiUrl"
        Add-LogEntry -message "Fetching Spotlight wallpaper from API"
        
        # Get API response
        $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -TimeoutSec 30
        $json = $response.Content
        
        # Parse JSON response
        try {
            $data = $json | ConvertFrom-Json
            
            # Extract landscape URL
            $landscapeUrl = $data.landscape_url
            
            if (-not $landscapeUrl) {
                throw "Landscape URL not found in API response"
            }
            
            Write-Host "Found landscape URL: $landscapeUrl"
            
            # Generate filename with timestamp
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $imageExtension = [System.IO.Path]::GetExtension($landscapeUrl)
            if (-not $imageExtension) {
                $imageExtension = ".jpg"  # Default to jpg if no extension
            }
            
            $imageFileName = "$imageNameBase$timestamp$imageExtension"
            $imagePath = Join-Path -Path $saveFolder -ChildPath $imageFileName
            
            # Download the image
            if (Download-ImageWithRetry -url $landscapeUrl -outputPath $imagePath -maxRetries $maxRetries -retryDelay $retryDelay) {
                # Verify file size
                $fileInfo = Get-Item -Path $imagePath
                if ($fileInfo.Length -ge $minFileSize) {
                    # Check for duplicates using the hash cache
                    if (Test-IsDuplicateWallpaper -newFilePath $imagePath -hashCache $hashCache) {
                        Write-Host "Duplicate image detected, removing file: $imagePath"
                        Add-LogEntry -message "Removed duplicate image: $imagePath"
                        Remove-Item -Path $imagePath -Force
                        return $null
                    }
                    
                    return @{
                        Path = $imagePath
                        Size = $fileInfo.Length
                        URL = $landscapeUrl
                    }
                } else {
                    Write-Host "Image file is too small: $([math]::Round($fileInfo.Length / 1KB, 2)) KB (minimum: $([math]::Round($minFileSize / 1KB, 2)) KB)"
                    Add-LogEntry -message "Image file too small: $($fileInfo.Length) bytes"
                    Remove-Item -Path $imagePath -Force
                    return $null
                }
            }
            
            return $null
        } catch {
            Write-Host "Error parsing JSON response: $($_.Exception.Message)"
            Add-LogEntry -message "Error parsing JSON response: $($_.Exception.Message)"
            Write-Host "Raw API response: $json"
            return $null
        }
    } catch {
        Write-Host "Error fetching from API: $($_.Exception.Message)"
        Add-LogEntry -message "Error fetching from API: $($_.Exception.Message)"
        return $null
    }
}

# Main execution
try {
    # First, clean up old wallpapers
    Cleanup-OldWallpapers
    
    # Load hash cache for duplicate detection optimization
    $hashCache = Get-HashCache
    
    # Clean up duplicate wallpapers
    $hashCache = Cleanup-DuplicateWallpapers -hashCache $hashCache
    
    # Try to get Spotlight wallpaper from API
    $wallpaperInfo = Get-SpotlightWallpaperFromAPI -hashCache $hashCache
    
    if ($wallpaperInfo) {
        Write-Host "Selected image: $($wallpaperInfo.Path) ($([math]::Round($wallpaperInfo.Size / 1MB, 2)) MB)"
        Add-LogEntry -message "Selected Spotlight image from API: $($wallpaperInfo.Path)"
        
        # Set as wallpaper
        if (Set-Wallpaper -imagePath $wallpaperInfo.Path) {
            Write-Host "Wallpaper successfully set! Please check your desktop."
            Add-LogEntry -message "Wallpaper successfully set: $($wallpaperInfo.Path)"
        }
    } else {
        Write-Host "No suitable Spotlight images available from API at this time."
        Write-Host "Please check your internet connection or try again later."
        Add-LogEntry -message "No suitable Spotlight images available from API"
    }
    
    # Save hash cache for future use
    Save-HashCache -cache $hashCache
    
} catch {
    Write-Host "Error in main execution: $($_.Exception.Message)"
    Add-LogEntry -message "Error in main execution: $($_.Exception.Message)"
    
    # Try to save cache even on error
    try {
        Save-HashCache -cache $hashCache
    } catch {
        # Silently ignore cache save errors
    }
}

Write-Host "Spotlight API Wallpaper Script completed!"
Add-LogEntry -message "Script completed"