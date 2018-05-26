#!/bin/bash

# script to periodically query non-critical tor runtime information to display in motd summary
# write the information to /var/run/tor/motd.info so ordinary user doesn't need access to tor control socket

# see https://gitweb.torproject.org/torspec.git/tree/control-spec.txt for details
# especially the 'getinfo config/names' and 'getinfo info/names' commands are helpful

# read the authentication cookie
control_socket=/var/run/tor/control
cookiefile=/var/run/tor/control.authcookie
cookie=$(hexdump -e '32/1 "%02x""\n"' $cookiefile)
outputfile=/var/run/tor/motd.info

execute_command()
{
    local cmd=$@
    echo -en "authenticate ""$cookie""\r\n$cmd\r\nquit\r\n" | nc -U $control_socket
}

remove_gossip()
{
    sed '/250 OK/d;/250 closing connection/d'
}

# circuit ready?
# 250-status/circuit-established=1
status_is_circuit_ready()
{
    local response=$(execute_command "getinfo status/circuit-established" | remove_gossip)
    if [[ $response =~ "250-status/circuit-established=1" ]]; then
        echo "YES"
    else
        echo "NO"
    fi
}

# how many open circuits?
# 250+circuit-status=... (ends with a newline having a dot)
count_open_circuits()
{
    # count lines containng " BUILT " using awk
    execute_command "getinfo circuit-status" | remove_gossip | awk '/ BUILT /{a++}END{print a}'
}

# how many onion services running?
# 551 No onion services of the specified type.
count_onion_services()
{
    local response=$(execute_command "getinfo onions/current" | remove_gossip | awk '{print $1}')
    if [[ $response = "551" ]]; then
        echo "0"
    else
        # TODO: what does a response look like and how to count???
        echo "?"
    fi
}

# running as a relay?
# 551 Only relays have descriptors
status_is_relay()
{
     local response=$(execute_command "getinfo status/fresh-relay-descs" | remove_gossip | awk '{print $1}')
     if [[ $response = "551" ]]; then
        echo "NO"
     else
        # TODO: does 250 mean the current node is a relay???
        echo "YES"
     fi
}

# only run when Tor is running
status=$(systemctl status tor 2>/dev/null | awk '/Active: / {print $2}')
if [[ $status = "active" ]]; then
    # write output to file
    currdate=$(date +"%Y-%m-%d %T")
    echo "TOR_INFO_DATE=\"$currdate\"" > $outputfile
    echo "TOR_INFO_IS_CIRCUIT_READY=\"$(status_is_circuit_ready)\"" >> $outputfile
    echo "TOR_INFO_NUM_OPEN_CIRCUITS=\"$(count_open_circuits)\"" >> $outputfile
    echo "TOR_INFO_NUM_ONION_SERVICES=\"$(count_onion_services)\"" >> $outputfile
    echo "TOR_INFO_IS_RELAY=\"$(status_is_relay)\"" >> $outputfile
fi
