# myLampiphant OpenLDAP image: current Debian stable slapd, built by Komodo.
# No secrets are baked into the image; the entrypoint bootstraps cn=config on first start.
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LDAP_BASE_DN=dc=example,dc=com \
    LDAP_ORGANISATION=Example

RUN apt-get update \
 && apt-get install -y --no-install-recommends slapd ldap-utils ca-certificates coreutils \
 && rm -rf /var/lib/apt/lists/* \
 && rm -rf /etc/ldap/slapd.d/* /var/lib/ldap/* \
 && mkdir -p /etc/ldap/slapd.d /var/lib/ldap /opt/mylampiphant/schema \
 && chown -R openldap:openldap /etc/ldap /var/lib/ldap

COPY schema/mylampiphant-mail.ldif /opt/mylampiphant/schema/mylampiphant-mail.ldif
COPY schema/ppolicy.ldif /opt/mylampiphant/schema/ppolicy.ldif
COPY entrypoint.sh /opt/mylampiphant/entrypoint.sh
COPY backup-loop.sh /opt/mylampiphant/backup-loop.sh
RUN chmod 755 /opt/mylampiphant/entrypoint.sh /opt/mylampiphant/backup-loop.sh

EXPOSE 389
VOLUME ["/etc/ldap/slapd.d", "/var/lib/ldap"]

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 \
    CMD ldapsearch -x -H ldap://127.0.0.1:389 -s base -b "" namingContexts >/dev/null || exit 1

# Entrypoint starts as root so it can fix volume permissions, then execs slapd as openldap.
ENTRYPOINT ["/opt/mylampiphant/entrypoint.sh"]
