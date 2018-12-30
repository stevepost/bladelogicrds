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
list_cookbook_file_name=
list_databag_file_name=
list_role_file_name=
list_environment_file_name=
databag_name="bag"
cookbooks_array=()
databags_array=()
roles_array=()
environments_array=()
has_new_blcli="false"
job_deploy_machine="localhost"
root_chef_group="Chef"
chef_content_group="ChefContent"
chef_cookbook_group="Cookbooks"
chef_accessories_group="ChefAccessories"
chef_roles_group="Roles"
chef_databags_group="Databags"
chef_environment_group="Environments"
debug_option=0

function printUsage()
{
    echo "\nUsage:"
    echo "------"
	echo "$script_name [-V] -c </AbsolutePath/Cookbook.tar.gz> -n </AbsolutePath/node.json> [ -d Databag name][ -b /absolutePath/databagList.csv] [ -r /absolutePath/roleList.csv] [ -e /absolutePath/environmentList.csv> [ -h Managed Hostname for aiding BSA job creation]\n"
	echo "$script_name can be used to create BlPackages of Chef Cookbooks a node.json and CookBook tar.gz bundles."
    echo "/AbsolutePath/Cookbook.tar.gz is absolute path of tar.gz bundles for chef cookbooks."
    echo "Each bundle should be named so as to indicate the cookbook it is providing and should contain all the dependency cookbooks"
    echo "e.g.: a Cookbook file path for apache bundle will look like this:"
    echo "/root/chef_5_x86_64/chef/cookbooks/apache.tar.gz"
    echo "[root@my-host modules]# tar ztvf /root/chef_5_x86_64/chef/cookbooks/apache.tar.gz"
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
	echo "/AbsolutePath/node.json is absolute path of node.json file for chef cookbooks."
    echo "e.g.: a node.json path for json will look like this:"
    echo "/root/chef_5_x86_64/chef/cookbooks/apache/node.json"
    echo
	echo "DatabagList.csv should contain name and group path of databags json files present in BSA(Comma Separated values)"
    echo "e.g.: a DatabagList.csv file that provides path for databag json file will look like this:"
	echo "[root@my-host databags]# cat DatabagList.csv"
    echo "Databag.json,/chef/Databag"
    echo "Databag1.json,/chef/Databag1"
	echo
	echo "RoleList.csv should contain name and group path of roles json files(Comma separated values)."
    echo "e.g.: a RoleList.csv file that provides path for role json file will look like this:"
	echo "[root@my-host roles]# cat RoleList.csv"
    echo "webserver.json,/chef/webserver.json"
	echo
	echo "EnvironmentList.csv should contain name and group path of environments json files(Comma separated values)."
    echo "e.g.: a EnvironmentList.csv file that provides path for environment json file will look like this:"
	echo "[root@my-host environment]# cat EnvironmentList.csv"
    echo "production.json,/chef/production.json"
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
	
	if [ -z "$json_name" ] ; then
        errorPrint "please provide Node.json with option -n file name"
    fi
	
	if [ ! -e "$json_path" ] ; then
        errorPrint "Unable to find file $json_name"
    fi
	
	if [ -z "$cookbook_name" ] ; then
        errorPrint "please provide cookbook with option -c file name"
    fi
	
	if [ ! -e "$cookbook_path" ] ; then
        errorPrint "Unable to find cookbook $cookbook_name"
    fi
	
	# Validating cookbook.csv file and its content
#	if [ -z "$list_cookbook_file_name" ] ; then
#        errorPrint "Please provide CookbookList file name using option '-c file name'"
#    fi
#    if [ ! -e "$list_cookbook_file_name" -o ! -f "$list_cookbook_file_name" -o ! -s "$list_cookbook_file_name" -o ! -r "$list_cookbook_file_name" ] ; then
#       errorPrint "File $list_cookbook_file_name either does not exist or is invalid."
#    fi
#    IFS=$'\n'
#    for fline in `cat "$list_cookbook_file_name"` ; do
#    	if [ -z "$fline" ] ; then
#            echo "Found an empty line, skipping... "
#        fi
#        fline=`echo "$fline" | tr -d '\r'`
#        fline=`echo "$fline" | tr -d '\n'`
#        cookbooks_array+=("$fline")
#        if [ ! -e "$fline" -o ! -f "$fline" -o ! -s "$fline" -o ! -r "$fline" ] ; then
#           errorPrint "File Named $fline specified in $list_cookbook_file_name either does not exist or is invalid."
#        fi
#    done
	
	# Validating role.csv file and its content
	if [ ! -z "$list_role_file_name" ] ; then
        
        if [ ! -e "$list_role_file_name" -o ! -f "$list_role_file_name" -o ! -r "$list_role_file_name" ] ; then
            errorPrint "File $list_role_file_name either does not exist or is invalid."
        fi
        
		IFS=$'\n'
        for fline in `cat "$list_role_file_name"` ; do
    	  	if [ -z "$fline" ] ; then
                echo "Found an empty line, skipping... "
            fi
            fline=`echo "$fline" | tr -d '\r'`
            fline=`echo "$fline" | tr -d '\n'`
            roles_array+=("$fline")
        done
	fi
	
	
    # Validating databag.csv file and its content
	if [ ! -z "$list_databag_file_name" ] ; then
        
        if [ ! -e "$list_databag_file_name" -o ! -f "$list_databag_file_name" -o ! -r "$list_databag_file_name" ] ; then
            errorPrint "File $list_databag_file_name either does not exist or is invalid."
        fi
        
		IFS=$'\n'
        for fline in `cat "$list_databag_file_name"` ; do
    	  	if [ -z "$fline" ] ; then
                echo "Found an empty line, skipping... "
            fi
            fline=`echo "$fline" | tr -d '\r'`
            fline=`echo "$fline" | tr -d '\n'`
            databags_array+=("$fline")
        done
	fi
	
	# Validating environment.csv file and its content
	if [ ! -z "$list_environment_file_name" ] ; then
        
        if [ ! -e "$list_environment_file_name" -o ! -f "$list_environment_file_name" -o !  -r "$list_environment_file_name" ] ; then
            errorPrint "File $list_environment_file_name either does not exist or is invalid."
        fi
        
		IFS=$'\n'
        for fline in `cat "$list_environment_file_name"` ; do
    	  	if [ -z "$fline" ] ; then
                echo "Found an empty line, skipping... "
            fi
            fline=`echo "$fline" | tr -d '\r'`
            fline=`echo "$fline" | tr -d '\n'`
            environments_array+=("$fline")
        done
	fi
}

function parseOptions()
{
   
	 while getopts ":b:r:e:c:n:d:hV" opt; do
      case $opt in
        d)
          databag_name="$OPTARG"
          ;;
		c)
		  cookbook_name="$OPTARG"
		  cookbook_path="$OPTARG"
          if [ "$cookbook_name[0]" != '/' ] ; then
               # Path is not an absolute path. Make it absolute.
               cookbook_path="$PWD/$cookbook_name"
          fi
		  cookbook_name="${cookbook_name##*/}"
          ;;
		n)
		  json_name="$OPTARG"
		  json_path="$OPTARG"
          if [ "$json_name[0]" != '/' ] ; then
               # Path is not an absolute path. Make it absolute.
               json_path="$PWD/$json_name"
          fi
		  json_name="${json_name##*/}"
          ;;
		b)
		  list_databag_file_name="$OPTARG"
		  ;;
        r)
		  list_role_file_name="$OPTARG"
          ;;
        e)
		  list_environment_file_name="$OPTARG"
          ;;
        h)
          job_deploy_machine="$OPTARG"
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
    blcli_execute DeployJob createDeployJobWithoutTarget > "${PWD}/blcliout" 2>&1
    grep "DeployJob has no commands by name" "${PWD}/blcliout" > /dev/null 2>&1
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
        blcli_execute Server getServerIdByName "$job_deploy_machine" > /dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "\"$job_deploy_machine\" is not enrolled with BSA Appserver."
            if [ "$job_deploy_machine" = "localhost" ] ; then
                errorPrint "\nThis script uses name of a BSA enrolled host name to create jobs, although only temporarily.\nPlease ensure that a host name is passed using -h option of the script or a host with name \"localhost\" is enrolled with BSA Appserver"
            else
                job_deploy_machine="localhost"
                blcli_execute Server getServerIdByName "$job_deploy_machine" > /dev/null 2>&1
                if [ $? -ne 0 ] ; then
                    errorPrint "\nThis script uses name of a BSA enrolled host name to create jobs, although only temporarily.\nPlease ensure that a host name is passed using -h option of the script or a host with name \"localhost\" is enrolled with BSA Appserver"
                else
                    echo "Found a host with name \"localhost\" enrolled with BSA, continuing with the same. The host will be used only temporarily for job creation"
                fi
            fi      
        fi
    fi



        blcli_execute DepotGroup groupNameToId "/$root_chef_group/$chef_content_group/$chef_cookbook_group/$cookbook_name" > /dev/null 2>&1
        if [ $? -eq 0 ] ; then
            echo "A Depot Group by name $cookbook_name already exists in /$root_chef_group which indicates that the packages for this cookbook already exist.\nSkipping processing for this module.\n"
        fi
 
 
}

function createPackages()
{
    cookbook_file_path=$1
    if [ -z "$cookbook_file_path" ] ; then
        errorPrint "createPackages() needs name of a cookbook tar file, received none."
    fi
    cookbook_file_name=`basename "$cookbook_file_path"`

    package_name=`echo "$cookbook_file_name" | sed -e 's/.tar.gz//' | sed -e 's/.tgz//'`
    if [ -z "$package_name" ] ; then
        errorPrint "Unable to derive package name from $cookbook_file_name"
    fi
    DEPOT_GROUP="$package_name"
    DEPOT_GROUP_FQDN="/$root_chef_group/$chef_content_group/$chef_cookbook_group/$DEPOT_GROUP"
    HOST=`hostname`
    blcli_execute DepotGroup groupNameToId / > /dev/null
    blcli_storeenv ROOT_DG_ID
    blcli_execute DepotGroup groupNameToId "/$root_chef_group" > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        blcli_execute DepotGroup createDepotGroup "$root_chef_group" "$ROOT_DG_ID" > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create depot group $root_chef_group"
        fi
    fi
	blcli_execute DepotGroup groupNameToId "/$root_chef_group" > /dev/null
    blcli_storeenv ROOT_CHEF_ID
    blcli_execute DepotGroup groupNameToId "/$root_chef_group/$chef_content_group" > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        blcli_execute DepotGroup createDepotGroup "$chef_content_group" "$ROOT_CHEF_ID" > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create depot group $chef_content_group"
        fi
    fi
	blcli_execute DepotGroup groupNameToId "/$root_chef_group/$chef_content_group" > /dev/null
    blcli_storeenv DEPOT_CHEF_PARENT_ID
    blcli_execute DepotGroup groupNameToId "/$root_chef_group/$chef_content_group/$chef_cookbook_group" > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        blcli_execute DepotGroup createDepotGroup "$chef_cookbook_group" "$DEPOT_CHEF_PARENT_ID" > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create depot group $chef_cookbook_group"
        fi
    fi
    blcli_storeenv CHEF_DEPOT_ID

    #===================================================
    # Create a Depot Group For Storing the main package
    # as well as any depot files we might have to create.
    blcli_execute DepotGroup createDepotGroup "$DEPOT_GROUP" "$CHEF_DEPOT_ID" > /dev/null
    if [ $? -ne 0 ]; then
        errorPrint "\nFailed to create depot group $DEPOT_GROUP_FQDN"
    fi
    blcli_storeenv DEPOT_GROUP_ID
    echo "\nCreated Depot Group $DEPOT_GROUP_FQDN"

    #===================================================
    # Create the main blpackage, but with nothing in it as of now.
    blcli_execute BlPackage createEmptyPackage "$package_name" "$package_name" "$DEPOT_GROUP_ID" > /dev/null
    if [ $? -ne 0 ]; then
        errorPrint "\nFailed to create empty package named $package_name"
    fi
    blcli_storeenv MAIN_PACKAGE_ID
    echo "\nCreated Empty BlPackage named: $package_name in group $DEPOT_GROUP"

    #===================================================
    # Add the tar.gz file to the package
    blcli_execute DepotFile addFileToDepot "$DEPOT_GROUP_FQDN" "$cookbook_file_path" "$cookbook_file_name" "$cookbook_file_name" > /dev/null
    if [ $? -ne 0 ]; then
    	echo "\nFailed to add cookbook file $cookbook_file_path to depot group. Cant proceed with creation of package for this cookbook."
        return
    fi
    blcli_storeenv COOKBOOK_BLFILE_ID
    blcli_execute BlPackage importDepotObjectToPackage "$DEPOT_GROUP_FQDN" "$package_name" true true true true true "$DEPOT_GROUP_FQDN" "$cookbook_file_name" DEPOT_FILE_OBJECT "Action,Owner,Permission,Path" "Add,1,505,??TARGET.STAGING_DIR??/$cookbook_file_name" NotRequired NotRequired > /dev/null
    if [ $? -ne 0 ]; then
	    errorPrint "\nFailed to add cookbook file $cookbook_file_path to blpackage $package_name"
    fi
    blcli_storeenv MAIN_PACKAGE_ID
    echo "\nAdded cookbook file $cookbook_file_path to blpackage $package_name"

	#===================================================
    # Add the JSON file to the package
    blcli_execute DepotFile addFileToDepot "$DEPOT_GROUP_FQDN" "$json_path" "$json_name" "$json_name" > /dev/null
    if [ $? -ne 0 ]; then
	    errorPrint "\nFailed to add json file to depot group"
    fi
    blcli_storeenv JSON_BLFILE_ID
    blcli_execute BlPackage importDepotObjectToPackage "$DEPOT_GROUP_FQDN" "$package_name" true true true true true "$DEPOT_GROUP_FQDN" "$json_name" DEPOT_FILE_OBJECT "Action,Owner,Permission,Path" "Add,1,505,??TARGET.STAGING_DIR??/chef/node.json" NotRequired NotRequired > /dev/null
    if [ $? -ne 0 ]; then
	    errorPrint "\nFailed to add json file to blpackage"
    fi
    blcli_storeenv MAIN_PACKAGE_ID
    echo "\nAdded $json_name to package $package_name"
	
	
    #===================================================
    # Add the databags json files to the package
	for databag_file_details in $databags_array ; do
    createPackagesForChefAccessories "$databag_file_details" "$DEPOT_GROUP_FQDN" "$package_name" "databags/$databag_name"
    done
	
	#===================================================
    # Add the roles json files to the package
	for role_file_details in $roles_array ; do
    createPackagesForChefAccessories "$role_file_details" "$DEPOT_GROUP_FQDN" "$package_name" 'roles'
    done
	
	
	#===================================================
    # Add the environment json files to the package
	for environment_file_details in $environments_array ; do
    createPackagesForChefAccessories "$environment_file_details" "$DEPOT_GROUP_FQDN" "$package_name" 'environments'
    done
	
	#======================================================
	#Removing temp files which will be used as external command
	rm -f "$PWD/pkgUnzipCommand.nsh" > /dev/null
    rm -f "$PWD/pkgUnzipCommandUndo.nsh" > /dev/null
	
    # Since we are already in a loop going over the list of packages, might as well generate the script for use on the target
    # For unzipping the files to the cookbook directory.
	echo "mkdir -p ??TARGET.STAGING_DIR??/chef/chef-solo/cookbooks" >> "$PWD/pkgUnzipCommand.nsh"
	echo "mv ??TARGET.STAGING_DIR??/$cookbook_file_name ??TARGET.STAGING_DIR??/chef/chef-solo/cookbooks" >> "$PWD/pkgUnzipCommand.nsh"
	echo "tar zxvf ??TARGET.STAGING_DIR??/chef/chef-solo/cookbooks/$cookbook_file_name -C ??TARGET.STAGING_DIR??/chef/chef-solo/cookbooks/" >> "$PWD/pkgUnzipCommand.nsh"
		echo "rm -f  ??TARGET.STAGING_DIR??/chef" >> "$PWD/pkgUnzipCommandUndo.nsh"
	
	# Add external commands to create the chef directories and to create the solo.rb in it.
    # We first need to generate the script though.
    echo "echo file_cache_path \\\"??TARGET.STAGING_DIR??/chef\\\" > ??TARGET.STAGING_DIR??/chef/solo.rb" >> "$PWD/externCmd.nsh"
    echo "echo cookbook_path \\\"??TARGET.STAGING_DIR??/chef/chef-solo/cookbooks\\\" >> ??TARGET.STAGING_DIR??/chef/solo.rb" >> "$PWD/externCmd.nsh"
    echo "echo data_bag_path \\\"??TARGET.STAGING_DIR??/chef/chef-solo/databags\\\" >> ??TARGET.STAGING_DIR??/chef/solo.rb" >> "$PWD/externCmd.nsh"
    echo "echo role_path \\\"??TARGET.STAGING_DIR??/chef/chef-solo/roles\\\" >> ??TARGET.STAGING_DIR??/chef/solo.rb" >> "$PWD/externCmd.nsh"
	echo "echo environment_path \\\"??TARGET.STAGING_DIR??/chef/chef-solo/environments\\\" >> ??TARGET.STAGING_DIR??/chef/solo.rb" >> "$PWD/externCmd.nsh"
    echo "rm -rf ??TARGET.STAGING_DIR??/chef" > "$PWD/externUndoCmd.nsh"

    # Now that the script is ready, add it as an external command to the package
    blcli_execute BlPackage addExternalCmdToEnd "$MAIN_PACKAGE_ID" SOLO_RB_EXTERN_CMD  "//$HOST$PWD/externCmd.nsh" "//$HOST$PWD/externUndoCmd.nsh" "Abort" > /dev/null
    if [ $? -ne 0 ]; then
        errorPrint "\nFailed while adding SOLO_RB_EXTERN_CMD to blpackage"
    else
        echo "\nAdded command for generating solo.rb on targets"
    fi
    blcli_storeenv MAIN_PACKAGE_ID

    #===================================================
    # Now we need external command to unzip all those cookbooks we got as a part of the package.
    # Unless we set the "path" attribute as written above, those zips would go to the same path
    # as that on the source. We use the pkgUnzipCommand script generated above.
    blcli_execute BlPackage addExternalCmdToEnd "$MAIN_PACKAGE_ID" CKBK_EXTRACT_EXTERN_CMD "//$HOST$PWD/pkgUnzipCommand.nsh" "//$HOST$PWD/pkgUnzipCommandUndo.nsh" "Abort" > /dev/null
    if [ $? -ne 0 ]; then
        errorPrint "\nFailed while adding CKBK_EXTRACT_EXTERN_CMD to blpackage"
    else
        echo "\nAdded commands for unpacking cookbooks on targets"
    fi
    blcli_storeenv MAIN_PACKAGE_ID
 
    #===================================================
    # Now we generate and add the chef-solo command to actually deploy the cookbooks.
    echo "chef-solo -c ??TARGET.STAGING_DIR??/chef/solo.rb -j ??TARGET.STAGING_DIR??/chef/node.json" > "$PWD/ChefSoloCmd.nsh"
    echo "if [ \$? -ne 0 ] ; then if [ -e ??TARGET.STAGING_DIR??/chef/chef-solo/chef-stacktrace.out ] ; then cat ??TARGET.STAGING_DIR??/chef/chef-solo/chef-stacktrace.out; fi; exit 1; fi" >> "$PWD/ChefSoloCmd.nsh"
    touch "$PWD/empty.nsh"
    blcli_execute BlPackage addExternalCmdToEnd "$MAIN_PACKAGE_ID" CHEF_SOLO_EXTERN_CMD "//$HOST$PWD/ChefSoloCmd.nsh" "//$HOST$PWD/empty.nsh" "Abort" > /dev/null
    if [ $? -ne 0 ]; then
        errorPrint "\nFailed while adding CHEF_SOLO_EXTERN_CMD to blpackage"
    else
        echo "\nAdded commands for running chef-solo on targets"
    fi
    blcli_storeenv MAIN_PACKAGE_ID
    echo "\nPackage $package_name is ready."
	
	#===================================================
    # Now we create a job group and a job for this package.
    blcli_execute JobGroup groupExists "/$root_chef_group" > /dev/null
    blcli_storeenv JOB_GROUP_EXISTS
    if [ $JOB_GROUP_EXISTS = "false" ]; then
        blcli_execute JobGroup createGroupWithParentName "$root_chef_group" "/" > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create Job Group $root_chef_group"
        fi
        blcli_storeenv JOB_CHEF_ROOT_GROUP_ID
    else
        blcli_execute JobGroup groupNameToId "/$root_chef_group" > /dev/null
        blcli_storeenv JOB_CHEF_ROOT_GROUP_ID
    fi

	blcli_execute JobGroup groupExists "/$root_chef_group/$chef_content_group" > /dev/null
    blcli_storeenv JOB_GROUP_EXISTS
    if [ $JOB_GROUP_EXISTS = "false" ]; then
        blcli_execute JobGroup createGroupWithParentName "$chef_content_group" "/$root_chef_group" > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create Job Group $chef_content_group"
        fi
        blcli_storeenv JOB_CHEF_PARENT_GROUP_ID
    else
        blcli_execute JobGroup groupNameToId "/$root_chef_group/$chef_content_group" > /dev/null
        blcli_storeenv JOB_CHEF_PARENT_GROUP_ID
    fi
	
	blcli_execute JobGroup groupExists "/$root_chef_group/$chef_content_group/$chef_cookbook_group" > /dev/null
    blcli_storeenv JOB_GROUP_EXISTS
    if [ $JOB_GROUP_EXISTS = "false" ]; then
        blcli_execute JobGroup createGroupWithParentName $chef_cookbook_group "/$root_chef_group/$chef_content_group" > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create Job Group $chef_cookbook_group"
        fi
        blcli_storeenv JOB_CHEF_GROUP_ID
    else
        blcli_execute JobGroup groupNameToId "/$root_chef_group/$chef_content_group/$chef_cookbook_group" > /dev/null
        blcli_storeenv JOB_CHEF_GROUP_ID
    fi
	blcli_execute JobGroup groupExists "/$root_chef_group/$chef_content_group/$chef_cookbook_group/$DEPOT_GROUP" > /dev/null
    blcli_storeenv JOB_GROUP_EXISTS
    if [ $JOB_GROUP_EXISTS = "false" ]; then
        blcli_execute JobGroup createGroupWithParentName $DEPOT_GROUP "/$root_chef_group/$chef_content_group/$chef_cookbook_group" > /dev/null
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed to create Job Group $DEPOT_GROUP"
        fi
        blcli_storeenv JOB_GROUP_ID
    else
        blcli_execute JobGroup groupNameToId "/$root_chef_group/$chef_content_group/$chef_cookbook_group/$DEPOT_GROUP" > /dev/null
        blcli_storeenv JOB_GROUP_ID
    fi
    echo "\nCreated Job group /$root_chef_group/$chef_content_group/$chef_cookbook_group/$DEPOT_GROUP"

    if [ "$has_new_blcli" = "false" ] ; then
        blcli_execute DeployJob createDeployJob "deploy_$package_name" "$JOB_GROUP_ID" "$MAIN_PACKAGE_ID" "$job_deploy_machine" true true false > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed while creating a deploy job deploy_$package_name using the package $package_name\nPlease ensure that a host with name $job_deploy_machine is enrolled with BSA Appserver"
        fi
        blcli_storeenv MODULE_JOB_DBKEY
        blcli_execute Job clearTargetServers $MODULE_JOB_DBKEY > /dev/null
    else
        blcli_execute DeployJob createDeployJobWithoutTarget "deploy_$package_name" "$JOB_GROUP_ID" "$MAIN_PACKAGE_ID" true true false > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            errorPrint "\nFailed while creating a deploy job deploy_$package_name using the package $package_name\n"
        fi
    fi
    blcli_storeenv MODULE_JOB_DBKEY
    echo "\nCreated a deploy job named deploy_$package_name in job group /$root_chef_group/$chef_content_group/$chef_cookbook_group/$DEPOT_GROUP"

    chef_deploy_script_group=/Chef/ChefAdministration
    chef_deploy_script_depot_object=ChefDeployScript
    chef_deploy_script_job=ChefDeployScriptJob
    CHEF_SCRIPT_DBKEY=
    CHEF_SCRIPT_JOB_DBKEY=

    blcli_execute NSHScriptJob findJobKeyByGroupAndName "$chef_deploy_script_group" "$chef_deploy_script_job" > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to find NSH Script Job $chef_deploy_script_job in $chef_deploy_script_group, This Job is provided out-of-the-box and has probably been deleted by user. Contact BMC support to find how the job can be reimported."
    fi
    blcli_storeenv CHEF_SCRIPT_JOB_DBKEY
    echo "\nFound NSH Script Job named $chef_deploy_script_job in $chef_deploy_script_group"

    
    #=========================================================
    # NSH Script Job is found, now lets create a batch job
    # that will first run the NSH Script job and then run the
    # module deploy job
    #=========================================================

    blcli_execute BatchJob createBatchJob "deploy_chef_agent_and_$package_name" "$JOB_GROUP_ID" "$CHEF_SCRIPT_JOB_DBKEY" false true true false > /dev/null
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to create Batch Job named deploy_chef_agent_and_$package_name."
    fi
    blcli_storeenv COOKBOOK_BATCH_JOB_DBKEY
    blcli_execute BatchJob addMemberJobByJobKey "$COOKBOOK_BATCH_JOB_DBKEY" "$MODULE_JOB_DBKEY" > /dev/null
    if [ $? -ne 0 ] ; then
        errorPrint "Unable to add the module deploy job to Batch Job named deploy_chef_agent_and_$package_name."
    fi
    blcli_storeenv COOKBOOK_BATCH_JOB_DBKEY
    echo "\nCreate a batch job named deploy_chef_agent_and_$package_name in /$root_chef_group/$chef_content_group/$chef_cookbook_group/$DEPOT_GROUP"
    rm -rf "$PWD/externCmd.nsh" "$PWD/externUndoCmd.nsh" "$PWD/ChefCmd.nsh" > /dev/null
}


# function which add chef accessories file to BLPackage

#Usage  createPackagesForChefAccessories  $accessories_file_path $depot_group_name $blpackage_name $staging_path
function createPackagesForChefAccessories()
{
    #variable containing the accessories file details FILE_NAME,FILE_DEPOT_PATH example webserver.json,/Chef/ChefAccessories/Roles
	accessories_file_details="$1"
	#fetching file name
	accessories_file_name=`echo "$accessories_file_details" | cut -d ',' -f1`
	#fetching file depot path
	accessories_file_depot_path=`echo "$accessories_file_details" | cut -d ',' -f2`
	#blpackage depot group name
	depot_group_name="$2"
	blpackage_name="$3"
	staging_path="$4/$accessories_file_name"


  
    # calling BLCLI to add accessories file in the blpackage  
	blcli_execute BlPackage importDepotObjectToPackage "$depot_group_name" "$blpackage_name" true true true true true "$accessories_file_depot_path" "$accessories_file_name" DEPOT_FILE_OBJECT "Action,Owner,Permission,Path" "Add,1,505,??TARGET.STAGING_DIR??/chef/chef-solo/$staging_path" NotRequired NotRequired > /dev/null
    if [ $? -ne 0 ]; then
	    errorPrint "\nFailed to add $accessories_file_name file to blpackage"
    fi
    blcli_storeenv MAIN_PACKAGE_ID
    echo "\nAdded $accessories_file_name to package $blpackage_name"


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


createPackages "$cookbook_path"
