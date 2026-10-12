#ifndef AppVersion
  #error AppVersion must be passed by package-windows.ps1
#endif

[Setup]
AppId={{B0919F84-CA67-47DD-89F4-B0326B803C54}
AppName=轻贴
AppVersion={#AppVersion}
AppPublisher=Lan Clip
AppPublisherURL=https://github.com/yyyzl/lan-clip
DefaultDirName={localappdata}\Programs\Lan Clip
DefaultGroupName=轻贴
DisableProgramGroupPage=yes
DisableWelcomePage=no
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
AppMutex=Local\LanClipReceiver
SetupMutex=Local\LanClipSetup
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\lan_clip.exe
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir={#OutputDir}
OutputBaseFilename=Lan-Clip-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
chinesesimp.AppRunningError=轻贴仍在后台运行。%n%n请从右下角托盘菜单选择「退出轻贴」，然后继续。

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\轻贴"; Filename: "{app}\lan_clip.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\轻贴"; Filename: "{app}\lan_clip.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\lan_clip.exe"; Description: "{cm:LaunchProgram,轻贴}"; Flags: nowait postinstall skipifsilent

; Settings and pairing credentials live outside {app}; never remove them on upgrade or uninstall.
