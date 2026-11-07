; FixPrinter Setup - Inno Setup script
; Build: ISCC.exe /DAppVersion=13.4.0 FixPrinter.iss
; Output: dist\FixPrinter-Setup-<version>.exe  (silent-capable: /VERYSILENT)

#ifndef AppVersion
  #define AppVersion "13.4.0"
#endif

#define AppName "FixPrinter"
#define AppPublisher "vulongvy"
#define AppURL "https://github.com/vulongvy/FixPrinter"

[Setup]
AppId={{1C350424-6A7E-41AA-A67B-BED1983AA349}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
VersionInfoDescription=FixPrinter Setup
DefaultDirName={autopf}\FixPrinter
DefaultGroupName=FixPrinter
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=dist
OutputBaseFilename=FixPrinter-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=FixPrinter {#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "src\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\FIX ALL PRINTER - MANG LAN"; Filename: "{app}\FIX_ALL_PRINTER_MANG_LAN.bat"; WorkingDir: "{app}"
Name: "{group}\FIX ALL PRINTER - MANG LAN"; Filename: "{app}\FIX_ALL_PRINTER_MANG_LAN.bat"; WorkingDir: "{app}"
Name: "{group}\FixPrinter - Menu day du"; Filename: "{app}\CHAY_FIXPRINTER.bat"; WorkingDir: "{app}"
Name: "{group}\Go cai dat FixPrinter"; Filename: "{uninstallexe}"

[UninstallDelete]
; Runtime leftovers so uninstall leaves the folder clean (winget checks this)
Type: filesandordirs; Name: "{app}\backup"
Type: files; Name: "{app}\fixprinter_v13_log.txt"
Type: files; Name: "{app}\diagnose_report_v13.txt"
Type: files; Name: "{app}\launcher_log.txt"
