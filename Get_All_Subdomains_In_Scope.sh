#!/bin/bash
# Created this script to get all in scope subdomains for the target provided. It achieves this by eliminating subdomains that do not match the target scope, CNAME points out of scope, is in the out_of_scope.txt file, dns query does not resolve, or location is outside of the US. 
# Create a file called "out_of_scope.txt" that contains all the out of scope domains and IP's that were provided.  List each out of scope domain/ip on a seperate line. 

target="doesnotexist.com" # Update the scope target value.  Use only domain name, no https:// 

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


# ffuf
if ! [[ -f subdomain_bf_wordlist.txt ]];then
cat /usr/share/seclists/Discovery/DNS/subdomains-top1million-110000.txt > a && cat /usr/share/seclists/Discovery/DNS/bitquark-subdomains-top100000.txt >> a && cat a|sort -uf > subdomain_bf_wordlist.txt && rm a
fi

ffuf -ic -w subdomain_bf_wordlist.txt -u https://FUZZ.$target -s > ffuf_output_subdomain_bf.txt

# Format ffuf found subdomains into the full subdomain name.  Example: shodan outputs test, turn that into test.doesnotexist.com. 
cat ffuf_output_subdomain_bf.txt | sed "s/$/.$target/g" > format_ffuf_output_into_full_subdomains.txt

# Creat a file that contains all found subdomains and removes any duplicate subdomains found.
cat shodan_output.txt crt.sh_output.txt format_ffuf_output_into_full_subdomains.txt | sort -uf > step1

# Make out of scope list match same formating of the step3 (sudbdomain list) file
if ! [[ -f format_out_of_scope.py ]];then
echo '# #!/usr/bin/env python3
target="example.com" # only domain name, no https:// 
with open("out_of_scope.txt", "r") as oos_file:
    oos_content = oos_file.read()
    oos_lines = oos_content.splitlines()
    for oos_line in oos_lines:
        if not oos_line[0].isdigit():
            print(f"www.{oos_line}.{target}")
            print(f"{oos_line}.{target}")
        else:
            pass' > format_out_of_scope_list.py
else
printf 'The file "format_out_of_scope_list.py" already exists. \n'
fi

# Run the python file
if ! [[ -f out_of_scope_complete_list.txt ]];then
python3 format_out_of_scope_list.py > out_of_scope_complete_list.txt && cat out_of_scope.txt >> out_of_scope_complete_list.txt
else
printf 'The file "out_of_scope_complete_list.txt" already exists.\n'
fi

# Eliminate subdomains that scope document listed as out of scope
cat step1|awk '{print $1}'| while read -r line;do if ! grep -qiw "$line" out_of_scope_complete_list.txt;then echo $line>> step2;fi;done 

# First remove duplicates. Next, if dns lookup does not resolve then remove from the in scope list
cat step2|sort -uf  >> step3 && for target in $(cat step3);do nslookup $target| grep -q "server can't find";if [[ $? -ne 0 ]];then echo $target >> step4;fi;done

# Convert from domain name to IP (geoiplookup does not work with domain name) and then do geoip lookup.
echo 'Whatever is output to this file means that it is not in the US and is therefore out of scope.' > step5 
for ip in $(cat step4);do host $ip | grep "address"|awk '{print $NF}' >> step5;done && cat step4 | xargs -I {} geoiplookup {}|grep -v "US\|can't resolve" >> step5 
