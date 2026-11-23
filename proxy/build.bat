@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
cl /nologo /LD /O2 /EHsc /W3 /DUNICODE /D_UNICODE version_proxy.cpp /Fe:version.dll /link /NOIMPLIB /NOEXP
