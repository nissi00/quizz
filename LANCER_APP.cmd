@echo off
setlocal
REM Lance un serveur web local puis ouvre l'application dans le navigateur.
REM Ne double-cliquez pas sur index.html : Windows peut l'associer à VS Code.
start "TS Quiz - serveur local (laisser cette fenêtre ouverte)" cmd /k "python -m http.server 5173 --directory ""%~dp0"""
timeout /t 2 /nobreak >nul
start "" "http://localhost:5173/index.html"
endlocal
