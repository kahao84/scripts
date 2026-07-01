# for lazy me, to remove history on fixed computer's
#
Remove-Item (Get-PSReadlineOption).HistorySavePath -ErrorAction SilentlyContinue; Clear-History
