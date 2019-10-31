# MANAGEMENT TASKS
slapadd_data(){
  echo "${FUNCNAME[ 0 ]} $@"
  while [[ "$#" -gt 0 ]]
  do
    case $1 in
      -l) local LDIF_FILE="$2" ; shift ; shift;
        ;;
      -b) local DB_NAME="$2" ; shift ; shift;
        ;;
      *) echo "unknown argument $1"; return 1
    esac
  done

  if [ ! LDIF_FILE ]; then echo "-l \$LDIF_FILE must be passed" ;return 1 ; fi
  if [ ! DB_NAME ]; then echo "-l \$DB_NAME must be passed" ;return 1 ; fi

  if [[ ! ${LDIF_FILE:0:1} = '/' ]]; then
    LDIF_FILE=/mnt/$LDIF_FILE
  fi

  slapadd -b $DB_NAME -l $LDIF_FILE
  chown -R ldap:ldap $DB_DATADIR/$DB_NAME
}

ldapmodify_change_rootpassword() {

  echo "${FUNCNAME[ 0 ]} $@"
  while [[ "$#" -gt 0 ]]
  do
    case $1 in
      -b) local DB_NAME="$2" ; shift ; shift;
        ;;
      -n) local DB_NUM="$2" ; shift ; shift;
        ;;
      -e|--backend) local DB_BACKEND="$2" ; shift ; shift;
        ;;
      -p|--password) local DB_NEW_ROOT_PW="$2" ; shift ; shift;
        ;;
      -h|---hashed-password) local DB_NEW_ROOT_PW_HASHED="$2" ; shift ; shift;
        ;;
      *) echo "unknown argument $1"; return 1
    esac
  done

  if [[ ( ! $DB_NAME &&  ! ( $DB_NUM && $DB_BACKEND )) || ($DB_NAME && ( $DB_NUM || $DB_BACKEND ) ) ]] ; then
    echo "either -b \DB_NAME or -e \$DB_BACKEND and -n \$DB_NUM must be passed - not both"
    return 1
  fi
  if [[ ! $DB_NEW_ROOT_PW && ! $DB_NEW_ROOT_PW_HASHED ]]; then
    echo "-l \$DB_NEW_ROOT_PW or \DB_NEW_ROOT_PW_HASHED must be passed" ;
    return 1
  fi
  if [[ $DB_NUM && $DB_BACKEND ]]; then
    DB_DN="dn: olcDatabase={$DB_NUM}$DB_BACKEND,cn=config"
  elif [ $DB_NAME ]; then
    if [ $DB_NAME = cn=config ]; then
      DB_DN="dn: olcDatabase={0}config,cn=config"
    else
      DB_DN=`ldapsearch -LLL -Y EXTERNAL -H $SOCKET_URL -b 'cn=config' "olcSuffix=$DB_NAME" | grep "^dn:"`
    fi
  fi
  if [[ ! $DB_NEW_ROOT_PW_HASHED ]]; then
    DB_NEW_ROOT_PW_HASHED=$(slappasswd -s $DB_NEW_ROOT_PW)
  fi

  read -r -d '' LDIF << EOT
$DB_DN
changetype: modify
replace: olcRootPW
olcRootPW: $DB_NEW_ROOT_PW_HASHED
EOT
  echo "$LDIF" | ldapmodify -Y EXTERNAL -H $SOCKET_URL
  unset LDIF
}

ldapmodify_add_database() {
  echo "${FUNCNAME[ 0 ]} $@"

  while [[ "$#" -gt 0 ]]
  do
    case $1 in
      -b|--database) local DB_SUFFIX="$2" ; shift ; shift;
        ;;
      -e|--backend) local DB_BACKEND="$2" ; shift ; shift;
        ;;
      -D|--rootdn) local DB_ROOT_DN="$2" ; shift ; shift;
        ;;
      -p|--password) local DB_ROOT_PW="$2" ; shift ; shift;
        ;;
      -h|--hashed-password) local DB_ROOT_PW_HASHED="$2" ; shift ; shift;
        ;;
      *) echo "unknown argument $1"; return 1
    esac
  done

  if [[ ! ( $DB_SUFFIX && $DB_BACKEND && $DB_ROOT_DN && ( $DB_ROOT_PW || $DB_ROOT_PW_HASHED )) ]]; then
    echo '-b $DB_SUFFIX, -e $DB_BACKEND, -D $DB_ROOT_DN and -p DB_ROOT_PW or -h $DB_ROOT_PW_HASHED must be passed'
    return 1;
  fi
  if [ ! $DB_ROOT_PW_HASHED ]; then
    DB_ROOT_PW_HASHED=$(slappasswd -s $DB_ROOT_PW | base64)
  fi
  enforce_db_dir $DB_DATADIR/$DB_SUFFIX

  read -r -d '' LDIF << EOT
dn: olcDatabase=$DB_BACKEND,cn=config
changetype: add
objectClass: olcHdbConfig
olcDatabase: $DB_BACKEND
olcDbDirectory: $DB_DATADIR/$DB_SUFFIX
olcSuffix: $DB_SUFFIX
olcRootDN: $DB_ROOT_DN
olcRootPW:: $DB_ROOT_PW_HASHED
EOT
  echo "$LDIF" | ldapadd -Y EXTERNAL -H $SOCKET_URL
  unset LDIF
}

ldapmodify_config() {
  # update cn=config with ldif-files foundn in /mnt/slapd.d-ldapmodify.d
  # better not to call this on ldifs that have already run for now
  # used in init_update_config
  echo "${FUNCNAME[ 0 ]} $@"
  for FILE in "$1"/*;do
    if [ -d "$FILE" ];then
      echo "recursing into: $FILE"
      enforce_db_dirs_from_olc "$FILE"
      ldapmodify_config "$FILE"
    elif [[ -f "$FILE" && ( $FILE == *".j2.ldif" )  ]]; then
      FILENAME="${FILE##*/}"
      echo "FILE is $FILE"
      echo "FILENAME is $FILENAME"
      cp $FILE /tmp/$FILENAME
      /jinja_replace.py /tmp/$FILENAME > /tmp/$FILENAME.result
      enforce_db_dirs_from_olc /tmp/$FILENAME.result
      ldapmodify -Y EXTERNAL -H $SOCKET_URL -f /tmp/$FILENAME.result
      rm /tmp/$FILENAME /tmp/$FILENAME.result
    elif [[ -f "$FILE" && ( $FILE == *".ldif" )  ]]; then
      ldapmodify -Y EXTERNAL -H $SOCKET_URL -f $FILE
      enforce_db_dirs_from_olc $FILE
    fi
  done
}
