# Runs all local Apex tests with coverage and prints a compact summary.
# Usage: .\scripts\run-tests.ps1 [-Org MedCare]
param([string]$Org = 'MedCare')

$raw = & sf apex run test -o $Org --test-level RunLocalTests --code-coverage --result-format json --wait 30 2>$null | Out-String
$result = ($raw | ConvertFrom-Json).result

$s = $result.summary
Write-Output ("Outcome: {0} | ran {1} | passed {2} | failed {3} | org-wide coverage {4}" -f $s.outcome, $s.testsRan, $s.passing, $s.failing, $s.orgWideCoverage)

foreach ($t in $result.tests | Where-Object { $_.Outcome -ne 'Pass' }) {
    $firstLine = ($t.StackTrace -split "`n")[0]
    Write-Output ("FAIL {0}: {1} @ {2}" -f $t.FullName, ($t.Message -replace "`n", ' '), $firstLine)
}

Write-Output ''
Write-Output 'Coverage by class:'
$result.coverage.coverage | Sort-Object name | ForEach-Object {
    Write-Output ("  {0,-32} {1,4}%" -f $_.name, $_.coveredPercent)
}
