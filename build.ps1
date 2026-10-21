# Build with Windows PowerShell 5.1 and the .NET Framework compiler included in Windows.
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '找不到 Windows 自带的 .NET Framework 编译器。' }
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw '请使用 Windows PowerShell 5.1 运行 build.ps1。' }
$output = Join-Path $PSScriptRoot 'ClaudeLauncher.exe'
$iconPath = Join-Path $PSScriptRoot 'launcher.ico'
$iconSource = Join-Path $PSScriptRoot 'assets/launcher-character.png'
foreach ($path in @($output,$iconPath)) {
    if (Test-Path -LiteralPath $path) {
        Copy-Item -LiteralPath $path -Destination ($path + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    }
}

Add-Type -AssemblyName System.Drawing
if (Test-Path -LiteralPath $iconSource -PathType Leaf) {
    $sizes=@(16,20,24,32,40,48,64,96,256)
    $images=New-Object 'System.Collections.Generic.List[byte[]]'
    $source=[Drawing.Image]::FromFile($iconSource)
    try {
        foreach ($size in $sizes) {
            $bitmap=New-Object Drawing.Bitmap $size,$size
            $graphics=[Drawing.Graphics]::FromImage($bitmap)
            $png=New-Object IO.MemoryStream
            try {
                $graphics.CompositingMode=[Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.DrawImage($source,0,0,$size,$size)
                $bitmap.Save($png,[Drawing.Imaging.ImageFormat]::Png)
                $images.Add($png.ToArray())
            } finally {$png.Dispose();$graphics.Dispose();$bitmap.Dispose()}
        }
    } finally {$source.Dispose()}
    $writer=New-Object IO.BinaryWriter ([IO.File]::Create($iconPath))
    try {
        $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$sizes.Count)
        $offset=6+16*$sizes.Count
        for ($index=0;$index -lt $sizes.Count;$index++) {
            $dimension=if($sizes[$index] -eq 256){0}else{$sizes[$index]}
            $writer.Write([byte]$dimension);$writer.Write([byte]$dimension)
            $writer.Write([byte]0);$writer.Write([byte]0)
            $writer.Write([uint16]1);$writer.Write([uint16]32)
            $writer.Write([uint32]$images[$index].Length);$writer.Write([uint32]$offset)
            $offset+=$images[$index].Length
        }
        foreach ($bytes in $images) {$writer.Write($bytes)}
    } finally {$writer.Dispose()}
} else {
    $stream=[IO.File]::Create($iconPath)
    try {[Drawing.SystemIcons]::Application.Save($stream)} finally {$stream.Dispose()}
}

$compilerArgs = @(
    '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', '/utf8output',
    ('/out:' + $output),
    ('/win32icon:' + $iconPath),
    ('/win32manifest:' + (Join-Path $PSScriptRoot 'launcher/app.manifest')),
    ('/reference:' + [Management.Automation.PowerShell].Assembly.Location),
    '/reference:System.Windows.Forms.dll',
    (Join-Path $PSScriptRoot 'launcher/Launcher.cs'),
    (Join-Path $PSScriptRoot 'launcher/TaskbarIdentity.cs')
)
& $compiler @compilerArgs
if ($LASTEXITCODE -ne 0) { throw ('编译失败，退出码 ' + $LASTEXITCODE) }
Write-Output ('已生成：' + $output)
