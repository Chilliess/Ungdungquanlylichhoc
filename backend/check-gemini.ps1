[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9._-]+$')]
    [string]$Model = 'gemini-3.8-flash',
    [switch]$FromClipboard
)

# Test the same Google endpoint without Supabase. The prompt is fixed, contains
# no user data, and consumes one provider request. Never write the key to disk.
$ErrorActionPreference = 'Stop'

function Get-GeminiErrorSummary {
    param([string]$Body, [string]$ApiKey)
    # Redact before parsing/fallback so malformed JSON and HTML are safe too.
    $safeBody = $Body
    if (-not [string]::IsNullOrEmpty($ApiKey)) {
        $safeBody = $safeBody.Replace($ApiKey, '[REDACTED]')
    }
    $safeBody = [regex]::Replace($safeBody, 'AIza[0-9A-Za-z_-]+', '[REDACTED]')
    $safeBody = [regex]::Replace($safeBody, '(?i)Bearer\s+[^\s"<>]+', 'Bearer [REDACTED]')
    $safeBody = $safeBody.TrimStart([char]0xFEFF).Trim()
    try {
        $failure = $safeBody | ConvertFrom-Json -ErrorAction Stop
        # Some Google endpoints wrap an error object in an array.
        if ($failure -is [array]) { $failure = $failure[0] }
        $summary = [string]$failure.error.message
    } catch {
        $summary = ''
    }
    if ([string]::IsNullOrWhiteSpace($summary)) {
        $summary = [regex]::Replace($safeBody, '<[^>]*>', ' ')
    }
    $summary = [regex]::Replace($summary, '[\p{C}\s]+', ' ').Trim()
    if ($summary.Length -gt 1200) { $summary = $summary.Substring(0, 1200) + '...' }
    if ([string]::IsNullOrWhiteSpace($summary)) { return '(empty response body)' }
    return $summary
}

Add-Type -AssemblyName System.Net.Http
$secretInput = $null
if ($FromClipboard) {
    # Wait until AFTER the user runs this command, otherwise the clipboard may
    # still contain the command itself instead of the API key.
    # Hide accidental pastes into the confirmation prompt as well.
    $confirmation = Read-Host 'Copy the FULL Gemini key now, return here, then press Enter (do not paste)' -AsSecureString
    $confirmation.Dispose()
    $clipboardText = Get-Clipboard -Raw
    if ([string]::IsNullOrWhiteSpace($clipboardText)) {
        Write-Output 'Clipboard is empty. Copy the full key and run again.'
        return
    }
    $secretInput = ConvertTo-SecureString -String $clipboardText -AsPlainText -Force
    $clipboardText = $null
} else {
    $secretInput = Read-Host 'Paste Gemini API key (hidden; press Enter)' -AsSecureString
}
$secretPointer = [IntPtr]::Zero
$apiKey = $null
$httpClient = $null
$httpHandler = $null
$request = $null
$response = $null
try {
    $secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secretInput)
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer).Trim()
    Write-Output ('Key length: ' + $apiKey.Length + ' characters (key hidden)')
    if ($apiKey.Length -lt 20 -or $apiKey -match '\s') {
        Write-Output 'The pasted key is too short or contains whitespace. Copy the complete key again.'
        return
    }
    $httpHandler = [System.Net.Http.HttpClientHandler]::new()
    $httpHandler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $httpClient = [System.Net.Http.HttpClient]::new($httpHandler)
    $httpClient.Timeout = [TimeSpan]::FromSeconds(45)
    $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::Post,
        "https://generativelanguage.googleapis.com/v1beta/models/${Model}:generateContent")
    $request.Headers.Add('x-goog-api-key', $apiKey)
    $payload = @{
        contents = @(@{ role = 'user'; parts = @(@{ text = 'Reply with OK.' }) })
        generationConfig = @{ maxOutputTokens = 512 }
    } | ConvertTo-Json -Depth 8 -Compress
    $request.Content = [System.Net.Http.StringContent]::new($payload, [Text.Encoding]::UTF8, 'application/json')
    $response = $httpClient.SendAsync($request).GetAwaiter().GetResult()
    $rawBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    Write-Output ('HTTP ' + [int]$response.StatusCode)
    Write-Output ('Content-Type: ' + [string]$response.Content.Headers.ContentType)
    if ($response.IsSuccessStatusCode) {
        Write-Output 'Google accepted the key and request from this computer.'
        Write-Output 'If Supabase still fails, compare its saved key/model and server access settings.'
    } else {
        Write-Output ('Google message: ' + (Get-GeminiErrorSummary -Body $rawBody -ApiKey $apiKey))
    }
} catch {
    # Do not print exception/request objects containing headers or credentials.
    Write-Output 'Check could not complete. Check your network and that the key is not empty.'
} finally {
    if ($response) { $response.Dispose() }
    if ($request) { $request.Dispose() }
    if ($httpClient) { $httpClient.Dispose() }
    if ($secretPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
    }
    if ($secretInput) { $secretInput.Dispose() }
    $apiKey = $null
}
