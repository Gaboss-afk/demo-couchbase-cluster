param(
    [string]$ClusterUrl = "http://localhost:8093/query/service",
    [string]$Bucket = "demo-bucket",
    [string]$Username = "Admin",
    [string]$Password = "Admin1"
)

$ErrorActionPreference = "Stop"

if ($Bucket -notmatch "^[A-Za-z0-9_-]+$") {
    throw "El nombre del bucket contiene caracteres no permitidos: $Bucket"
}

$dataPath = Join-Path $PSScriptRoot "data\productos.json"
if (-not (Test-Path -LiteralPath $dataPath)) {
    throw "No se encontró el archivo de datos: $dataPath"
}

$documents = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8)
if ($documents.Count -eq 0) {
    throw "El archivo de datos no contiene documentos."
}

$credentialBytes = [Text.Encoding]::UTF8.GetBytes("${Username}:${Password}")
$authorization = [Convert]::ToBase64String($credentialBytes)
$headers = @{
    Authorization = "Basic $authorization"
    Accept        = "application/json"
}

$statement = "UPSERT INTO ``$Bucket`` (KEY, VALUE) VALUES (`$docId, `$doc)"
$processedCount = 0
foreach ($document in $documents) {
    if ([string]::IsNullOrWhiteSpace($document.id)) {
        throw "Cada documento debe tener un campo 'id' no vacío."
    }

    $requestBodyJson = @{
        statement = $statement
        '$docId'  = [string]$document.id
        '$doc'    = $document
    } | ConvertTo-Json -Depth 100 -Compress
    $requestBody = [Text.Encoding]::UTF8.GetBytes($requestBodyJson)

    $response = Invoke-RestMethod `
        -Uri $ClusterUrl `
        -Method Post `
        -Headers $headers `
        -ContentType "application/json; charset=utf-8" `
        -Body $requestBody

    if ($response.errors -and @($response.errors).Count -gt 0) {
        throw "Couchbase no pudo insertar '$($document.id)': $($response.errors | ConvertTo-Json -Compress)"
    }

    $processedCount++
    if ($processedCount % 100 -eq 0) {
        Write-Host "Procesados $processedCount de $($documents.Count) productos..."
    }
}

Write-Host "Carga finalizada: $($documents.Count) documentos en el bucket '$Bucket'."
