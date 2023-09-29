#!/bin/bash

ocserv_dir=/etc/ocserv/
get_config_line(){
    echo $(grep -rne '^'$1' =' ${ocserv_dir}ocserv.conf | grep -Eo '^[^:]+') 
}
if [ -z "$TZ" ]
then
	TZ=Europe/Berlin
fi

set_config(){
    option=$1
    value=$2
    ocserv_file=$(awk '/^auth/&&c++ {next} 1' ${ocserv_dir}ocserv.conf)
    echo "$ocserv_file" > ${ocserv_dir}ocserv.conf
    option_line=$(get_config_line $option)
    option_line=${option_line##* }
    if [ ! -z "${option_line}" ]; then
        sed -i "s?^${option} .*?${option} = ${value}?g" ${ocserv_dir}ocserv.conf
    else
        echo -e "${option} = ${value}" >> ${ocserv_dir}ocserv.conf
    fi
}

run_server(){
    # Open ipv4 ip forward
    # sysctl -w net.ipv4.ip_forward=1
    # Enable NAT forwarding
    iptables -t nat -A POSTROUTING -j MASQUERADE
    iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    # Enable TUN device
    # mkdir -p /dev/net
    # mknod /dev/net/tun c 10 200
    # chmod 600 /dev/net/tun
    # Run OpennConnect Server
    exec "$@";
}

generate_cert(){
    server_cert_path=${ocserv_dir}certs/server-cert.pem
    server_key_path=${ocserv_dir}certs/server-key.pem
    cert_dir=${ocserv_dir}certs
    if [ -f ${ocserv_dir}ocserv.conf ]; then
        server_cert_path_temp="$(grep "^server-cert*" ${ocserv_dir}ocserv.conf | tail -1 | sed -e 's#.*=\(\)#\1#;s/^[ \t]*//;s/#.*//')"
        server_key_path_temp="$(grep "^server-key*" ${ocserv_dir}ocserv.conf | tail -1 | sed -e 's#.*=\(\)#\1#;s/^[ \t]*//;s/#.*//')"
        if [ ! -z "${server_cert_path_temp}" ]; then
            server_cert_path=$server_cert_path_temp
        else
            echo "server-cert = $server_cert_path" >> ${ocserv_dir}ocserv.conf
        fi
        if [ ! -z "${server_key_path_temp}" ]; then
            server_key_path=$server_key_path_temp
        else
            echo "server-key = $server_key_path" >> ${ocserv_dir}ocserv.conf
        fi
    fi
    
    mkdir -p ${ocserv_dir}certs
    if [ ! -f $server_key_path ] || [ ! -f $server_cert_path ]; then
        if [ -z "$CA_CN" ]; then
                CA_CN="VPN CA"
        fi
    
        if [ -z "$CA_ORG" ]; then
                CA_ORG="My Organization"
        fi
    
        if [ -z "$CA_DAYS" ]; then
                CA_DAYS=9999
        fi
    
        if [ -z "$DOMAIN" ]; then
                DOMAIN="example.com"
        fi
    
        if [ -z "$SRV_ORG" ]; then
                SRV_ORG="My Company"
        fi
    
        if [ -z "$SRV_DAYS" ]; then
                SRV_DAYS=9999
        fi
    
        # No certification found, generate one
        certtool --generate-privkey --outfile $cert_dir/ca-key.pem
        cat > /tmp/ca.tmpl <<-EOCA
        cn = "$CA_CN"
        organization = "$CA_ORG"
        serial = 1
        expiration_days = $CA_DAYS
        ca
        signing_key
        cert_signing_key
        crl_signing_key
EOCA
        certtool --generate-self-signed --load-privkey $cert_dir/ca-key.pem --template /tmp/ca.tmpl --outfile $cert_dir/ca-cert.pem
        certtool --generate-privkey --outfile $server_key_path
        cat > /tmp/server.tmpl <<-EOSRV
        cn = "$DOMAIN"
        organization = "$SRV_ORG"
        expiration_days = $SRV_DAYS
        signing_key
        encryption_key
        tls_www_server
EOSRV
        certtool --generate-certificate --load-privkey $server_key_path --load-ca-certificate $cert_dir/ca-cert.pem \
	--load-ca-privkey $cert_dir/ca-key.pem --template /tmp/server.tmpl --outfile $server_cert_path
    fi
}

if [ "$POWER_MODE" = "TRUE" ]; then
	echo "::: POWER MODE activated"
	generate_cert
	exec $@
else
	POWER_MODE="FALSE"
fi


if [ ! -e ${ocserv_dir}ocserv.conf ] || [ ! -e ${ocserv_dir}connect.sh ] || [ ! -e ${ocserv_dir}disconnect.sh ]; then
	echo "::: Default config loaded."
	cp -vipr "/etc/default/ocserv/" "/etc/" &>/dev/null
fi
chmod a+x ${ocserv_dir}*.sh
generate_cert

LISTEN_PORT=$(echo "${LISTEN_PORT}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~;s/[^0-9]*//g;s/^0*//')
if [ -z "${LISTEN_PORT}" ]; then
    echo "::: LISTEN_PORT not defined, defaulting to '443'"
    LISTEN_PORT=443
else
    if [ "$LISTEN_PORT" -gt "65535" ]; then
        echo "::: Specified port out of range, defaulting to '443'"
        LISTEN_PORT=443
    else
        echo "::: Defined LISTEN_PORT as '${LISTEN_PORT}'"
        echo "::: Make sure you expose the port you selected!"
    fi
fi
set_config tcp-port "${LISTEN_PORT}"
set_config udp-port "${LISTEN_PORT}"


DOMAIN=$(echo "${DOMAIN}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [ -z "${DOMAIN}" ]; then
    echo "::: LISTEN_PORT not defined, defaulting to '443'"
    DOMAIN="example.com"
else
    echo "::: Defined DOMAIN as '${DOMAIN}'"
fi
set_config default-domain "${DOMAIN}"

SPLIT_DNS_DOMAINS=$(echo "${SPLIT_DNS_DOMAINS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
sed -i '/^split-dns =/d' ${ocserv_dir}ocserv.conf
if [ ! -z "${SPLIT_DNS_DOMAINS}" ]; then
	IFS=',' read -ra split_domain_list <<< "${SPLIT_DNS_DOMAINS}"
	for split_domain_item in "${split_domain_list[@]}"; do
		DOMDUP=$(cat ${ocserv_dir}ocserv.conf | grep "split-dns = ${split_domain_item}")
		if [[ -z "$DOMDUP" ]]; then
			split_domain_item=$(echo "${split_domain_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
			echo "::: Defined SPLIT_DNS_DOMAIN as "${split_domain_item}""
			echo "split-dns = ${split_domain_item}" >> ${ocserv_dir}ocserv.conf
		fi
	done
else
	echo "::: SPLIT_DNS_DOMAINS not defined"
fi

TUNNEL_MODE=$(echo "${TUNNEL_MODE}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
sed -i '/^route =/d' ${ocserv_dir}ocserv.conf
if [ "${TUNNEL_MODE}" = "all" ]; then
	echo "::: TUNNEL_MODE defined as 'all', ignoring TUNNEL_ROUTES. If you want to define specific routes, change TUNNEL_MODE to split-include"
	echo "route = default" >> ${ocserv_dir}ocserv.conf
elif [ "${TUNNEL_MODE}" = "split-include" ]; then
    TUNNEL_ROUTES=$(echo "${TUNNEL_ROUTES}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [ ! -z "${TUNNEL_ROUTES}" ]; then
		echo "::: TUNNEL_ROUTES defined as '${TUNNEL_ROUTES}'"
        echo "$TUNNEL_ROUTES" | IFS=',' read -a myarray
        IFS=', ' read -r -a routes_array <<< "$TUNNEL_ROUTES"
        for route in "${routes_array[@]}"
        do
            echo "route = ${route}" >> ${ocserv_dir}ocserv.conf
        done		
	else
		echo "::: No TUNNEL_ROUTES defined, but TUNNEL_MODE is defined as split-include, defaulting to 'all'"
		echo "route = default" >> ${ocserv_dir}ocserv.conf
	fi
else
	echo "::: TUNNEL_MODE not defined, defaulting to 'all'"
	echo "route = default" >> ${ocserv_dir}ocserv.conf
fi

DNS_SERVERS=$(echo "${DNS_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [ ! -z "${DNS_SERVERS}" ]; then
	echo "::: DNS_SERVERS defined as '${DNS_SERVERS}'"
else
	echo "::: DNS_SERVERS not defined, defaulting to Cloudflare and Google name servers"
	DNS_SERVERS="1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4"
fi

sed -i '/^dns =/d' ${ocserv_dir}ocserv.conf
IFS=',' read -ra dns_servers_list <<< "${DNS_SERVERS}"
for dns_server in "${dns_servers_list[@]}"; do
	split_domain_item=$(echo "${dns_server}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	echo "dns = ${dns_server}" >> ${ocserv_dir}ocserv.conf
done

N=10
for (( counter=1; counter<=N; counter++ ))
do
    username=USER_${counter}
    password=PASS_${counter}
    if [[ -n ${!username} ]]
    then
        echo "::: Adding user ${!username}"
        ocpasswd -c ${ocserv_dir}ocpasswd -g "Route,All" ${!username}<<< "${!password}"
    fi
done

AUTH_METHOD=${AUTH_METHOD^^}
if [[ "${AUTH_METHOD}" == *"OTP"* ]] && [[ "${AUTH_METHOD}" == *"TEXT"* ]]
then
    echo "::: Auth method set to \"TEXT+OTP\" auth"
    bash /generate_otp.sh
    set_config "auth" "\"plain[passwd=/etc/ocserv/ocpasswd,otp=/etc/ocserv/otp]\""
    
elif [[ "${AUTH_METHOD}" == *"CERT"* ]] && [[ "${AUTH_METHOD}" == *"OTP"* ]] && [[ "${AUTH_METHOD}" == *"TEXT"* ]]
then
    echo "::: Auth method set to \"TEXT+OTP+CERTIFICATE\" auth"
    bash /generate_otp.sh
    bash /gen_cert.sh
    set_config "auth" "\"plain[passwd=/etc/ocserv/ocpasswd,otp=/etc/ocserv/otp]\" \nauth = \"certificate\""
    
elif [[ "${AUTH_METHOD}" == *"CERT"* ]] && [[ "${AUTH_METHOD}" == *"OTP"* ]]
then
    echo "::: Auth method set to \"OTP+CERTIFICATE\" auth"
    bash /generate_otp.sh
    bash /gen_cert.sh
    set_config "auth" "\"plain[otp=/etc/ocserv/otp]\" \nauth = \"certificate\""
    
elif [[ "${AUTH_METHOD}" == *"CERT"* ]] && [[ "${AUTH_METHOD}" == *"TEXT"* ]]
then
    echo "::: Auth method set to \"TEXT+CERTIFICATE\" auth"
    bash /gen_cert.sh
    set_config "auth" "\"plain[passwd=/etc/ocserv/ocpasswd]\" \nauth = \"certificate\""

elif [[ "${AUTH_METHOD}" == *"CERT"* ]]
then
    echo "::: Auth method set to \"CERTIFICATE\" auth"
    bash /gen_cert.sh
    set_config "auth" "\"certificate\""

elif [[ "${AUTH_METHOD}" == *"TEXT"* ]]
then
    echo "::: Auth method set to \"TEXT\" auth"
    set_config "auth" "\"plain[passwd=/etc/ocserv/ocpasswd]\""

elif [[ "${AUTH_METHOD}" == *"OTP"* ]]
then
    echo "::: Auth method set to \"OTP\" auth"
    bash /generate_otp.sh
    set_config "auth" "\"plain[otp=/etc/ocserv/otp]\""
    
else
    set_config "auth" "\"plain[passwd=/etc/ocserv/ocpasswd]\""
fi



run_server $@
