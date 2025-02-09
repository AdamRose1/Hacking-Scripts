#!/bin/bash
# Created this script to get all in scope subdomains for the target provided.
# Create a file called "out_of_scope.txt" that contains all the out of scope domains and IP's that were provided.  List each out of scope domain/ip on a seperate line. 

target="example.com" # Update the target value.  Use only domain name, no https:// 

if ! [[ -f out_of_scope.txt ]];then
    echo "out_of_scope.txt not found in current working directory"
    exit 1
fi

shodan domain $target >> step1

curl -s "https://crt.sh/?q=$target&output=json" | jq -r '.[] | select(.name_value)|.name_value'|sort -u  >>step1

# if ! [[ -f subdomain_list.txt ]];then
# for subdomain in $(ls /usr/share/seclists/Discovery/DNS/);do cat /usr/share/seclists/Discovery/DNS/$subdomain >> temp_subdomain_list;done && sort -uf temp_subdomain_list > subdomain_list.txt && rm temp_subdomain_list
# fi
# dnsenum --enum $target -f subdomain_list.txt -r # If using dnsenum, then need to output into file step1 properly (either manually or by adding scripting for this)

# Eliminate subdomains that do not match the scope
cat step1 |grep -i "\.$target" > step2

# Eliminate subdomains that have a CNAME that point to an out of scope domain name
exclude_t=$(cat step2 |grep -i cname|awk '{print $3}'|grep -iv "$target$");cat step2 |grep -v `echo $exclude_t` > step3

# Make out of scope list match same formating of step3 (sudbdomain list)
if ! [[ -f prepare_out_of_scope.py ]];then
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
cat step3|awk '{print $1}'| while read -r line;do if ! grep -qiw "$line" out_of_scope_complete_list.txt;then echo $line>> step4;fi;done 

# First remove duplicates. Next, if dns lookup does not resolve then remove from the in scope list
cat step4|sort -uf  >> step5 && for target in $(cat step5);do nslookup $target| grep -q "server can't find";if [[ $? -ne 0 ]];then echo $target >> step6;fi;done

# Convert from domain name to IP (geoiplookup does not work with domain name) and then do geoip lookup.
echo 'Whatever is output to the file called step8 means that it is not in the US and is therefore out of scope.' > step8 
for ip in $(cat step6);do host $ip | grep "address"|awk '{print $NF}' >> step7;done && cat step7 | xargs -I {} geoiplookup {}|grep -v "US\|can't resolve" >> step8 
