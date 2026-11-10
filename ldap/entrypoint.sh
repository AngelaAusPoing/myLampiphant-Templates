#!/bin/bash
# Bootstrap cn=config + the base tree on first start, then exec slapd as openldap.
# Passwords are read from files; they are never printed.
set -euo pipefail

CONFIG_DIR="${LDAP_CONFIG_DIR:-/etc/ldap/slapd.d}"
DATA_DIR="${LDAP_DATA_DIR:-/var/lib/ldap}"
SCHEMA_DIR="${LDAP_SCHEMA_DIR:-/etc/ldap/schema}"
MAIL_SCHEMA="${LDAP_MAIL_SCHEMA:-/opt/mylampiphant/schema/mylampiphant-mail.ldif}"
RUN_DIR="${LDAP_RUN_DIR:-/var/run/slapd}"

BASE_DN="${LDAP_BASE_DN:?LDAP_BASE_DN is required}"
ORGANISATION="${LDAP_ORGANISATION:-Example}"
ROOT_DN="${LDAP_ROOT_DN:-cn=admin,${BASE_DN}}"
READONLY_DN="${LDAP_READONLY_DN:-cn=readonly,ou=system,${BASE_DN}}"
ROOT_PW_FILE="${LDAP_ROOT_PW_FILE:-/run/secrets/ldap_root_pw}"
READONLY_PW_FILE="${LDAP_READONLY_PW_FILE:-/run/secrets/ldap_readonly_pw}"

mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$RUN_DIR"
chown openldap:openldap "$CONFIG_DIR" "$DATA_DIR" "$RUN_DIR"

# Already initialized? (config + data present)
if [ -d "${CONFIG_DIR}/cn=config" ] || [ -f "${CONFIG_DIR}/cn=config.ldif" ]; then
    if [ -f "${DATA_DIR}/data.mdb" ] || [ -f "${DATA_DIR}/id2entry.mdb" ] || ls "${DATA_DIR}"/*.mdb >/dev/null 2>&1; then
        echo "OpenLDAP already initialized, starting slapd"
        exec slapd -h "ldap://0.0.0.0:389/ ldapi:///" -F "$CONFIG_DIR" -u openldap -g openldap -d stats
    fi
fi

echo "First start: bootstrapping OpenLDAP (cn=config + base tree)"

if [ ! -s "$ROOT_PW_FILE" ] || [ ! -s "$READONLY_PW_FILE" ]; then
    echo "ERROR: password files are missing or empty" >&2
    exit 1
fi

# Wipe any leftover incomplete config from a failed first start
rm -rf "${CONFIG_DIR:?}/"*
# keep data dir empty too on first bootstrap
find "$DATA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

ROOT_HASH=$(slappasswd -T "$ROOT_PW_FILE")
READONLY_HASH=$(slappasswd -T "$READONLY_PW_FILE")

# Escape dots in the base DN for regex-based ACLs
BASE_RE=$(printf '%s' "$BASE_DN" | sed 's/\./\\./g')
# RDN value of a dc=/o=/c= suffix
SUFFIX_RDN_TYPE="${BASE_DN%%=*}"
SUFFIX_RDN_VALUE="${BASE_DN%%,*}"
SUFFIX_RDN_VALUE="${SUFFIX_RDN_VALUE#*=}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# cn=config (database 0)
# ---------------------------------------------------------------------------
cat > "$WORK/00-frontend.ldif" <<EOF
dn: cn=config
objectClass: olcGlobal
cn: config
olcArgsFile: ${RUN_DIR}/slapd.args
olcPidFile: ${RUN_DIR}/slapd.pid
olcLogLevel: stats
olcTLSCipherSuite: HIGH:-SSLv3
olcSizeLimit: unlimited

dn: cn=module{0},cn=config
objectClass: olcModuleList
cn: module{0}
olcModulePath: /usr/lib/ldap
olcModuleLoad: {0}back_mdb.la
olcModuleLoad: {1}memberof.la
olcModuleLoad: {2}refint.la
olcModuleLoad: {3}ppolicy.la

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema
EOF

# Main database + ACLs
cat > "$WORK/90-database.ldif" <<EOF
dn: olcDatabase={1}mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: {1}mdb
olcDbDirectory: ${DATA_DIR}
olcSuffix: ${BASE_DN}
olcRootDN: ${ROOT_DN}
olcRootPW: ${ROOT_HASH}
olcDbIndex: objectClass eq
olcDbIndex: entryUUID eq
olcDbIndex: entryCSN eq
olcDbIndex: cn eq,sub
olcDbIndex: uid eq,sub
olcDbIndex: mail eq,sub
olcDbIndex: mailAlias eq,sub
olcDbIndex: member eq
olcDbIndex: memberOf eq
olcDbMaxSize: 1073741824
olcLastMod: TRUE
olcAccess: {0}to dn.regex="^(.+,)?o=([^,]+),${BASE_RE}\$" attrs=userPassword,shadowLastChange,pwdChangedTime,pwdFailureTime,pwdAccountLockedTime,pwdPolicySubentry by self write by dn.exact,expand="cn=admin,o=\$2,${BASE_DN}" write by dn.exact="${READONLY_DN}" read by anonymous auth by * none
olcAccess: {1}to attrs=userPassword,shadowLastChange,pwdChangedTime,pwdFailureTime,pwdAccountLockedTime,pwdPolicySubentry by self write by dn.exact="${READONLY_DN}" read by anonymous auth by * none
olcAccess: {2}to dn.subtree="ou=system,${BASE_DN}" by dn.exact="${READONLY_DN}" read by * none
olcAccess: {3}to dn.regex="^(.+,)?o=([^,]+),${BASE_RE}\$" by dn.exact,expand="cn=admin,o=\$2,${BASE_DN}" write by dn.exact="${READONLY_DN}" read by self read by * none
olcAccess: {4}to * by dn.exact="${READONLY_DN}" read by * none

dn: olcOverlay={0}memberof,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcMemberOf
olcOverlay: {0}memberof
olcMemberOfDangling: ignore
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: groupOfNames
olcMemberOfMemberAD: member
olcMemberOfMemberOfAD: memberOf

dn: olcOverlay={1}refint,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcRefintConfig
olcOverlay: {1}refint
olcRefintAttribute: member
olcRefintAttribute: memberOf

dn: olcOverlay={2}ppolicy,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcPPolicyConfig
olcOverlay: {2}ppolicy
olcPPolicyDefault: cn=default,ou=policies,ou=system,${BASE_DN}
olcPPolicyHashCleartext: TRUE
olcPPolicyUseLockout: TRUE
EOF

# Load standard schemas then our mail schema into cn=config (order matters)
copy_schema() {
    local name="$1"
    local src
    if [ -f "${SCHEMA_DIR}/${name}.ldif" ]; then
        src="${SCHEMA_DIR}/${name}.ldif"
    else
        echo "ERROR: Debian schema ${name}.ldif not found in ${SCHEMA_DIR}" >&2
        ls -1 "$SCHEMA_DIR" >&2 || true
        return 1
    fi
    # Keep the file as shipped (dn: cn=NAME,cn=schema,cn=config)
    cp "$src" "$WORK/schema-${name}.ldif"
}

copy_schema core
copy_schema cosine
# Debian may ship nis or rfc2307bis
if [ -f "${SCHEMA_DIR}/nis.ldif" ]; then
    copy_schema nis
elif [ -f "${SCHEMA_DIR}/rfc2307bis.ldif" ]; then
    copy_schema rfc2307bis
else
    echo "WARN: no nis/rfc2307bis schema found, continuing without it" >&2
fi
copy_schema inetorgperson
# Debian 13 / OpenLDAP 2.6 already ships the pwdPolicy attribute types;
# do not load a second ppolicy schema (duplicate OID errors).
cp "$MAIL_SCHEMA" "$WORK/schema-mylampiphant-mail.ldif"

# slapadd config in order
slapadd -n 0 -F "$CONFIG_DIR" -l "$WORK/00-frontend.ldif"
for f in "$WORK"/schema-core.ldif \
         "$WORK"/schema-cosine.ldif \
         "$WORK"/schema-nis.ldif \
         "$WORK"/schema-rfc2307bis.ldif \
         "$WORK"/schema-inetorgperson.ldif \
         "$WORK"/schema-ppolicy.ldif \
         "$WORK"/schema-mylampiphant-mail.ldif; do
    [ -f "$f" ] || continue
    slapadd -n 0 -F "$CONFIG_DIR" -l "$f"
done
slapadd -n 0 -F "$CONFIG_DIR" -l "$WORK/90-database.ldif"

# ---------------------------------------------------------------------------
# Base tree (database 1)
# ---------------------------------------------------------------------------
{
    if [ "$SUFFIX_RDN_TYPE" = "dc" ]; then
        cat <<EOF
dn: ${BASE_DN}
objectClass: top
objectClass: dcObject
objectClass: organization
o: ${ORGANISATION}
dc: ${SUFFIX_RDN_VALUE}
EOF
    else
        cat <<EOF
dn: ${BASE_DN}
objectClass: top
objectClass: organization
o: ${ORGANISATION}
EOF
    fi
    cat <<EOF

dn: ou=system,${BASE_DN}
objectClass: top
objectClass: organizationalUnit
ou: system
description: Host-level service accounts and policies

dn: ou=policies,ou=system,${BASE_DN}
objectClass: top
objectClass: organizationalUnit
ou: policies

dn: cn=default,ou=policies,ou=system,${BASE_DN}
objectClass: top
objectClass: device
objectClass: pwdPolicy
cn: default
pwdAttribute: userPassword
pwdMinLength: 8
pwdMaxFailure: 10
pwdLockout: TRUE
pwdLockoutDuration: 600
pwdMustChange: FALSE
pwdAllowUserChange: TRUE
pwdSafeModify: FALSE
pwdCheckQuality: 1
pwdInHistory: 0

dn: ${READONLY_DN}
objectClass: top
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: readonly
description: Read-only bind for docker-mailserver, Authelia and other services
userPassword: ${READONLY_HASH}
EOF
} > "$WORK/base-tree.ldif"

slapadd -n 1 -F "$CONFIG_DIR" -l "$WORK/base-tree.ldif"

chown -R openldap:openldap "$CONFIG_DIR" "$DATA_DIR" "$RUN_DIR"
# Test the config before exec
slaptest -F "$CONFIG_DIR" -Q
echo "OpenLDAP bootstrap complete"
unset ROOT_HASH READONLY_HASH

exec slapd -h "ldap://0.0.0.0:389/ ldapi:///" -F "$CONFIG_DIR" -u openldap -g openldap -d stats
