; FluxDM — Windows Setup Wizard Installer Script (Inno Setup 6)
; Opens directly on a branded Welcome Wizard screen (classic Back/Next/Cancel),
; lets the user pick ANY installation folder, creates shortcuts & uninstaller.

#define MyAppName "FluxDM"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "FluxDM"
#define MyAppExeName "FluxDM.exe"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{8F6C4A2E-9D1B-4E7A-A3F1-6C8E2B4D9A10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes

; Open directly into the Welcome to the FluxDM Setup Wizard screen (like Go/MSI setup)
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=auto
DisableReadyPage=no
ShowLanguageDialog=no
PrivilegesRequired=admin

; Custom FluxDM dark sidebar & top-right header badge
WizardStyle=classic
WizardImageFile=wizard_sidebar.bmp
WizardSmallImageFile=wizard_small.bmp
WizardImageStretch=yes
WizardImageBackColor=$070F0C
LicenseFile=LICENSE.txt

OutputDir=output
OutputBaseFilename=FluxDM-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName} {#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
SetupWindowTitle={#MyAppName} {#MyAppVersion} Setup
WelcomeLabel1=Welcome to the {#MyAppName} {#MyAppVersion} Setup Wizard
WelcomeLabel2=The Setup Wizard will install {#MyAppName} {#MyAppVersion} on your computer. You can choose any destination folder and optional shortcuts on the next screens.%n%nClick Next to continue, or Cancel to exit the Setup Wizard.
FinishedHeadingLabel=Completed the {#MyAppName} {#MyAppVersion} Setup Wizard
FinishedLabel=Setup has finished installing {#MyAppName} on your computer. The application may be launched by selecting the installed shortcuts.

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"
Name: "startup"; Description: "Launch {#MyAppName} automatically when Windows starts"; GroupDescription: "Startup:"

[Files]
; Core Flutter Windows Release bundle (FluxDM.exe, dm_engine.exe, DLLs, data/)
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Browser extension folder (for Chrome / Edge / Brave integration)
Source: "..\browser_extension\*"; DestDir: "{app}\browser_extension"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "taskkill"; Parameters: "/F /IM dm_engine.exe"; Flags: runhidden; RunOnceId: "KillGoEngine"
Filename: "taskkill"; Parameters: "/F /IM {#MyAppExeName}"; Flags: runhidden; RunOnceId: "KillFluxDM"

[Code]
procedure StopRunningFluxDM();
var
  ResultCode: Integer;
begin
  Exec('taskkill', '/F /IM dm_engine.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/F /IM FluxDM.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopRunningFluxDM();
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  StopRunningFluxDM();
  Result := True;
end;
