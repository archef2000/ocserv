# OpenConnect VPN Server

# Customisation
* Base: Alpine 3.16
* Latest OpenConnect Server 1.1.6
* Size: 90 MB 
* Modification of the listening port, dns servers, routing and authentication
* Advanced manual configuration for power users

## Basic Configuration
### Without customizing cert variables
```
$ docker run --privileged  -d \
              -p 443:443 \
              -p 443:443/udp \
              -e "DOMAIN=vpn.example.com" \
              archef2000/ocserv
```
### With customizing cert variables
```
$ docker run --privileged  -d \
              -p 443:443 \
              -p 443:443/udp \
              -e "CA_CN=VPN CA" \
              -e "CA_ORG=OCSERV" \
              -e "CA_DAYS=9999" \
              -e "DOMAIN=vpn.example.com" \
              -e "SRV_ORG=MyCompany" \
              -e "SRV_DAYS=9999" \
              archef2000/ocserv
```

```
$ docker run --privileged  -d \
              -v /your/config/path/:/etc/ocserv \
              -e "LISTEN_PORT=443" \
              -e "DNS_SERVERS=1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4" \
              -e "TUNNEL_MODE=split-include" \
              -e "TUNNEL_ROUTES=192.168.178/24,10.11.0.0/24" \
              -e "SPLIT_DNS_DOMAINS=example.com" \
              -p 443:443 \
              -p 443:443/udp \
              archef2000/ocserv
```

## Advanced Configuration:
This container allows for advanced configurations for power users who know what they are doing by **mounting the /etc/ocserv volume to a host directory**. Users can then drop in their own certs and modify the configuration. The **POWER_USER** environmental variable is required to stop the container from overwriting options set from container environment variables. Some advanced features include setting up site to site VPN links, User Groups, Proxy Protocol support and more.

# Variables
## Environment Variables
| Variable | Required | Function | Example |
|----------|----------|----------|----------|
|`LISTEN_PORT`| No | Listening port for VPN connections|`LISTEN_PORT=443`|
|`DNS_SERVERS`| No | Comma delimited name servers |`DNS_SERVERS=8.8.8.8,8.8.4.4`|
|`TUNNEL_MODE`| No | Tunnel mode (all / split-include) |`TUNNEL_MODE=split-include`|
|`TUNNEL_ROUTES`| No | Comma delimited tunnel routes in CIDR notation |`TUNNEL_ROUTES=192.168.178/24,10.11.0.0/24`|
|`SPLIT_DNS_DOMAINS`| No | Comma delimited dns domains |`SPLIT_DNS_DOMAINS=example.com`|
|`POWER_MODE`| No | Allows for advanced manual configuration via host mounted /etc/ocserv volume |`POWER_USER=no`|

## Volumes
| Volume | Required | Function | Example |
|----------|----------|----------|----------|
| `/etc/ocserv` | No | OpenConnect config files | `/your/config/path/:/etc/ocserv`|

## Ports
| Port | Proto | Required | Function | Example |
|----------|----------|----------|----------|----------|
| `443` | TCP | Yes | OpenConnect server TCP listening port | `443:443/tcp`|
| `443` | UDP | Yes | OpenConnect server UDP listening port | `443:443/udp`|

## Add User/Change Password with Variables
Add users by adding var USER_$N and PASS_$N in the Environment Variables.
Example:
```
    USER_1=test
    PASS_1=test
    CERT_1=test # For P12 cert if enabled.
```


## Add User/Change Password with commandline
Add users by executing the following command on the host running the docker container
```
docker exec -ti openconnect ocpasswd -c /etc/ocserv/ocpasswd user_1
Enter password:
Re-enter password:
```

## Delete User
Delete users by executing the following command on the host running the docker container
```
docker exec -ti openconnect ocpasswd -c /etc/ocserv/ocpasswd -d user_1
```

## Login and Logout Log Messages
After a user successfully logins to the VPN a message will be logged in the docker log.<br>
*Example of login message:*
```
User user_1 Connected - Server: 192.168.179.165 VPN IP: 192.168.255.194 Remote IP: 10.10.0.188 
```

*Example of logoff message:*
```
 User user_1 Disconnected - Bytes In: 175856 Bytes Out: 4746819 Duration:50
```

# Building the container yourself
To build this container, clone the repository and cd into it.

### Build it:
```
$ cd /repo/location/openconnect
$ docker build -t openconnect .
```
### Run it:
```
$ docker run --privileged  -d \
              -p 443:443 \
              -p 443:443/udp \
              openconnect
```

This will start a container as described in the "Run container from Docker registry" section. View the other run configurations for more advanced setups.
