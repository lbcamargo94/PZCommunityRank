$src = "d:\workspace\PZCommunityRank\PZCommunityRank\Contents\mods\PZCommunityRank\42\media\lua\client\RankMod"
$dst = "F:\Steam\steamapps\workshop\content\108600\3746228308\mods\PZCommunityRank\42\media\lua\client\RankMod"

Get-ChildItem $src -Filter "*.lua" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $dst $_.Name) -Force
    Write-Host "  copiado: $($_.Name)"
}
Write-Host "Sync concluido."
