#############################################################################################################################
# Copyright 2013 BMC. BMC Software, the BMC logos, and other BMC marks are trademarks or registered                         #
# trademarks of BMC Software, Inc. in the U.S. and/or certain other countries.                                              #
#############################################################################################################################

SCRIPT_VERSION="1.0"

function errorPrint()
{
    echo "ERROR:" >&2
    echo "------" >&2
    echo $1"\n" >&2
    exit 1
}

function printUsage()
{
    echo
    echo "Usage:"
    echo "------"
    echo "$script_name -c <chef version> -h <HostName1> [HostName2 HostName3 ... HostNameN]"
    exit 1
}

function getTargetOS()
{
    __target_host=$1
    __target_os=`blquery $__target_host -e "os_name()"`
    if [ $__target_os = "RedHat" ] ; then
        echo "el"
      elif [ $__target_os = "Ubuntu" ] ; then
        echo "ubuntu"
    fi
}

function getTargetOSVersion()
{
    __target_host=$1
    __target_osversion=`blquery $__target_host -e "os_release()"`
    # For RHEL, the OSversion is given out as Server6.3 or Server5.2. We only need the Major version number
    if [ $host_os = "el" ] ;then
           if [[ "$__target_osversion" == Server* ]] ; then
               echo $__target_osversion | sed -e 's/Server//'
         fi
      elif [ $host_os = "ubuntu" ] ; then
         echo $__target_osversion 
      fi    
}

function getTargetArch()
{
    __target_host=$1
    __target_host_arch=`nexec $__target_host uname -m`
    if [ $? -eq 0 ] ; then
        echo $__target_host_arch
    fi
}

jobs_to_execute=
chef_ruby_job_group_name=Chef/ChefContent/Agent

function prepareRubyChefDeployJob()
{
   __target_host=$1
    os_name_option=$2
    os_version_option=$3
    os_arch_option=$4
    chef_version_option=$5

    combo_package_name=ruby_and_chef-$os_name_option-$os_version_option-$os_arch_option-$chef_version_option

    blcli_execute DeployJob getDBKeyByGroupAndName /$chef_ruby_job_group_name deploy_$combo_package_name > /dev/null
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to find the Ruby & Chef package deploy job with name deploy_$combo_package_name in /$chef_ruby_job_group_name"
    fi
    blcli_storeenv CR_JOB_DBKEY
    blcli_execute DeployJob addNamedServerToJobByJobDBKey $CR_JOB_DBKEY $__target_host
    if [ $? -ne 0 ] ; then
        echo "Failure while adding $__target_host to job deploy_$combo_package_name"
    fi

    # For optimizing a bit, we will only add the job name to this list if it aint already there
    # For further optimizing, we could store the DBKey of the job, but thats a bit risky in case some modifications are carried out
    # to the job after the key is stored.
    echo $jobs_to_execute | grep deploy_$combo_package_name > /dev/null
    if [ $? -ne 0 ] ; then
        jobs_to_execute=$jobs_to_execute" deploy_$combo_package_name"
    fi
}

function triggerDeployJobs()
{
    oldIFS=$IFS
    IFS=" "
    for i in $jobs_to_execute ; do
        blcli_execute DeployJob getDBKeyByGroupAndName /$chef_ruby_job_group_name $i
        if [ $? -ne 0 ] ; then
            errorPrint "Unable to find the Ruby & Chef package deploy job with name $i in /$chef_ruby_job_group_name"
        fi
        blcli_storeenv CR_JOB_DBKEY
        blcli_execute DeployJob executeJobAndWait $CR_JOB_DBKEY > /dev/null
        if [ $? -ne 0 ] ; then
            echo "Job $i seems to have failed"
        fi
        blcli_execute Job clearTargetServers $CR_JOB_DBKEY > /dev/null
    done
}

function checkPreReqs()
{
    which blquery > /dev/null
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to find 'blquery' command which is essential for running this script. Terminating"
    fi
}

function checkIfRubyAndChefInstalled()
{
    __target_host=$1
    nexec $__target_host which ruby > /dev/null
    if [ $? -ne 0 ] ; then
        return 1
    fi
    which $__target_host chef-solo > /dev/null
    if [ $? -ne 0 ] ; then
        return 1
    fi
    return 0
}

########
# Main #
########

min_count=3
arg_count=$#
chef_version=$1
if [ $arg_count -lt $min_count ] ; then
    errorPrint "The script needs atlesat one host to work with"
fi

checkPreReqs

host_list=$@[3]

for i in $host_list ; do
    target_host_name=$i
    checkIfRubyAndChefInstalled $target_host_name
    if [ $? -ne 0 ] ; then
        host_os=`getTargetOS $target_host_name`
        host_os_version=`getTargetOSVersion $target_host_name`
        host_arch=`getTargetArch $target_host_name`
        prepareRubyChefDeployJob $target_host_name $host_os $host_os_version $host_arch $chef_version
    fi
    let i=$i+1
done
triggerDeployJobs
