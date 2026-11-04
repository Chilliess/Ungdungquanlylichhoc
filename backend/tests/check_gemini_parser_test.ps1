$ErrorActionPreference = 'Stop'
# Load just the pure parser, without prompting for a key or making requests.
$sourcePath = Join-Path $PSScriptRoot '..\check-gemini.ps1'
$tokens = $null
$errors = $null
$tree = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $sourcePath).Path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$parserFunction = $tree.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-GeminiErrorSummary'
}, $true)
. ([scriptblock]::Create($parserFunction.Extent.Text))

$fakeKey = 'AIzaFAKE_KEY_FOR_TEST_ONLY_123456789'
$cases = @(
    @{ Body = '{"error":{"message":"API key not valid"}}'; Expected = 'API key not valid' },
    @{ Body = '[{"error":{"message":"Permission denied"}}]'; Expected = 'Permission denied' },
    @{ Body = '<html><body>Bad request</body></html>'; Expected = 'Bad request' },
    @{ Body = ''; Expected = '(empty response body)' },
    @{ Body = ('{"error":{"message":"Invalid key ' + $fakeKey + '"}}'); Expected = 'Invalid key [REDACTED]' },
    @{ Body = ('not json: ' + $fakeKey); Expected = 'not json: [REDACTED]' },
    @{ Body = 'Denied Bearer fake-token'; Expected = 'Denied Bearer [REDACTED]' },
    @{ Body = (([char]0xFEFF).ToString() + '{"error":{"message":"BOM accepted"}}'); Expected = 'BOM accepted' }
)
foreach ($case in $cases) {
    $actual = Get-GeminiErrorSummary -Body $case.Body -ApiKey $fakeKey
    if ($actual -ne $case.Expected) { throw 'Error parser test failed' }
    if ($actual.Contains($fakeKey)) { throw 'Key was not redacted' }
}
'8 parser tests passed; no API calls or real credentials used.'
