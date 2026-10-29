# Deploys (or validates with -DryRun) source paths to an org and prints only the failures.
# Usage: .\scripts\deploy-check.ps1 -Org MedCare -Paths force-app [-DryRun] [-TestLevel RunLocalTests]
param(
    [string]$Org = 'MedCare',
    [string[]]$Paths = @('force-app'),
    [switch]$DryRun,
    [string]$TestLevel = 'NoTestRun'
)

$argsList = @('project', 'deploy', 'start', '-o', $Org, '--test-level', $TestLevel, '--wait', '30', '--json')
foreach ($p in $Paths) { $argsList += @('-d', $p) }
if ($DryRun) { $argsList += '--dry-run' }

$raw = & sf @argsList 2>$null | Out-String
$json = $raw | ConvertFrom-Json
$result = $json.result
Write-Output ("Status: {0}  {1}" -f $result.status, $json.message)

foreach ($f in @($result.details.componentFailures)) {
    if ($f) { Write-Output ("{0} {1} L{2}: {3}" -f $f.componentType, $f.fullName, $f.lineNumber, $f.problem) }
}
foreach ($t in @($result.details.runTestResult.failures)) {
    if ($t) { Write-Output ("TEST FAIL {0}.{1}: {2}" -f $t.name, $t.methodName, $t.message) }
}
if ($result.details.runTestResult.numTestsRun) {
    Write-Output ("Tests run: {0}, failures: {1}" -f $result.details.runTestResult.numTestsRun, $result.details.runTestResult.numFailures)
}
