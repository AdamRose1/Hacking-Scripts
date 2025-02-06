#!/bin/bash
# Created this script to automate and organize nmap and httpx subnet scanning

# Ask the user if they want to use predefined values or be prompted for input. If predefined, user has to update the predefined values for target,speed,protocol,host_discovery, and httpx_scan.
printf "Do you want to use predefined values and skip the questions? (y/n): "
read use_predefined
use_predefined=$(printf "$use_predefined" | tr '[:upper:]' '[:lower:]')
if [[ "$use_predefined" == "y" || "$use_predefined" == "yes" ]]; then

    target="-iL /full/path/inscope.txt"
    speed="--min-rate=1000"
    protocol=""  # Leave empty if you want to use TCP. For UDP enter -sU here.
    host_discovery="-sn"
    httpx_scan="yes"

    printf "Using predefined values. Skipping prompts...\n\n"
else
    # Get user input for the target subnet/IP
    printf "What is the target subnet/IP address that you want to scan? "
    read target
    printf "Scan will run on $target.\n\n"

    # Get user input for speed option
    printf "Do you want to add --min-rate=5000 to the nmap scans? (y/n)
    If you are concerned about causing disruptions on a target, then do not use --min-rate=5000. "
    read speed
    speed=$(printf "$speed" | tr '[:upper:]' '[:lower:]')

    # Check if the user wants to use --min-rate=5000
    if [[ "$speed" == "y" || "$speed" == "yes" ]]; then
        speed="--min-rate=5000"
        printf "Nmap will scan with --min-rate=5000.\n\n"
    else
        speed=""
        printf "Nmap will use default speed scan, it will not add --min-rate=5000.\n\n"
    fi

    # Get user input for protocol option
    printf "Do you want to scan UDP or TCP? "
    read protocol
    protocol=$(printf "$protocol" | tr '[:upper:]' '[:lower:]')

    # Get user input for httpx scan option
    printf "\nDo you want to use httpx to check if open ports are serving websites? "
    read httpx_scan
    httpx_scan=$(printf "$httpx_scan" | tr '[:upper:]' '[:lower:]')
    printf "Will run httpx scan\n\n"

    # Check what protocol user wants to use
    if [[ "$protocol" == "udp" || "$protocol" == "u" ]]; then
        protocol="-sU"
        host_discovery="" 
        printf "Starting UDP scan.\n\n"
    else
        protocol=""
        host_discovery="-sn"
        printf "Starting TCP scan.\n\n"
    fi
fi

# nmap host discovery 
# While UDP doesn't have a great way for host discovery, it is still important to run this first scan even if using protocol UDP, because it will determine if the host is up based on scanning 1000 ports instead of scanning 65k ports on all hosts.  That will save a lot of time.
mkdir step1_host-discovery && cd step1_host-discovery
sudo nmap $target $host_discovery $speed $protocol -oN nmap_host-discovery 

# nmap scan all 65k ports on every host discovered in the previous command
mkdir step2_65k-find-open-ports && cd step2_65k-find-open-ports
for ip in $(cat ../nmap_host-discovery|grep 'scan report' | awk '{print $5}');do sudo nmap -Pn -p- $ip $speed $protocol -oN nmap_65k-ports_$ip;done

# nmap version and script scanning on every open port for each host discovered
mkdir step3_sCV && cd step3_sCV
for ip in $(cat ../../nmap_host-discovery|grep 'scan report'|awk '{print $5}');do for ports in $(cat ../nmap_65k-ports_$ip|grep open|awk -F '/' '{print $1}'|sed -z 's/\n/,/g'|sed 's/,$//');do sudo nmap -Pn $ip $speed $protocol -p $ports -sCV -oN nmap_sCV_$ip;done;done

# httpx scan to find ports that are serving websites 
if [[ "$httpx_scan" == "yes" || "$httpx_scan" == "y" ]]; then
    for ip in $(cat ../../nmap_host-discovery|grep 'scan report'|awk '{print $5}');do for ports in $(cat ../nmap_65k-ports_$ip|grep open|awk -F '/' '{print $1}'|sed -z 's/\n/,/g'|sed 's/,$//');do httpx -u $ip -p $ports -title -status-code -tech-detect -follow-redirects -ip -method -o httpx_output_$ip;done;done
fi

# Create a directory for each host discovered with open ports, and then move each nmap file output to the target directory.  This is helpful for organizing notes on large subnets
mkdir all_targets && cd all_targets
for ip in $(ls ../nmap*|awk -F '_' '{print $3}');do mkdir $ip && cp ../nmap_sCV_$ip ../httpx_output_$ip $ip;done

# Clean up
cd ../ && mv all_targets ../../../ && cd ../../../ && rm -rf step1_host-discovery

# If you do not want to create the below empty files in each target IP, then comment out the line below
for ip in $(ls all_targets);do touch all_targets/$ip/enumeration.txt all_targets/$ip/exploit_path.txt all_targets/$ip/creds.txt;done
