@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "REPO_ROOT=%~dp0"
pushd "%REPO_ROOT%" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Cannot access repository root: %REPO_ROOT%
    exit /b 1
)

where docker >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Docker CLI not found in PATH.
    echo [ERROR] Install Docker Desktop and ensure docker is available from the command line.
    popd
    exit /b 1
)

docker info >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Docker engine is not reachable.
    echo [ERROR] Start Docker Desktop and wait until it is fully running, then re-run this script.
    popd
    exit /b 1
)

set "REPO_ROOT_DOCKER=%CD%"

if defined BRUNO_CLI_IMAGE set "BRUNO_CLI_IMAGE=%BRUNO_CLI_IMAGE:\"=%"
if not defined BRUNO_CLI_IMAGE set "BRUNO_CLI_IMAGE=alpine/bruno"

if defined BRUNO_DOCKER_NETWORK set "BRUNO_DOCKER_NETWORK=%BRUNO_DOCKER_NETWORK:\"=%"
if not defined BRUNO_DOCKER_NETWORK set "BRUNO_DOCKER_NETWORK=host"

if defined BRUNO_ENV set "BRUNO_ENV=%BRUNO_ENV:\"=%"
if not defined BRUNO_ENV set "BRUNO_ENV=docker"

set "BRUNO_RESULTS_DIR=%REPO_ROOT%tests\bruno\results"
if not exist "%BRUNO_RESULTS_DIR%" mkdir "%BRUNO_RESULTS_DIR%"

echo [INFO] Using Bruno container runtime image: %BRUNO_CLI_IMAGE%
echo [INFO] Bruno CLI Docker network: %BRUNO_DOCKER_NETWORK%
echo [INFO] Bruno environment: %BRUNO_ENV%

set /a TOTAL=0
set /a PASSED=0
set /a FAILED=0
set "PASSED_LIST="
set "FAILED_LIST="

call :run_suite cert-auth
call :run_suite frank-sender
call :run_suite generic-oauth
call :run_suite jwt-client
call :run_suite limit-size
call :run_suite oidc-client
call :run_suite soap-action-router

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
set /a TOTAL+=1
set "SUITE_FAILED=0"
set "CONTAINERS_STARTED=0"
set "DIR_PUSHED=0"

echo.
echo ===== [%TOTAL%] %SUITE% =====

pushd "%REPO_ROOT%tests\%SUITE%" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Cannot access tests\%SUITE%.
    set "SUITE_FAILED=1"
    goto :run_suite_finish
)
set "DIR_PUSHED=1"
if defined RUN_ALL_TESTS_TRACE echo [TRACE] Entered tests\%SUITE%

echo [INFO] Starting containers...
docker compose up -d --force-recreate
if errorlevel 1 (
    echo [ERROR] Failed to start containers for %SUITE%.
    set "SUITE_FAILED=1"
    goto :run_suite_finish
)
if defined RUN_ALL_TESTS_TRACE echo [TRACE] Containers started for %SUITE%

set "CONTAINERS_STARTED=1"
if defined RUN_ALL_TESTS_TRACE echo [TRACE] Warm-up start for %SUITE%

call :warm_up_suite "%SUITE%"
if defined RUN_ALL_TESTS_TRACE echo [TRACE] Warm-up returned !errorlevel! for %SUITE%
if errorlevel 1 (
    echo [ERROR] Dependency warm-up failed for %SUITE%.
    set "SUITE_FAILED=1"
    goto :run_suite_finish
)

if defined RUN_ALL_TESTS_TRACE echo [TRACE] Bruno run start for %SUITE%
echo [INFO] Running Bruno tests for %SUITE%...
call :run_bruno_suite "%SUITE%"
if defined RUN_ALL_TESTS_TRACE echo [TRACE] Bruno run returned !errorlevel! for %SUITE%
if errorlevel 1 (
    echo [ERROR] Bruno test execution failed for %SUITE%.
    set "SUITE_FAILED=1"
)

:run_suite_finish
if "%CONTAINERS_STARTED%"=="1" (
    echo [INFO] Stopping containers...
    docker compose down --remove-orphans
    if errorlevel 1 echo [WARN] Failed to fully stop containers for %SUITE%.
    if "%DIR_PUSHED%"=="1" popd
) else (
    if "%DIR_PUSHED%"=="1" popd
    echo [INFO] Skipping container shutdown for %SUITE% because startup failed.
)

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

goto :eof

:run_bruno_suite
set "BRUNO_SUITE=%~1"

docker run --rm --network "%BRUNO_DOCKER_NETWORK%" --add-host "apisix.localhost:host-gateway" --add-host "host.docker.internal:host-gateway" -v "%REPO_ROOT_DOCKER%:/workspace" -w "/workspace/tests/bruno/%BRUNO_SUITE%" "%BRUNO_CLI_IMAGE%" run . -r --env "%BRUNO_ENV%" --insecure --reporter-junit "/workspace/tests/bruno/results/%BRUNO_SUITE%.xml"
if errorlevel 1 exit /b 1

goto :eof

:warm_up_suite
set "WARMUP_SUITE=%~1"

if /I "%WARMUP_SUITE%"=="generic-oauth" goto :warm_up_keycloak
if /I "%WARMUP_SUITE%"=="oidc-client" goto :warm_up_keycloak
goto :eof

:warm_up_keycloak
echo [INFO] Waiting for Keycloak readiness (%WARMUP_SUITE%)...
call :wait_http_ok "http://localhost:9081/realms/fg-testing/.well-known/openid-configuration" 30
if errorlevel 1 exit /b 1
call :wait_token_ready "http://localhost:9081/realms/fg-testing/protocol/openid-connect/token" "oidc-test-client" "KVJEeHx2gaX8Sg0siDMtHD1z1zsxJUqx" 30
if errorlevel 1 exit /b 1
goto :eof

:wait_http_ok
set "WAIT_URL=%~1"
set "WAIT_TRIES=%~2"
set /a WAIT_I=0

:wait_http_loop
set /a WAIT_I+=1
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 -Uri '%WAIT_URL%'; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>nul
if not errorlevel 1 exit /b 0
if !WAIT_I! geq %WAIT_TRIES% exit /b 1
timeout /t 2 /nobreak >nul
goto :wait_http_loop

:wait_token_ready
set "TOKEN_URL=%~1"
set "TOKEN_CLIENT_ID=%~2"
set "TOKEN_CLIENT_SECRET=%~3"
set "TOKEN_TRIES=%~4"
set /a TOKEN_I=0

:wait_token_loop
set /a TOKEN_I+=1
powershell -NoProfile -Command "try { $body = 'client_id=' + [uri]::EscapeDataString('%TOKEN_CLIENT_ID%') + '&client_secret=' + [uri]::EscapeDataString('%TOKEN_CLIENT_SECRET%') + '&grant_type=client_credentials'; $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 4 -Method Post -ContentType 'application/x-www-form-urlencoded' -Body $body -Uri '%TOKEN_URL%'; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { exit 0 } else { exit 1 } } catch { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -lt 500) { exit 0 } else { exit 1 } }" >nul 2>nul
if not errorlevel 1 exit /b 0
if !TOKEN_I! geq %TOKEN_TRIES% exit /b 1
timeout /t 2 /nobreak >nul
goto :wait_token_loop
