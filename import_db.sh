
import_dbs() {
    # Import databases from /mnt/databases if they don't exist
    local DB_PATH
    local DB_NAME
    for DB_PATH in /mnt/database/copy/* ; do
      if [[ -d $DB_PATH && "$(ls -A $DB_PATH)" ]]; then
        # assume DB_NAME as dirname
        DB_NAME=${DB_PATH##*/}
        copy_db $DB_NAME
        echo "copy_db $DB_NAME"
      fi
    done
    for DB_PATH in /mnt/database/slapadd/* ; do
      if [[ -f $DB_PATH && $DB_PATH == *".ldif" ]]; then
        # assume DB_NAME filename
        DB_NAME="${DB_PATH##*/}"
        DB_NAME="${DB_NAME%.*}"
        echo "import_db_slapadd $DB_NAME"
        import_db_slapadd $DB_NAME
      fi
    done
}

copy_db() {
  local DB_NAME=$1
  if [ ! -d $DB_DATADIR/$DB_NAME -o -z "$(ls -A $DB_DATADIR/$DB_NAME)" ]; then
    echo "copying $DB_NAME ..."
    mkdir -p $DB_DATADIR/$DB_NAME
    cp -r /mnt/database/copy/$DB_NAME/* $DB_DATADIR/$DB_NAME/
  else
    echo "$DB_NAME was already there, not copied"
  fi
}

import_db_slapadd() {
  local DB_NAME=$1
  if [ ! -d $DB_DATADIR/$DB_NAME -o -z "$(ls -A $DB_DATADIR/$DB_NAME)" ]; then
    echo "importing $DB_NAME using slapadd..."
    slapadd -v -b $DB_NAME  -l /mnt/database/slapadd/$DB_NAME.ldif
    chown -R ldap:ldap $DB_DATADIR/$DB_NAME
  else
    echo "$DB_NAME was already there, not imported"
  fi
}
