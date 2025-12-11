@echo off
set CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe

if not exist "%CSC%" (
    echo Error: C# Compiler not found at %CSC%
    exit /b 1
)

echo Compiling Sortify...
"%CSC%" /target:exe /out:Sortify.exe /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Xml.dll FileSorter.cs

if %errorlevel% neq 0 (
    echo Compilation Failed!
    exit /b %errorlevel%
)

echo Compilation Successful. Created Sortify.exe
exit /b 0
