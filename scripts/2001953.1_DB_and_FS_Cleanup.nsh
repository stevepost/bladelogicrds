#!/bin/nsh
################################################################################
#  DB_and_FS_Delete.nsh
#
#  Check and clean various elements of the Bladelogic infrastructure 
# -----------------------------------------------------------------------------
# Author: BladeLogic, Inc.
# Date: 2010-03-04
# -----------------------------------------------------------------------------
# Revisions
#  The script uses blcli instead of blcli_execute. The blcli_execute writes out
#  any messages (stdout/stderr) after the launched command finished.
#  It does not allow to monitor any command execution progress.
# -----------------------------------------------------------------------------
# Arguments
#
# $1: MODE - Execution mode
#     Allowed values are TYPICAL, HISTORY, HISTORY_O, HISTORY_RDR, HISTORY_ORDR, RETENTION, CLEAN_DB,
#     CLEAN_DB_TL, CLEAN_SHARED_OBJECTS, CLEAN_FS, CLEAN_FS_TL, CLEAN_AGENT, CLEAN_ALL_AS
#     CLEAN_AS, CLEAN_REPEATER, CHECK_FS. 
# $2: CONTINUE_ON_ERR - Continue execution on error (true/false)
# $3: DURATION - Maximum duration of operation in minutes
# $4: DURATION_DIST - Distribution of the duration across commands
# $5: RETENTION_DAYS - Retention in days
# $6: OBJECT_TYPE - Type of object
# $7: ROLE - Role to cleanup objects from 
# $8: TARGET_LIST - List of device targets
# $9: MAX_MEGS - Target size in MB of the repeater repository 
#
# -----------------------------------------------------------------------------
# Execution modes
#
# TYPICAL - BladeLogic recommend cleanup steps
#   Optional arguments are: CONTINUE_ON_ERR, DURATION, DURATION_DIST, RETENTION_DAYS and ROLE
#
# HISTORY - BladeLogic historical data cleanup based on retention time
#   No additional arguments
#
# HISTORY_O - BladeLogic historical data cleanup for type of object
#   Required argument is: OBJECT_TYPE
#
# HISTORY_RDR - BladeLogic objects older than RETENTION_DAYS days historical data cleanup for ROLE. Runtime duration DURATION minutes.
#   Required argument are:  RETENTION_DAYS DURATION ROLE
#
# HISTORY_ORDR - BladeLogic objects older than RETENTION_DAYS days historical data cleanup for type of object and for ROLE. Runtime duration DURATION minutes.
#   Required argument are: OBJECT_TYPE RETENTION_DAYS DURATION ROLE
#
# RETENTION - BladeLogic retention policy enforcement
#   No additional arguments
#
# CLEAN_DB - BladeLogic Database cleanup
#   No additional arguments
#
# CLEAN_DB_TL - BladeLogic Database cleanup with duration limitation DURATION minutes
#   Required argument are: CONTINUE_ON_ERR DURATION
#
# CLEAN_SHARED_OBJECTS - BladeLogic cleanup of all types of shared objects with duration limitation DURATION minutes
#   Required arguments are: CONTINUE_ON_ERR DURATION
#
# CLEAN_FS - BladeLogic FileServer cleanup
#   No additional arguments
#
# CLEAN_FS_TL - BladeLogic FileServer cleanup with duration limitation DURATION minutes
#   Required argument is: DURATION
#
# CLEAN_AGENT - BladeLogic RSCD Agent temporary files older than RETENTION_DAYS days cleanup (transactions, staging, ...)
#   Required argument is: RETENTION_DAYS
#
# CLEAN_ALL_AS - BladeLogic ApplicationServer caches cleanup (files older than RETENTION_DAYS days on all AppServers)
#   Required argument is: RETENTION_DAYS
#
# CLEAN_AS - BladeLogic ApplicationServer caches cleanup (files older than RETENTION_DAYS days)
#   Required arguments are: RETENTION_DAYS and TARGET_LIST
#
# CLEAN_REPEATER - BladeLogic Repeater cleanup (shrink repeater staging dirs to MAX_MEGS Mb by removing files unaccessed for RETENTION_DAYS days)
#   Required arguments are: RETENTION_DAYS, TARGET_LIST and MAX_MEGS
#
# CHECK_FS - BladeLogic FileServer integrity check
#   No additional arguments
#
# -----------------------------------------------------------------------------
# Supported BLCLI Delete Commands
#
# Delete cleanupHistoricalData
#
#   The command cleans up a specific type of historical data from the database. Historical data includes 
#   Compliance Job results, Audit Job results, snapshot results, job run events, job schedules, and the audit trail.
#
# Delete executeRetentionPolicy
#
#   This command marks entries for deletion based on retention time in the BMC BladeLogic database. It marks old 
#   job runs and automatically created jobs and depot objects.
#
# Delete cleanupDatabase
#
#   This command deletes database rows for objects that have been previously marked for deletion.
#
# Delete hardDeleteAllSharedObjects
#   This command deletes database rows for shared objects. It includes data for file, file checksum, acl and blvalue.
#
# Delete cleanupFileServer
#
#   This command cleans all the unused files from the file server and from temporary file storage on the Application Server.
#
# Delete cleanupAgent
#
#   This command cleans up old temporary files on a target server (agent). This includes old files that were created by
#   Deploy Jobs (transactions, staging, etc.)
#
# Delete cleanupAllAppServerCaches
#
#   This command deletes old temporary files on all the Application Servers that are currently up and running (and accessible).
#
# Delete cleanupAppServerCache
#   
#   This command deletes old temporary files on a specific Application Server.
#
# Delete cleanupRepeater
#
#   This command cleans up files from the staging directory of a repeater server.
#
#
################################################################################
# set -x

################################################################################
# -----------------------------------------------------------------------------
# Script arguments

MODE=TYPICAL
CONTINUE_ON_ERR=true
DURATION=720
DURATION_DIST=""
RETENTION_DAYS=14
OBJECT_TYPE=""
ROLE="null"
TARGET_LIST=""
MAX_MEGS=""

while getopts m:c:d:p:r:o:R:t:s:h: Option
	do
	case "${Option}" in
		m) MODE="${OPTARG}"
		;;
		c) CONTINUE_ON_ERR="${OPTARG}"
		;;
		d) DURATION="${OPTARG}"
		;;
		p) DURATION_DIST="${OPTARG}"
		;;
		r) RETENTION_DAYS="${OPTARG}"
		;;
		o) OBJECT_TYPE="${OPTARG}"
		;;
		R) ROLE="${OPTARG}"
		;;
		t) TARGET_LIST="${OPTARG}"
		;;
		s) MAX_MEGS="${OPTARG}"
		;;
		h) HOSTS="${OPTARG}"
		;;
	esac
done


# overall max. duration = 720 min (100%)
TYPICAL_DEFAULT_DURATION=720
# cleanupHistoricalData = 30% (216 min), cleanupDatabase = 40% (288 min), hardDeleteAllSharedData = 20% (144 min), cleanupFileServer = 10% (72 min)
TYPICAL_DEFAULT_DURATION_DIST=(cleanupHistoricalData=30 cleanupDatabase=40 hardDeleteAllSharedObjects=20 cleanupFileServer=10)

# The default retention time for JobRunEvent, AuditTrail, cleanupRepeater, cleanupAppServerCache
DEFAULT_RETENTION_DAYS=14


# -----------------------------------------------------------------------------
isEmpty() # return 0=y, 1=no
{
  inp=$1

  inp=`echo $inp | tr -d '"' | tr -d "'"`  
  
  len=`blexpr "strlen(\"${inp}\")"` 

  # On windows it returns a string with carriage return.  
  len=`echo $len | tr -d '\r'`
  
  if [ "$len" -ne 0 ]
  then
    return 1    
  fi
  
  return 0
}
# -----------------------------------------------------------------------------

# Argument input validation
if [ "$CONTINUE_ON_ERR" = "" ]
then
  CONTINUE_ON_ERR=true
else
  case "$CONTINUE_ON_ERR" in
    true)  ;;
    false) ;;
    *)     echo "Invalid value for argument CONTINUE_ON_ERR: $CONTINUE_ON_ERR [true|false]"
           exit 1
           ;;
  esac
fi

if [ "$DURATION" = "" ]
then
  DURATION=$TYPICAL_DEFAULT_DURATION
fi

if isEmpty "$DURATION"
then
  DURATION=$TYPICAL_DEFAULT_DURATION
fi

if [ "$DURATION_DIST" = "" ]
then
  DURATION_DIST=$TYPICAL_DEFAULT_DURATION_DIST
else
  DURATION_DIST=`echo $DURATION_DIST | tr -d '"' | tr -d "'"`  
fi

if isEmpty "$DURATION_DIST"
then
  DURATION_DIST=$TYPICAL_DEFAULT_DURATION_DIST
fi

if [ "$RETENTION_DAYS" = "" ]
then
  RETENTION_DAYS=$DEFAULT_RETENTION_DAYS
fi

if isEmpty "$RETENTION_DAYS"
then
  RETENTION_DAYS=$DEFAULT_RETENTION_DAYS
fi

# -----------------------------------------------------------------------------
checkDurationDist()
{
  overall_percent=0
  
  for i in ${DURATION_DIST[@]}
  do
    tmp=$i
    
    percent=${tmp#*=}     
    
    # echo "percent: $percent"
    
    if [ "$percent" -lt 5 ]
    then
      echo "${tmp} defines a duration of less than 5%"
      exit 1
    fi
    
    overall_percent=`blexpr $percent + $overall_percent`
    
    # On windows it returns a string with carriage return.  
    overall_percent=`echo $overall_percent | tr -d '\r'`
    
  done
  
  
  # echo $overall_percent

  if [ "$overall_percent" -ne 100 ]
  then
    echo "The sum of all percent durations is not 100%"
    exit 1
  fi  
}
# -----------------------------------------------------------------------------
# It returns the duration time based on the delete command name like
# getDuration JobRunEvent
getDuration()
{
  cmd=$1

  # echo $cmd

  for i in ${DURATION_DIST[@]}
  do
    tmp=$i

    len=`blexpr "strlen(strstr(\"${tmp}\",\"${cmd}\"))"` 

    # On windows it returns a string with carriage return.  
    len=`echo $len | tr -d '\r'`

    # if [ `expr match "$tmp" ${cmd}` != 0 ]
    if [ "$len" -ne 0 ]
    then
      percent=${tmp#*=} 
      # echo "percent: $percent"
      amount=`blexpr $DURATION \* $percent`
      
      # On windows it returns a string with carriage return.  
      amount=`echo $amount | tr -d '\r'`
      
      # echo "amount: $amount"
      dur=`blexpr $amount / 100`
      
      # On windows it returns a string with carriage return.  
      dur=`echo $dur | tr -d '\r'`
      
      return $dur
    fi
  done
}


month_to_number()
{
  # Convert variations of month input to a number....
	case $1 in
		Jan|1|01) echo 1;;
		Feb|2|02) echo 2;;
		Mar|3|03) echo 3;;
		Apr|4|04) echo 4;;
 	    May|Maj|5|05) echo 5;;
		Jun|6|06) echo 6;;
		Jul|7|07) echo 7;;
		Aug|8|08) echo 8;;
		Sep|9|09) echo 9;;
	      Oct|Okt|10) echo 10;;
		  Nov|11) echo 11;;
		  Dec|12) echo 12;;
		       *) echo Specified format for month:$1 is not in table;exit;;
	esac
}




leapyear()	# Is a year a leapyear? return 0=y, 1=no
{
	YEAR_TO_TEST=$1
        if [ $(($YEAR_TO_TEST % 400 )) -eq 0 ]
        then
                # leapyear
                return 0
        else
                if [ $(($YEAR_TO_TEST % 100 )) -eq 0 ]
                then
                        #  not leapyear
                        return 1
                elif [ $(($YEAR_TO_TEST % 4 )) -eq 0 ]
                then
                        # leapyear
                        return 0
                else
                        # not leapyear
                        return 1 
                fi
        fi
}




no_of_days_in_month()
{
    # Match month no.|name against table of months, return no_of days.
    # Supply YEAR as $2 for determining the no. of days of February
    #  - Except when calculating the no. of MONTHS, where you
    # need to supply the stored copy of the input year, $YEAR1 as $2.
    #
    case $1 in
        1)  echo 31 ;;
        2)  if leapyear $2; then echo 29; else echo 28; fi ;;
        3)  echo 31 ;;
        4)  echo 30 ;;
    	5)  echo 31 ;;
        6)  echo 30 ;;
        7)  echo 31 ;;
        8)  echo 31 ;;
        9)  echo 30 ;;
       10)  echo 31 ;;
       11)  echo 30 ;;
       12)  echo 31 ;;
        *)  echo  "Specified number:$1 for month is not in table";exit 1 ;;
    esac
}

currentTimestamp() # returns the current time in seconds since 2000-1-1
{
  REFERENCE_YEAR=2000
  CENTURY=`date +%C`
  YEAR_TD=`date +%y`
  YEAR=${CENTURY}${YEAR_TD}
  MONTH=`date +%m`
  DAY=`date +%d`
  HOUR=`date +%H`
  MINUTE=`date +%M`
  SECS=`date +%S`

  MONTH=$( month_to_number $MONTH );

  # Subtract last month
  MONTH=$(( $MONTH - 1 ));

  # Subtract one day
  DAY=$(( $DAY - 1 ))

  # Remember input year for leapyear test
  YEAR1=$YEAR

  # Calculate no. of days of the years back to REFERENCE_YEAR, sum 
  # and turn into seconds.
  while [ $YEAR -gt ${REFERENCE_YEAR} ]
  do
    if leapyear $YEAR
    then
      YEARS_TO_DAYS=$(( $YEARS_TO_DAYS + 366 ))
    else
      YEARS_TO_DAYS=$(( $YEARS_TO_DAYS + 365 ))
    fi
    YEAR=$(( $YEAR - 1 ))
  done

  # Calculate number of months passed since beginning of the
  # year entered till, and including, the last day of the
  # month before the month entered.
  while [ $MONTH -gt 0 ]
  do
    MONTHS_TO_DAYS=$(( $MONTHS_TO_DAYS + $(no_of_days_in_month $MONTH $YEAR1) ))
    MONTH=$(( $MONTH - 1 ))
  done

  # Sum the full days of years, months and days:
  SUM_OF_DAYS=$(( $YEARS_TO_DAYS + $MONTHS_TO_DAYS + $DAY ))

  # Turn full days into secs.:
  DAYS_TO_SECONDS=$(( $SUM_OF_DAYS * 24 * 60 * 60 )) 

  # Turn entered hour into secs.:
  HOUR_TO_SECONDS=$(($HOUR * 60 * 60))

  # Turn entered minute into secs.:
  MINUTES_TO_SECONDS=$(($MINUTE * 60))

  # Sum everything ....
  SUM_OF_SECONDS=$(( $DAYS_TO_SECONDS + $HOUR_TO_SECONDS + $MINUTES_TO_SECONDS + $SECS ))


  # Write out result
  # echo $SUM_OF_SECONDS

  return $SUM_OF_SECONDS
}

timestampDiff() # minutes diff: $1 - start timestamp in seconds $2 - end timestamp in seconds
{
  dte1=$1
  dte2=$2
  diffSec=$((dte2-dte1))
  # echo $diffSec
  if ((diffSec < 0)); then abs=-1; else abs=1; fi
  diffMin=$((diffSec*abs/60))
  # echo $diffMin
  return $diffMin
}


checkIsExpired() # run-time expired: $1 - start date $2 - end date $3 - allowed duration in minutes
{
  diffMin=$(timestampDiff "$1" "$2")
  allowed=$3

  # echo $1 $2 $3

  if ((diffMin > allowed));
  then
    echo "Command expired";
    exit 0;
  fi
}

checkIsFailed() # last exit code: $1 - last executed command: $2
{
  lastExitCode=$1
  lastExecCmd="$2"

  if [ "$lastExitCode" -ne 0 ]
  then
    lastErrorCode=$lastExitCode
    lastFailedCmd=${lastExecCmd}
    
    if [ "$CONTINUE_ON_ERR" = "false" ]
    then
      # Something failed in the blcli execution. Let the user know.
      echo "";
      echo "${lastFailedCmd} failed in the blcli execution : $MESSAGE.";
      exit $lastExitCode;
    fi
  fi

}
# -----------------------------------------------------------------------------




case $MODE in

  TYPICAL)        MESSAGE="BladeLogic recommend cleanup steps"
								ARGUMENT_NAMES=()
                                ARGUMENT_VALUES=($CONTINUE_ON_ERR $DURATION $DURATION_DIST $RETENTION_DAYS $ROLE)
                                DO_LOOPS="false" ;;

  HISTORY)	MESSAGE="BladeLogic historical data cleanup based on retention time"
				NAMESPACE="Delete cleanupHistoricalData"
								ARGUMENT_NAMES=()
                                ARGUMENT_VALUES=()
				DO_LOOPS="false" ;;
				
  HISTORY_O)	MESSAGE="BladeLogic $OBJECT_TYPE historical data cleanup"
				NAMESPACE="Delete cleanupHistoricalData"
								ARGUMENT_NAMES=(OBJECT_TYPE)
                                ARGUMENT_VALUES=($OBJECT_TYPE)
				DO_LOOPS="false" ;;

  HISTORY_RDR)	MESSAGE="BladeLogic objects older than $RETENTION_DAYS days historical data cleanup for $ROLE. Runtime duration $DURATION minutes."
				NAMESPACE="Delete cleanupHistoricalData"
								ARGUMENT_NAMES=(RETENTION_DAYS DURATION ROLE)
                                ARGUMENT_VALUES=($RETENTION_DAYS $DURATION $ROLE)
				DO_LOOPS="false" ;;

  HISTORY_ORDR)	MESSAGE="BladeLogic $OBJECT_TYPE historical deletion older than $RETENTION_DAYS days for $ROLE. Runtime duration $DURATION minutes."
				NAMESPACE="Delete cleanupHistoricalData"
								ARGUMENT_NAMES=(OBJECT_TYPE RETENTION_DAYS DURATION ROLE)
                                ARGUMENT_VALUES=($OBJECT_TYPE $RETENTION_DAYS $DURATION $ROLE)
				DO_LOOPS="false" ;;

  RETENTION)	MESSAGE="BladeLogic retention policy enforcement"
				NAMESPACE="Delete executeRetentionPolicy"
								ARGUMENT_NAMES=()
                                ARGUMENT_VALUES=()
				DO_LOOPS="false" ;;


  CLEAN_DB)	MESSAGE="BladeLogic Database cleanup"
				NAMESPACE="Delete cleanupDatabase"
								ARGUMENT_NAMES=()
                                ARGUMENT_VALUES=()
				DO_LOOPS="false" ;;

  CLEAN_DB_TL)	MESSAGE="BladeLogic Database cleanup with duration limitation $DURATION minutes"
					NAMESPACE="Delete cleanupDatabase"
				ARGUMENT_NAMES=(CONTINUE_ON_ERR DURATION)
                                ARGUMENT_VALUES=($CONTINUE_ON_ERR $DURATION)
					DO_LOOPS="false" ;;


  CLEAN_SHARED_OBJECTS)	MESSAGE="BladeLogic cleanup of all types of shared objects with duration limitation $DURATION minutes"
					NAMESPACE="Delete hardDeleteAllSharedObjects"
								ARGUMENT_NAMES=(CONTINUE_ON_ERR DURATION)
                                ARGUMENT_VALUES=($CONTINUE_ON_ERR $DURATION)
					DO_LOOPS="false" ;;


  CLEAN_FS)	MESSAGE="BladeLogic FileServer cleanup"
				NAMESPACE="Delete cleanupFileServer"
								ARGUMENT_NAMES=()
                                ARGUMENT_VALUES=()
				DO_LOOPS="false" ;;

  CLEAN_FS_TL)	MESSAGE="BladeLogic FileServer cleanup with duration limitation $DURATION minutes"
					NAMESPACE="Delete cleanupFileServer"
								ARGUMENT_NAMES=(DURATION)
                                ARGUMENT_VALUES=($DURATION)
					DO_LOOPS="false" ;;

  CLEAN_AGENT)	MESSAGE="BladeLogic RSCD Agent temporary files older than $RETENTION_DAYS days cleanup (transactions, staging, ...)"
					NAMESPACE="Delete cleanupAgent"
								ARGUMENT_NAMES=(RETENTION_DAYS)
                                ARGUMENT_VALUES=($RETENTION_DAYS)
					DO_LOOPS="true" ;;

  CLEAN_ALL_AS)	MESSAGE="BladeLogic ApplicationServer caches cleanup (files older than $RETENTION_DAYS days on all AppServers)"
					NAMESPACE="Delete cleanupAllAppServerCaches"
								ARGUMENT_NAMES=(RETENTION_DAYS)
                                ARGUMENT_VALUES=($RETENTION_DAYS)
					DO_LOOPS="false" ;;

  CLEAN_AS)	MESSAGE="BladeLogic ApplicationServer caches cleanup (files older than $RETENTION_DAYS days)"
				NAMESPACE="Delete cleanupAppServerCache"
								ARGUMENT_NAMES=(RETENTION_DAYS)
                                ARGUMENT_VALUES=($RETENTION_DAYS)
				DO_LOOPS="true" ;;

	
  CLEAN_REPEATER)	MESSAGE="BladeLogic Repeater cleanup (shrink repeater staging dirs to $MAX_MEGS Mb by removing files unaccessed for $RETENTION_DAYS days)"
					NAMESPACE="Delete cleanupRepeater"                                        
								ARGUMENT_NAMES=(RETENTION_DAYS MAX_MEGS)
                                ARGUMENT_VALUES=($RETENTION_DAYS $MAX_MEGS)
					DO_LOOPS="true" ;;
	

  CHECK_FS)	MESSAGE="BladeLogic FileServer integrity check"
				NAMESPACE="Delete checkFileServerIntegrity" 
								ARGUMENT_NAMES=()
                                ARGUMENT_VALUES=()
				DO_LOOPS="false" ;;

    *)     echo "Invalid value for argument MODE: $MODE"
           exit 1
           ;;

esac


# required argument values
if [ "${#ARGUMENT_NAMES[@]}" -ne 0 ]
then
  if [ "${#ARGUMENT_NAMES[@]}" -ne "${#ARGUMENT_VALUES[@]}" ]
  then
    echo "Invalid argument values for MODE: $MODE"
    echo "It requires values for ${ARGUMENT_NAMES[@]}"
    exit 1
  fi
fi

checkDurationDist


echo "Action launched: $MESSAGE"

if [ "$DO_LOOPS" = "true" ]
then
  for TARGET in $TARGET_LIST
  do
    blcli_cmd="$NAMESPACE $TARGET ${ARGUMENT_VALUES[@]}"

    echo "Command: $blcli_cmd"

    cmdOutput=`blcli -n false $NAMESPACE $TARGET ${ARGUMENT_VALUES[@]}`

    ########
    ### Make sure we did not have errors
    ########
    retvalue=$?
    
    # enforce failure immediately
    if [[ `echo "$cmdOutput" | grep -E "[aA]ccess [dD]enied"` != "" ]]
    then
      echo "$cmdOutput"
      CONTINUE_ON_ERR=false
    fi
    

    checkIsFailed "$retvalue" "$NAMESPACE $TARGET"
  done
else
  if [ "$MODE" = "TYPICAL" ]
  then
    if [ "$DURATION" -lt 120 ]
    then
      echo "The duration time cannot be less than 120 minutes"
      exit 1
    fi
    
    currentTimestamp
    startDte=$?

    echo "Running cleanupHistoricalData"
	blcli -n false Delete cleanupHistoricalData
	retvalue=$?

    currentTimestamp
    endDte=$?
    checkIsExpired "$startDte" "$endDte" "$DURATION"

    cmdOutput=`blcli -n false Delete executeRetentionPolicy`
    retvalue=$?

	echo "$cmdOutput"
    checkIsFailed "$retvalue" "Retention Policy"

    currentTimestamp
    endDte=$?
    checkIsExpired "$startDte" "$endDte" "$DURATION"


    getDuration cleanupDatabase
    dbDuration=$?
    echo "Clean Database data (max $dbDuration minutes)"
    blcli -n false Delete cleanupDatabase $CONTINUE_ON_ERR $dbDuration
    retvalue=$?

    checkIsFailed "$retvalue" "Database"

    currentTimestamp
    endDte=$?
    checkIsExpired "$startDte" "$endDte" "$DURATION"


    getDuration hardDeleteAllSharedObjects
    sharedObjectsDuration=$?
    echo "Clean Shared Objects data (max $sharedObjectsDuration minutes)"
    blcli -n false Delete hardDeleteAllSharedObjects $CONTINUE_ON_ERR $sharedObjectsDuration
    retvalue=$?

    checkIsFailed "$retvalue" "Shared Objects"

    currentTimestamp
    endDte=$?
    checkIsExpired "$startDte" "$endDte" "$DURATION"

    getDuration cleanupFileServer
    fileServerDuration=$?
    echo "Clean File Server (max $fileServerDuration minutes)"
    blcli -n false Delete cleanupFileServer $fileServerDuration
    retvalue=$?

    checkIsFailed "$retvalue" "File Server"
  else
    blcli_cmd="$NAMESPACE ${ARGUMENT_VALUES[@]}"

    echo "Command: $blcli_cmd"

    blcli -n false $NAMESPACE ${ARGUMENT_VALUES[@]}

    # for test purposes only: blcli -v defaultProfile $NAMESPACE ${ARGUMENT_VALUES[@]}

    ########
    ### Make sure we did not have errors
    ########
    retvalue=$?
    
    checkIsFailed "$retvalue" "$NAMESPACE"   
  fi
fi

if [ "$lastErrorCode" -ne 0 ]
then
  # Something failed in the blcli execution. Let the user know.
  echo ""
  #Fix for defect QM001885604
  #echo "The command '${lastFailedCmd}' failed. Please run 'Cleanup Diagnostic Test' for further details." 1>&2
  
  exit $lastErrorCode  
fi

exit $retvalue
