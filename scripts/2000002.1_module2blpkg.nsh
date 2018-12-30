#set -x
#############################################################################################################################
# Copyright 2013 BMC. BMC Software, the BMC logos, and other BMC marks are trademarks or registered                         #
# trademarks of BMC Software, Inc. in the U.S. and/or certain other countries.                                              #
#############################################################################################################################

#******************************************
#******************************************
# THIS IS A NSH SCRIPT.
# DO NOT EXECUTE IT IN REGULAR SHELLS
#******************************************
#******************************************

SCRIPT_VERSION="1.0"

script_name=`basename $0`
list_file_name=
modules_array=()
has_new_blcli="false"
job_deploy_machine="localhost"
root_puppet_group="Puppet"
puppet_module_parent_group="PuppetContent"
puppet_module_group="Modules"
debug_option=0

function printUsage()
{
    echo "\nUsage:"
    echo "------"
    echo "$script_name [-V] [-h Managed Hostname for aiding BSA job creation] -f </AbsolutePath/ModuleList.lst>\n"
	echo "$script_name can be used to create BlPackages of Puppet Modules."
    echo "ModuleList.lst should contain absolute path of tar.gz bundles for puppet modules."
    echo "Each bundle should be named so as to indicate the module it is providing and should contain all the dependency modules"
    echo "e.g.: a ModuleList.lst file that provides a bundle for apache will look like this:"
    echo "[root@my-host modules]# cat ModuleList.lst"
    echo "/root/puppet_5_x86_64/mods/modules/apache.tar.gz"
    echo "[root@my-host modules]# tar ztvf /root/puppet_5_x86_64/mods/modules/apache.tar.gz"
    echo "drwxr-xr-x 502/503         0 2012-08-13 21:20:44 apache/"
    echo "drwxr-xr-x 502/503         0 2013-07-03 13:37:49 apache/files/"
    echo "drwxr-xr-x 502/503         0 2012-08-13 21:20:44 apache/files/mod/"
    echo "-rw-r--r-- 502/503       663 2012-08-13 21:20:44 apache/files/httpd"
    echo "-rw-r--r-- 502/503       218 2012-08-13 21:20:44 apache/Rakefile"
    echo "-rw-r--r-- 502/503      2095 2012-08-13 21:20:44 apache/README.md"
    echo "-rw-r--r-- 502/503      1566 2012-08-13 21:20:44 apache/CHANGELOG"
    echo "drwxr-xr-x 502/503         0 2013-07-03 13:37:49 apache/spec/"
    echo "-rw-r--r-- 502/503       263 2012-08-13 21:20:44 apache/spec/spec_helper.rb"
    echo "drwxr-xr-x 502/503         0 2013-07-03 13:37:49 apache/spec/classes/"
    echo "-rw-r--r-- 502/503       411 2012-08-13 21:20:44 apache/spec/classes/params_spec.rb"
    echo "drwxr-xr-x 502/503         0 2013-07-03 13:37:49 apache/spec/classes/mod/"
    echo
    echo "**** IMPORTANT NOTE **** "
    echo "You need to acquire credentials for connecting to Appserver and set serviceProfile & roleName BEFORE you run this script"
    echo "Commands used for this are: 'blcred cred -acquire ...' and 'blcli_setoption ...'"
    echo "Also ensure that you set the environment variable named BL_AUTH_PROFILE_NAME to the profile you want to use"
    echo "This can be done using the command:  export BL_AUTH_PROFILE_NAME=<profile name>\n"
    exit
}

function printVersion()
{
    echo "\n$script_name Version: $SCRIPT_VERSION BMC Software."
    exit 0
}

function errorPrint()
{
    echo "ERROR:" >&2
    echo "------" >&2
    echo "$1\n" >&2
    exit 1
}

function validatePreConnectOptions()
{
    echo "\nValidating pre connect options ..."
	if [ -z "$list_file_name" ] ; then
        errorPrint "Please provide ModuleList file name using option '-f file name'"
    fi
    if [ ! -e "$list_file_name" -o ! -f "$list_file_name" -o ! -s "$list_file_name" -o ! -r "$list_file_name" ] ; then
       errorPrint "File $list_file_name either does not exist or is invalid."
    fi
    IFS=$'\n'
    for fline in `cat "$list_file_name"` ; do
    	if [ -z "$fline" ] ; then
            echo "Found an empty line, skipping... "
        fi
        fline=`echo "$fline" | tr -d '\r'`
        fline=`echo "$fline" | tr -d '\n'`
        modules_array+=("$fline")
        if [ ! -e "$fline" -o ! -f "$fline" -o ! -s "$fline" -o ! -r "$fline" ] ; then
           errorPrint "File Named $fline specified in $list_file_name either does not exist or is invalid."
        fi
    done
}

function parseOptions()
{
   
	 while getopts ":f:h:dV" opt; do
      case $opt in
        f)
          list_file_name="$OPTARG"
          ;;
        h)
          job_deploy_machine=$OPTARG
          ;;
		d)
          debug_option=1
          ;;
        V)
          printVersion
          ;;
		\?)
          echo "ERROR:" >&2
          echo "------"
          echo "Invalid option: -$OPTARG" >&2
          printUsage
          ;;
        :)
          echo "ERROR:" >&2
          echo "------"
          echo "Option -$OPTARG requires an argument." >&2
          printUsage
          ;;
      esac
    done
}

function checkIfNewBlCli()
{
    # Not redirecting blcli_execute output directly to grep as there is some Java related issue with
    # such usage on Solaris.
    blcli_execute DeployJob createDeployJobWithoutTarget > $PWD/blcliout 2>&1
    grep "DeployJob has no commands by name" $PWD/blcliout > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        # Yay, we have new BLCLI, can use the new commands!
        has_new_blcli="true"
    else
        # Old BLCLI, cannot use the new commands :(
        has_new_blcli="false"
    fi
}

function validatePostConnectOptions()
{
    echo "\nValidating post connect options ..."

    # Lets first find if the BLCLI we are using has commands in DeployJob namespace that allow
    # Job creation without the need to pass a target name.
    checkIfNewBlCli

    if [ "$has_new_blcli" = "false" ] ; then
        # We need name of an enrolled host so as to be able to create a job using BLCLI.
        # If user has passed us a name, lets check if its actually enrolled.
        # Else we will try with "localhost".
        blcli_execute Server getServerIdByName $job_deploy_machine > /dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "\"$job_deploy_machine\" is not enrolled with BSA Appserver."
            if [ $job_deploy_machine = "localhost" ] ; then
                errorPrint "\nThis script uses name of a BSA enrolled host name to create jobs, although only temporarily.\nPlease ensure that a host name is passed using -h option of the script or a host with name \"localhost\" is enrolled with BSA Appserver"
            else
                job_deploy_machine="localhost"
                blcli_execute Server getServerIdByName $job_deploy_machine > /dev/null 2>&1
                if [ $? -ne 0 ] ; then
                    errorPrint "\nThis script uses name of a BSA enrolled host name to create jobs, although only temporarily.\nPlease ensure that a host name is passed using -h option of the script or a host with name \"localhost\" is enrolled with BSA Appserver"
                else
                    echo "Found a host with name \"localhost\" enrolled with BSA, continuing with the same. The host will be used only temporarily for job creation"
                fi
            fi      
        fi
    fi


    cntr=1
    for i in $modules_array ; do
        blcli_execute DepotGroup groupNameToId /$root_puppet_group/$puppet_module_parent_group/$puppet_module_group/$i > /dev/null 2>&1
        if [ $? -eq 0 ] ; then
            echo "A Depot Group by name $i already exists in /$root_puppet_group which indicates that the packages for this module already exist.\nSkipping processing for this module.\n"
            $modules_array[$cntr]=""
        fi
        let cntr=$cntr+1
    done
}

function createPackages()
{
    module_file_path=$1
    if [ -z $module_file_path ] ; then
        errorPrint "createPackages() needs name of a module zip file, received none."
    fi
    module_file_name=`basename $module_file_path`

    package_name=`echo $module_file_name | sed -e 's/.tar.gz//' | sed -e 's/.tgz//'`
    if [ -z $package_name ] ; then
        errorPrint "Unable to derive package name from $module_file_name"
    fi
    DEPOT_GROUP=$package_name
    DEPOT_GROUP_FQDN=/$root_puppet_group/$puppet_module_parent_group/$puppet_module_group/$DEPOT_GROUP
    HOST=`hostname`
    blcli_execute DepotGroup groupNameToId / > /dev/null
    blcli_storeenv ROOT_DG_ID
    blcli_execute DepotGroup groupNameToId /$root_puppet_group > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        blcli_execute DepotGroup createDepotGroup $root_puppet_group $ROOT_DG_ID > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create depot group $root_puppet_group"
        fi
    fi
	blcli_execute DepotGroup groupNameToId /$root_puppet_group > /dev/null
    blcli_storeenv ROOT_PUPPET_ID
    blcli_execute DepotGroup groupNameToId /$root_puppet_group/$puppet_module_parent_group > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        blcli_execute DepotGroup createDepotGroup $puppet_module_parent_group $ROOT_PUPPET_ID > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create depot group $puppet_module_parent_group"
        fi
    fi
	blcli_execute DepotGroup groupNameToId /$root_puppet_group/$puppet_module_parent_group > /dev/null
    blcli_storeenv DEPOT_PUPPET_PARENT_ID
    blcli_execute DepotGroup groupNameToId /$root_puppet_group/$puppet_module_parent_group/$puppet_module_group > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        blcli_execute DepotGroup createDepotGroup $puppet_module_group $DEPOT_PUPPET_PARENT_ID > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create depot group $root_puppet_group"
        fi
    fi
    blcli_storeenv PUPPET_DEPOT_ID

    #===================================================
    # Create a Depot Group For Storing the main package
    # as well as any depot files we might have to create.
    blcli_execute DepotGroup createDepotGroup $DEPOT_GROUP $PUPPET_DEPOT_ID > /dev/null
    if [ $? -ne 0 ]; then
        errorPrint "\nFailed to create depot group $DEPOT_GROUP_FQDN"
    fi
    blcli_storeenv DEPOT_GROUP_ID
    echo "\nCreated Depot Group" $DEPOT_GROUP_FQDN

    #===================================================
    # Create the main blpackage, but with nothing in it as of now.
    blcli_execute BlPackage createEmptyPackage $package_name $package_name $DEPOT_GROUP_ID > /dev/null
    if [ $? -ne 0 ]; then
        errorPrint "\nFailed to create empty package named $package_name"
    fi
    blcli_storeenv MAIN_PACKAGE_ID
    echo "\nCreated Empty BlPackage named:" $package_name "in group" $DEPOT_GROUP

    #===================================================
    # Add the tar.gz file to the package
    blcli_execute DepotFile addFileToDepot $DEPOT_GROUP_FQDN $module_file_path $module_file_name $module_file_name > /dev/null
    if [ $? -ne 0 ]; then
    	echo "\nFailed to add module file $module_file_path to depot group. Cant proceed with creation of package for this module."
        return
    fi
    blcli_storeenv MODULE_BLFILE_ID
    blcli_execute BlPackage importDepotObjectToPackage $DEPOT_GROUP_FQDN $package_name true true true true true $DEPOT_GROUP_FQDN $module_file_name DEPOT_FILE_OBJECT "Action,Owner,Permission,Path" "Add,1,505,??TARGET.STAGING_DIR??/$module_file_name" NotRequired NotRequired > /dev/null
    if [ $? -ne 0 ]; then
	    errorPrint "\nFailed to add module file $module_file_path to blpackage $package_name"
    fi
    blcli_storeenv MAIN_PACKAGE_ID
    echo "\nAdded module file $module_file_path to blpackage $package_name"

    # Add external commands to create the puppet directories and to create the site.pp in it.
    # We first need to generate the script though.
    echo "mkdir -p ??TARGET.STAGING_DIR??/puppet/modules" > $PWD/externCmd.nsh
    echo "mkdir -p ??TARGET.STAGING_DIR??/puppet/manifests" >> $PWD/externCmd.nsh
    echo "echo \"node default {\ninclude $package_name\n}\" > ??TARGET.STAGING_DIR??/puppet/manifests/site.pp" >> $PWD/externCmd.nsh
    echo "mv ??TARGET.STAGING_DIR??/$module_file_name ??TARGET.STAGING_DIR??/puppet/modules" >> $PWD/externCmd.nsh
    echo "tar zxvf ??TARGET.STAGING_DIR??/puppet/modules/$module_file_name -C ??TARGET.STAGING_DIR??/puppet/modules/" >> $PWD/externCmd.nsh
    echo "rm -rf ??TARGET.STAGING_DIR??/puppet" > $PWD/externUndoCmd.nsh

    # Now that the script is ready, add it as an external command to the package
    blcli_execute BlPackage addExternalCmdToEnd $MAIN_PACKAGE_ID PREPARE_SPACE  //$HOST$PWD/externCmd.nsh //$HOST$PWD/externUndoCmd.nsh "Abort" > /dev/null
    if [ $? -ne 0 ]; then
        errorPrint "\nFailed while adding PREPARE_SPACE to blpackage"
    else
        echo "\nAdded command for generating puppet environment on target"
    fi
    blcli_storeenv MAIN_PACKAGE_ID

    #===================================================
    # Now we generate and add the puppet command to actually deploy the module.
    echo "puppet apply -v --modulepath ??TARGET.STAGING_DIR??/puppet/modules ??TARGET.STAGING_DIR??/puppet/manifests/site.pp" > $PWD/PuppetCmd.nsh
	echo "rm -rf ??TARGET.STAGING_DIR??/puppet" >> $PWD/PuppetCmd.nsh
    touch $PWD/empty.nsh
    blcli_execute BlPackage addExternalCmdToEnd $MAIN_PACKAGE_ID PUPPET_CMD //$HOST$PWD/PuppetCmd.nsh //$HOST$PWD/empty.nsh "Abort" > /dev/null
    if [ $? -ne 0 ]; then
        errorPrint "\nFailed while adding PUPPET_CMD to blpackage"
    else
        echo "\nAdded commands for running puppet on target"
    fi
    blcli_storeenv MAIN_PACKAGE_ID


    echo "\nPackage" $package_name "is ready."

    #===================================================
    # Now we create a job group and a job for this package.
    blcli_execute JobGroup groupExists "/$root_puppet_group" > /dev/null
    blcli_storeenv JOB_GROUP_EXISTS
    if [ $JOB_GROUP_EXISTS = "false" ]; then
        blcli_execute JobGroup createGroupWithParentName $root_puppet_group "/" > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create Job Group" $root_puppet_group
        fi
        blcli_storeenv JOB_PUPPET_ROOT_GROUP_ID
    else
        blcli_execute JobGroup groupNameToId "/$root_puppet_group" > /dev/null
        blcli_storeenv JOB_PUPPET_ROOT_GROUP_ID
    fi

	blcli_execute JobGroup groupExists "/$root_puppet_group/$puppet_module_parent_group" > /dev/null
    blcli_storeenv JOB_GROUP_EXISTS
    if [ $JOB_GROUP_EXISTS = "false" ]; then
        blcli_execute JobGroup createGroupWithParentName $puppet_module_parent_group "/$root_puppet_group" > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create Job Group" $puppet_module_parent_group
        fi
        blcli_storeenv JOB_PUPPET_PARENT_GROUP_ID
    else
        blcli_execute JobGroup groupNameToId "/$root_puppet_group/$puppet_module_parent_group" > /dev/null
        blcli_storeenv JOB_PUPPET_PARENT_GROUP_ID
    fi
	
	blcli_execute JobGroup groupExists "/$root_puppet_group/$puppet_module_parent_group/$puppet_module_group" > /dev/null
    blcli_storeenv JOB_GROUP_EXISTS
    if [ $JOB_GROUP_EXISTS = "false" ]; then
        blcli_execute JobGroup createGroupWithParentName $puppet_module_group "/$root_puppet_group/$puppet_module_parent_group" > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create Job Group" $puppet_module_group
        fi
        blcli_storeenv JOB_PUPPET_GROUP_ID
    else
        blcli_execute JobGroup groupNameToId "/$root_puppet_group/$puppet_module_parent_group/$puppet_module_group" > /dev/null
        blcli_storeenv JOB_PUPPET_GROUP_ID
    fi
	blcli_execute JobGroup groupExists "/$root_puppet_group/$puppet_module_parent_group/$puppet_module_group/$DEPOT_GROUP" > /dev/null
    blcli_storeenv JOB_GROUP_EXISTS
    if [ $JOB_GROUP_EXISTS = "false" ]; then
        blcli_execute JobGroup createGroupWithParentName $DEPOT_GROUP "/$root_puppet_group/$puppet_module_parent_group/$puppet_module_group" > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create Job Group" $DEPOT_GROUP
        fi
        blcli_storeenv JOB_GROUP_ID
    else
        blcli_execute JobGroup groupNameToId "/$root_puppet_group/$puppet_module_parent_group/$puppet_module_group/$DEPOT_GROUP" > /dev/null
        blcli_storeenv JOB_GROUP_ID
    fi
    echo "\nCreated Job group /$root_puppet_group/$puppet_module_parent_group/$puppet_module_group/$DEPOT_GROUP"

    if [ "$has_new_blcli" = "false" ] ; then
        blcli_execute DeployJob createDeployJob "deploy_"$package_name $JOB_GROUP_ID $MAIN_PACKAGE_ID $job_deploy_machine true true false > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed while creating a deploy job deploy_$package_name using the package $package_name\nPlease ensure that a host with name $job_deploy_machine is enrolled with BSA Appserver"
        fi
        blcli_storeenv MODULE_JOB_DBKEY
        blcli_execute Job clearTargetServers $MODULE_JOB_DBKEY > /dev/null
    else
        blcli_execute DeployJob createDeployJobWithoutTarget "deploy_"$package_name $JOB_GROUP_ID $MAIN_PACKAGE_ID true true false > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed while creating a deploy job deploy_$package_name using the package $package_name\n"
        fi
    fi
    blcli_storeenv MODULE_JOB_DBKEY
    echo "\nCreated a deploy job named deploy_$package_name in job group /$root_puppet_group/$puppet_module_parent_group/$puppet_module_group/$DEPOT_GROUP"

    puppet_deploy_script_group=/Puppet/PuppetAdministration
    puppet_deploy_script_depot_object=PuppetDeployScript
    puppet_deploy_script_job=PuppetDeployScriptJob
    CHEF_SCRIPT_DBKEY=
    PUPPET_SCRIPT_JOB_DBKEY=

    blcli_execute NSHScriptJob findJobKeyByGroupAndName $puppet_deploy_script_group $puppet_deploy_script_job > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to find NSH Script Job $puppet_deploy_script_job in $puppet_deploy_script_group, This Job is provided out-of-the-box and has probably been deleted by user. Contact BMC support to find how the job can be reimported."
    fi
    blcli_storeenv PUPPET_SCRIPT_JOB_DBKEY
    echo "\nFound NSH Script Job named $puppet_deploy_script_job in $puppet_deploy_script_group"

    
    #=========================================================
    # NSH Script Job is found, now lets create a batch job
    # that will first run the NSH Script job and then run the
    # module deploy job
    #=========================================================

    blcli_execute BatchJob createBatchJob "deploy_puppet_agent_and_"$package_name $JOB_GROUP_ID $PUPPET_SCRIPT_JOB_DBKEY false true true false > /dev/null
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to create Batch Job named deploy_puppet_agent_and_$package_name."
    fi
    blcli_storeenv MODULE_BATCH_JOB_DBKEY
    blcli_execute BatchJob addMemberJobByJobKey $MODULE_BATCH_JOB_DBKEY $MODULE_JOB_DBKEY > /dev/null
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to add the module deploy job to Batch Job named deploy_puppet_agent_and_$package_name."
    fi
    blcli_storeenv MODULE_BATCH_JOB_DBKEY
    echo "\nCreate a batch job named deploy_puppet_agent_and_$package_name in /$root_puppet_group/$puppet_module_parent_group/$puppet_module_group/$DEPOT_GROUP"
    rm -rf $PWD/externCmd.nsh $PWD/externUndoCmd.nsh $PWD/PuppetCmd.nsh > /dev/null
}

########
# Main #
########

if [ "$1" = "-help" ] ; then
    printUsage
fi

if [ "$1" = "-V" ] ; then
    printVersion
fi

if [ $# -lt 2 ] ; then
    printUsage
fi

parseOptions "$@"

validatePreConnectOptions

echo "\nTrying to connect to Appserver as configured by the cached credentials, please wait ..."
blcli_connect
if [ $? -ne 0 ] ; then
    errorPrint "\nFailed to connect to appserver, please check whether you have acquired credentials and have set the required options.\nCheck script usage for more information by executing '$script_name -help'\n"
fi

validatePostConnectOptions

if [ $debug_option -eq 1 ] ; then
    set -x
fi

for i in $modules_array ; do
    createPackages $i
done
