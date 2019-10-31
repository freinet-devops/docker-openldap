FROM alpine:3.10
LABEL maintainer="Sebastian Pitsch <pitsch@freinet.de>" \
      version="2.4.48" \
      name="freinet/openldap" \
      updated="2019-10-31"
ARG OPENLDAP_VERSION=2.4.48-r0
ARG OPENSSL_VERSION=1.1.1d-r0

ENV DB_DATADIR=/var/lib/openldap \
    RUNDIR=/var/run/openldap \
    OLC=1

RUN apk -U add openldap=$OPENLDAP_VERSION \
openldap-back-mdb=$OPENLDAP_VERSION \
openldap-back-bdb=$OPENLDAP_VERSION \
openldap-back-hdb=$OPENLDAP_VERSION \
openldap-back-monitor=$OPENLDAP_VERSION \
openldap-back-relay=$OPENLDAP_VERSION \
openldap-overlay-auditlog=$OPENLDAP_VERSION \
openldap-overlay-syncprov=$OPENLDAP_VERSION \
openldap-overlay-memberof=$OPENLDAP_VERSION \
openldap-overlay-ppolicy=$OPENLDAP_VERSION \
openldap-clients=$OPENLDAP_VERSION \
openssl=${OPENSSL_VERSION} \
bash \
tree \
python \
py-jinja2 \
ca-certificates

COPY build.sh /build.sh
COPY jinja_replace.py /jinja_replace.py
RUN chmod 0700 /build.sh
RUN /build.sh

COPY entrypoint.sh /entrypoint.sh
COPY management.sh /management.sh
COPY tools.sh /tools.sh
RUN chmod 0770 /entrypoint.sh management.sh

EXPOSE 389

CMD ["run"]
ENTRYPOINT ["/entrypoint.sh"]
