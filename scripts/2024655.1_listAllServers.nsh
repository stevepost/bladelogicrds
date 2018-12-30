#set -x

blcli_setjvmoption -Dcom.bladelogic.cli.execute.quietmode.enabled=true

blcli_execute Server listAllServers
blcli_storeenv SERVERS
echo $SERVERS