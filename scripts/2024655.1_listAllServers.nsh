#set -x

blcli_execute Server listAllServers > /dev/null
blcli_storeenv SERVERS
echo $SERVERS