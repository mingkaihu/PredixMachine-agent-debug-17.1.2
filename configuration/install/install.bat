@ECHO OFF
REM Copyright (c) 2012-2016 General Electric Company. All rights reserved.
REM The copyright to the computer software herein is the property of
REM General Electric Company. The software may be used and/or copied only
REM with the written permission of General Electric Company or in accordance
REM with the terms and conditions stipulated in the agreement/contract
REM under which the software has been supplied.

REM This install script will be called by yeti which will provide two arguments
REM The first argument is the Predix Home directory which is the directory to the 
REM Predix Machine container
REM The second argument is the path to the configuration directory.  This contains 
REM the new configuration to be installed.
REM Files can be added to the whitelist so they are not overwritten.  These could 
REM include configurations that contain encoded passwords or parameters generated
REM by the container on startup.

REM Updating the configuration proceeds as follows:
REM 1. Make a backup of the current configuration
REM 2. Overlay configuration files found in the directory if they are not in the whitelist
REM 3. Return an error code or 0 for success

SETLOCAL EnableDelayedExpansion
REM PREDIX_MACHINE_DATA - path to the data directory of the container, passed in by Yeti
SET PREDIX_MACHINE_DATA=%1
REM CONFIG - path to the new configuration, passed in by yeti
SET CONFIG=%2
REM ZIPNAME - the name of the zip file being installed surrounded by quotes. Write a json file to
REM appdata\packageframework to give the package status
SET ZIPNAME=%~3

SET RUNDATE=%date:~-10,2%%date:~-7,2%%date:~-2,4%%time:~-11,2%%time:~-8,2%%time:~-5,2%
SET LOG="%PREDIX_MACHINE_DATA%"\logs\installations\%ZIPNAME%.log

ECHO ##########################################################################>"%LOG%"
ECHO #                 Shutting down container for update                     #>>"%LOG%"
ECHO ##########################################################################>>"%LOG%"
REM Check for the stop_watchdog.sh file.  This won't exist in a dockerized machine so we don't shut down.
IF EXIST "%PREDIX_MACHINE_DATA%\yeti\watchdog\stop_watchdog.bat" (
	CMD /C "%PREDIX_MACHINE_DATA%\yeti\watchdog\stop_watchdog.bat"
)

REM These configurations should not be overwritten
REM    com.ge.dspmicro.predixcloud.identity.config (client id and secret)
REM    com.ge.dspmicro.storeforward-*.config  (generated database password will never accessible again if you overwrite)
REM    com.ge.dspmicro.device.techconsole.config – This says if the technician console should be enabled. This should only be done through the the command and not through configuration overwrite.

SET WHITELIST[0]=com.ge.dspmicro.predixcloud.identity.config
SET WHITELIST[1]=com.ge.dspmicro.device.techconsole.config
SET WHITELIST[2]=org.apache.http.proxyconfigurator-0.config
SET WHITELIST[3]=com.ge.dspmicro.predix.connectivity.openvpn.config
SET WHITELIST[4]=com.ge.dspmicro.storeforward-0.config
SET WHITELIST[5]=com.ge.dspmicro.storeforward-1.config
SET WHITELIST[6]=com.ge.dspmicro.storeforward-2.config
SET WHITELIST[7]=com.ge.dspmicro.storeforward-3.config

CALL :WRITECONSOLELOG "Updating the configuration directory."
ECHO Looking for whitelisted files in the installation package.  Disregard any file not found errors produced by this process. 
ECHO !RUNTIME! Looking for whitelisted files in the installation package.>>"%LOG%"

SET i=0
CD "%CONFIG%"

:WHITELISTLOOP
IF "!WHITELIST[%i%]!" EQU "" (
	GOTO :WHITELISTDONE
) ELSE (
    FOR /F "delims=" %%A IN ('FORFILES /S /M !WHITELIST[%i%]! /C "CMD /C ECHO @relpath"') DO (
    	SET file="%%~A"
    	IF EXIST "%PREDIX_MACHINE_DATA%"\"!file:~3!" (
    		CALL :WRITECONSOLELOG "Removing whitelisted !file:~3! from installation."
    		DEL "!file:~3!">>"%LOG%" 2>&1
    	)
	)
    SET /A i+=1
    GOTO :WHITELISTLOOP
)
:WHITELISTDONE
CALL :WRITECONSOLELOG "Whitelisted files processed, beginning configuration update." 

REM Update the configuration by removing any old backups, renaming the
REM current installed to configuration.old, and adding the updated configuration
CD "%PREDIX_MACHINE_DATA%"
IF EXIST configuration.old\ (
	CALL :WRITECONSOLELOG "Removing the configuration.old backup."
	RMDIR /Q /S configuration.old>>"%LOG%" 2>&1
	IF !ERRORLEVEL! NEQ 0 (
		SET MESSAGE=Previous configuration.old could not be removed. This is most likely due to another process.  Be sure no processes such as CMD or Explorer are holding resources in this directory.
		SET ERRORCODE=54
		SET STATUS=failure
		CALL :FINISH
	)
	IF EXIST configuration.old\ (
		SET MESSAGE=Previous configuration.old could not be removed. This is most likely due to another process.  Be sure no processes such as CMD or Explorer are holding resources in this directory.
		SET ERRORCODE=54
		SET STATUS=failure
		CALL :FINISH
	) ELSE (
		CALL :WRITECONSOLELOG "Previous configuration.old removed."
	)
)
IF EXIST configuration\ (
	CALL :WRITECONSOLELOG "Updating configuration. Backup of current stored in configuration.old."
	CALL :WRITECONSOLELOG "Copying previous configuration to configuration.old."
	XCOPY /S /E /G /C configuration configuration.old\>>"%LOG%" 2>&1
	IF !ERRORLEVEL! NEQ 0 (
		SET MESSAGE=Configuration could not be backed up. This is most likely due to another process.  Be sure no processes such as CMD or Explorer are holding resources in this directory.
		SET ERRORCODE=55
		SET STATUS=failure
		CALL :FINISH
	)
	IF NOT EXIST configuration.old\ (
		SET MESSAGE=Configuration could not be backed up. This is most likely due to another process.  Be sure no processes such as CMD or Explorer are holding resources in this directory.
		SET ERRORCODE=55
		SET STATUS=failure
		CALL :FINISH
	) ELSE (
		CALL :WRITECONSOLELOG "Configuration backup created as configuration.old"
	)
)
CALL :WRITECONSOLELOG "Copying configuration update to configuration."
IF NOT EXIST configuration\ (
	MKDIR configuration
)
XCOPY /S /E /Y "%CONFIG%"\configuration configuration>>"%LOG%" 2>&1
IF %ERRORLEVEL% NEQ 0 (
	SET MESSAGE=Configuration backup could not be updated.
	SET ERRORCODE=56
	SET STATUS=failure
	CALL :ROLLBACK "configuration"
	CALL :FINISH
) ELSE (
	SET MESSAGE=Configuration backup updated.
	SET ERRORCODE=0
	SET STATUS=success
	CALL :FINISH
)

:ROLLBACK
	CALL :WRITECONSOLELOG "Update unsuccessful. Attempting to rollback."
	SET DIRECTORY=%1
	IF EXIST "%PREDIX_MACHINE_DATA%"\%DIRECTORY%\ (
		RMDIR /Q /S "%PREDIX_MACHINE_DATA%"\%DIRECTORY%>>"%LOG%" 2>&1
	)
	MOVE "%PREDIX_MACHINE_DATA%"\%DIRECTORY%.old "%PREDIX_MACHINE_DATA%"\%DIRECTORY%>>"%LOG%" 2>&1
	IF !ERRORLEVEL! NEQ 0 (
		CALL :WRITECONSOLELOG "Rollback unsuccessful."
	) ELSE (
		CALL :WRITECONSOLELOG "Rollback successful."
	)
	EXIT /B

:TIMESTAMP
	SET RUNTIME=%date:~4,10% %time:~0,8%
	EXIT /B

:WRITECONSOLELOG
	CALL :TIMESTAMP
	ECHO %RUNTIME% %~1 >> "%LOG%"
	ECHO %RUNTIME% %~1
	EXIT /B
	
:FINISH
	CD "%PREDIX_MACHINE_DATA%"
	CALL :WRITECONSOLELOG "Installation completed with errorcode !ERRORCODE!"
	CALL :WRITECONSOLELOG "!MESSAGE!"
	IF !ERRORCODE! EQU 0 (
		(
		ECHO {
		ECHO     "status" : "!STATUS!",
		ECHO     "message" : "!MESSAGE!"
		ECHO }
		) > appdata\packageframework\%ZIPNAME%.json
	) ELSE (
		(
		ECHO {
		ECHO     "status" : "!STATUS!",
		ECHO     "errorcode" : !ERRORCODE!,
		ECHO     "message" : "!MESSAGE!"
		ECHO }
		) > appdata\packageframework\%ZIPNAME%.json
	)
	CALL :WRITECONSOLELOG "Starting up the container..."
	REM Check for the start_watchdog.sh file.  This won't exist in a dockerized machine so we don't start up.
	IF EXIST "%PREDIX_MACHINE_DATA%\yeti\watchdog\start_watchdog.bat" (
		CMD /C START "Predix Machine Watchdog" "%PREDIX_MACHINE_DATA%\yeti\watchdog\start_watchdog.bat"
	)
	EXIT ERRORCODE!