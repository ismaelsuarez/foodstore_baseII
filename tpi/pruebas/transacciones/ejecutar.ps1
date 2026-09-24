#requires -Version 7.0
<#
Arnés TPI-B: tres experimentos pequeños, sin cambiar lógica productiva.
Requiere laboratorio ya instalado y exclusivo. No crea ni elimina bases.
La coordinación usa respuestas de psql y observación de locks, no demoras fijas.
#>
[CmdletBinding()]
param(
    [ValidateSet('127.0.0.1','localhost')][string]$HostName = '127.0.0.1',
    [ValidateSet(5432)][int]$Port = 5432,
    [ValidatePattern('^[a-zA-Z_][a-zA-Z0-9_]*$')][string]$UserName = 'postgres',
    [ValidateRange(5,120)][int]$TimeoutSeconds = 30
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$psql = (Get-Command psql -CommandType Application -ErrorAction Stop).Source
$database = 'foodstore_tpi_cierre_b'
$runId = [guid]::NewGuid().ToString('N')
$logDirectory = Join-Path ([IO.Path]::GetTempPath()) "foodstore-tpi-b-$runId"
if (Test-Path -LiteralPath $logDirectory) { throw 'Directorio de logs ya existente.' }
$null = New-Item -ItemType Directory -Path $logDirectory
$sessions = [Collections.Generic.List[object]]::new()
$summary = [ordered]@{ status='RUNNING'; database=$database; started_at=[DateTimeOffset]::Now.ToString('o'); logs=$logDirectory }

function Start-Session([string]$Name) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $psql
    $info.WorkingDirectory = $PSScriptRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($arg in @('-X','-w','-qAt','-h',$HostName,'-p',"$Port",'-U',$UserName,'-d',$database,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose')) {
        $info.ArgumentList.Add($arg)
    }
    $info.Environment['PGAPPNAME'] = "tpi_b_${runId}_$Name"
    $info.Environment['PGCLIENTENCODING'] = 'UTF8'
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { throw "No se pudo iniciar $Name" }
    $session = [pscustomobject]@{
        Name=$Name; Process=$process; ErrorTask=$process.StandardError.ReadToEndAsync()
        Output=[Collections.Generic.List[string]]::new(); Input=[Collections.Generic.List[string]]::new()
        Pid=0; Closed=$false; ExitCode=$null; ErrorText=''
    }
    $sessions.Add($session)
    $startup = Invoke-Block $session "SELECT 'PID=' || pg_backend_pid();"
    $session.Pid = [int]([regex]::Match($startup,'(?m)^PID=(\d+)$').Groups[1].Value)
    if ($session.Pid -le 0) { throw "PID inválido de $Name" }
    return $session
}

function Send-Block($Session,[string]$Sql) {
    if ($Session.Process.HasExited) { throw "Sesión $($Session.Name) terminó prematuramente." }
    $marker = "TPI_B_END_$([guid]::NewGuid().ToString('N'))"
    $Session.Input.Add($Sql)
    $Session.Process.StandardInput.WriteLine($Sql)
    $Session.Process.StandardInput.WriteLine("\echo $marker")
    $Session.Process.StandardInput.Flush()
    return $marker
}

function Receive-Block($Session,[string]$Marker) {
    $lines = [Collections.Generic.List[string]]::new()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $remaining = [int]($TimeoutSeconds*1000 - $clock.ElapsedMilliseconds)
        if ($remaining -le 0) { throw "Timeout esperando $($Session.Name)." }
        $task = $Session.Process.StandardOutput.ReadLineAsync()
        if (-not $task.Wait($remaining)) { throw "Timeout de salida de $($Session.Name)." }
        $line = $task.Result
        if ($null -eq $line) { throw "EOF inesperado en $($Session.Name); revisar stderr." }
        $Session.Output.Add($line)
        if ($line -eq $Marker) { break }
        $lines.Add($line)
    }
    return ($lines -join "`n")
}

function Invoke-Block($Session,[string]$Sql) {
    $marker = Send-Block $Session $Sql
    return Receive-Block $Session $marker
}

function Read-Sql([string]$Name) {
    return [IO.File]::ReadAllText((Join-Path $PSScriptRoot $Name))
}

function Get-Blocks([string]$Name) {
    return [regex]::Split((Read-Sql $Name),'(?m)^-- BARRIER --\r?$')
}

function Assert-Line([string]$Output,[string]$Expected) {
    if ($Expected -notin ($Output -split '\r?\n')) { throw "Resultado ausente: $Expected. Salida: $Output" }
}

function Close-Session($Session,[int]$ExpectedExit=0) {
    if (-not $Session.Process.HasExited) { $Session.Process.StandardInput.Close() }
    if (-not $Session.Process.WaitForExit($TimeoutSeconds*1000)) { throw "Timeout al cerrar $($Session.Name)." }
    $remaining = $Session.Process.StandardOutput.ReadToEnd()
    if ($remaining) { $Session.Output.Add($remaining) }
    $Session.ErrorText = $Session.ErrorTask.GetAwaiter().GetResult()
    $Session.ExitCode = $Session.Process.ExitCode
    $Session.Closed = $true
    if ($Session.ExitCode -ne $ExpectedExit) { throw "Exit inesperado de $($Session.Name): $($Session.ExitCode). $($Session.ErrorText)" }
    if ($ExpectedExit -eq 0 -and $Session.ErrorText -match '(?m)(ERROR|FATAL|PANIC):') {
        throw "Error SQL inesperado en $($Session.Name): $($Session.ErrorText)"
    }
}

function Get-Audit($Session) {
    $raw = Invoke-Block $Session (Read-Sql 'auditoria.sql')
    return ($raw | ConvertFrom-Json)
}

function Assert-Audit($Audit) {
    if ($Audit.database -ne $database -or $Audit.stock -ne 50) { throw 'Base o stock final incorrectos.' }
    $expected = @{ categoria=2; usuario=3; producto=3; pedido=5; detalle_pedido=7 }
    foreach ($name in $expected.Keys) {
        if ($Audit.counts.$name -ne $expected[$name]) { throw "Conteo incorrecto: $name" }
    }
    $catalogExpected = @{ tables=5; pk=5; fk=4; checks=6; unique=3; unvalidated=0 }
    foreach ($name in $catalogExpected.Keys) {
        if ($Audit.catalog_counts.$name -ne $catalogExpected[$name]) { throw "Catálogo incorrecto: $name" }
    }
    foreach ($name in @('subtotal_errors','total_errors','fk_errors','unique_errors','check_errors','null_errors')) {
        if ($Audit.$name -ne 0) { throw "Integridad fallida: $name=$($Audit.$name)" }
    }
    if ($Audit.routines -ne 7 -or $Audit.triggers -ne 5) { throw 'Inventario de objetos incorrecto.' }
}

function Restore-Stock($Session,[int]$Expected) {
    # Solo después del cierre de ambos actores y si el valor comprometido es el previsto.
    $sql = @'
BEGIN;
DO $$
DECLARE v_stock integer;
BEGIN
 IF current_database() <> 'foodstore_tpi_cierre_b' THEN RAISE EXCEPTION 'Base incorrecta'; END IF;
 SELECT stock INTO STRICT v_stock FROM public.producto WHERE id=1 FOR UPDATE;
 IF v_stock <> __EXPECTED__ THEN RAISE EXCEPTION 'No restaurar stock inesperado: %',v_stock; END IF;
 UPDATE public.producto SET stock=50 WHERE id=1;
END;
$$;
COMMIT;
SELECT 'RESTORED=' || stock FROM public.producto WHERE id=1;
'@
    $output = Invoke-Block $Session $sql.Replace('__EXPECTED__',"$Expected")
    Assert-Line $output 'RESTORED=50'
    return $output
}

try {
    $control = Start-Session 'control'
    $null = Invoke-Block $control (Read-Sql 'guard.sql')
    $others = Invoke-Block $control "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid();"
    if ([int]$others -ne 0) { throw 'El laboratorio no es exclusivo; hay otras conexiones.' }
    $before = Get-Audit $control
    Assert-Audit $before
    $summary.before = $before

    $save = Start-Session 'savepoint'
    $saveResult = Invoke-Block $save (Read-Sql 'savepoint.sql')
    foreach ($expected in @('BEFORE=50','AFTER_FIRST_CHANGE=49','AFTER_SECOND_CHANGE=47','AFTER_ROLLBACK_TO_SAVEPOINT=49','FINAL=50')) {
        Assert-Line $saveResult $expected
    }
    Close-Session $save
    $summary.savepoint = @{ status='PASS'; output=$saveResult }

    $rrA = Start-Session 'rr_a'
    $rrB = Start-Session 'rr_b'
    $rrBlocks = Get-Blocks 'rr_a.sql'
    $rrFirst = Invoke-Block $rrA $rrBlocks[0]
    Assert-Line $rrFirst 'RR_A_ISOLATION=repeatable read'
    Assert-Line $rrFirst 'A_READ_1=50'
    $rrBResult = Invoke-Block $rrB (Read-Sql 'rr_b.sql')
    Assert-Line $rrBResult 'RR_B_ISOLATION=read committed'
    Assert-Line $rrBResult 'B_BEFORE=50'
    Assert-Line $rrBResult 'B_AFTER_COMMIT=51'
    Close-Session $rrB
    $rrLast = Invoke-Block $rrA $rrBlocks[1]
    Assert-Line $rrLast 'A_READ_2=50'
    Assert-Line $rrLast 'AFTER_A_NEW_TRANSACTION=51'
    Close-Session $rrA
    $rrRestore = Restore-Stock $control 51
    $summary.repeatable_read = @{ status='PASS'; a_first=$rrFirst; b=$rrBResult; a_last=$rrLast; restoration=$rrRestore }

    $serialA = Start-Session 'serial_a'
    $serialB = Start-Session 'serial_b'
    $aBlocks = Get-Blocks 'serial_a.sql'
    $bBlocks = Get-Blocks 'serial_b.sql'
    $serialAFirst = Invoke-Block $serialA $aBlocks[0]
    $serialBFirst = Invoke-Block $serialB $bBlocks[0]
    Assert-Line $serialAFirst 'SERIAL_A_ISOLATION=serializable'
    Assert-Line $serialBFirst 'SERIAL_B_ISOLATION=serializable'
    Assert-Line $serialAFirst 'SERIAL_A_READ=50'
    Assert-Line $serialBFirst 'SERIAL_B_READ=50'
    $serialAWrite = Invoke-Block $serialA $aBlocks[1]
    Assert-Line $serialAWrite 'SERIAL_A_UNCOMMITTED=52'
    # No se espera un marcador de B: ON_ERROR_STOP debe terminar psql con exit 3.
    $null = Send-Block $serialB $bBlocks[1]
    $monitorSql = @'
SELECT json_build_object(
 'observed_at',clock_timestamp(),
 'a', (SELECT row_to_json(x) FROM (SELECT pid,state,wait_event_type,wait_event,xact_start FROM pg_stat_activity WHERE pid=__A__) x),
 'b', (SELECT row_to_json(x) FROM (SELECT pid,state,wait_event_type,wait_event,xact_start,pg_blocking_pids(pid) AS blockers FROM pg_stat_activity WHERE pid=__B__) x),
 'locks', (SELECT json_agg(x) FROM (SELECT pid,locktype,mode,granted,transactionid::text,relation::regclass::text,page,tuple FROM pg_locks WHERE pid IN (__A__,__B__) ORDER BY pid,locktype,mode) x)
);
'@
    $monitorSql = $monitorSql.Replace('__A__',"$($serialA.Pid)").Replace('__B__',"$($serialB.Pid)")
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $blocked = $false
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if ($serialB.Process.HasExited) { throw 'B terminó antes de observar el bloqueo esperado.' }
        $observation = (Invoke-Block $control $monitorSql) | ConvertFrom-Json
        if ($null -ne $observation.b -and $observation.b.wait_event_type -eq 'Lock' -and
            $observation.b.wait_event -eq 'transactionid' -and $serialA.Pid -in $observation.b.blockers) {
            $waitingLock = @($observation.locks | Where-Object { $_.pid -eq $serialB.Pid -and $_.locktype -eq 'transactionid' -and -not $_.granted })
            if ($waitingLock.Count -gt 0) { $blocked=$true; break }
        }
        Start-Sleep -Milliseconds 50 # Intervalo de sondeo; nunca prueba por sí solo el intercalado.
    }
    if (-not $blocked) { throw 'No se acreditó el bloqueo de B por A.' }
    $serialAFinal = Invoke-Block $serialA $aBlocks[2]
    Assert-Line $serialAFinal 'SERIAL_A_COMMITTED=52'
    Close-Session $serialA
    Close-Session $serialB 3
    $states = @([regex]::Matches($serialB.ErrorText,'(?m)ERROR:\s+([0-9A-Z]{5}):') | ForEach-Object { $_.Groups[1].Value })
    if ($states.Count -ne 1 -or $states[0] -ne '40001' -or
        $serialB.ErrorText -match '40P01|(?m)(FATAL|PANIC):') {
        throw "No fue exactamente el conflicto 40001 esperado: $($serialB.ErrorText)"
    }
    $serialFinal = Invoke-Block $control "SELECT 'SERIAL_FINAL=' || stock FROM public.producto WHERE id=1;"
    Assert-Line $serialFinal 'SERIAL_FINAL=52'
    $serialRestore = Restore-Stock $control 52
    $summary.serializable = @{
        status='PASS'; winner='A'; aborted='B'; sqlstate=$states[0]; a_first=$serialAFirst; b_first=$serialBFirst
        a_write=$serialAWrite; a_commit=$serialAFinal; final=$serialFinal; b_exit=$serialB.ExitCode
        b_stderr=$serialB.ErrorText; blocked_observation=$observation; restoration=$serialRestore
    }

    $null = Invoke-Block $control (Read-Sql 'guard.sql')
    $after = Get-Audit $control
    Assert-Audit $after
    foreach ($name in @('data_fingerprints','sequences','catalog_fingerprint')) {
        if (($before.$name | ConvertTo-Json -Depth 12 -Compress) -cne ($after.$name | ConvertTo-Json -Depth 12 -Compress)) {
            throw "Estado final diferente: $name"
        }
    }
    $remaining = Invoke-Block $control "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid();"
    if ([int]$remaining -ne 0) { throw 'Quedan sesiones inesperadas en el laboratorio.' }
    $summary.after = $after
    $summary.remaining_test_sessions = [int]$remaining
    Close-Session $control
    $summary.status = 'PASS'
    $summary.database_status = 'PRESERVED'
}
catch {
    $summary.status = 'FAIL'
    $summary.error = $_.Exception.Message
    $summary.database_status = 'PRESERVED_FOR_DIAGNOSIS'
    # No restaurar valores automáticamente tras un fallo no clasificado.
    throw
}
finally {
    foreach ($session in $sessions) {
        if (-not $session.Closed) {
            try {
                # Solo procesos propios. La desconexión revierte transacciones pendientes.
                if (-not $session.Process.HasExited) { $session.Process.Kill() }
                $session.Process.WaitForExit()
                $session.ErrorText = $session.ErrorTask.GetAwaiter().GetResult()
                $session.ExitCode = $session.Process.ExitCode
            } catch { $session.ErrorText += "`nError de cierre del proceso propio: $($_.Exception.Message)" }
        }
        [IO.File]::WriteAllText((Join-Path $logDirectory "$($session.Name).stdout.txt"),($session.Output -join "`n"))
        [IO.File]::WriteAllText((Join-Path $logDirectory "$($session.Name).stderr.txt"),$session.ErrorText)
        [IO.File]::WriteAllText((Join-Path $logDirectory "$($session.Name).sql"),($session.Input -join "`n"))
    }
    $summary.sessions = @($sessions | ForEach-Object { @{name=$_.Name; pid=$_.Pid; exit_code=$_.ExitCode} })
    $summary.finished_at = [DateTimeOffset]::Now.ToString('o')
    [IO.File]::WriteAllText((Join-Path $logDirectory 'summary.json'),($summary | ConvertTo-Json -Depth 20))
    Write-Host "TPI_B_STATUS=$($summary.status)"
    Write-Host "TPI_B_LOG_DIRECTORY=$logDirectory"
}
