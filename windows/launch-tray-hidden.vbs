Option Explicit

Function Quote(ByVal value)
    Quote = Chr(34) & value & Chr(34)
End Function

Function ReadEnv(ByVal shell, ByVal name)
    Dim expanded
    expanded = shell.ExpandEnvironmentStrings("%" & name & "%")

    If expanded = "%" & name & "%" Then
        ReadEnv = ""
    Else
        ReadEnv = expanded
    End If
End Function

Dim shell
Dim fso
Dim scriptPath
Dim scriptDirectory
Dim projectRoot
Dim installRoot
Dim dataDir
Dim localAppData
Dim command

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptPath = WScript.ScriptFullName
scriptDirectory = fso.GetParentFolderName(scriptPath)
projectRoot = fso.GetParentFolderName(scriptDirectory)
localAppData = ReadEnv(shell, "LOCALAPPDATA")

installRoot = ReadEnv(shell, "BOT_IMPRESION_INSTALL_ROOT")
If installRoot = "" Then
    If LCase(fso.GetFileName(projectRoot)) = "app" Then
        installRoot = fso.GetParentFolderName(projectRoot)
    ElseIf localAppData <> "" Then
        installRoot = fso.BuildPath(localAppData, "BotImpresion")
    Else
        installRoot = projectRoot
    End If
End If

dataDir = ReadEnv(shell, "BOT_IMPRESION_DATA_DIR")
If dataDir = "" Then
    If LCase(fso.GetFileName(projectRoot)) = "app" Then
        dataDir = fso.BuildPath(installRoot, "data")
    ElseIf localAppData <> "" Then
        dataDir = fso.BuildPath(fso.BuildPath(localAppData, "BotImpresion"), "data")
    Else
        dataDir = projectRoot
    End If
End If

shell.Environment("PROCESS")("BOT_IMPRESION_HOME") = projectRoot
shell.Environment("PROCESS")("BOT_IMPRESION_INSTALL_ROOT") = installRoot
shell.Environment("PROCESS")("BOT_IMPRESION_DATA_DIR") = dataDir
shell.CurrentDirectory = projectRoot

command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Quote(fso.BuildPath(scriptDirectory, "tray.ps1"))
shell.Run command, 0, False
