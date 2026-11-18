@echo off
setlocal
set "ROOT=%~dp0"
set "JULIA=%ROOT%.tools\julia-1.10.12\bin\julia.exe"
if exist "%JULIA%" goto run
for /f "delims=" %%I in ('where julia 2^>nul') do (
  echo %%I | findstr /I /C:"WindowsApps" >nul
  if errorlevel 1 (
    set "JULIA=%%I"
    goto run
  )
)
echo Julia was not found. Expected bundled Julia at "%JULIA%".
exit /b 1
:run
"%JULIA%" --project="%ROOT%" %*
exit /b %errorlevel%
