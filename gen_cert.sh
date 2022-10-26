#!/bin/bash
ocserv_dir=/etc/ocserv/
otp_file_path=${ocserv_dir}otp
user_file_path=${ocserv_dir}ocpasswd
user_cert_file_path=${ocserv_dir}user-certs/
cert_file_path=${ocserv_dir}certs/
issuer="OpenConnect"

generate_user_tmpl(){
    path=$1
    user=$2
    cat << _EOF_ > ${path}/user.tmpl
cn = "$user"
unit = "admins"
expiration_days = 365
signing_key
tls_www_client
dn = "cn = $user, UID=$user"
_EOF_
}
generate_user_client_key(){
    path=$1
    certtool --generate-privkey --outfile ${path}/user-key.pem  2> /dev/null
}

generate_user_client_cert(){
    path=$1
    certtool --generate-certificate --load-privkey ${path}/user-key.pem \
             --load-ca-certificate ${cert_file_path}ca-cert.pem --load-ca-privkey ${cert_file_path}ca-key.pem \
             --template ${path}/user.tmpl --outfile ${path}/user-cert.pem 2> /dev/null
}
convert_to_p12(){
    path=$1
    pass=$2
    p12=${path}/user.p12
    certtool --to-p12 --load-privkey ${path}/user-key.pem \
             --pkcs-cipher 3des-pkcs12 \
             --load-certificate ${path}/user-cert.pem \
             --outfile ${p12} --p12-name="OpenConnect cert for user ${user}" \
             --outder --password $pass 1>/dev/null 2>&1
}
generate_client_cert(){
    user=$1
    PASSWORD=$2
    user_path=${user_cert_file_path}${user}
    mkdir -p ${user_path}/
    RECREATE="FALSE"
    if [[ ! -f ${user_path}/user.tmpl ]]
    then
        generate_user_tmpl "${user_path}" "${user}"
        RECREATE="TRUE"
    fi   
    
    if [[ ! -f ${user_path}/user-key.pem ]] || [[ "${RECREATE}" == "TRUE" ]]
    then
        echo "::: Generating private key for user ${user}"
        generate_user_client_key "${user_path}"
        RECREATE="TRUE"
    fi
    
    if [[ ! -f ${user_path}/user-cert.pem ]] || [[ "${RECREATE}" == "TRUE" ]]
    then
        echo "::: Generating public key for user ${user}"
        generate_user_client_cert "${user_path}"
        RECREATE="TRUE"
    fi
    
    if [[ ! -f ${user_path}/user.p12 ]] || [[ "${RECREATE}" == "TRUE" ]]
    then
        echo "::: Generating P12 file for user ${user}"
        convert_to_p12 "${user_path}" "${PASSWORD}"
    fi
}

N=10
for (( counter=1; counter<=N; counter++ ))
do
    username=USER_${counter}
    password=PASS_${counter}
    certpass=CERT_${counter}
    if [[ -n ${!username} ]]
    then
        if [[ -n ${!certpass} ]]
        then
            cert_password=${!certpass}
        else
            cert_password=${!password}
        fi
        generate_client_cert "${!username}" "$cert_password"
    fi
done

