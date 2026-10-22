' Starts the ESHARI Admin server with no window (used by the Windows startup
' entry). The folder is the one this file is in, so moving the project is fine.
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
sh.CurrentDirectory = root
' 0 = hidden window, False = do not wait
sh.Run "cmd /c npm run start:local >> ""%TEMP%\eshary-admin.log"" 2>&1", 0, False
