#!/bin/nsh
bluser=
blrole=
blpassword=
blprofile=
retention=5
bdssaServer=
send_notification=
from_email_id=
to_email_id=
OS=
BSA_INSTALL=
NULL=
IS_APP_SERVER=
HOST_NAME=
configFile=
configBackupFile=
fsName=
fsLocation=
fsPath=
DASHBOARD_ZIP_FILE_NAME=
FS_ZIP_CKSUM=
COPY_NEED=0
JS_ZIP_CKSUM=
WIN_BSA_INSTALL=
FS_REPORTS_DIR=
LATEST_REPORTS_DIR=
RESETUP_TOOL=false

function printUsage()
{
    echo
    echo "Usage:"
    echo "------"
	echo "<script_name> [BLUser] [BLRole] [BLPassword] [BLProfile]"
	echo
	echo "Arguments:"
    echo "--------------"
    echo "1 : BLUser"
    echo "2 : BLRole"
    echo "3 : BLPassword"
    echo "4 : BLProfile"
    echo "5 : BDSSA Server Host"
    echo "6 : Retention : Integer value which keeps the same number of reports on Job Server and cleans up additional reports."
    echo "    Default Value: 5"
    exit 1
}

function parseOptions()
{
    if [ $# -eq 0 ] ; then
        printUsage
    fi
	
	bluser=$1
	blrole=$2
	blpassword=$3
	blprofile=$4
	if [ "$5" = "" ] || [ "$5" = "-h" ]; then
        retention=5
	else
		retention=$5    
    fi
	if [ "$6" = "" ] || [ "$6" = "-h" ]; then
        send_notification="n"
	else
		send_notification=$6    
    fi
    if [ "$7" = "" ] || [ "$7" = "-h" ]; then
        from_email_id=
	else
		from_email_id=$7   
    fi
    if [ "$8" = "" ] || [ "$8" = "-h" ]; then
        to_email_id=
	else
		to_email_id=$8   
    fi
    if [ "$9" = "" ] || [ "$9" = "-h" ] ; then
    	bdssaServer=
	else
		bdssaServer=$9
	fi
}

init_()
{
	OS="$(uname -s)"
	
	if [ "${OS}" = "WindowsNT" ]
		then
		BSA_INSTALL="$(cat /C/Windows/rsc/HOME | sed "s/\/cygdrive//" | tr -d '[:cntrl:]')"
		DASHBOARD_EXEC="dashboard.bat"
		NULL=NUL
	else
		BSA_INSTALL="$(cat /usr/lib/rsc/HOME)"
		DASHBOARD_EXEC="dashboard.sh"
		NULL=/dev/null
	fi
	
	# check if this is an appserver
	if [ ! -f "${BSA_INSTALL}/br/blasadmin" ] && [ ! -f "${BSA_INSTALL}/bin/blasadmin.exe" ]
		then
		echo "Warning : This utility must run from the BSA application server for App Server reports."
		IS_APP_SERVER=1
	fi
	
	HOST_NAME="$(hostname)"
	
	configFile="//${HOST_NAME}${BSA_INSTALL}/dashboard/config.properties"
	configBackupFile="//${HOST_NAME}${BSA_INSTALL}/dashboard/config_backup.properties"

	echo "BSA Installation Location : //${HOST_NAME}${BSA_INSTALL}"
	
	fsName="$(blasadmin -s _template show FileServer name 2>${NULL} | grep name: | awk -F ':' '{print $NF}')"
	fsLocation="$(blasadmin -s _template show FileServer location 2>${NULL} | grep location: | awk -F ':' '{print $NF}')"
	fsPath="//$fsName$fsLocation"
	echo "File Server Path : $fsPath"
	
	DASHBOARD_ZIP_FILE_NAME=`ls -tr "${fsPath}dashboard" | grep "^dashboard" | grep ".zip$" | tail -1`
	#echo $DASHBOARD_ZIP_FILE_NAME
	
	if [ ${DASHBOARD_ZIP_FILE_NAME} = "" ]
	then
		echo "Dashboard tool can not be located on file server, please upload the same at location ${fsPath}dashboard"
		exit 1
	fi	
	
	FS_ZIP_CKSUM=`cksum "${fsPath}dashboard/${DASHBOARD_ZIP_FILE_NAME}" | awk -F' ' '{print $1}'`
	#echo "cksum-${FS_ZIP_CKSUM}"
	
	if [ ! -f "//${HOST_NAME}${BSA_INSTALL}/${DASHBOARD_ZIP_FILE_NAME}" ]
	then
		echo "Dashboard tool do not exists !"
		COPY_NEED=1
	else
		JS_ZIP_CKSUM=`cksum "//${HOST_NAME}${BSA_INSTALL}/${DASHBOARD_ZIP_FILE_NAME}" | awk -F' ' '{print $1}'`
		#echo "JS_ZIP_CKSUM-$JS_ZIP_CKSUM"
		if [ $FS_ZIP_CKSUM != $JS_ZIP_CKSUM ]
		then
			COPY_NEED=1
			echo "Dashboard tool exists with different version."	
		else
			if [ ! -d "//${HOST_NAME}${BSA_INSTALL}/dashboard" ]; then
			  	COPY_NEED=1
			  	echo "Dashboard tool needs to be re-configured."
			else
				if [ ! -f "//${HOST_NAME}${BSA_INSTALL}/dashboard/$DASHBOARD_EXEC" ]
				then
					echo "Dashboard executable do not exists, tool needs to be re-setup."
					RESETUP_TOOL=true
				else	
					echo "Dashboard tool already exists ! Skipping few steps."
				fi				  
			fi		
		fi			
	fi	
}

copyAndExtractTool()
{
	echo "Copying Dashboard zip from file server..."
	cp "${fsPath}dashboard/${DASHBOARD_ZIP_FILE_NAME}" "//${HOST_NAME}${BSA_INSTALL}"
	
	if [ $? -eq 0 ]
		then
			echo "Dashboard zip copied successfully."
		else
			echo "Error while copying dashboard zip. Exiting..."
			exit 1
	fi
	
	echo "Extracting Dashboard zip..."
	
	unzip -u -o -q "//${HOST_NAME}${BSA_INSTALL}/${DASHBOARD_ZIP_FILE_NAME}" -d "//${HOST_NAME}${BSA_INSTALL}/"
	chmod -R 777 "//${HOST_NAME}${BSA_INSTALL}/dashboard"
	
	if [ $? -eq 0 ]
		then
			echo "Dashboard zip extracted successfully."
		else
			echo "Error while extracting dashboard zip. Exiting..."
			exit 1
	fi
}

editProp()
{
	prop=$1
	arg=$2
	if grep -Fq $prop "$configFile" ; then
	    sed -e "s/^[#]*${prop}=.*/${prop}=${arg}/" "$configFile" > "$configBackupFile"
	    cp -f "$configBackupFile" "$configFile" 
	else
	    echo $prop=$arg >> "$configFile"
	fi
	chmod 777 "$configFile"
}

configureProp()
{
	echo "Setting up params..."
	editProp "bluser" $bluser
	editProp "blrole" $blrole
	editProp "blpassword" $blpassword
	editProp "blprofile" $blprofile
	editProp "bdssa.server" $bdssaServer
	editProp "max.old.reports" $retention
	editProp "send.notification" $send_notification
	editProp "from.email.id" $from_email_id
	editProp "to.email.id" $to_email_id
#	editProp "recheck.count" $recheck_count
	
	rm -f "$configBackupFile"
	
	bdssaPropFile="//${HOST_NAME}${BSA_INSTALL}/dashboard/bdssa.properties"
	#echo "bdssa server value in job = $bdssaServer"
	if [[ "${bdssaServer}" = "" ]]
		then
			echo "Warning : BDSSA server not specified. BDSSA report will not be populated"
		else
			BDSSA_SERVER="$bdssaServer"
			update_bdssa_flag=false
			if [ -f "$bdssaPropFile" ] 
			then
				BDSSA_SERVER=`cat "$bdssaPropFile" | egrep bdssa.server | cut -d"=" -f2`
				if [ "$BDSSA_SERVER" = "" ]
				then
					BDSSA_SERVER="$bdssaServer"
					update_bdssa_flag=true
				fi
			else
				update_bdssa_flag=true		
			fi		
			
			echo "Using BDSSA host : ${bdssaServer}" 			
			if [ "$BDSSA_SERVER" != "$bdssaServer" ] || [ "$update_bdssa_flag" = true ]
			then
				echo "Configuring BDSSA properties..."
				echo "bdssa.server=${bdssaServer}" > "$bdssaPropFile"
				nexec -i -ncq ${bdssaServer} nsh -c 'egrep -s \"DATABASE_TYPE|BSA_DATABASE_HOSTNAME|BSA_DATABASE_PORT|BSA_DATABASE_NAME_SID|BSA_DATABASE_USER|BSA_DATABASE_PASSWORD|BSA_WORK_DATABASE_HOSTNAME|BSA_WORK_DATABASE_PORT|BSA_WORK_DATABASE_NAME_SID|BSA_WORK_DATABASE_USER|BSA_WORK_DATABASE_PASSWORD\" \"$BDS_HOME/shared/ConfigurationManagement/bds.properties\"' >> "$bdssaPropFile"
				nexec -i -ncq ${bdssaServer} nsh -c 'egrep -s \"className|userName|password|connectionString\" \"$BLREPORTS_HOME/bin/blreports_config.properties\"' >> "$bdssaPropFile"
				nexec -i -ncq ${bdssaServer} nsh -c 'egrep -s \"odi_execution_repo_driver_name|odi_execution_repo_url|odi_execution_repo_db_user_name|odi_execution_repo_db_user_password\" \"$BLREPORTS_HOME/bin/odi_settings.properties\"' >> "$bdssaPropFile"
			fi
	fi	
}

setupTool()
{
	cd "${BSA_INSTALL}/dashboard/"
	./setup.nsh dashboard
	rm -f ./NUL
}

runTool()
{
	echo "Generating Dashboard Reports..."
	cd "${BSA_INSTALL}/dashboard/"

	if [ "${OS}" = "WindowsNT" ]
	then
		cmd /c dashboard.bat
	else
		sh ./dashboard.sh
	fi
	
	if [ $? -eq 0 ]
		then
			echo "Dashboard reports generated successfully."
		else
			echo "Error while generating dashboard reports. Exiting..."
			exit 1
	fi
}

copyReports()
{
	FS_REPORTS_DIR="${fsPath}dashboard/reports"
	FS_REPORTS_LATEST_DIR="${FS_REPORTS_DIR}/latest"
	
	if [ ! -d "$FS_REPORTS_DIR" ]; then
	  echo "Reports directory do not exists on file server: creating the same. $FS_REPORTS_DIR"
	  mkdir "$FS_REPORTS_DIR"
	fi
	
	if [ ! -d "$FS_REPORTS_LATEST_DIR" ]; then
	  mkdir "$FS_REPORTS_LATEST_DIR"	
	fi
	
	cd "${BSA_INSTALL}/dashboard/reports"
	LATEST_REPORTS_DIR=`ls -lt | grep "^d" | head -1 | awk -F' ' '{print $9}'`
	if [ "$LATEST_REPORTS_DIR" = "css" ] || [ "$LATEST_REPORTS_DIR" = "images" ]
	then
		LATEST_REPORTS_DIR=`ls -lt | grep "^d" | head -2 | awk -F' ' '{print $9}' | awk 'NR==2'`
		if [ "$LATEST_REPORTS_DIR" = "css" ] || [ "$LATEST_REPORTS_DIR" = "images" ]
		then		
			LATEST_REPORTS_DIR=`ls -lt | grep "^d" | head -3 | awk -F' ' '{print $9}' | awk 'NR==3'`
			if [ "$LATEST_REPORTS_DIR" = "" ]
			then
				echo "ERROR: It looks like reports are not generated, Unable to copy reports..."
				exit 1
			fi		
		fi	
	fi
	#echo "latest reports dir "$LATEST_REPORTS_DIR
	
	CHECK_DIR=`ls -lt "$FS_REPORTS_LATEST_DIR/" | grep "^d" | head -1`
	
	if [ "$CHECK_DIR" != "" ]; then
		for d in "$FS_REPORTS_LATEST_DIR/"*/.; do
	  		rm -rf "${d/.}"
		done
	fi
	
	echo "Copying reports to file server..."
	
	cp -r "//${HOST_NAME}${BSA_INSTALL}/dashboard/reports/${LATEST_REPORTS_DIR}" "${FS_REPORTS_LATEST_DIR}"
	#cp "//${HOST_NAME}${BSA_INSTALL}/dashboard/reports/index.html" "${FS_REPORTS_DIR}"
	echo "latest_report_folder_name_key=${LATEST_REPORTS_DIR}" > "${FS_REPORTS_LATEST_DIR}/latestReportMetaInf.tmp"
	
	#This check is added if css/images folders are not on file server then we need to copy them forcefully.
	COPY_FORCEFULLY=0
	
	if [ ! -d "//${FS_REPORTS_DIR}/css" ] || [ ! -d "//${FS_REPORTS_DIR}/images" ]
	then
	  COPY_FORCEFULLY=1
	fi

	if [ $COPY_NEED = 1 ] || [ $COPY_FORCEFULLY = 1 ]
	then
		rm -rf "${FS_REPORTS_DIR}/css/."
		rm -rf "${FS_REPORTS_DIR}/images/."
		rm -rf "${FS_REPORTS_DIR}/dbChecklist.xlsx"
		
		cp -r "//${HOST_NAME}${BSA_INSTALL}/dashboard/reports/css" "${FS_REPORTS_DIR}"
		cp -r "//${HOST_NAME}${BSA_INSTALL}/dashboard/reports/images" "${FS_REPORTS_DIR}"
		cp "//${HOST_NAME}${BSA_INSTALL}/dashboard/reports/dbChecklist.xlsx" "${FS_REPORTS_DIR}"
		echo "copy_css_images_key=true" >> "${FS_REPORTS_LATEST_DIR}/latestReportMetaInf.tmp"
	else
		echo "copy_css_images_key=false" >> "${FS_REPORTS_LATEST_DIR}/latestReportMetaInf.tmp"
	fi
	echo "Reports copied to file server..."	
}

########
# Main #
########

if [ $# -eq 0 ] ; then
    printUsage
fi

if [ "$1" = "-help" ] ; then
    printUsage
fi

## Get all the command line options and do basic validation
#---------------------------------------------------------
parseOptions $@
init_

if [ $COPY_NEED = 1 ]
then
	copyAndExtractTool	
fi	

configureProp

if [ $COPY_NEED = 1 ] || [ $RESETUP_TOOL = true ]
then
	setupTool	
fi	

runTool	
copyReports