$modRoot = "d:\workspace\PZCommunityRank\PZCommunityRank\Contents\mods\PZCommunityRank\42"
$dstRoot  = "F:\Steam\steamapps\workshop\content\108600\3746228308\mods\PZCommunityRank\42"

# client RankMod Lua files
$srcClient = Join-Path $modRoot "media\lua\client\RankMod"
$dstClient = Join-Path $dstRoot "media\lua\client\RankMod"
Get-ChildItem $srcClient -Filter "*.lua" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $dstClient $_.Name) -Force
    Write-Host "  client: $($_.Name)"
}

# shared Sandbox Lua files
$srcShared = Join-Path $modRoot "media\lua\shared\Sandbox"
$dstShared = Join-Path $dstRoot "media\lua\shared\Sandbox"
if (Test-Path $srcShared) {
    if (-not (Test-Path $dstShared)) { New-Item -ItemType Directory -Force $dstShared | Out-Null }
    Get-ChildItem $srcShared -Filter "*.lua" | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $dstShared $_.Name) -Force
        Write-Host "  shared: $($_.Name)"
    }
}

# mod.info (lives inside 42/)
$modInfo = Join-Path $modRoot "mod.info"
$dstInfo = Join-Path $dstRoot "mod.info"
if (Test-Path $modInfo) {
    Copy-Item $modInfo $dstInfo -Force
    Write-Host "  mod.info copiado"
}

Write-Host "Sync concluido (v2.11.0)."
