@echo off
setlocal
cd /d "%~dp0\.."

set PYTHON_EXE=python
where python >nul 2>nul
if errorlevel 1 (
  if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" (
    set PYTHON_EXE=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe
  )
)
for /d %%D in ("%LOCALAPPDATA%\Python\pythoncore-*") do (
  if exist "%%~fD\python.exe" set PYTHON_EXE=%%~fD\python.exe
)

if exist ".env" (
  for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
    if "%%A"=="FFMPEG_PATH" set FFMPEG_PATH=%%B
  )
)

if not "%FFMPEG_PATH%"=="" (
  if exist "%FFMPEG_PATH%" (
    echo FOUND FFMPEG_PATH=%FFMPEG_PATH%
    "%FFMPEG_PATH%" -version
    exit /b 0
  )
  echo FFMPEG_PATH is set but file was not found: %FFMPEG_PATH%
  exit /b 1
)

where ffmpeg >nul 2>nul
if errorlevel 1 (
  goto imageio_check
)

ffmpeg -version
exit /b 0

:imageio_check
for /f "delims=" %%F in ('"%PYTHON_EXE%" -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())" 2^>nul') do set IMAGEIO_FFMPEG=%%F
if not "%IMAGEIO_FFMPEG%"=="" (
  if exist "%IMAGEIO_FFMPEG%" (
    echo FOUND imageio-ffmpeg=%IMAGEIO_FFMPEG%
    "%IMAGEIO_FFMPEG%" -version
    exit /b 0
  )
)

echo FFmpeg not found on PATH or through imageio-ffmpeg.
echo Run scripts\install_ffmpeg.cmd, or install FFmpeg and set FFMPEG_PATH in .env.
exit /b 1
endlocal
