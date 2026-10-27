@echo off
set "DEVECO_SDK_HOME=E:\DevEco Studio\sdk"
cd /d "%~dp0"
call "E:\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p module=entry@default -p product=default assembleHap --analyze=normal --parallel --incremental
