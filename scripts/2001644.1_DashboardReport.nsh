#!/bin/nsh
#Do not change the name of the DashboardReport.nsh

EXIT_CODE=0
echo "Executing Dashboard Job..."

logAndExitIfError()
{
      if [ $1 -ne 0 ]
      then
            echo "$2"         
            echo "Exiting..."
            exit $1
      fi
}
logAndContinueIfError()
{
      if [ $1 -ne 0 ]
      then
            EXIT_CODE=1
            echo "$2"       
      fi
}
storeVarOrLogError()
{
      if [ $1 -ne 0 ]
      then
            echo "$2"
      else
            blcli_storeenv "$3"
      fi
}
executeDashboardJob() 
{
      echo "Executing Dashboard generation cli"
      blcli_execute Utility generateDashboardReport 
      logAndExitIfError $? "$BLCLI_ERROR_MSG"
}
executeDashboardJob

if [ $EXIT_CODE -eq 0 ]; then
      echo "Successfully executed Dashboard job."
fi
exit $EXIT_CODE
