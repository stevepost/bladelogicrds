#!/bin/nsh

TARGETS=$1
JOB_FOLDER=$2
JOB_NAME=$3
CUSTOM_SOFTWARE_FOLDER=$4
CUSTOM_SOFTWARE_NAME=$5
CONCURRENT_SCANS=$6
OVALS_INTERPRETER="OSCAP"
SCAN_TYPE=$7
TMP_LOCATION=$8
TARGETS_COMMA_SEPARATED=`echo $TARGETS | sed 's/ /,/g'`
JOB_NAME_WITHOUT_SPACES=`echo $JOB_NAME | sed 's/ /_/g'`

TIMESTAMP=$(date +%Y%m%d%H%M%S)
UNIQUE_ID=${JOB_NAME_WITHOUT_SPACES}_${TIMESTAMP}
EXIT_CODE=0
NEW_LINE='
'
TAB='	'
DEPOT_SOFTWARE_FIND_ERR_MSG="Failed to get the depot Software with the passed Name ${CUSTOM_SOFTWARE_NAME} and folder ${CUSTOM_SOFTWARE_FOLDER}.${NEW_LINE}Please check the job configuration."
COMMAND_UPDATE_ERR_MSG="Failed to update Install command of the Depot Software"
COMMAND_RETRIEVE_ERR_MSG="Failed to Retrieve Install Command for Depot Software ${CUSTOM_SOFTWARE_NAME}"
JOB_EXECUTION_FAILED_ERR_MSG="Failed to start Job ${JOB_NAME}"
JOB_NOT_FOUND_ERR_MSG="Failed to find Job with Name ${JOB_NAME} in Folder ${JOB_FOLDER}"
COMMAND_REVERT_ERR_MSG="Failed to Revert Install Command for Depot Software ${CUSTOM_SOFTWARE_NAME}"
JOB_STATUS_NOT_RETRIEVED_ERR_MSG="Failed to retrieve Job Run Status for Job ${JOB_NAME} with Job Run"
FILE_SERVER_ERR_MSG="Failed to retrieve File Server Complete Path"
FILE_SERVER_COPY_ERR_MSG="Failed to copy reports from"
FILE_DELETE_ERR_MSG="Failed to delete reports from"
JOB_COMPLETION_CHECK_FAILED_ERR_MSG="Failed to Check Job Run Completion status for Job ${JOB_NAME} with Job Run"
JOB_EXITED_WITH_ERRORS_MSG="Job ${JOB_NAME} has exited with errors. Please check the job run logs for Job Run"


connect() {
	echo "Starting Script Execution"
	blcli_connect
}

getDepotSoftwareKeyAndInstallCommand() {
	blcli_execute DepotObject getDBKeyByTypeStringGroupAndName CUSTOM_SOFTWARE_INSTALLABLE "$CUSTOM_SOFTWARE_FOLDER"  "$CUSTOM_SOFTWARE_NAME" > /dev/null
	logAndExitIfError $? "${DEPOT_SOFTWARE_FIND_ERR_MSG}"
	blcli_storeenv DEPOT_SOFTWARE_DB_KEY
	echo "Depot Software key is $DEPOT_SOFTWARE_DB_KEY"
	blcli_execute  DepotSoftware getInstallCmd > /dev/null
	logAndExitIfError $? "${COMMAND_RETRIEVE_ERR_MSG}"
	blcli_storeenv DEPOT_SOFTWARE_COMMAND
}

updateInstallCommand() {
	#echo "$DEPOT_SOFTWARE_COMMAND $UNIQUE_ID"
	blcli_execute DepotSoftware updateInstallCommand "$DEPOT_SOFTWARE_DB_KEY" "$DEPOT_SOFTWARE_COMMAND $CONCURRENT_SCANS $UNIQUE_ID $OVALS_INTERPRETER $SCAN_TYPE $TMP_LOCATION" > /dev/null
	logAndExitIfError $? "${COMMAND_RETRIEVE_ERR_MSG}"
}

executeJob() {
	blcli_execute DeployJob getDBKeyByGroupAndName "$JOB_FOLDER" "$JOB_NAME" > /dev/null
	logAndExitIfError $? "${JOB_NOT_FOUND_ERR_MSG}"
	blcli_storeenv JOB_DB_KEY
	echo "Executing Job $JOB_NAME Against Targets ${TARGETS_COMMA_SEPARATED}"
	blcli_execute Job executeAgainstServersForRunID "$JOB_DB_KEY" "$TARGETS_COMMA_SEPARATED" > /dev/null
	#Incase job execution fails we need to ensure that command is reverted back. Else there will be issues with the next run.
	revertInstallCommandAndExit $? "${JOB_EXECUTION_FAILED_ERR_MSG}" 
	blcli_storeenv JOB_RUN_ID
	echo "Job Run Started with Run Key $JOB_RUN_ID"
}

revertBackInstallCommand() {
	echo "Changing back the Install Command"
	blcli_execute DepotSoftware updateInstallCommand "$DEPOT_SOFTWARE_DB_KEY" "$DEPOT_SOFTWARE_COMMAND" > /dev/null
	logAndExitIfError $? "COMMAND_REVERT_ERR_MSG"
}
#	echo "Unique ID for this JOB run is $UNIQUE_ID"
	

waitForJobRunToComplete() {
	blcli_execute JobRun getJobRunIsRunningByRunKey $JOB_RUN_ID > /dev/null
	logAndExitIfError $? "${JOB_STATUS_NOT_RETRIEVED_ERR_MSG} ${JOB_RUN_ID}"
	blcli_storeenv IS_JOB_RUNNING
	echo -n "Waiting for Job to finish"
	while [ "$IS_JOB_RUNNING" = "true" ]
	do
		blcli_execute JobRun getJobRunIsRunningByRunKey $JOB_RUN_ID > /dev/null
		logAndExitIfError $? "${JOB_STATUS_NOT_RETRIEVED_ERR_MSG} ${JOB_RUN_ID}" 
		blcli_storeenv IS_JOB_RUNNING
		sleep 10
		echo -n "."
	done
	echo ""
	checkIfJobRunHasErrorsAndExit
	echo "Job Has Completed Successfully."
}

checkIfJobRunHasErrorsAndExit() {
	blcli_execute JobRun getJobRunHadErrors $JOB_RUN_ID > /dev/null
	logAndExitIfError $? "${JOB_COMPLETION_CHECK_FAILED_ERR_MSG} ${JOB_RUN_ID}"
	blcli_storeenv JOB_RUN_HAS_ERRORS
	if [ "$JOB_RUN_HAS_ERRORS" = "true" ]
	then
		logAndExitIfError 1 "${JOB_EXITED_WITH_ERRORS_MSG} ${JOB_RUN_ID}"
	fi
}

collateResults() {
	echo "Collecting Results with Unique ID ${UNIQUE_ID}"
	#Getting FileServer DetailsButtonText
	local IS_FIRST="true"
	local TARGETS_FILE="targets.json"
	local TARGETS_FILE_WITH_PATH="`pwd`/${TARGETS_FILE}"
	echo "Targets File ${TARGETS_FILE_WITH_PATH}"
	if [ -e "${TARGETS_FILE_WITH_PATH}" ]
	then
		rm "${TARGETS_FILE_WITH_PATH}"  > /dev/null
	fi

	for TARGET_NAME in ${TARGETS}
	do 
		echo "Collecting Results for ${TARGET_NAME}"
		blcli_execute FileManagerModel getFileServerFullPath > /dev/null
		logAndExitIfError $? "${FILE_SERVER_ERR_MSG}"
		blcli_storeenv FSLocation
		blcli_execute FileTransfer copySvrToSvr null "//${TARGET_NAME}/tmp/${UNIQUE_ID}/data/${TARGET_NAME}" "${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}/data/${TARGET_NAME}" > /dev/null
		logAndExitIfError $? "${FILE_SERVER_COPY_ERR_MSG} //${TARGET_NAME}/tmp/${UNIQUE_ID} to ${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}"
		blcli_execute FileTransfer copySvrToSvr null "//${TARGET_NAME}/tmp/${UNIQUE_ID}/css" "${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}/css" > /dev/null
		blcli_execute FileTransfer copySvrToSvr null "//${TARGET_NAME}/tmp/${UNIQUE_ID}/images" "${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}/images" > /dev/null
		blcli_execute FileTransfer copySvrToSvr null "//${TARGET_NAME}/tmp/${UNIQUE_ID}/js" "${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}/js" > /dev/null
		blcli_execute FileTransfer copySvrToSvr null "//${TARGET_NAME}/tmp/${UNIQUE_ID}/home.html" "${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}/home.html" > /dev/null
		blcli_execute FileTransfer copySvrToSvr null "//${TARGET_NAME}/tmp/${UNIQUE_ID}/containerResults.html" "${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}/containerResults.html" > /dev/null
		blcli_execute FileTransfer copySvrToSvr null "//${TARGET_NAME}/tmp/${UNIQUE_ID}/container.html" "${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}/container.html" > /dev/null
		blcli_execute FileTransfer copySvrToSvr null "//${TARGET_NAME}/tmp/${UNIQUE_ID}/images.html" "${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}/images.html" > /dev/null		
		blcli_execute FileTransfer copySvrToSvr null "//${TARGET_NAME}/tmp/${UNIQUE_ID}/imageResults.html" "${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}/imageResults.html" > /dev/null		
		
		echo "Cleaning up results from Target ${TARGET_NAME}"
		blcli_execute FileTransfer delete "//${TARGET_NAME}/tmp/${UNIQUE_ID}" > /dev/null
		logAndExitIfError $? "${FILE_DELETE_ERR_MSG} //${TARGET_NAME}/tmp/${UNIQUE_ID}" 
		if [ ${IS_FIRST} = "true" ]
		then
			echo "[{\"Hostname\": \"${TARGET_NAME}\"}" >> "${TARGETS_FILE_WITH_PATH}"
			IS_FIRST="false"
		else
			echo ",{\"Hostname\": \"${TARGET_NAME}\"}" >> "${TARGETS_FILE_WITH_PATH}"
		fi
	done
	echo "]" >> "${TARGETS_FILE_WITH_PATH}"
	echo "Copy targets file to FS"
	blcli_execute FileTransfer copySvrToSvr null "//`hostname`${TARGETS_FILE_WITH_PATH}" "${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}/data/${TARGETS_FILE}" > /dev/null
	echo "Results for this Job Run can be found at ${FSLocation}/ContainerReports/${JOB_NAME}/${UNIQUE_ID}"
}

logAndExitIfError() {
	if [ $1 -ne 0 ]
	then
		echo "$2"		
		echo "Exiting..."
		exit $1
	fi
}

revertInstallCommandAndExit() {
	if [ $1 -ne 0 ]
	then
	    revertBackInstallCommand
		echo "$2"		
		echo "Exiting..."
		exit $1
	fi
}

logAndContinueIfError() {
	if [ $1 -ne 0 ]
	then
		EXIT_CODE=1
		echo "$2"		
	fi
}

checkInputValues() {

	if [ ! $OVALS_INTERPRETER = "OVALDI" ] && [ ! $OVALS_INTERPRETER = "OSCAP" ]; then
		>&2 echo "OVALS Interpreter option specified was $OVALS_INTERPRETER, Supported Options are \"OVALDI\" for Ovaldi or \"OSCAP\" for Open SCAP"
	fi
	
	if [ ! $SCAN_TYPE = "IMAGE" ] && [ ! $SCAN_TYPE = "CONTAINER" ] && [ ! $SCAN_TYPE = "BOTH" ]; then
		>&2 echo "Scan type should be one, 1. IMAGE for image checks, 2. CONTAINER for containers check and 3. BOTH for both images and containers"
	fi
	
	if [ $OVALS_INTERPRETER = "OVALDI" ]; then
		if [ $SCAN_TYPE = "BOTH" ] || [ $SCAN_TYPE = "IMAGE" ]; then
			>&2 echo "Cannot use OVALDI interpreter for IMAGE or BOTH scan type"
			>&2 echo "Please use OSCAP as the interpreter if you want to scan images and/or images and containers"
			exit 1
		fi
	fi
}


main() {
	checkInputValues
	connect
	getDepotSoftwareKeyAndInstallCommand
	updateInstallCommand
	executeJob
	revertBackInstallCommand
	waitForJobRunToComplete
	collateResults
}

main