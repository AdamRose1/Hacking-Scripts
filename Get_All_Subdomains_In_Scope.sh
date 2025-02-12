#!/bin/bash
# Created this script to find all in scope subdomains for the target provided. This is achieved by by using shodan, crt.sh, subdomain brute force, and virtual host brute force to find all subdomains under the target scope, and then eliminating subdomains that do not match the target scope, CNAME points out of scope, is in the out_of_scope.txt file, dns query does not resolve, or location is outside of the US. 
# Create a file called "out_of_scope.txt" that contains all the out of scope domains and IP's that were provided.  List each out of scope domain/ip on a seperate line. 

target="doesnotexist.com" # Update the target value both here and in the python script below.  Use only domain name, no https:// 

if ! [[ -f out_of_scope.txt ]];then
    echo "out_of_scope.txt not found in current working directory"
    exit 1
fi

# Shodan to get subdomains for the target and then format the output into the full subdomain name. Example: shodan outputs test, turn that into test.doesnotexist.com. 
shodan domain -T A,AAAA $target |awk '{print $1}'| awk -v target=$(echo $target) 'FNR>2 { $1=$1"."target; print }' > shodan_output.txt

# Use shodan to get subdomains that have a CNAME that points do a domain in scope. This gets rid of the subdomains that have a CNAME that point to an out of scope domain name. 
shodan domain -T CNAME $target|grep -i CNAME |grep -i "$target$" |awk '{print $1; print $3}'|awk -v target=$(echo $target) '{ $1=$1"."target; print }' >> shodan_output.txt


# crt.sh to get subdomains for the target
curl -s "https://crt.sh/?q=$target&output=json" | jq -r '.[] | select(.name_value)|.name_value'|sort -u |grep -v '*' >> crt.sh_output.txt


# ffuf subdomain brute force
if ! [[ -f subdomain_bf_wordlist.txt ]];then
cat /usr/share/seclists/Discovery/DNS/subdomains-top1million-110000.txt > a && cat /usr/share/seclists/Discovery/DNS/bitquark-subdomains-top100000.txt >> a && cat a|sort -uf > subdomain_bf_wordlist.txt && rm a
fi

ffuf -ic -w subdomain_bf_wordlist.txt -u https://FUZZ.$target -s > ffuf_output_subdomain_bf.txt

# Format ffuf found subdomains into the full subdomain name.  Example: shodan outputs test, turn that into test.doesnotexist.com. 
cat ffuf_output_subdomain_bf.txt | sed "s/$/.$target/g" > format_ffuf_output_into_full_subdomains.txt


# wfuzz virtual host subdomain brute force (run manually because need to get the correct filter of --hh)
# wfuzz -c -w subdomain_bf_wordlist.txt -u "https://$target" -H "Host: FUZZ.$target" --hh <value> | tee wfuzz_output_subdomain_bf.txt

# Creat a file that contains all found subdomains and removes any duplicate subdomains found.
cat shodan_output.txt crt.sh_output.txt format_ffuf_output_into_full_subdomains.txt | sort -uf > step1

# Make out_of_scope.txt list match same formating of the step1 (sudbdomain list) file so that grep elminiates out of scope domains correctly
cat out_of_scope.txt | awk -v target=$(echo $target) '{print $1="www."$1"."target}' > formatted_out_of_scope.txt
cat out_of_scope.txt | awk -v target=$(echo $target) '{print $1=$1"."target}' >> formatted_out_of_scope.txt
cat out_of_scope.txt >> formatted_out_of_scope.txt

# Eliminate subdomains that scope document listed as out of scope
cat step1 | while read -r line;do if ! grep -qix "$line" formatted_out_of_scope.txt;then echo $line>> step2;fi;done 
#for line in $(cat step1);do if ! grep -qix $line formatted_out_of_scope.txt;then echo $line >> step2;fi;done # another way to do the above line

# First remove duplicates. Next, if dns lookup does not resolve then remove from the in scope list
cat step2|sort -uf  >> step3 && for target in $(cat step3);do nslookup $target| grep -q "server can't find";if [[ $? -ne 0 ]];then echo $target >> step4;fi;done

# Convert from domain name to IP (geoiplookup does not work with domain name) and then do geoip lookup.
echo 'Whatever is output to this file means that it is not in the US and is therefore out of scope.' > step5 
for ip in $(cat step4);do host $ip | grep "address"|awk '{print $NF}' >> step5;done && cat step4 | xargs -I {} geoiplookup {}|grep -v "US\|can't resolve" >> step5 
