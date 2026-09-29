@echo off
cd /d "%~dp0"
call dart tool/setup.dart
if errorlevel 1 exit /b 1
call flutter analyze --no-fatal-infos
if errorlevel 1 exit /b 1
call flutter test
