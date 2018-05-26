#!/bin/bash

# script to periodically test hyperboria connection quality, to display summary in motd
# it would take too long to do this on-the-fly when a login shell is started
# write the information to /var/run/cjdns/hyperboria-connection-test.txt

test_hosts[0]="fc8f:dcbf:74b9:b3b9:5305:7816:89ac:53f3" # h.ipfs.io
test_hosts[1]="fc6a:30c9:53a1:2c6b:ccbf:1261:2aef:45d3" # h.transitiontech.ca/public
test_hosts[2]="fc81:7e39:ae21:1d67:e89c:9ff0:3f7e:5e5c" # mesh.dontsell.me
test_hosts[3]="fc53:dcc5:e89d:9082:4097:6622:5e82:c654" # h.fc00.org
test_hosts[4]="fc02:2735:e595:bb70:8ffc:5293:8af8:c4b7" # h.magik6k.net

outputfile=/var/run/cjdns/hyperboria-connection-test.txt
mkdir -p $(dirname $outputfile)

# only run when Cjdns is running
status=$(systemctl status cjdns 2>/dev/null | awk '/Active: / {print $2}')
if [[ $status = "active" ]]; then
    # write output to file
    currdate=$(date +"%Y-%m-%d %T")
    echo "HYPERBORIA_INFO_DATE=\"$currdate\"" > $outputfile

    # ping test all the hosts
    for host in ${test_hosts[*]}
    do
        ping6 -c3 $host | tail -n3 >> $outputfile
    done
fi
