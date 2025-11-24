@echo off
cd /d %~dp0
if not exist build mkdir build
cd build
if not exist CMakeCache.txt cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.14
cmake --build . --config Release
copy /Y Release\earth_native.dll ..\..\earth_native.dll
cd ..
echo Build complete.
