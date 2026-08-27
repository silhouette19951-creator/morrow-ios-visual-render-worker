param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,
    [Parameter(Mandatory = $true)]
    [string]$DestinationRoot,
    [Parameter(Mandatory = $true)]
    [string]$KeyFile
)

$ErrorActionPreference = 'Stop'
$iterations = 200000
$sourceNames = @(
    '01-mist-cathedral',
    '02-pearl-coast',
    '03-rosy-after-rain',
    '04-mirror-salt-moon',
    '05-moonlit-glasshouse'
)

New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $KeyFile) | Out-Null

if (-not (Test-Path -LiteralPath $KeyFile)) {
    $secretBytes = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($secretBytes)
    $secret = [Convert]::ToHexString($secretBytes).ToLowerInvariant()
    [IO.File]::WriteAllText($KeyFile, $secret)
}

$passphrase = [IO.File]::ReadAllText($KeyFile).Trim()
$passphraseBytes = [Text.Encoding]::UTF8.GetBytes($passphrase)

foreach ($name in $sourceNames) {
    $inputPath = Join-Path $SourceRoot "$name\wallpaper-2160x4682.jpg"
    $outputPath = Join-Path $DestinationRoot "$name.jpg.enc"
    if (-not (Test-Path -LiteralPath $inputPath)) {
        throw "Missing source wallpaper: $inputPath"
    }

    $salt = [byte[]]::new(8)
    [Security.Cryptography.RandomNumberGenerator]::Fill($salt)
    $derive = [Security.Cryptography.Rfc2898DeriveBytes]::new(
        $passphraseBytes,
        $salt,
        $iterations,
        [Security.Cryptography.HashAlgorithmName]::SHA256
    )
    $key = $derive.GetBytes(32)
    $iv = $derive.GetBytes(16)
    $derive.Dispose()

    $aes = [Security.Cryptography.Aes]::Create()
    $aes.Mode = [Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $key
    $aes.IV = $iv
    $encryptor = $aes.CreateEncryptor()
    $plain = [IO.File]::ReadAllBytes($inputPath)
    $cipher = $encryptor.TransformFinalBlock($plain, 0, $plain.Length)
    $encryptor.Dispose()
    $aes.Dispose()

    $header = [Text.Encoding]::ASCII.GetBytes('Salted__')
    $sealed = [byte[]]::new($header.Length + $salt.Length + $cipher.Length)
    [Array]::Copy($header, 0, $sealed, 0, $header.Length)
    [Array]::Copy($salt, 0, $sealed, $header.Length, $salt.Length)
    [Array]::Copy($cipher, 0, $sealed, $header.Length + $salt.Length, $cipher.Length)
    [IO.File]::WriteAllBytes($outputPath, $sealed)
}

