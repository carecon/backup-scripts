#!/bin/bash

# Installation local:
# curl https://raw.githubusercontent.com/carecon/backup-scripts/master/backup-hetzner.sh --output backup.sh
# chmod +x backup.sh
# 
# 
print_usage() {
    echo "Usage:"
    echo "  ./backup.sh -h=my.sftp-server.com -u=username -p=password -d=/backup/site.com -p=/data,/etc"
    echo "  ./backup.sh -h=my.sftp-server.com -u=username -p=password -d=/backup/site.com -i=paths-to-backup.txt"
    
    echo "-h|--help                                  prints out the help"
    
    echo "-h=[host]|--host=[host]                    sftp backup host"
    echo "-u=[user]|--user=[user]                    sftp backup user"
    echo "-p=[pass]|--pass=[pass]                    sftp backup password"
    echo "-d=[directory]|--directory=[directory]     sftp backup directory"
    echo ""
    echo "-i=[input-file]|--input=[input-file]       file containing paths to backup"
    echo "-p=[paths]|--paths=[paths].                paths to backup separated by comma"
    echo "-e=[exclusions]|--exclude=[exclusions]     paths to be excluded from backup separated by comma"
    echo ""
    echo "--postgres-container=[container]           the postgres docker container"
    echo "--postgres-user=[user]                     the postgres user"
    echo "--postgres-db=[db]                         the postgres database to be backed up"
    echo ""
    echo "--mysql-container=[container]              the mysql docker container"
    echo "--mysql-user=[user]                        the mysql user"
    echo "--mysql-db=[db]                            the mysql database to be backed up"
}

for i in "$@"
do
    case $i in
        -h=*|--host=*)
            REMOTE_HOST="${i#*=}"
            shift # past argument=value
            ;;
        -u=*|--user=*)
            REMOTE_USER="${i#*=}"
            shift # past argument=value
            ;;
        -p=*|--pass=*)
            REMOTE_PASS="${i#*=}"
            shift # past argument=value
            ;;
        -d=*|--directory=*)
            REMOTE_DIRECTORY="${i#*=}"
            shift # past argument=value
            ;;
        -i=*|--input=*)
            INPUT="${i#*=}"
            shift # past argument=value
            ;;
        -p=*|--paths=*)
            IFS=',' read -ra PATHS <<< "${i#*=}"
            shift # past argument=value
            ;;
        -e=*|--exclude=*)
            IFS=',' read -ra EXCLUDED_PATHS <<< "${i#*=}"
            shift # past argument=value
            ;;
        -t=*|--trim=*)
            TRIM="${i#*=}"
            shift # past argument=value
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        --postgres-container=*)
            POSTGRES_CONTAINER="${i#*=}"
            shift # past argument=value
            ;;
        --postgres-user=*)
            POSTGRES_USER="${i#*=}"
            shift # past argument=value
            ;;
        --postgres-db=*)
            POSTGRES_DB="${i#*=}"
            shift # past argument=value
            ;;
        --mysql-container=*)
            MYSQL_CONTAINER="${i#*=}"
            shift # past argument=value
            ;;
        --mysql-user=*)
            MYSQL_USER="${i#*=}"
            shift # past argument=value
            ;;
        --mysql-db=*)
            MYSQL_DB="${i#*=}"
            shift # past argument=value
            ;;
        *)
            # unknown option
        ;;
    esac
done

if [ -n "$INPUT" ]; then
    if [ ! -f $INPUT ]; then
        echo "Could not find $INPUT"
        exit 1
    fi
    PATHS=$(cat $INPUT)
fi

if [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_PASS" ] || [ -z "$REMOTE_DIRECTORY" ]; then
    print_usage
    exit 1
fi

if [ -z "$PATHS" ] && [ -z "$POSTGRES_USER" ] && [ -z "$MYSQL_USER" ]; then
    print_usage
    exit 1
fi


STORAGE_BOX_USER=$REMOTE_USER
STORAGE_BOX_PASS=$REMOTE_PASS
STORAGE_BOX_HOST="${REMOTE_HOST:-$STORAGE_BOX_USER.your-backup.de}"
TSTAMP=`date "+%Y%m%d-%H%M"`

#####
# Setup (sshpass, known_hosts)
#####
install_package () {
  if command -v apt &> /dev/null; then
    apt install -y $1
  fi
  if command -v yum &> /dev/null; then
    yum install -y $1
  fi 
}

if ! command -v sshpass &> /dev/null; then
  install_package sshpass
fi

if ! ssh-keygen -F $STORAGE_BOX_HOST > /dev/null 2>&1 ; then
  # To remove old one use: ssh-keygen -R $STORAGE_BOX_HOST
  ssh-keyscan -H $STORAGE_BOX_HOST >> ~/.ssh/known_hosts
fi

# OPTIONAL #########################################################################

PATHS_TO_DELETE=""

#####
# Optional Postgres
#####
if [ -n "$POSTGRES_CONTAINER" ] && [ -n "$POSTGRES_USER" ] && [ -n "$POSTGRES_DB" ]; then
    BACKUP_FILE_POSTGRES=/tmp/backup-$TSTAMP-postgres-$POSTGRES_DB.backup
    printf -v PATHS "%s $BACKUP_FILE_POSTGRES" "$PATHS"
    printf -v PATHS_TO_DELETE "%s $BACKUP_FILE_POSTGRES" "$PATHS_TO_DELETE"

    docker exec $POSTGRES_CONTAINER pg_dump -U $POSTGRES_USER $POSTGRES_DB -Fc > $BACKUP_FILE_POSTGRES

    # Restore with:
    # createdb -h localhost -U postgres -T template0 $POSTGRES_DB
    # pg_restore -h localhost -U $POSTGRES_USER --create --clean -d $POSTGRES_DB $BACKUP_FILE_POSTGRES
fi

#####
# Optional MySQL
#####
if [ -n "$MYSQL_CONTAINER" ] && [ -n "$MYSQL_USER" ]; then
    BACKUP_FILE_MYSQL=/tmp/backup-$TSTAMP-mysql-${MYSQL_DB:-all-databases}.sql
    printf -v PATHS "%s $BACKUP_FILE_MYSQL" "$PATHS"
    printf -v PATHS_TO_DELETE "%s $BACKUP_FILE_MYSQL" "$PATHS_TO_DELETE"

    if [ -n "$MYSQL_DB" ]; then
        docker exec $MYSQL_CONTAINER mysqldump -u $MYSQL_USER -p$MYSQL_PASS $MYSQL_DB > $BACKUP_FILE_MYSQL
    else
        docker exec $MYSQL_CONTAINER mysqldump -u $MYSQL_USER -p$MYSQL_PASS --all-databases > $BACKUP_FILE_MYSQL
    fi
    # Restore with: mysql -u <user> -p < backup.sql
fi

####################################################################################

#####
# Create backup file
#####
BACKUP_FILE=/tmp/backup-$TSTAMP.tar.gz

tar_exclude_options=()
for exclude in "${EXCLUDED_PATHS[@]}"; do
  tar_exclude_options+=(--exclude="$exclude")
done
tar -czf $BACKUP_FILE ${tar_exclude_options[@]} ${PATHS[@]}

#####
# Encrypt backup (optional)
#####

if [ -n "$ENCRYPTION_PASSWORD" ]; then
  if ! command -v gpg &> /dev/null; then
    install_package gpg
  fi
  ENCRYPTED_BACKUP_FILE=$BACKUP_FILE.gpg
  echo "$ENCRYPTION_PASSWORD" | gpg --batch --yes --passphrase-fd 0 -o "$ENCRYPTED_BACKUP_FILE" -c $BACKUP_FILE
  BACKUP_FILE=$ENCRYPTED_BACKUP_FILE
fi

#####
# Copy to backup storage
#####
REMOTE_FILE_DAILY=backup-daily-`date +%A`.${BACKUP_FILE#*.}
REMOTE_FILE_WEEKLY=backup-weekly-$((($(date +%-d)-1)/7+1)).${BACKUP_FILE#*.}
REMOTE_FILE_MONTHLY=backup-monthly-`date +%B`.${BACKUP_FILE#*.}

backup () {
  sshpass -p "$STORAGE_BOX_PASS" scp $BACKUP_FILE $STORAGE_BOX_USER@$STORAGE_BOX_HOST:$REMOTE_DIRECTORY/$1
}
backup $REMOTE_FILE_DAILY
backup $REMOTE_FILE_WEEKLY
backup $REMOTE_FILE_MONTHLY

#####
# Clean up
#####
rm $BACKUP_FILE

if [ -n "$PATHS_TO_DELETE" ]; then
     rm -rf $PATHS_TO_DELETE
fi
