[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+$')]
    [string]$ProjectRef,

    [ValidateSet('study-assistant', 'import-timetable', 'delete-account', 'purge-accounts')]
    [string[]]$Functions = @('study-assistant')
)

$ErrorActionPreference = 'Stop'
# The CLI expects supabase/functions. Prepare that layout only in a temporary
# directory; backend/functions remains the sole source in the repository.
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$stagePath = [IO.Path]::GetFullPath((Join-Path $tempRoot ('schedule-backend-' + [guid]::NewGuid().ToString('N'))))
$expectedPrefix = $tempRoot + [IO.Path]::DirectorySeparatorChar
if (-not $stagePath.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary directory is outside the expected location.'
}
try {
    $stageSupabase = Join-Path $stagePath 'supabase'
    New-Item -ItemType Directory -Path $stageSupabase -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'functions') -Destination $stageSupabase -Recurse
    Set-Content -LiteralPath (Join-Path $stageSupabase 'config.toml') -Encoding utf8 -Value 'project_id = "study-schedule-backend"'
    foreach ($functionName in $Functions) {
        & npx.cmd --yes supabase functions deploy $functionName --project-ref $ProjectRef --workdir $stagePath --no-verify-jwt
        if ($LASTEXITCODE -ne 0) { throw "Deployment failed for $functionName (exit $LASTEXITCODE)." }
    }
}
finally {
    # Re-check the exact absolute target before recursive cleanup.
    $cleanupPath = [IO.Path]::GetFullPath($stagePath)
    if ($cleanupPath.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($cleanupPath).StartsWith('schedule-backend-') -and
        (Test-Path -LiteralPath $cleanupPath)) {
        Remove-Item -LiteralPath $cleanupPath -Recurse -Force
    }
}
