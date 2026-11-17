@echo off
setlocal DisableDelayedExpansion
rem Optional convenience entry point. The .sh file still contains all programs.
set "DSA_BASH="
if defined DSA_GIT_BASH if exist "%DSA_GIT_BASH%" set "DSA_BASH=%DSA_GIT_BASH%"
if not defined DSA_BASH if exist "%ProgramFiles%\Git\bin\bash.exe" set "DSA_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined DSA_BASH if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "DSA_BASH=%LocalAppData%\Programs\Git\bin\bash.exe"
if not defined DSA_BASH (
    echo Git Bash is required to run the .sh file on Windows.
    echo Install Git for Windows, then reopen this file. Nothing is installed automatically.
    echo For a custom installation, set DSA_GIT_BASH to the full path of Git's bash.exe.
    pause
    exit /b 127
)
if not exist "%~dp0dsa.sh" (
    echo Keep dsa.sh beside this Windows starter.
    pause
    exit /b 1
)
"%DSA_BASH%" "%~dp0dsa.sh" %*
set "DSA_STATUS=%ERRORLEVEL%"
if not "%DSA_STATUS%"=="0" pause
exit /b %DSA_STATUS%
