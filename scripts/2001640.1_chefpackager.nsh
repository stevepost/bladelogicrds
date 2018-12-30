#############################################################################################################################
# Copyright 2013 BMC. BMC Software, the BMC logos, and other BMC marks are trademarks or registered                         #
# trademarks of BMC Software, Inc. in the U.S. and/or certain other countries.                                              #
#############################################################################################################################

###################################################################
# Script for creating BSA bundle of ruby installer and chef client
###################################################################
# For ruby:
#     1. You can pass path of ruby binary RPM/DEB [option: -r <path to rpm/deb>]
#     2. If you have compiled ruby, you can pass path of the dir that contains
#        the compiled ruby [option: -R <path to dir>]
#
# For chef:
#     1. You can pass path of Chef binary RPM/DEB [option: -c <path to rpm/deb>] 
#
# For ruby dependencies:
#     1. you can pass path of dependencies separated by comma which need to be installed before installing Chef and Ruby [options: - p <path to rpm/deb, path to rpm/deb, path to rpm/deb>
#
# Other Options:
#
#     You need to pass the OS Name, OS Version, OS Architecture.
#       OS Name: -n <os name>. Currently 'el' for enterprise linux and 'ubuntu' for Ubuntu is supported
#       OS Version: -v <os version>. Currently '5' or '6' is supported for el and 10.x,11.x.12.x is supported for Ubuntu
#       OS Arch: -a <os arch>. Can be 'x86_64' or 'i686'
#
# Using the installers for Ruby & Chef, the script creates 
# depot objects and deploy job that are leveraged during cookbook 
# deploy operations

SCRIPT_VERSION="1.0"

function getDefaultOsName()
{
    if [ -e /etc/redhat-release ] ; then
        __os_name_option='el'
    elif [ -e /etc/lsb-release ] ; then
        grep Ubuntu /etc/lsb-release > /dev/null 2>&1
        if [ $? -eq 0 ] ; then
            __os_name_option='ubuntu'
        fi
    fi
    echo $__os_name_option
}

function getDefaultOsVersion()
{
    which lsb_release > /dev/null
    if [ $? -eq 0 ] ; then
        __os_version_option=`lsb_release -r | awk '{print $2}' | awk -F'.' '{print $1}'`
    fi
    echo $__os_version_option
}

function getDefaultOsArch()
{
    __os_arch_option=`uname -m`
    echo $__os_arch_option
}

script_name=`basename $0`
path_to_ruby_installer_option=
path_to_ruby_dir_option=
os_name_option=`getDefaultOsName`
os_version_option=`getDefaultOsVersion`
os_arch_option=`getDefaultOsArch`
chef_version_option=
path_to_chef_installer_option=
debug_option=0
ruby_package_name=
ruby_pkg_type_for_blcli=
chef_package_name=
combo_package_name=
chef_depot_root_name=Chef
chef_depot_group_parent_name=ChefContent
chef_ruby_depot_group_name=Agent
chef_job_root_name=Chef
chef_job_group_parent_name=ChefContent
chef_ruby_job_group_name=Agent
chef_ruby_absolute_depot_group_name=/Chef/ChefContent/Agent
chef_ruby_absolute_job_group_name=/Chef/ChefContent/Agent
PR_DG_ID=
PR_JG_ID=
RUBY_DSW_DBKEY=
CHEF_DSW_DBKEY=
HOST=`hostname`
array_ruby_dependencies=()
job_deploy_machine="localhost"
has_new_blcli="false"
location_type_flag="T"
ruby_location_type="FILE_SERVER"
chef_location_type="FILE_SERVER"
dep_location_type_arr=()
t_done="false"
T_done="false"
d_done="false"
pkg_type_for_blcli=
on_appserver="false"
pre_install_dependencies_file_name=
d_length=

function printUsage()
{
    echo
    echo "Usage:"
    echo "------"
    echo "$script_name [-n OS Name] [-v OS Version] [-a OS Architecture] -r <path to ruby RPM> -c <Chef Version> -i <path to chef agent installer> -d </AbsolutePath/dependencies.lst>] [-h Managed Hostname for aiding BSA job creation] [[-T CommonFileLocationType] | [-t CSV List Of File Location Type For All Installers]]"
    echo ""
    echo "**** IMPORTANT NOTE **** "
    echo "You need to acquire credentials for connecting to Appserver and set serviceProfile & roleName BEFORE you run this script."
    echo "Commands used for this are: 'blcred cred -acquire ...' and 'blcli_setoption ...'"
    echo "Also ensure that you set the environment variable named BL_AUTH_PROFILE_NAME to the profile you want to use."
    echo "This can be done using the command: 'export BL_AUTH_PROFILE_NAME=<profile name>'"
    echo ""
    echo "This script enables a user to create a BSA Depot Object encompassing"
    echo "Ruby, Chef Client for a particular OS Version and architecture."
    echo "The Depot Objects can then be used to deploy ruby & Chef Client to BSA managed Hosts."
    echo ""
    echo "By default, a package will be created for the OS Version and architecture"
    echo "of the system where the script is run."
    echo "Else, OS Name, Version & Architecture can be passed to the script via following options :-"
    echo ""
    echo "OS Options:"
    echo "-----------"
    echo "  -n <os name>. Currently only 'el' for enterprise Linux & 'ubuntu' for Ubuntu is supported"
    echo "  -v <os version>. Currently only '5' or '6' is supported"
    echo "  -a <os arch>. Can be 'x86_64' or 'i686'".
    echo ""
    echo "Options for ruby:"
    echo "-----------------"
    echo "  -r <path to rpm>"
    echo "      You can pass path of ruby binary RPM"
    echo ""
    echo "Option for chef:"
    echo "----------------"
    echo "  -c <Chef version>. Format needs to be: NN.NN.N-N"
    echo "  -i <path to chef agent installer>"
    echo ""
    echo "Other options:"
    echo "--------------"
    echo "  -d </AbsolutePath/DependenciesList.lst>"
    echo "	   DependenciesList.lst should contain absolute path of dependencies to be installed before installing Chef and Ruby>"
    echo "  -h <managed host name>."
    echo "     Name of a managed host needs to be passed and will be used temporarily to aid job creation. Host will not be modified. This option is needed only for BSA version before 8.5"
    echo "     Default Value: \"localhost\".\n"
    echo "  -T <CommonFileLocationType>."
    echo "     This flag indicates the type of path being passed for ruby, chef and other installers."
    echo "     Supported values: FILE_SERVER, AGENT_COPY_AT_STAGING, AGENT_MOUNT. Default is FILE_SERVER."
    echo "  -t <CSV List Of File Location Type For All Installers>."
    echo "     Use this option if some installer files have a different location. You need to specify type for all installers"
    echo "     First two values in this list would be for ruby and chef respectively. The rest would be for dependencies."
    echo "     '-T' and '-t' are mutually exclusive"
    echo "  -help. Shows this help message"
    echo "  -D. Turns on Shell Script debugging. Very verbose."

    exit 1
}

function printVersion()
{
    echo "\n$script_name Version: $SCRIPT_VERSION BMC Software."
    exit 0
}

function debugPrint()
{
    if [ "$debug_option" = "1" ] ; then
        echo $0
    fi
}

function errorPrint()
{
    echo "ERROR:" >&2
    echo "------" >&2
    echo $1"\n" >&2
    exit 1
}

function validatePreConnectOptions()
{
    echo "\nValidating pre connect options ...\n"

    if [ "$location_type_flag" = "T" ] ; then
        if [ "$ruby_location_type" != "AGENT_MOUNT" -a "$ruby_location_type" != "AGENT_COPY_AT_STAGING" -a "$ruby_location_type" != "FILE_SERVER" ] ; then
            errorPrint "Invalid value passed for -T option. Check usage for supported value."
        fi
    else
        for i in $dep_location_type_arr ; do
            if [ "$i" != "AGENT_MOUNT" -a "$i" != "AGENT_COPY_AT_STAGING" -a "$i" != "FILE_SERVER" ] ; then
                errorPrint "Invalid value '$i' passed for -t option. Check usage for supported value."
            fi
        done
    fi

    if [ -z "$path_to_ruby_installer_option" ] ; then
        errorPrint "It is mandatory to pass ruby installer path to this script using -r option."
    fi

    if [ -z "$path_to_chef_installer_option" ] ; then
        errorPrint "Please pass chef installer path to the script using the -i option."
    fi

    if [ "$chef_location_type" = "FILE_SERVER" ] ; then
        if [ ! -e "$path_to_chef_installer_option" -o ! -f "$path_to_chef_installer_option" -o ! -s "$path_to_chef_installer_option" -o ! -r "$path_to_chef_installer_option" ] ; then
            errorPrint "File $path_to_chef_installer_option either does not exist or is invalid."
        fi
    fi
    if [ "$ruby_location_type" = "FILE_SERVER" ] ; then
        if [ ! -e "$path_to_ruby_installer_option" -o ! -f "$path_to_ruby_installer_option" -o ! -s "$path_to_ruby_installer_option" -o ! -r "$path_to_ruby_installer_option" ] ; then
            errorPrint "File $path_to_ruby_installer_option either does not exist or is invalid."
        fi
    fi

    if [ ! -z $array_ruby_dependencies ] ; then
        cnt=1
        for element in "${array_ruby_dependencies[@]}" ; do
            if [ "$dep_location_type_arr[$cnt]" = "FILE_SERVER" ] ; then
                if [ -n "$element" ] ; then
                    # if (file doesnt exist or file is not a regular file or file size is 0 or file is not readable)
                    if [ ! -e "$element" -o ! -f "$element" -o ! -s "$element" -o ! -r "$element" ] ; then
                        errorPrint "File $element either does not exist or is invalid."
                    fi
                fi
            fi
            let cnt=$cnt+1
        done
    fi

    if [ -z $os_name_option ] ; then
        errorPrint "Unable to detect system's OS, please provide OS Name with option -n OS name"
    fi
    
    if [ $os_name_option != "el" -a $os_name_option != "ubuntu" ] ; then
        errorPrint "This script currently works only for RHEL and Ubuntu"
    fi
    
    if [ -z $os_version_option ] ; then
        errorPrint "Unable to detect OS's version, please provide OS version with option -v OS Version"
    fi
     
    if [ -z $os_arch_option ] ; then
        errorPrint "Unable to detect OS architecture, please provide RHEL architecture with option -a OS Architecture"
    fi
}

function checkIfOnAppServer()
{
    which blasadmin > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        on_appserver="true"
    fi
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
    echo "\nValidating post connect options ...\n"

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
    # Before we do all the work, its better to ensure that the packages we will create dont already exist.
    # If they do, then we fail.
    # Ideally, we should check for all the three, i.e. ruby, chef & combined pack.
    # For now, checking only for the combo pack.
    blcli_execute DepotObject getDBKeyByTypeStringGroupAndName BLPACKAGE $chef_ruby_absolute_depot_group_name $combo_package_name > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        errorPrint "A Chef & Ruby package for OS $os_name_option, Version $os_version_option, Architecture $os_arch_option, Chef Version $chef_version_option already exists.\nCan not continue\n"
    fi
}

function makeLocationType()
{
    cntr=1
    for (( ; cntr <= $d_length; cntr++ )) ; do
        dep_location_type_arr+=($ruby_location_type)
    done
}

function parseLocationType()
{
    __location_type_array=($@)
    __location_type_length=${#__location_type_array}
    if [ $__location_type_length -lt 2 ] ; then
        errorPrint "Insufficient location types passed with -t option"
    fi

    ruby_location_type=$__location_type_array[1]
    chef_location_type=$__location_type_array[2]

    dep_location_type_arr=()
    if [ $__location_type_length -gt 2 ] ; then
        dep_location_type_arr=($__location_type_array[3,$__location_type_length])
    fi
    dep_location_type_arr_len=${#dep_location_type_arr}
    if [ $dep_location_type_arr_len -ne $d_length ] ; then
        errorPrint "Number of installers passed via -d: $d_length, Number of file locations found for dependencies in -t: $dep_location_type_arr_len\nPlease provide location types for all dependencies."
    fi
}

function editPathIfNeeded()
{
    in_path=$1
    if [[ "$in_path" == //* || "$in_path" == nfs* || "$in_path" == smb* ]] ; then
        echo $in_path
    elif [ "$on_appserver" = "false" ] ; then
        if [ "$in_path[0]" = '/' ] ; then
            echo "//$HOST$in_path"
        else
            echo "//$HOST$PWD/$in_path"
        fi
    else
        if [ "$in_path[0]" = '/' ] ; then
            echo "$in_path"
        else
            echo "$PWD/$in_path"
        fi
    fi
}

function parseOptions()
{
    if [ $# -eq 0 ] ; then
        printUsage
    fi
    while getopts ":r:n:v:a:c:h:i:d:T:t:D" opt; do
      case $opt in
        r)
          path_to_ruby_installer_option=$OPTARG
          path_to_ruby_installer_option=`editPathIfNeeded "$path_to_ruby_installer_option"`
		  ;;
        n)
          os_name_option=$OPTARG
		  ;;
        v)
          os_version_option=$OPTARG
          ;;
        a)
          os_arch_option=$OPTARG
          ;;
        c)
          chef_version_option=$OPTARG
          ;;
        h)
          job_deploy_machine=$OPTARG
          ;;  
        d)
          pre_install_dependencies_file_name=$OPTARG
		  parseDependenciesFile
		  d_done="true"
          d_length=${#array_ruby_dependencies}
          ;;
        i)
          path_to_chef_installer_option=$OPTARG
          path_to_chef_installer_option=`editPathIfNeeded "$path_to_chef_installer_option"`
          ;;
        T)
          location_type_flag='T'
          ruby_location_type=$OPTARG
          chef_location_type=$OPTARG
          T_done="true"
          ;;
        t)
          location_type_flag='t'
          IFS=, location_type_array=($OPTARG)
          t_done="true"
          parseLocationType $location_type_array
		  ;;
        D)
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

function printOptions()
{
    echo path_to_ruby_installer_option = $path_to_ruby_installer_option
    echo path_to_ruby_dir_option = $path_to_ruby_dir_option
    echo os_name_option = $os_name_option
    echo os_version_option = $os_version_option
    echo os_arch_option = $os_arch_option
    echo chef_version_option = $chef_version_option
}

function checkPreReqs()
{
    echo "\nChecking pre-requisites ...\n"

    which blcli > /dev/null
    if [ $? -ne 0 ] ; then
        errorPrint "\nThis script uses BSA BLCLI interface which couldnt be located on this machine.\nPlease ensure that blcli is installed on this machine and exists in the path"
    fi

    which agentinfo > /dev/null
    if [ $? -ne 0 ] ; then
        errorPrint "\nThis script uses BSA NSH commands like 'agentinfo' which couldn't be located on this machine.\nPlease ensure that complete NSH is installed on this machine and exists in the path"
    fi

    checkIfOnAppServer
}

function createDepotObjectsForOther()
{
    errorPrint "This script currently works only for RHEL/DEB"
}

function createRubyDepotObjects()
{
    __cli_name=$1
    __pkg_type=$2
	__update_install_command=$3
    # Create depot objects of ruby dependencies
    if [ ! -z $array_ruby_dependencies ] ; then
        cnt=1
        for element in "${array_ruby_dependencies[@]}" ; do
            element_path=`editPathIfNeeded "$element"`
            element_name=${element##*/}
            # It is possible that the depot object for dependency already exists, in that case, we wont recreate it.
            blcli_execute DepotObject getDBKeyByTypeStringGroupAndName $__pkg_type $chef_ruby_absolute_depot_group_name $element_name > /dev/null 2>&1
            if [ $? -ne 0 ] ; then
                blcli_execute DepotSoftware $__cli_name $chef_ruby_absolute_depot_group_name $element_path $element_name false $dep_location_type_arr[$cnt] "" > /dev/null 2>&1
                if [ $? -ne 0 ] ; then
                    errorPrint "\nFailure while creating Depot Object $element"
                fi
                blcli_storeenv RUBY_DEP_DBKEY
                blcli DepotSoftware updateInstallCommand $RUBY_DEP_DBKEY $__update_install_command	> /dev/null 2>&1		
            else
                echo "\nFound an existing depot object for $element_name in $chef_ruby_absolute_depot_group_name, reusing it"
            fi
            let cnt=$cnt+1
        done
    fi

    # If ruby was provided as RPM, create a RPM depot object, else create a custom depot object with extraction commands
    # It is possible that the depot object for dependency already exists, in that case, we wont recreate it.
    blcli_execute DepotObject getDBKeyByTypeStringGroupAndName $__pkg_type $chef_ruby_absolute_depot_group_name $ruby_package_name > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        blcli_execute DepotSoftware $__cli_name $chef_ruby_absolute_depot_group_name $path_to_ruby_installer_option $ruby_package_name false $ruby_location_type "" > /dev/null 2>&1
        if [ $? -ne 0 ] ; then
            errorPrint "\nFailure while creating Depot Object $ruby_package_name using $path_to_ruby_installer_option"
        fi
        blcli_storeenv RUBY_DSW_DBKEY
    else
        blcli_storeenv RUBY_DSW_DBKEY
        echo "\nFound an existing depot object for $ruby_package_name in $chef_ruby_absolute_depot_group_name, reusing it"
    fi
}

function createChefDepotObjects()
{
    __cli_name=$1
    __pkg_type=$2
   
    # Create a rpm/deb depot object of chef installer
    # It is possible that the depot object for chef already exists, in that case, we wont recreate it.
    blcli_execute DepotObject getDBKeyByTypeStringGroupAndName $__pkg_type $chef_ruby_absolute_depot_group_name $chef_package_name > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        blcli_execute DepotSoftware $__cli_name $chef_ruby_absolute_depot_group_name $path_to_chef_installer_option $chef_package_name false $chef_location_type "" > /dev/null 2>&1
        if [ $? -ne 0 ] ; then
            errorPrint "\nFailure while creating RPM/DEB Depot Object $chef_package_name using $path_to_chef_installer_option"
        fi
        blcli_storeenv CHEF_DSW_DBKEY
    else
        echo "\nnFound an existing depot object for $chef_package_name, reusing it"
    fi

}

function createDepotObjectsForRHEL()
{  
    pkg_type_for_blcli=RPM_INSTALLABLE
	update_install_command="rpm --nodeps -i ??SOURCE??"
    createRubyDepotObjects addRpmToDepotByGroupName $pkg_type_for_blcli "$update_install_command"
    createChefDepotObjects addRpmToDepotByGroupName $pkg_type_for_blcli
	
}

function createDepotObjectsForUbuntu()
{  
    pkg_type_for_blcli=DEBIAN_PACKAGE_INSTALLABLE
	update_install_command="dpkg --force-all -i ??SOURCE??"  
    createRubyDepotObjects addDebToDepotByGroupName $pkg_type_for_blcli "$update_install_command"
    createChefDepotObjects addDebToDepotByGroupName $pkg_type_for_blcli
}

function parseDependenciesFile()
{
 	if [ ! -z "$pre_install_dependencies_file_name" ] ; then

          if [ ! -e "$pre_install_dependencies_file_name" -o ! -f "$pre_install_dependencies_file_name" -o ! -r "$pre_install_dependencies_file_name" ] ; then
               errorPrint "File $pre_install_dependencies_file_name either does not exist or is invalid."
		  fi
		  if [ -s "$pre_install_dependencies_file_name" ] ;then
		       oldIFS=$IFS
		       IFS=$'\n'
               for fline in `cat "$pre_install_dependencies_file_name"` ; do
    	           if [ -z "$fline" ] ; then
                       echo "Found an empty line, skipping... "
                   fi
                   fline=`echo "$fline" | tr -d '\r'`
                   fline=`echo "$fline" | tr -d '\n'`
                   array_ruby_dependencies+=("$fline")
               done
			   d_length=${#array_ruby_dependencies}
			   IFS=$oldIFS
          fi
	fi
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

if [ "$1" = "-V" ] ; then
    printVersion
fi

## Ensure we have all that we need to run this script
#----------------------------------------------------
checkPreReqs

## Get all the command line options and do basic validation
#---------------------------------------------------------
parseOptions "$@"
if [ $debug_option -eq 1 ] ; then
    printOptions
fi

# This bit of option validation is being done outside validatePreConnectOptions
# because we need to generate values before validation.

if [ "$T_done" = "true" -a "$t_done" = "true" ] ; then
    errorPrint "'-t' and '-T' are mutually exclusive. Use only one of them"
fi

## Users can pass either -t or -T.
#  Irrespective of what they pass, we want to keep logic in createRubyDepotObjects & createchefDepotObjects same and simple.
#  If user has passed -t, we have an array of locations for dependencies, but if -T has been passed, we need to build such an array.
if [ "$T_done" = "true" ] ; then
    if [ "$d_done" = "true" ] ; then
        makeLocationType
    fi
elif [ "$T_done" = "false" -a "$t_done" = "false" ] ; then
    if [ "$d_done" = "true" ] ; then
        makeLocationType
    fi
fi

validatePreConnectOptions

ruby_package_name=ruby-$os_name_option-$os_version_option-$os_arch_option
chef_package_name=chef-$os_name_option-$os_version_option-$os_arch_option-$chef_version_option
combo_package_name=ruby_and_chef-$os_name_option-$os_version_option-$os_arch_option-$chef_version_option

## Trying to connect to the Appserver
#-----------------------------------
echo "\nTrying to connect to Appserver as configured by the cached credentials, please wait ...\n"
blcli_connect
if [ $? -ne 0 ] ; then
    errorPrint "\nFailed to connect to appserver, please check whether you have acquired credentials and have set the required options.\nCheck script usage for more information by executing '$script_name -help'\n"
fi

validatePostConnectOptions

if [ $debug_option -eq 1 ] ; then
    set -x
fi

## Create a blpackage for the bundle. The blpackage should have commands for "installing" the package
#-----------------------------------------------------------------------------------------------------
# 1. Check if depot group for ruby & chef exists. If it does, get its id, else create it
# 2. We should check if a blpackage already exists for the OS etc. selected. If it does, we should fail. But this is better done in validateOptions() above
# 3. Create a OS specific software depot for ruby if we got its installer, else create a custom software object that will extract ruby on to the target
# 5. Create a OS specific software depot for chef.
# 6. Create a blpackage for the depot objects created above.

echo "\nCreating BSA Depot objects, this can take some time, please wait ...\n"

blcli_execute DepotGroup groupNameToId /$chef_depot_root_name > /dev/null 2>&1
if [ $? -ne 0 ] ; then
    blcli_execute DepotGroup createGroupWithParentName $chef_depot_root_name / > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to create Depot Group $chef_depot_root_name, please check permissions"
    fi
fi
blcli_execute DepotGroup groupNameToId /$chef_depot_root_name/$chef_depot_group_parent_name > /dev/null 2>&1
if [ $? -ne 0 ] ; then
    blcli_execute DepotGroup createGroupWithParentName $chef_depot_group_parent_name /$chef_depot_root_name > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to create Depot Group $chef_depot_group_parent_name, please check permissions"
    fi
fi

blcli_execute DepotGroup groupNameToId $chef_ruby_absolute_depot_group_name > /dev/null 2>&1
if [ $? -ne 0 ] ; then
    blcli_execute DepotGroup createGroupWithParentName $chef_ruby_depot_group_name /$chef_depot_root_name/$chef_depot_group_parent_name > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to create Depot Group $chef_ruby_depot_group_name, please check permissions"
    fi
fi
blcli_storeenv PR_DG_ID

case $os_name_option in

    el)
        createDepotObjectsForRHEL
        ;;
    ubuntu)
        createDepotObjectsForUbuntu
        ;;
    *)
        createDepotObjectsForOther
        ;;
esac
 
## Depot Software objects for ruby and chef are ready,
#  lets bundle them up in a blpackage so that they can be deployed in one shot.
#------------------------------------------------------------------------------

blcli_execute BlPackage createEmptyPackage $combo_package_name $combo_package_name $PR_DG_ID > /dev/null
if [ $? -ne 0 ]; then
    errorPrint "\Failure while creating BlPackage $combo_package_name"
fi
# Adding Ruby Dependencies depot object to the empty blpackage
if [ ! -z $array_ruby_dependencies ] ; then 
    for element in "${array_ruby_dependencies[@]}" ; do
        element_name=${element##*/}    
        blcli_execute BlPackage importDepotObjectToPackage $chef_ruby_absolute_depot_group_name $combo_package_name true false false false false $chef_ruby_absolute_depot_group_name $element_name $pkg_type_for_blcli "ActionOnFailure" "Ignore" NotRequired NotRequired > /dev/null 2>&1
        if [ $? -ne 0 ] ; then
            errorPrint "\nFailure while importing $element_name into BlPackage $combo_package_name"
        fi
        blcli_storeenv PR_BLPKG_DBKEY
    done
fi     
# Adding Ruby depot object to the same blpackage
blcli_execute BlPackage importDepotObjectToPackage $chef_ruby_absolute_depot_group_name $combo_package_name true false false false false $chef_ruby_absolute_depot_group_name $ruby_package_name $pkg_type_for_blcli "" "" NotRequired NotRequired > /dev/null 2>&1
if [ $? -ne 0 ] ; then
   errorPrint "\nFailure while importing $ruby_package_name into BlPackage $combo_package_name"
fi
blcli_storeenv PR_BLPKG_DBKEY

# Adding Chef depot object to the same blpackage
blcli_execute BlPackage importDepotObjectToPackage $chef_ruby_absolute_depot_group_name $combo_package_name true false false false false $chef_ruby_absolute_depot_group_name $chef_package_name $pkg_type_for_blcli "" "" NotRequired NotRequired > /dev/null 2>&1
if [ $? -ne 0 ] ; then
    errorPrint "\nFailure while importing $chef_package_name into BlPackage $combo_package_name"
fi
blcli_storeenv PR_BLPKG_DBKEY
echo "\nSuccessfully created BlPackage $combo_package_name in Depot Group $chef_ruby_absolute_depot_group_name\n"

## Create a deploy job using the package created above.
#------------------------------------------------------
blcli_execute JobGroup groupNameToId /$chef_job_root_name > /dev/null 2>&1
if [ $? -ne 0 ] ; then
    blcli_execute JobGroup createGroupWithParentName $chef_job_root_name / > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to create Job Group $chef_job_root_name, please check permissions"
    fi
fi
blcli_execute JobGroup groupNameToId /$chef_job_root_name/$chef_job_group_parent_name > /dev/null 2>&1
if [ $? -ne 0 ] ; then
    blcli_execute JobGroup createGroupWithParentName $chef_job_group_parent_name /$chef_job_root_name > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to create Job Group /$chef_job_root_name/$chef_job_group_parent_name, please check permissions"
    fi
fi
blcli_execute JobGroup groupNameToId $chef_ruby_absolute_job_group_name > /dev/null 2>&1
if [ $? -ne 0 ] ; then
    blcli_execute JobGroup createGroupWithParentName $chef_ruby_job_group_name /$chef_job_root_name/$chef_job_group_parent_name > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to create Job Group $chef_ruby_job_group_name, please check permissions"
    fi
fi
blcli_storeenv PR_JG_ID

if [ "$has_new_blcli" = "false" ] ; then
    blcli_execute DeployJob createDeployJob deploy_$combo_package_name $PR_JG_ID $PR_BLPKG_DBKEY $job_deploy_machine true true false > /dev/null
    if [ $? -ne 0 ]; then
        errorPrint "\nFailed while creating deploy job deploy_$combo_package_name using the package $combo_package_name.\nPlease ensure that a host with name $job_deploy_machine is enrolled with BSA Appserver"
    fi
    blcli_storeenv PR_JOB_DBKEY
    blcli_execute Job clearTargetServers $PR_JOB_DBKEY > /dev/null
else
    blcli_execute DeployJob createDeployJobWithoutTarget deploy_$combo_package_name $PR_JG_ID $PR_BLPKG_DBKEY true true false > /dev/null
    if [ $? -ne 0 ]; then
        errorPrint "\nFailed while creating deploy job deploy_$combo_package_name using the package $combo_package_name.\n"
    fi
    blcli_storeenv PR_JOB_DBKEY
fi

echo "\nCreated a deploy job named deploy_$combo_package_name in job group $chef_ruby_absolute_job_group_name"
