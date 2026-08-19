$f = 'c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\screens\workout_details_screen.dart'
$lines = [System.IO.File]::ReadAllLines($f)
Write-Output ("Total: " + $lines.Count)
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^class _' -or $lines[$i] -match '^}' -or $lines[$i] -match 'Widget _equipmentLabel') {
    Write-Output ("{0,5}: {1}" -f ($i+1), $lines[$i])
  }
}
