#!/bin/bash
# Created this script to find all in scope subdomains for the target provided. This is achieved by by using shodan, crt.sh, subdomain brute force, and virtual host brute force to find all subdomains under the target scope, and then eliminating subdomains that do not match the target scope, CNAME points out of scope, is in the out_of_scope.txt file, dns query does not resolve, or location is outside of the US. 
# Create a file called "out_of_scope.txt" that contains all the out of scope domains and IP's that were provided.  List each out of scope domain/ip on a seperate line. 

target="doesnotexist.com" # Update the target value both here and in the python script below.  Use only domain name, no https:// 

if ! [[ -f out_of_scope.txt ]];then
    echo "out_of_scope.txt not found in current working directory"
    exit 1
fi

# Shodan to get subdomains for the target and then format the output into the full subdomain name. Example: shodan outputs test, turn that into test.doesnotexist.com. 
shodan domain -T A,AAAA $target |awk '{print $1}'| awk -v target=$(echo $target) 'FNR>2 {$1=$1"."target; print}' > shodan_output.txt

# Use shodan to get subdomains that have a CNAME in scope. This removes the subdomains that have a CNAME that point to an out of scope domain name and puts them into a seperate file. 
shodan domain -T CNAME $target |grep -i "$target$" |awk -v target=$(echo $target) 'FNR>1 {print $1=$1"."target; print $3}' >> shodan_output.txt
shodan domain -T CNAME $target |grep -iv "$target$" |awk -v target=$(echo $target) 'FNR>1 {print $1=$1"."target; print $3}' > CNAMES_out_of_scope_shodan.txt

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

# If dns lookup does not resolve then remove from the subdomain from the in scope list found in the file step2
for subd in $(cat step2);do nslookup_output=$(nslookup "$subd");if [[ ! "$nslookup_output" =~ "server can't find" ]];then echo $subd >> step3;fi;done

# Remove any subdomain in the list that has a CNAME pointing out of scope and place them into a seperate file.
for ip in $(cat step3);do if dig "$ip"|grep -i cname|awk '{print $NF}'| sed 's/\.$//g' | grep -qi $target;then echo $ip >>step4
elif ! dig "$ip" | grep -i cname > /dev/null; then echo $ip >> step4 
elif dig "$ip"|grep -i cname|awk '{print $NF}'| sed 's/\.$//g' | grep -qiv $target;then echo $ip >> CNAMES_out_of_scope_crt_ffuf-bf.txt
else :
fi;done

# Convert from domain name to IP (geoiplookup does not work with domain name) and then do geoiplookup on each IP. 
for subd in $(cat step4); do
  dig +short A $subd | while read ip_addr; do
    echo -n "IP: $subd  $ip_addr   " >> step5
    geoiplookup $ip_addr >> step5
  done
done

for subd in $(cat step4); do
  dig +short AAAA $subd | while read ip_addr6; do
    echo -n "IP: $subd  $ip_addr6   " >> step5
    geoiplookup6 $ip_addr6 >> step5
  done
done

# Only retain the IP's that are confirmed to be in the US (geoiplookup will not find private IP's and therefore will not retain those IP's either).
cat step5|while IFS= read -r line;do if echo "$line" | grep -qi "United States";then echo $line| awk '{print $2}' >> step6
else echo $line >> bogon_ips_identified.txt;fi;done

# Eliminate duplicates and organize final results
mkdir final_results
cat CNAMES_out_of_scope_shodan.txt CNAMES_out_of_scope_crt_ffuf-bf.txt  | sort -uf > final_results/CNAMES_out_of_scope.txt
cat step6 | sort -uf >> final_results/In_scope_subdomains_found.txt
