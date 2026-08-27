param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [Parameter(Mandatory = $true)]
    [string]$KeyFile
)

$ErrorActionPreference = 'Stop'
$iterations = 200000
$sealed = [IO.File]::ReadAllBytes($InputPath)
$magic = [Text.Encoding]::ASCII.GetString($sealed, 0, 8)
if ($magic -ne 'Salted__') {
    throw "Unexpected encrypted result header: $magic"
}

$salt = [byte[]]::new(8)
[Array]::Copy($sealed, 8, $salt, 0, 8)
$cipher = [byte[]]::new($sealed.Length - 16)
[Array]::Copy($sealed, 16, $cipher, 0, $cipher.Length)

$passphrase = [IO.File]::ReadAllText($KeyFile).Trim()
$passphraseBytes = [Text.Encoding]::UTF8.GetBytes($passphrase)
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
$decryptor = $aes.CreateDecryptor()
$plain = $decryptor.TransformFinalBlock($cipher, 0, $cipher.Length)
$decryptor.Dispose()
$aes.Dispose()
[IO.File]::WriteAllBytes($OutputPath, $plain)

