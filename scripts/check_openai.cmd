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

echo Optional paid provider checker. The free default is scripts\check_local_ai.cmd.
%PYTHON_EXE% -c "import pathlib, sys; p=pathlib.Path('.env'); print('FOUND .env' if p.exists() else 'MISSING .env'); text=p.read_text() if p.exists() else ''; print('AI_PROVIDER=openai selected' if 'AI_PROVIDER=openai' in text else 'AI_PROVIDER is not openai'); print('OPENAI_API_KEY present' if 'OPENAI_API_KEY=' in text and 'sk-your-key-here' not in text else 'OPENAI_API_KEY missing or placeholder'); print('OPENAI_MODEL present' if 'OPENAI_MODEL=' in text else 'OPENAI_MODEL missing, backend will use default')"

echo.
echo If backend is running, open:
echo   http://127.0.0.1:8788/api/ai/status
endlocal
