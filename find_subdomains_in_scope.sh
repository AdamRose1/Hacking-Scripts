#!/bin/bash 

# Created this script to find all in scope subdomains for the target provided. This is achieved by using shodan, crt.sh, and subdomain brute force to find all subdomains under the targets in scope. Then eliminating subdomains that are outside of the US, have a dns query that does not resolve to an IP, is listed as out of scope in the out_of_scope.txt file, or have a CNAME that is out of scope

# Preperation before running the script
# Run shodan init <api_key>
# Create a file called in_scope_target_list.txt that contains all target domains in scope. List each domain on a seperate line. 
# Create a file called out_of_scope.txt that contains all specified out of scope targets. List each domain on a seperate line. 
# Create a file called CNAMES_inscope.txt that contains all (if any) CNAME's that if target domain has that CNAME record, then that domain is still considered in scope even though it is not one of the targets listed in scope. 

if ! [[ -f in_scope_target_list.txt ]] || ! [[ -f out_of_scope.txt ]] || ! [[ -f CNAMES_inscope.txt ]];then
    echo "One of the required files (in_scope_target_list.txt, out_of_scope.txt, CNAMES_inscope.txt) for this script are not found in the current working directory"
    exit 1
fi

mkdir find_subdomains_in_scope

# Section 1: Find subdomains

# SHODAN
# The purpose of the awk command below is used to filter out rows that shodan returned that do not contain any domain name. This is achieved by looking at the first column in each returned row, if the first column has any letter besides 'a' then it saves the row to the file (since the first column in a shodan returned row that has no domain name will be either the A or AAAA). The second purpose of the awk command is used to print out the full domain found (otherwise it only prints the found subdomain which is not helpful if multiple targets are used in this shodan command since we won't know which domain is associated to the found domain). The purpose of the sed command below is to remove the first line returned for each target shodan runs before piping it to the awk command. This is important to do because shodan outputs the targeted domain name on the first line. Without removing that first line, it would return $target.$target. For exmaple: shodan domain example.com would return example.com on the first line. Then awk would return it as example.com.example.com which is not correct. 
for target in $(cat in_scope_target_list.txt);do shodan domain -T A,AAAA,CNAME $target| sed '1d'| awk -v target=$(echo $target) '$1 ~ /[^aA]/ {print $1=$1"."target}' | sort -uf >> find_subdomains_in_scope/shodan_output;done

# CRT.sh
#The purpose of the jq, sort, and grep commands below are to organize crt.sh output due to crt.sh output being very cluttered and messy. 
for target in $(cat in_scope_target_list.txt);do curl -s "https://crt.sh/?q=$target&output=json" | jq -r '.[] | select(.name_value)|.name_value'|sort -u |grep -v '*' >> find_subdomains_in_scope/crt.sh_output.txt;done

# Combine shodan and crt.sh found subdomains into one file and remove any duplicate findings.
cat find_subdomains_in_scope/shodan_output > find_subdomains_in_scope/temp && cat find_subdomains_in_scope/crt.sh_output.txt >> find_subdomains_in_scope/temp && sort -uf find_subdomains_in_scope/temp > find_subdomains_in_scope/all_found_subdomains_before_checking_if_they_are_inscope.txt && rm find_subdomains_in_scope/temp 


# Section 2: Remove out of scope subdomains --> still need to fix the grep for word ending in both places below for CNAME and outofscope checks

# Remove subdomains that have out of scope CNAMES. The dig command below is being used in a way that it extracts the final CNAME.  This way we avoid using CNAME that may not be the final CNAME and can cause incorrect results.  For example, if domain example.com has CNAME of test.com, and test.com has CNAME of somethingelse.com then to ensure it is in scope we must check the final CNAME and not the in between CNAMES. 
inscope_cnames=$(cat CNAMES_inscope.txt)
for subdomain in $(cat find_subdomains_in_scope/all_found_subdomains_before_checking_if_they_are_inscope.txt); do
    # Check if the subdomain has a CNAME record
    cname_record=$(dig "$subdomain" CNAME +short)

    # If there's no CNAME record, add to the in scope list
    if [[ -z "$cname_record" ]]; then
        echo "$subdomain" >> find_subdomains_in_scope/step1-all_found_subdomains_after_removing_subdomains_that_had_outofscope_CNAMES.txt
    else
        cleaned_cname=$(echo "$cname_record" | sed 's/\.$//'| tr '[:upper:]' '[:lower:]')
        echo "$inscope_cnames" | while IFS= read -r line_inscope_cnames; do
        if [[ "$cleaned_cname" == *"$line_inscope_cnames" ]]; then
            echo "$subdomain" >> find_subdomains_in_scope/step1-all_found_subdomains_after_removing_subdomains_that_had_outofscope_CNAMES.txt
            break        
            fi
        done
    fi
done

# Remove subdomains that are listed in the out_of_scope.txt file
out_of_scope=$(cat out_of_scope.txt)
for subdomain in $(cat find_subdomains_in_scope/step1-all_found_subdomains_after_removing_subdomains_that_had_outofscope_CNAMES.txt); do
    echo "$out_of_scope" | while IFS= read -r line_out_of_scope; do
    is_it_out_of_scope=false
    if ! [[ "$subdomain" == *"$line_out_of_scope" ]]; then
        echo "$subdomain" >> find_subdomains_in_scope/step2-all_found_subdomains_after_removing_subdomains_that_have_outofscope_domains.txt
        break
    fi
    done
done

# Remove subdomains that do not resolve to an IP. The ${,,} part is to convert the nslookup_output variable into lowercase because Can't is sometimes uppercase 'C' and sometimes lower case 'c'. 
for subdomain in $(cat find_subdomains_in_scope/step2-all_found_subdomains_after_removing_subdomains_that_have_outofscope_domains.txt);do nslookup_output=$(nslookup "$subdomain");if [[ ! "${nslookup_output,,}" == *"can't find"* ]];then echo $subdomain >> find_subdomains_in_scope/step3-all_found_subdomains_after_removing_nonresolving_IPs.txt;fi;done

# Remove subdomains that are not based in the US
for subdomain in $(cat find_subdomains_in_scope/step3-all_found_subdomains_after_removing_nonresolving_IPs.txt); do geoip=$(dig +short A "$subdomain" |tail -n 1 | xargs -I {} geoiplookup {});if echo "$geoip" | grep -qi "US, United States";then echo "$subdomain" >> find_subdomains_in_scope/finalresults-step4--all_found_subdomains_that_are_US_based.txt;else echo "$subdomain: $geoip" >> find_subdomains_in_scope/step4-all_found_subdomains_that_did_not_return_as_US_based.txt;fi;done


# Section 3 FFUF
# Ffuf is put in a section of its own because fuff subdomain brute force with a huge wordlist will take a very lot of time, therefore this is done at the end so that we can start testing with results from the beginning part of thes cript while this finishes running. 

# Create the wordlist
if ! [[ -f subdomain_bf_wordlist.txt ]];then
cat /usr/share/seclists/Discovery/DNS/dns-Jhaddix.txt >> a && cat /usr/share/seclists/Discovery/DNS/bug-bounty-program-subdomains-trickest-inventory.txt >> a && cat /usr/share/seclists/Discovery/DNS/subdomains-top1million-110000.txt >> a && cat /usr/share/seclists/Discovery/DNS/bitquark-subdomains-top100000.txt >> a && sort -uf a > find_subdomains_in_scope/subdomain_bf_wordlist.txt && rm a
fi

# The awk below is used to print out the full domain found (otherwise it only prints the found subdomain which is not helpful if multiple targets are used in this ffuf command since we won't know which domain is associated to the found domain) 
for target in $(cat in_scope_target_list.txt);do ffuf -ic -w find_subdomains_in_scope/subdomain_bf_wordlist.txt  -u "https://FUZZ.$target" | awk -v target=$(echo $target) '{print $1=$1"."target}' >> find_subdomains_in_scope/ffuf_output_subdomain.txt;done


# Repeat section 2 on the ffuf output to perform the same checks to remove anything that is out of scope or not based in the US
inscope_cnames=$(cat CNAMES_inscope.txt)
for subdomain in $(cat find_subdomains_in_scope/ffuf_output_subdomain.txt); do
    # Check if the subdomain has a CNAME record
    cname_record=$(dig "$subdomain" CNAME +short)

    # If there's no CNAME record, add to the in scope list
    if [[ -z "$cname_record" ]]; then
        echo "$subdomain" >> find_subdomains_in_scope/ffuf_output_after_removing_subdomains_that_have_outofscope_CNAMES.txt
    else
        cleaned_cname=$(echo "$cname_record" | sed 's/\.$//'| tr '[:upper:]' '[:lower:]')
        echo "$inscope_cnames" | while IFS= read -r line_inscope_cnames; do
        if [[ "$cleaned_cname" == *"$line_inscope_cnames" ]]; then
            echo "$subdomain" >> find_subdomains_in_scope/ffuf_output_after_removing_subdomains_that_have_outofscope_CNAMES.txt
            break        
            fi
        done
    fi
done

# Remove subdomains that are listed in the out_of_scope.txt file
out_of_scope=$(cat out_of_scope.txt)
for subdomain in $(cat find_subdomains_in_scope/ffuf_output_after_removing_subdomains_that_have_outofscope_CNAMES.txt); do
    echo "$out_of_scope" | while IFS= read -r line_out_of_scope; do
    is_it_out_of_scope=false
    if ! [[ "$subdomain" == *"$line_out_of_scope" ]]; then
        echo "$subdomain" >> find_subdomains_in_scope/ffuf_output_after_removing_subdomains_that_have_outofscope_domains.txt
        break
    fi
    done
done

# Remove subdomains that do not resolve to an IP. The ${,,} part is to convert the nslookup_output variable into lowercase because Can't is sometimes uppercase 'C' and sometimes lower case 'c'. 
for subdomain in $(cat find_subdomains_in_scope/ffuf_output_after_removing_subdomains_that_have_outofscope_domains.txt);do nslookup_output=$(nslookup "$subdomain");if [[ ! "${nslookup_output,,}" == *"can't find"* ]];then echo $subdomain >> find_subdomains_in_scope/ffuf_output_after_removing_nonresolving_IPs.txt;fi;done

# Remove subdomains that are not based in the US
for subdomain in $(cat find_subdomains_in_scope/ffuf_output_after_removing_nonresolving_IPs.txt); do geoip=$(dig +short A "$subdomain" |tail -n 1 | xargs -I {} geoiplookup {});if echo "$geoip" | grep -qi "US, United States";then echo "$subdomain" >> find_subdomains_in_scope/ffuf_output_finalresults-step4_that_are_US_based.txt;else echo "$subdomain: $geoip" >> find_subdomains_in_scope/ffuf_output-step4-all_found_subdomains_that_did_not_return_as_US_based.txt;fi;done
