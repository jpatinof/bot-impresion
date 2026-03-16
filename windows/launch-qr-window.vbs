Option Explicit

Function Quote(ByVal value)
    Quote = Chr(34) & value & Chr(34)
End Function

Dim shell
Dim fso
Dim scriptDirectory
Dim statePath
Dim imagePath
Dim parentProcessId
Dim command

If WScript.Arguments.Count < 2 Then
    WScript.Quit 1
End If

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fso.GetParentFolderName(WScript.ScriptFullName)
statePath = WScript.Arguments.Item(0)
imagePath = WScript.Arguments.Item(1)

If WScript.Arguments.Count >= 3 Then
    parentProcessId = WScript.Arguments.Item(2)
Else
    parentProcessId = "0"
End If

command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File " _
    & Quote(fso.BuildPath(scriptDirectory, "whatsapp-qr-window.ps1")) _
    & " -StatePath " & Quote(statePath) _
    & " -ImagePath " & Quote(imagePath) _
    & " -ParentProcessId " & Quote(parentProcessId)

shell.Run command, 0, False
