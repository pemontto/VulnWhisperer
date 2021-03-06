#!/usr/bin/env bash

NORMAL=$(tput sgr0)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)

function red() {
    echo -e "$RED$*$NORMAL"
}

function green() {
    echo -e "$GREEN$*$NORMAL"
}

function yellow() {
    echo -e "$YELLOW$*$NORMAL"
}

return_code=0

elasticsearch_url="localhost:9200"
logstash_url="localhost:9600"

until curl -s "$elasticsearch_url/_cluster/health?pretty" | grep '"status"' | grep -qE "green|yellow"; do
    yellow "Waiting for Elasticsearch..."
    sleep 5
done
green "✅ Elasticsearch status is green..."

count=0
until [[ $(curl -s "$logstash_url/_node/stats" | jq '.events.out') -ge 1617 ]]; do
    yellow "Waiting for Logstash load to finish...  $(curl -s "$logstash_url/_node/stats" | jq '.events.out') of 1617 (attempt $count of 60)"
    ((count++)) && ((count==60)) && break
    sleep 5
done

if [[ count -le 60 && $(curl -s "$logstash_url/_node/stats" | jq '.events.out') -ge 1617 ]]; then
    green "✅ Logstash load finished $(curl -s "$logstash_url/_node/stats" | jq '.events.out') logs processed..."
else
    red "❌ Logstash load didn't complete  $(curl -s "$logstash_url/_node/stats" | jq '.events.out') logs processed... $(curl -s "$logstash_url/_node/stats" | jq '.events.out')"
fi


count=0
until [[ $(curl -s "$elasticsearch_url/logstash-vulnwhisperer-*/_count" | jq '.count') -ge 1617 ]] ; do
    yellow "Waiting for Elasticsearch index to sync... $(curl -s "$elasticsearch_url/logstash-vulnwhisperer-*/_count" | jq '.count') of 1617 logs loaded (attempt $count of 150)"
    ((count++)) && ((count==150)) && break
    sleep 2
done
if [[ count -le 50 && $(curl -s "$elasticsearch_url/logstash-vulnwhisperer-*/_count" | jq '.count') -ge 1617 ]]; then
    green "✅ logstash-vulnwhisperer-* document count $(curl -s "$elasticsearch_url/logstash-vulnwhisperer-*/_count" | jq '.count') >= 1617"
else
    red "❌ TIMED OUT waiting for logstash-vulnwhisperer-* document count: $(curl -s "$elasticsearch_url/logstash-vulnwhisperer-*/_count" | jq) != 1617"
fi

# if [[ $(curl -s "$elasticsearch_url/logstash-vulnwhisperer-*/_count" | jq '.count') == 1232 ]]; then
#     green "✅ Passed: logstash-vulnwhisperer-* document count == 1232"
# else
#     red "❌ Failed: logstash-vulnwhisperer-* document count == 1232 was: $(curl -s "$elasticsearch_url/logstash-vulnwhisperer-*/_count") instead"
#     ((return_code = return_code + 1))
# fi

# Test Nessus signature:Backported Security Patch Detection (FTP)
nessus_doc=$(curl -s "$elasticsearch_url/logstash-vulnwhisperer-*/_search?q=signature:%22Backported%20Security%20Patch%20Detection%20(FTP)%22%20AND%20asset:176.28.50.164%20AND%20tags:nessus" | jq '.hits.hits[]._source')
if echo $nessus_doc | jq '.risk' | grep -q "none"; then
    green "✅ Passed: Nessus risk == none"
else
    red "❌ Failed: Nessus risk == none was: $(echo $nessus_doc | jq '.risk') instead"
    ((return_code = return_code + 1))
fi

# Test Tenable signature:Backported Security Patch Detection (FTP)
tenable_doc=$(curl -s "$elasticsearch_url/logstash-vulnwhisperer-*/_search?q=signature:%22Backported%20Security%20Patch%20Detection%20(FTP)%22%20AND%20asset:176.28.50.164%20AND%20tags:tenable" | jq '.hits.hits[]._source')
# Test asset
if echo $tenable_doc | jq .asset | grep -q '176.28.50.164'; then
    green "✅ Passed: Tenable asset == 176.28.50.164"
else
    red "❌ Failed: Tenable asset == 176.28.50.164 was: $(echo $tenable_doc | jq .asset) instead"
    ((return_code = return_code + 1))
fi

# Test @timestamp
if echo $tenable_doc | jq '.["@timestamp"]' | grep -q '2019-03-30T15:45:44.000Z'; then
    green "✅ Passed: Tenable @timestamp == 2019-03-30T15:45:44.000Z"
else
    red "❌ Failed: Tenable @timestamp == 2019-03-30T15:45:44.000Z was: $(echo $tenable_doc | jq '.["@timestamp"]') instead"
    ((return_code = return_code + 1))
fi

# Test Qualys signature:OpenSSL Multiple Remote Security Vulnerabilities
qualys_vm_doc=$(curl -s "$elasticsearch_url/logstash-vulnwhisperer-*/_search?q=tags:qualys_vm%20AND%20ip:%22176.28.50.164%22%20AND%20signature:%22OpenSSL%20Multiple%20Remote%20Security%20Vulnerabilities%22%20AND%20port:465" | jq '.hits.hits[]._source')
# Test @timestamp
if echo $qualys_vm_doc | jq '.["@timestamp"]' | grep -q '2019-03-30T10:17:41.000Z'; then
    green "✅ Passed: Qualys VM @timestamp == 2019-03-30T10:17:41.000Z"
else
    red "❌ Failed: Qualys VM @timestamp == 2019-03-30T10:17:41.000Z was: $(echo $qualys_vm_doc | jq '.["@timestamp"]') instead"
    ((return_code = return_code + 1))
fi

# Test @XXXX
if echo $qualys_vm_doc | jq '.cvss' | grep -q '5.6'; then
    green "✅ Passed: Qualys VM cvss == 5.6"
else
    red "❌ Failed: Qualys VM cvss == 5.6 was: $(echo $qualys_vm_doc | jq '.cvss') instead"
    ((return_code = return_code + 1))
fi

exit $return_code
