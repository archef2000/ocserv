FROM alpine:3.16
ENV OC_VERSION=1.1.6
ENV USER=test
ENV PASS=test
# Install dependencies
RUN buildDeps=" \
		curl \
		g++ \
		gawk \
		geoip \
		gnutls-dev \
		gpgme \
		krb5-dev \
		libc-dev \
		libev-dev \
		libnl3-dev \
		libproxy \
		libseccomp-dev \
		libtasn1 \
		linux-headers \
		linux-pam-dev \
		lz4-dev \
		make \
		oath-toolkit-liboath \
		oath-toolkit-libpskc \
		oath-toolkit-dev \
		p11-kit \
		pcsc-lite-libs \
		protobuf-c \
		readline-dev \
		scanelf \
		stoken-dev \
		tar \
		tpm2-tss-esys \
		xz \
		tar \
		apache2-dev \
        	openssl-dev \
	"; \
	set -x \
	&& apk add --update --virtual .build-deps $buildDeps \
	&& curl -SL "ftp://ftp.infradead.org/pub/ocserv/ocserv-$OC_VERSION.tar.xz" -o ocserv.tar.xz \
	&& mkdir -p /usr/src/ocserv \
	&& tar -xf ocserv.tar.xz -C /usr/src/ocserv --strip-components=1 \
	&& rm ocserv.tar.xz*

RUN curl -L https://s3.amazonaws.com/archie-public/mod-authn-otp/mod_authn_otp-1.1.10.tar.gz -o authn-otp.tar.gz \
    && tar -xvzf authn-otp.tar.gz \
    && cd mod-authn-otp-1.1.10 \
    && ls \
    && ./autogen.sh \
    && ./configure \
    && make \
    && cp genotpurl /usr/local/bin/ \
    && chmod +x /usr/local/bin/genotpurl

RUN cd /usr/src/ocserv \
	&& ./configure --with-liboath \
	&& make \
	&& make install \
	&& cd / \
	&& rm -rf /usr/src/ocserv \
	&& runDeps="$( \
			scanelf --needed --nobanner /usr/local/sbin/ocserv \
				| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
				| xargs -r apk info --installed \
				| sort -u \
			)" \
	&& apk add --update --virtual .run-deps $runDeps gnutls-utils iptables \
	&& apk del .build-deps \
	&& rm -rf /var/cache/apk/* 
	
RUN apk add --update bash rsync ipcalc sipcalc ca-certificates rsyslog logrotate runit libseccomp\
	&& rm -rf /var/cache/apk/* 

RUN update-ca-certificates

ADD ocserv /etc/default/ocserv
ADD ocserv /etc/ocserv
RUN chmod a+x /etc/ocserv/*.sh /etc/default/ocserv/*.sh

WORKDIR /etc/ocserv

COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 4443
EXPOSE 4443/udp
CMD ["ocserv", "-c", "/etc/ocserv/ocserv.conf", "-f"]
