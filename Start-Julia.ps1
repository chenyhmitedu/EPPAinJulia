param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$bundled = Join-Path $root '.tools\julia-1.10.12\bin\julia.exe'

if (Test-Path -LiteralPath $bundled) {
    & $bundled --project=$root @Args
    exit $LASTEXITCODE
}

$candidate = (Get-Command julia -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if ($candidate -and $candidate -notlike '*WindowsApps*') {
    & $candidate --project=$root @Args
    exit $LASTEXITCODE
}

throw "Julia was not found. Expected bundled Julia at '$bundled'."
