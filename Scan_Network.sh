#!/bin/bash
# Created this script to automate and organize nmap and httpx scanning of large networks. Run this in tmux

# Update these variable before running the script. 
target="-iL /must/be/full/path/step7-final_results"
speed="" # If left blank then nmap will use the default speed
protocol=""  # Leave empty if you want to use TCP. For UDP enter -sU here.
host_discovery="-sn" # Change to empty if using UDP protocol
httpx_scan="yes" 
httpx_scan_with_screenshot="yes" # Use httpx with -ss to get screenshot of websites httpx found
ports_to_scan="" # If left blank nmap will use the default. Can put -p- for all 65k ports


# nmap host discovery 
# While UDP doesn't have a great way for host discovery, it is still important to run this first scan for UDP, because it will determine if the host is up based on scanning 1000 ports instead of scanning 65k ports on all hosts.  That will save a lot of time.
mkdir step1_host-discovery && cd step1_host-discovery
sudo nmap $target $host_discovery $speed $protocol -oN nmap_host-discovery 

# nmap scan all 65k ports on every host discovered in the previous command
mkdir step2_65k-find-open-ports && cd step2_65k-find-open-ports
for ip in $(cat ../nmap_host-discovery|grep 'scan report' | awk '{print $5}');do sudo nmap -Pn $ports_to_scan $ip $speed $protocol -oN nmap_ports_$ip;done

# nmap version and script scanning for every open port. This will eliminate any hosts that have no open ports bc it will not write a file for a host that has no open ports. 
mkdir step3_sCV && cd step3_sCV
for ip in $(cat ../../nmap_host-discovery|grep 'scan report'|awk '{print $5}');do for ports in $(cat ../nmap_ports_$ip|grep open|awk -F '/' '{print $1}'|sed -z 's/\n/,/g'|sed 's/,$//');do sudo nmap -Pn $ip $speed $protocol -p $ports -sCV -oN nmap_sCV_$ip;done;done

# httpx scan to find ports that are serving websites. 
if [[ "$httpx_scan" == "yes" || "$httpx_scan" == "y" ]]; then
    if [[ "httpx_scan_with_screenshot" == "yes" || "httpx_scan_with_screenshot" =="y" ]];then
        for ip in $(cat ../../nmap_host-discovery|grep 'scan report'|awk '{print $5}');do echo $ip >> httpx_targets.txt;done
        for ports in $(cat ../nmap_ports_$ip|grep open|awk -F '/' '{print $1}'|sed -z 's/\n/,/g'|sed 's/,$//');do httpx -l httpx_targets.txt -p $ports -ss -title -status-code -tech-detect                
        -follow-redirects -ip -method;done
        mv output/screenshot/screenshot.html ../../../../httpx_output_all_targets_screenshots.html
        # Create a directory for each host discovered with open ports, and then move each nmap file output to the target directory.  This is helpful for organizing notes on large subnets
        mkdir all_targets && cd all_targets
        for ip in $(ls ../nmap*|awk -F '_' '{print $3}');do mkdir -p $ip/enumeration && cp ../nmap_sCV_$ip $ip/enumeration/;done
    else
        for ip in $(cat ../../nmap_host-discovery|grep 'scan report'|awk '{print $5}');do for ports in $(cat ../nmap_ports_$ip|grep open|awk -F '/' '{print $1}'|sed -z 's/\n/,/g'|sed 's/,$//');do httpx  
        -u $ip -p $ports -title -status-code -tech-detect -follow-redirects -ip -method -o httpx_output_$ip;done;done 
        # Create a directory for each host discovered with open ports, and then move each nmap and httpx file ouptut to the target directory. This is helpful for organizing notes on large subnets
        mkdir all_targets && cd all_targets
        for ip in $(ls ../nmap*|awk -F '_' '{print $3}');do mkdir -p $ip/enumeration && cp ../nmap_sCV_$ip ../httpx_output_$ip $ip/enumeration/;done
else
    # Create a directory for each host discovered with open ports, and then move each nmap file output to the target directory.  This is helpful for organizing notes on large subnets
    mkdir all_targets && cd all_targets
    for ip in $(ls ../nmap*|awk -F '_' '{print $3}');do mkdir -p $ip/enumeration && cp ../nmap_sCV_$ip $ip/enumeration/;done
fi

# Organize, not deleting the step1-3 directories so that issues can be debugged if needed
cd ../ && mv all_targets ../../../ && cd ../../../

# If you do not want to create the below empty files in each target IP, then comment out the line below
for ip in $(ls all_targets);do touch all_targets/$ip/enumeration/enumeration.txt all_targets/$ip/exploit_path.txt all_targets/$ip/creds.txt;done
