# Levanta el backend y un tunel publico, y comprueba que la ruta del webhook
# sea alcanzable desde internet. Todo se apaga al terminar.
$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
$env:PYTHONPATH = Join-Path $raiz "backend"

# Tras instalar, el PATH de la sesion actual puede seguir desactualizado, asi
# que se busca el ejecutable en disco antes de asumir el comando.
$cmdTunel = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cmdTunel) { $exeTunel = $cmdTunel.Source }
else {
    $candidatos = @(
        "C:\Program Files (x86)\cloudflared\cloudflared.exe",
        "C:\Program Files\cloudflared\cloudflared.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\cloudflared.exe"
    )
    $encontrado = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (!$encontrado) {
        "No se encontro cloudflared. Instalalo con:"
        "  winget install --id Cloudflare.cloudflared --exact"
        exit 1
    }
    $exeTunel = $encontrado
}
"   cloudflared: $exeTunel"

$logUvicorn = Join-Path $env:TEMP "opencode\uvicorn_tunel.log"
$logUvicornErr = Join-Path $env:TEMP "opencode\uvicorn_tunel.err.log"
$logTunel = Join-Path $env:TEMP "opencode\cloudflared.log"
$logTunelErr = Join-Path $env:TEMP "opencode\cloudflared.err.log"
$procUvicorn = $null
$procTunel = $null

function Cerrar {
    if ($procUvicorn -and !$procUvicorn.HasExited) { Stop-Process -Id $procUvicorn.Id -Force -ErrorAction SilentlyContinue }
    if ($procTunel -and !$procTunel.HasExited) { Stop-Process -Id $procTunel.Id -Force -ErrorAction SilentlyContinue }
}
try {
    # El 8000 suele estar tomado (Docker, WSL, un uvicorn de la sesion anterior).
    # Si el puerto esta ocupado, uvicorn no puede tomar nada y aun asi el chequeo
    # de "esta vivo" da 200, porque responde la app ajena que lo ocupa. Por eso
    # se exige un puerto libre y despues se verifica que la ruta del webhook
    # responda 400, que es lo unico que distingue nuestra app de otra.
    $puerto = 8020
    for ($intento = 0; $intento -lt 12; $intento++) {
        $ocupado = Get-NetTCPConnection -LocalPort $puerto -State Listen -ErrorAction SilentlyContinue
        if (!$ocupado) { break }
        $puerto++
    }
    if (Get-NetTCPConnection -LocalPort $puerto -State Listen -ErrorAction SilentlyContinue) {
        "   No hay ningun puerto libre desde 8020. Cierra las apps que esten escuchando."
        exit 1
    }

    "1. Levantando el backend en el puerto $puerto..."
    $procUvicorn = Start-Process -FilePath "python" `
        -ArgumentList "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "$puerto" `
        -WorkingDirectory (Join-Path $raiz "backend") -PassThru `
        -RedirectStandardOutput $logUvicorn -RedirectStandardError $logUvicornErr -WindowStyle Hidden

    $listo = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 500
        $sondeo = & curl.exe -s -o NUL -w "%{http_code}" --max-time 3 "http://127.0.0.1:$puerto/api/v1/pagos/webhook/qr" 2>$null
        # 400 = nuestra app,respondio y pedio referencia. Un 404 significaria
        # que hay otra aplicacion ocupando el puerto.
        if ($sondeo -eq "400") { $listo = $true; break }
    }
    if (!$listo) {
        "   El backend no respondio en el puerto $puerto. Log:"
        Get-Content $logUvicornErr -Tail 20 -ErrorAction SilentlyContinue
        exit 1
    }
    "   Backend OK (respondio 400 en /api/v1/pagos/webhook/qr, puerto $puerto)"

    "2. Levantando el tunel publico con cloudflared..."
    $procTunel = Start-Process -FilePath $exeTunel `
        -ArgumentList "tunnel", "--url", "http://localhost:$puerto", "--no-autoupdate" `
        -PassThru -RedirectStandardOutput $logTunel -RedirectStandardError $logTunelErr -WindowStyle Hidden

    $url = $null
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 1000
        # cloudflared escribe toda su salida por stderr, no por stdout: buscar la
        # URL solo en stdout la devuelve como 0 bytes y el tunel parece caido.
        foreach ($log in @($logTunel, $logTunelErr)) {
            if (Test-Path $log) {
                $m = Select-String -Path $log -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" -ErrorAction SilentlyContinue |
                     Select-Object -First 1
                if ($m) { $url = $m.Matches[0].Value; break }
            }
        }
        if ($url) { break }
        if ($procTunel.HasExited) { break }
    }
    if (!$url) {
        "   No se obtuvo URL publica. Log:"
        Get-Content $logTunelErr -Tail 25 -ErrorAction SilentlyContinue
        exit 1
    }
    "   Tunel: $url"

    "3. Esperando que el dominio del tunel se resuelva por DNS..."
    $nombre = ([uri]$url).Host
    $resuelve = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 2
        if (Resolve-DnsName $nombre -Type A -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress } | Select-Object -First 1) {
            $resuelve = $true
            break
        }
    }
    if (!$resuelve) {
        "   $nombre no resuelve. Puede ser que la red local bloquee el dominio;"
        "   proba con otro tunel (ngrok, localtunnel) antes de seguir."
        exit 1
    }
    "   $nombre resuelve"

    # curl.exe se usa porque en PowerShell 5.1 un 400 o 404 lanza excepcion y
    # `Invoke-WebRequest` no devuelve el codigo, que es justo lo que se quiere ver.
    function Sondear($destino) {
        $salida = & curl.exe -s -o - -w "`n%{http_code}" --max-time 25 $destino 2>$null
        $lineas = $salida -split "`n"
        $codigo = $lineas[-1].Trim()
        $cuerpo = ($lineas[0..($lineas.Length - 2)] -join "`n")
        return @{ Codigo = $codigo; Cuerpo = $cuerpo }
    }

    "4. Probando la ruta del webhook desde internet..."
    $r = Sondear "$url/api/v1/pagos/webhook/qr"
    "   GET /api/v1/pagos/webhook/qr -> $($r.Codigo)  $($r.Cuerpo.Substring(0, [Math]::Min(80, $r.Cuerpo.Length)))"

    "5. Probando una notificacion falsificada (no debe aprobar nada)..."
    $r2 = Sondear "$url/api/v1/pagos/webhook/qr?transaction_id=TXN-INVENTADO"
    "   GET ?transaction_id=TXN-INVENTADO -> $($r2.Codigo)  $($r2.Cuerpo)"

    ""
    "RESULTADO"
    if ($r.Codigo -eq "400") { "  [OK] La ruta del webhook es alcanzable desde internet y responde 400 sin referencia" }
    else { "  [AVISO] Se esperaba 400 en la sonda, llego $($r.Codigo)" }
    if ($r2.Codigo -eq "404") { "  [OK] Una transaccion inventada da 404: no existe ningun cobro que aprobar" }
    else { "  [AVISO] Se esperaba 404 para una transaccion inexistente, llego $($r2.Codigo)" }

    ""
    "  Copia esto en backend/.env:"
    "  QR_CALLBACK_BASE=$url"
}
finally {
    Cerrar
}
