param(
    [ValidateSet('main','case337','frequency','stability','reference','theory','sensitivity')]
    [string]$Stage = 'main',
    [string]$Rscript,
    [string]$OutputRoot,
    [int]$Seeds = 0,
    [string]$Method = 'all',
    [string]$DataRoot,
    [string]$Dataset,
    [string]$BaseModel = 'elastic_net'
)
$ErrorActionPreference = 'Stop'
$taskCodeRoot = $PSScriptRoot
if (!$DataRoot) { $DataRoot = Join-Path (Split-Path $taskCodeRoot -Parent) 'Real Data' }
if (!$Rscript) {
    $availableR = Get-Command Rscript -ErrorAction SilentlyContinue
    if ($availableR) { $Rscript = $availableR.Source }
    else {
        $availableR = Get-ChildItem -Path "$env:ProgramFiles\R\*\bin\Rscript.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($availableR) { $Rscript = $availableR.FullName }
    }
}
if (!$Rscript -or !(Test-Path -LiteralPath $Rscript -PathType Leaf)) { throw 'Supply an installed Rscript path using -Rscript.' }
if ($Seeds -eq 0) { $Seeds = if ($Stage -eq 'stability') { 1000 } else { 100 } }
if ($Seeds -lt 1) { throw 'Seeds must be positive.' }
if (!$OutputRoot) { $OutputRoot = Join-Path $taskCodeRoot ('runs\batch_' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmss') + '_' + $PID) }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$records = Join-Path $OutputRoot 'records'
New-Item -ItemType Directory -Path $OutputRoot,$records -Force | Out-Null
$jobNumber = 0
function Invoke-RecordedR([string]$Script, [string[]]$Options) {
    $script:jobNumber += 1
    $jobId = '{0:D3}_{1}' -f $script:jobNumber,([IO.Path]::GetFileNameWithoutExtension($Script))
    $arguments = @((Join-Path $taskCodeRoot $Script)) + $Options + @("--runs-root=$records")
    # Windows paths cannot contain quotes; reject them in all arguments rather than construct an ambiguous command line.
    if ($arguments | Where-Object { $_.Contains('"') -or $_.EndsWith('\') }) { throw 'Arguments cannot contain quotes or end with a backslash.' }
    $quoted = @($arguments | ForEach-Object { '"' + $_ + '"' })
    $quoted | Set-Content -LiteralPath (Join-Path $OutputRoot ($jobId + '_arguments.txt')) -Encoding UTF8
    $process = Start-Process -FilePath $Rscript -ArgumentList $quoted -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $OutputRoot ($jobId + '_stdout.log')) `
        -RedirectStandardError (Join-Path $OutputRoot ($jobId + '_stderr.log'))
    [PSCustomObject]@{Job=$jobId; ExitCode=$process.ExitCode; EndedUTC=(Get-Date).ToUniversalTime().ToString('o')} |
        Export-Csv -LiteralPath (Join-Path $OutputRoot ($jobId + '_status.csv')) -NoTypeInformation -Encoding UTF8
    if ($process.ExitCode -ne 0) { throw "R job failed: $jobId. Inspect its logs in $OutputRoot" }
    Write-Output "Completed $jobId"
}
$matrix = @(@('sim_NO','elastic_net'),@('sim1','elastic_net'),@('sim1','random_forest'),
    @('sim2','elastic_net'),@('sim2','random_forest'),@('sim3','elastic_net'),@('sim3','random_forest'),
    @('Concrete','elastic_net'),@('Concrete','random_forest'),@('Diabetes','elastic_net'),
    @('Diabetes','random_forest'),@('WineRed','elastic_net'),@('WineRed','random_forest'))
if ($Dataset) { $matrix = @(,@($Dataset,$BaseModel)) }
switch ($Stage) {
    'main' {
        foreach ($cell in $matrix) {
            Invoke-RecordedR 'conformal_prediction_pipeline.R' @('--stage=main',"--dataset=$($cell[0])","--base-model=$($cell[1])",
                "--method=$Method","--n-seeds=$Seeds","--data-root=$DataRoot","--export-root=$(Join-Path $OutputRoot 'results')")
        }
    }
    'case337' {
        Invoke-RecordedR 'conformal_prediction_pipeline.R' @('--stage=case337','--dataset=Diabetes','--base-model=elastic_net',
            '--method=all',"--data-root=$DataRoot","--export-root=$(Join-Path $OutputRoot 'results')")
    }
    'frequency' {
        Invoke-RecordedR 'conformal_prediction_pipeline.R' @('--stage=frequency','--dataset=Diabetes','--base-model=elastic_net',
            "--method=$Method","--n-seeds=$Seeds","--data-root=$DataRoot","--export-root=$(Join-Path $OutputRoot 'results')")
    }
    'stability' {
        Invoke-RecordedR 'empirical_coverage_stability.R' @('--mode=experiment',"--seed-max=$Seeds","--export-root=$(Join-Path $OutputRoot 'results')")
    }
    'reference' {
        Invoke-RecordedR 'empirical_coverage_stability.R' @('--mode=reference',"--export-root=$(Join-Path $OutputRoot 'results')")
    }
    'theory' {
        Invoke-RecordedR 'theoretical_proof_numerical_integration.R' @('--mode=table',"--export-root=$(Join-Path $OutputRoot 'results')")
    }
    'sensitivity' {
        foreach ($lambda in @('0','0.25','0.5','0.75','1')) {
            foreach ($cell in $matrix) {
                Invoke-RecordedR 'conformal_prediction_pipeline.R' @('--stage=main',"--dataset=$($cell[0])","--base-model=$($cell[1])",
                    '--method=G-DRPI',"--n-seeds=$Seeds","--g-drpi-lambda=$lambda",'--lambda-sensitivity-output=true',
                    "--data-root=$DataRoot","--export-root=$(Join-Path $OutputRoot 'sensitivity')")
            }
        }
    }
}
Write-Output "Batch output: $OutputRoot"
