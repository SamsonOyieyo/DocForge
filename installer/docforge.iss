; DocForge Windows installer (Inno Setup 6).
;
; Per-user by design: no administrator rights, no UAC prompt, and no writes to
; Program Files or HKLM. DocForge installs under
; %LOCALAPPDATA%\Programs\DocForge and upgrades in place when a newer
; DocForge-Setup-<version>.exe is run (same AppId, UsePreviousAppDir).
;
; CI passes the version from pubspec.yaml:
;   ISCC.exe /DMyAppVersion=1.0.1 installer\docforge.iss
; The fallback below matches lib/core/app_info.dart and pubspec.yaml; run
; `python tool/bump_version.py <version>` to keep all three in sync.
;
; Code signing: unsigned builds trigger the standard Windows SmartScreen
; prompt on first run. Once a certificate is available, configure a SignTool
; in Inno Setup and add `SignTool=<name>` under [Setup].

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#define MyAppName "DocForge"
#define MyAppPublisher "DocForge"
#define MyAppUrl "https://github.com/SamsonOyieyo/DocForge"
#define MyAppExeName "docforge.exe"
#define MyAppId "{{71C59410-7E0D-4353-8320-E26FD906D84D}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppUrl}
AppSupportURL={#MyAppUrl}/issues
AppUpdatesURL={#MyAppUrl}/releases
VersionInfoVersion={#MyAppVersion}.0
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

; Per-user install: never elevates, never needs admin rights.
DefaultDirName={localappdata}\Programs\DocForge
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

; Keep the same AppId so a newer installer upgrades instead of duplicating.
OutputDir=..\dist
OutputBaseFilename=DocForge-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName} {#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=no
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no
AppMutex=DocForge.SingleInstance
SetupMutex=DocForgeSetup
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Installed files are removed by Inno; this clears anything the app added to
; its own program folder (for example staged engine binaries). User settings,
; history and documents live elsewhere and are kept.
Type: filesandordirs; Name: "{app}"
