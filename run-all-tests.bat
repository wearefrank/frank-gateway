@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "REPO_ROOT=%~dp0"
pushd "%REPO_ROOT%" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Cannot access repository root: %REPO_ROOT%
    exit /b 1
)

if defined TEST_RUNNER_CMD set "TEST_RUNNER_CMD=%TEST_RUNNER_CMD:\"=%"

if not defined TEST_RUNNER_CMD (
    where testrunner.bat >nul 2>nul
    if not errorlevel 1 set "TEST_RUNNER_CMD=testrunner.bat"
)

if not defined TEST_RUNNER_CMD (
    for /d %%D in ("%LOCALAPPDATA%\Programs\SmartBear\SoapUI-*") do (
        if exist "%%D\bin\testrunner.bat" set "TEST_RUNNER_CMD=%%D\bin\testrunner.bat"
    )
)

if not defined TEST_RUNNER_CMD (
    for /d %%D in ("%ProgramFiles%\SmartBear\SoapUI-*") do (
        if exist "%%D\bin\testrunner.bat" set "TEST_RUNNER_CMD=%%D\bin\testrunner.bat"
    )
)

if defined TEST_RUNNER_CMD (
    if not "%TEST_RUNNER_CMD%"=="testrunner.bat" (
        if not exist "%TEST_RUNNER_CMD%" set "TEST_RUNNER_CMD="
    )
)

if not defined TEST_RUNNER_CMD (
    echo [ERROR] No SoapUI test runner found.
    echo [ERROR] In PowerShell use:
    echo [ERROR]   $env:TEST_RUNNER_CMD="C:\Users\vincent.v.medenbach\AppData\Local\Programs\SmartBear\SoapUI-5.9.1\bin\testrunner.bat"
    popd
    exit /b 1
)

echo [INFO] Using SoapUI test runner: %TEST_RUNNER_CMD%

if not "%SKIP_IMAGE_BUILD%"=="1" (
    docker image inspect frank-gateway:local >nul 2>nul
    if errorlevel 1 (
        echo [INFO] Building frank-gateway:local image...
        docker build -t frank-gateway:local "%REPO_ROOT%"
        if errorlevel 1 (
            echo [ERROR] Failed to build frank-gateway:local.
            popd
            exit /b 1
        )
    ) else (
        echo [INFO] Using existing frank-gateway:local image.
    )
) else (
    echo [INFO] Skipping image build because SKIP_IMAGE_BUILD=1.
)

set /a TOTAL=0
set /a PASSED=0
set /a FAILED=0
set "PASSED_LIST="
set "FAILED_LIST="

call :run_suite cert-auth cert-auth-tests.xml
call :run_suite frank-sender frank-sender-tests.xml
call :run_suite generic-oauth generic-oauth-tests.xml
call :run_suite jwt-client jwt-client-tests.xml
call :run_suite limit-size limit-size-tests.xml
call :run_suite oidc-client oidc-client-tests.xml
call :run_suite soap-action-router soap-action-router-tests.xml

echo.
echo ========================================
echo Test run complete.
echo Total : %TOTAL%
echo Passed: %PASSED%
echo Failed: %FAILED%
if defined PASSED_LIST (
    echo Passed suites: !PASSED_LIST!
) else (
    echo Passed suites: (none)
)
if defined FAILED_LIST (
    echo Failed suites: !FAILED_LIST!
) else (
    echo Failed suites: (none)
)
echo ========================================

popd
if %FAILED% gtr 0 exit /b 1
exit /b 0

:run_suite
set "SUITE=%~1"
set "TEST_XML=%~2"
set /a TOTAL+=1
set "SUITE_FAILED=0"

echo.
echo ===== [%TOTAL%] %SUITE% =====

pushd "%REPO_ROOT%tests\%SUITE%" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Cannot access tests\%SUITE%.
    set "SUITE_FAILED=1"
    goto :suite_result
)

echo [INFO] Starting containers...
docker compose up -d --force-recreate
if errorlevel 1 (
    echo [ERROR] Failed to start containers for %SUITE%.
    set "SUITE_FAILED=1"
) else (
    echo [INFO] Running tests with %TEST_RUNNER_CMD% %TEST_XML%...
    call "%TEST_RUNNER_CMD%" "%TEST_XML%"
    if errorlevel 1 (
        echo [ERROR] Test execution failed for %SUITE%.
        set "SUITE_FAILED=1"
    )
)

echo [INFO] Stopping containers...
docker compose down --remove-orphans
if errorlevel 1 echo [WARN] Failed to fully stop containers for %SUITE%.

popd

:suite_result
if "%SUITE_FAILED%"=="1" (
    set /a FAILED+=1
    if defined FAILED_LIST (
        set "FAILED_LIST=!FAILED_LIST!, %SUITE%"
    ) else (
        set "FAILED_LIST=%SUITE%"
    )
    echo [RESULT] %SUITE%: FAILED
) else (
    set /a PASSED+=1
    if defined PASSED_LIST (
        set "PASSED_LIST=!PASSED_LIST!, %SUITE%"
    ) else (
        set "PASSED_LIST=%SUITE%"
    )
    echo [RESULT] %SUITE%: PASSED
)

exit /b 0
