; OpenLucid desktop app: Windows installer (Inno Setup 6).
;
; Built by .github/workflows/release.yml. By hand:
;   iscc /DAppVersion=0.4.0+5 ^
;        /DSourceDir=..\..\build\windows\x64\runner\Release ^
;        /DOutputDir=..\..\dist windows\installer\openlucid.iss
;
; Installs per user into %LOCALAPPDATA%\Programs\OpenLucid, without admin rights.
; That folder must stay user-writable: the in-app updater (desktop_updater)
; replaces files in the install folder itself. Never install to Program Files.

#ifndef AppVersion
  #error Pass /DAppVersion=X.Y.Z+N
#endif
#ifndef SourceDir
  #error Pass /DSourceDir=<flutter build output folder>
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

#define AppName "OpenLucid"
#define AppExe "openlucid.exe"
; Windows file versions are numeric only: 0.4.0+5 -> 0.4.0.5
#define NumericVersion StringChange(AppVersion, "+", ".")

[Setup]
; Never change AppId: Windows uses it to recognise upgrades and the uninstaller.
AppId={{6E9F2C2B-6E36-4C3A-9C0F-7C9B7A6B5A4D}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=OpenLucid
AppPublisherURL=https://openlucid.nl
VersionInfoVersion={#NumericVersion}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=
DefaultDirName={localappdata}\Programs\{#AppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
UsePreviousAppDir=yes
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
SetupIconFile=..\runner\resources\app_icon.ico
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Close a running OpenLucid before upgrading, and start it again afterwards.
CloseApplications=yes
RestartApplications=no
OutputDir={#OutputDir}
OutputBaseFilename=OpenLucid-Setup-{#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; WorkingDir matters: the auto-updater uses paths relative to it.
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Files the in-app updater added after installation.
Type: filesandordirs; Name: "{app}"
