#! /bin/bash
# BASE SERVICE
init_container(){
  if [ $TZ ]; then
    echo "Setting Timezone to $TZ"
    cp /usr/share/zoneinfo/$TZ /etc/localtime
    echo $TZ > /etc/timezone
  fi
  ulimit -n 1024 # slapd as well as some other precompiled binaries seem to require this
}

init_service() {
  mkdir -p $DB_DATADIR && chown ldap:ldap $DB_DATADIR
  mkdir -p $RUNDIR && chown ldap:ldap $RUNDIR
}

export_vars() {
  export CONF_OPT SOCKET SOCKET_URL
}

init_vars() {
    SOCKET=$RUNDIR/slapd.socket
    SOCKET_URL=ldapi://$(url_encode $SOCKET)

    if [[ $OLC && ( $OLC = 1 || "$OLC" = "true" || "$OLC" = "yes" )  ]]; then
      OLC=1
      CONF_OPT="-F /etc/openldap/slapd.d"
    else
      OLC=
      CONF_OPT="-f /etc/openldap/slapd.conf"
    fi
}

init_config() {
  if [ $OLC ]; then
    if [ -d /etc/openldap/slapd.d -a "$(ls -A /etc/openldap/slapd.d)" ]; then
      echo "slapd.d found"
    else
      init_olc_config
    fi
  else
    if [ -f /etc/openldap/slapd.conf ]; then
      echo "slapd.conf found"
    else
      init_flat_config
    fi
  fi
}

init_olc_config() {
  echo "Initializing slapd.d"
  mkdir -p /etc/openldap/slapd.d
  if [ -d /mnt/slapd.d -a "$(ls -A /mnt/slapd.d)" ]; then
    echo "Copying mounted slapd.d dir"
    cp -rf /mnt/slapd.d/* /etc/openldap/slapd.d/
    chown -R ldap:ldap /etc/openldap/slapd.d
    chmod -R 700 /etc/openldap/slapd.d
  elif [[ -f /mnt/slapd.d-slapadd.j2.ldif   ]]; then
    echo "Running slapadd slapd.d-slapadd.j2.ldif"
    cp /mnt/slapd.d-slapadd.j2.ldif /tmp/slapd.d-slapadd.j2.ldif
    /jinja_replace.py /tmp/slapd.d-slapadd.j2.ldif > /tmp/slapd.d-slapadd.j2.ldif.result
    enforce_db_dirs_from_olc /tmp/slapd.d-slapadd.j2.ldif.result
    slapadd -F /etc/openldap/slapd.d -v -bcn=config -l /tmp/slapd.d-slapadd.j2.ldif.result
    rm /tmp/slapd.d-slapadd.j2.ldif.result /tmp/slapd.d-slapadd.j2.ldif
  elif [ -f /mnt/slapd.d-slapadd.ldif ]; then
    echo "Running slapadd slapd.d-slapadd.ldif"
    enforce_db_dirs_from_olc /mnt/slapd.d-slapadd.ldif
    slapadd -F /etc/openldap/slapd.d -v -bcn=config -l /mnt/slapd.d-slapadd.ldif
  elif [[ $LDAP_OLC_ACCESS && $LDAP_OLC_ROOT_DN && ( $LDAP_OLC_ROOT_PW || $LDAP_OLC_HASHED_ROOT_PW ) ]]; then
    echo "generating base config from ENV"
    init_generate_olc_config # uses slapadd
    if [ $MODULES ]; then
      echo "Modules requested. expanding config"
      init_module_config
    fi
    if [ $SCHEMAS ]; then
      echo "Schemas requested. expanding config"
      init_schema_config
    fi
    if [[ $DB_SUFFIX && $DB_ROOT_DN && ( $DB_ROOT_PW || $DB_ROOT_HASHED_PW ) ]]; then
      init_db_config
    fi
  else
    echo "No slapd.d source found. Trying to convert slapd.conf to slapd.d"
    init_flat_config
    migrate_flat_config
  fi
  chown -R ldap:ldap /etc/openldap/slapd.d
  if [ -d /mnt/slapd.d-ldapmodify.d ]; then
    echo "/mnt/slapd.d-ldapmodify.d found. running ldifs to expand slapd.d config"
    init_update_config
  fi
  chown -R ldap:ldap /etc/openldap/slapd.d
  chmod -R 700 /etc/openldap/slapd.d
  echo "Fixing slapd.d permissions"
}

init_db_config() {
  echo "Database $DB_SUFFIX requested. expanding config"
  if [ $DB_ROOT_HASHED_PW ]; then
    PW_OPTION="-h $DB_ROOT_PW_HASHED"
  elif [ $DB_ROOT_PW ]; then
    PW_OPTION="-p $DB_ROOT_PW"
  fi
  ldapmodify_add_database -b $DB_SUFFIX -e $DB_BACKEND -D $DB_ROOT_DN $PW_OPTION
}

init_schema_config() {
  echo TODO
}
init_module_config() {
  echo TODO
}

init_generate_olc_config() {
  echo "No slapd.d source found. Altering base config from environment variables"
  if [[ ! $LDAP_OLC_HASHED_ROOT_PW && $LDAP_OLC_ROOT_PW ]]; then
    LDAP_OLC_HASHED_ROOT_PW=$(slappasswd -s $LDAP_OLC_ROOT_PW | base64)
  fi
read -r -d '' SLAPDDBASELDIF << EOT
dn: cn=config
objectClass: olcGlobal
cn: config
olcArgsFile: $RUNDIR/slapd.args
olcIdleTimeout: 300
olcPidFile: $RUNDIR/slapd.pid

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema
structuralObjectClass: olcSchemaConfig

dn: olcDatabase={-1}frontend,cn=config
objectClass: olcDatabaseConfig
objectClass: olcFrontendConfig
olcDatabase: {-1}frontend

dn: olcDatabase={0}config,cn=config
objectClass: olcDatabaseConfig
olcDatabase: {0}config
olcAccess: $LDAP_OLC_ACCESS
olcRootDN: $LDAP_OLC_ROOT_DN
olcRootPW:: $LDAP_OLC_HASHED_ROOT_PW
EOT
  echo "$SLAPDDBASELDIF"
  echo "$SLAPDDBASELDIF" | slapadd -F /etc/openldap/slapd.d -v -bcn=config
}

init_update_config() {
  # Run when /mnt/slapd.d-ldapmodify.d exists. Modify with mounted ldif snippets
  # Only runs in init_config (when no config was found on container start)
  init_service
  echo "Starting slapd to modify config..."
  /usr/sbin/slapd $CONF_OPT -h "ldap://$(hostname)/ $SOCKET_URL" -u ldap -g ldap $EXTRA_ARGS &
  echo "waiting for server"
  sleep 3
  ldapmodify_config /mnt/slapd.d-ldapmodify.d
  sleep 2
  echo "Stopping slapd."
  killall slapd
  sleep 2
}

init_flat_config() {
  if [ -f /mnt/slapd.conf ]; then
    echo "Copying mounted slapd.conf"
    cp /mnt/slapd.conf /etc/openldap/slapd.conf
    init_flat_schemas
  else
    echo "Copying distribution defaults for slapd.conf"
    copy_dist_config
  fi
  chown root:ldap /etc/openldap/slapd.conf
  chmod 0640 /etc/openldap/slapd.conf
}

init_flat_schemas() {
  for SCHEMA in $(cat /etc/openldap/slapd.conf | grep '^include' | awk '{print $2}' | sed 's!.*/!!') ; do
    echo "Trying to install $SCHEMA "
    if [ -f /mnt/schema/$SCHEMA ]; then
      cp /mnt/schema/$SCHEMA /etc/openldap/schema/$SCHEMA
      echo "Installed from /mnt/schema/$SCHEMA"
    else
      cp /build/conf/dist/schema/$SCHEMA /etc/openldap/schema/$SCHEMA
      echo "Installed from /build/conf/dist/schema/$SCHEMA"
    fi
  done
}

migrate_flat_config() {
    # Pre-generate database directories from flat config - slaptest fails otherwise
    mkdir -p /etc/openldap/slapd.d
    enforce_db_dirs_from_flat
    echo "Converting flat config to OLC format"
    slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d
}

copy_dist_config() {
  echo "running copy_dist_config"
  cp /build/conf/dist/slapd.conf /etc/openldap/slapd.conf
  cp -r /build/conf/dist/schema /etc/openldap/schema
}

enforce_db_dirs_from_olc() {
  OLC_SOURCE=${1:-/etc/openldap/slapd.d}
  echo "enforce_db_dirs_from_olc in $OLC_SOURCE"
  for DB_NAME in $(grep -r '^olcDbDirectory' $OLC_SOURCE | awk '{print $2}' | sed 's!.*/!!') ; do
    enforce_db_dir $DB_DATADIR/$DB_NAME
  done
}

enforce_db_dirs_from_flat() {
  echo "Enforcing database dirs from flat..."
  cat /etc/openldap/slapd.conf
  #for DB_NAME in $(cat /etc/openldap/slapd.conf | grep '^directory' | awk '{print $2}' | sed 's!.*!!') ; do
  for DB_FULLPATH in $(cat /etc/openldap/slapd.conf | grep '^directory' | awk '{print $2}'); do
    echo "DB_FULLPATH is $DB_FULLPATH"
    enforce_db_dir $DB_FULLPATH
  done
}

enforce_db_dir () {
  echo "enforce $1"
  mkdir -p $1
  chown ldap:ldap $1
  chmod 0700 $1
}

start_service()
{
  if [ $OLC ]; then
    echo "Using OLC."
    enforce_db_dirs_from_olc
  else
    echo "NOT using OLC"
    enforce_db_dirs_from_flat
  fi
  EXTRA_ARGS=$@
  if [ -z "$EXTRA_ARGS" ]; then
    EXTRA_ARGS="-d 0"
  fi
  echo "Starting slapd..."
  exec /usr/sbin/slapd $CONF_OPT -h "ldap://$(hostname)/ $SOCKET_URL" -u ldap -g ldap $EXTRA_ARGS
}

run(){
  init_container
  init_service
  init_config
  start_service $@
}

# ENTRYPOINT

helptext(){
printf "Usage: docker run freinet/openldap {command} {options}\n\
  commands
    run \$ARGS
    slapadd_data -l \$LDIF_FILE -b \$DB_NAME
      - ldif file must be mounted, preferably in /mnt>
    ldapmodify_config \$PATH_TO_NEW_LDIF_FILES
      - ldif files must be mounted, preferably in /mnt>
      - do NOT run files that have already run
    ldapmodify_change_rootpassword -b \$DB_NAME -n \$DB_NUM -e \$BACKEND -p \$PASSWORD -h \$HASHED_PASSWORD
      - DB_NUM in cn=config and DB_BACKEND such as hdb,mdb needed to address entry in cn=config
    ldapmodify_add_database -b \$DB_NAME -e BACKEND -D \$ROOT_DN -p \$PASSWORD -h \$HASHED_PASSWORD
      - DB_NUM in cn=config and DB_BACKEND such as hdb,mdb needed to address entry in cn=config
"
}

run_command() {
  source management.sh
  source tools.sh

  echo "command line was $@"
  local command=$1
  echo $command
  shift

  init_vars
  export_vars

  case "$command" in
    run)
      run $@
      ;;
    slapadd_data)
      init_config
      slapadd_data $@
      ;;
    ldapmodify_config)
      ldapmodify_config $@
      ;;
    ldapmodify_change_rootpassword)
      ldapmodify_change_rootpassword $@
      ;;
    ldapmodify_add_database)
      ldapmodify_add_database $@
      ;;
    bash)
      /bin/bash
      ;;
    *)
      helptext
      exit 1
      ;;
  esac
}

run_command $@
