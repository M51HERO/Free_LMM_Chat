# Run once from the project root (PowerShell): .\tool\setup.ps1
$ErrorActionPreference = 'Stop'

# 1. Generate only the platform folders; keep our lib/ and pubspec.yaml.
$bak = Join-Path $env:TEMP 'free_llm_chat_bak'
if (Test-Path $bak) { Remove-Item $bak -Recurse -Force }
New-Item $bak -ItemType Directory | Out-Null
Copy-Item lib -Destination $bak -Recurse
Copy-Item pubspec.yaml -Destination $bak
flutter create --platforms=windows,android --org com.example.freellmchat --project-name free_llm_chat .
Remove-Item lib -Recurse -Force
Copy-Item (Join-Path $bak 'lib') -Destination . -Recurse
Copy-Item (Join-Path $bak 'pubspec.yaml') -Destination . -Force
# flutter create adds a default widget_test.dart that references a missing MyApp: drop only that file.
Remove-Item (Join-Path 'test' 'widget_test.dart') -Force -ErrorAction SilentlyContinue

# 2. Android: INTERNET permission for release builds.
$manifest = 'android\app\src\main\AndroidManifest.xml'
$t = Get-Content $manifest -Raw
if ($t -notmatch 'android.permission.INTERNET') {
  $perm = '<uses-permission android:name="android.permission.INTERNET"/>'
  $t = $t -replace '<application', ($perm + "`n    <application")
  Set-Content $manifest $t -NoNewline
}

# 2b. Android 9+ blocks plain http by default; allow it so a Manifest on your LAN (http://192.168.x.x:2099) works.
$t = Get-Content $manifest -Raw
if ($t -notmatch 'usesCleartextTraffic') {
  $t = $t -replace '<application', '<application android:usesCleartextTraffic="true"'
  Set-Content $manifest $t -NoNewline
}

# 3. Android: flutter_secure_storage needs minSdk 23.
foreach ($g in 'android\app\build.gradle.kts', 'android\app\build.gradle') {
  if (Test-Path $g) {
    $c = Get-Content $g -Raw
    if ($c -match 'maxOf\(23|Math\.max\(23') { continue }
    if ($g -like '*.kts') { $min = 'maxOf(23, flutter.minSdkVersion)' } else { $min = 'Math.max(23, flutter.minSdkVersion)' }
    $c = $c.Replace('flutter.minSdkVersion', $min)
    Set-Content $g $c -NoNewline
  }
}

flutter pub get
Write-Host 'Setup complete.'
