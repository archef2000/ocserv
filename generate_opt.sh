#!/bin/bash
ocserv_dir=/etc/ocserv/
otp_file_path=${ocserv_dir}otp
user_file_path=${ocserv_dir}ocpasswd
issuer="OpenConnect"
contains() {
    [[ $1 =~ (^|[[:space:]])$2($|[[:space:]]) ]] && echo "TRUE" || echo "FALSE"
}
to_totp_token(){
    user=$2
    totp_string=$(genotpurl -L $user -I $issuer -k $1)
    echo $totp_string
}
gen_hotp_token(){
    label=$1
    . <({ hotp_token=$({ totp_string=$(genotpurl -L $label -I $issuer -K 20 ); } 2>&1 ; declare -p totp_string >&2); declare -p hotp_token; } 2>&1)
    hotp_token=$(echo $hotp_token | sed -e 's/.* //')
    echo "${hotp_token}"
}
item_in_hotp_user_array(){
    item=$1
    if [[ ${hotp_user_array[*]} =~ (^|[[:space:]])"$item"($|[[:space:]]) ]] ; then
      result="TRUE"
    else
      result="FALSE"
    fi
    echo $result
}
print_seperator(){
    START=1
    for i in $(eval echo "{$START..$(tput cols)}")
    do
	    echo -n "="
    done
}
echo "::: OTP Auth enabled"
i=0
hotp_user_array=()
hotp_token_array=()
while read line || [[ -n $line ]];
do 
    line=$(echo $line | sed -e 's#.*=\(\)#\1#;s/^[ \t]*//;s/#.*//')
    if [ ! -z "${line}" ]; then
        IFS=' ' read -ra array_list <<< "${line}"
        if [[ "${#array_list[@]}" -lt 4 ]]
        then
            continue 
        fi
        hotp_user_array[i]=${array_list[1]} #user
        hotp_token_array[i]=${array_list[3]} #hotp_token
        i+=1
    fi
done < <(cat $otp_file_path)

i=0
user_name_list=()
while read line || [[ -n $line ]];
do
    user_name_list[i]=$(echo $line | sed -e 's#.*=\(\)#\1#;s/^[ \t]*//;s/#.*//;s/:.*//') #user_name
    i+=1
done < <(cat $user_file_path)

for user in "${user_name_list[@]}"
do
    hotp_token=""
    if [ "$(item_in_hotp_user_array $user)" = "TRUE" ]
    then
        for i in "${!hotp_user_array[@]}";
        do
            if [[ "${hotp_user_array[$i]}" = "${user}" ]];
            then
                index=$i
                hotp_token="${hotp_token_array[$i]}"
            fi
        done
    fi
    if [ -z "$hotp_token" ] || [ ${#hotp_token} -ne 40 ]
    then
        echo "::: Generating HOTP token for user $user"
        hotp_token="$(gen_hotp_token $user)"
        tabs 4
        echo -e "\nHOTP/T30\t${user}\t-\t${hotp_token}\n" >> $otp_file_path 
        hotp_user_array+=($user)
        hotp_token_array+=($hotp_token)
    fi
    totp_string="$(to_totp_token $hotp_token $user)"
    totp_token=$(echo $totp_string| sed -e 's/.*=//')
    echo "::: TOTP token/QRCode for user ${user} is: \"${totp_token}\""
    qrencode -m 2  -t ANSIUTF8 ${totp_string}
done

