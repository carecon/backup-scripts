#!/bin/bash

# Usage local:
# curl -fsSL https://raw.githubusercontent.com/carecon/backup-scripts/master/backup-hetzner.sh | sh -s -- -i=files.txt -u=username -p=password -d=/my.server.com

print_usage() {
    echo "Usage: ./backup.sh -i=files.txt -u=user123 -p=password -d=/backup/site.com"
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
        -f=*|--files=*)
            FILES="${i#*=}"
            shift # past argument=value
            ;;
        --postgres-user=*)
            POSTGRES_USER="${i#*=}"
            shift # past argument=value
            ;;
        --postgres-pass=*)
            POSTGRES_PASS="${i#*=}"
            shift # past argument=value
            ;;
        --postgres-db=*)
            POSTGRES_DB="${i#*=}"
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
    FILES=$(cat $INPUT)
fi

if [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_PASS" ] || [ -z "$REMOTE_DIRECTORY" ]; then
    print_usage
    exit 1
fi

if [ -z "$FILES" ] && [ -z "$POSTGRES_USER" ]; then
    print_usage
    exit 1
fi


STORAGE_BOX_USER=$REMOTE_USER
STORAGE_BOX_PASS=$REMOTE_PASS
STORAGE_BOX_HOST="${REMOTE_HOST:-$STORAGE_BOX_USER.your-backup.de}"
TSTAMP=`date "+%Y%m%d-%H%M"`

#####
# setup (TODO only do this once! check how though?)
#####
yum install -y sshpass
ssh-keygen -R $STORAGE_BOX_HOST || echo 'Host was not yet added'
ssh-keyscan -H $STORAGE_BOX_HOST >> ~/.ssh/known_hosts

# OPTIONAL #########################################################################

#####
# Optional Postgres
#####
FILES_TO_DELETE=""

if [ -n "$POSTGRES_USER" ] && [ -n "$POSTGRES_PASS" ] && [ -n "$POSTGRES_DB" ]; then
    BACKUP_FILE_POSTGRES=/tmp/backup-$TSTAMP-postgres-$POSTGRES_DB.backup
    printf -v FILES "%s $BACKUP_FILE_POSTGRES" "$FILES"
    printf -v FILES_TO_DELETE "%s $BACKUP_FILE_POSTGRES" "$FILES_TO_DELETE"

    export PGPASSWORD=$POSTGRES_PASS
    pg_dump -h 127.0.0.1 -U $POSTGRES_USER -d $POSTGRES_DB -Fc > $BACKUP_FILE_POSTGRES
    # pg_restore -h localhost -U $POSTGRES_USER --create --clean -d $POSTGRES_DB ~/insurtec.backup
fi

####################################################################################

#####
# Create backup file
#####
BACKUP_FILE=/tmp/backup-$TSTAMP.tar.gz

tar -czf $BACKUP_FILE $FILES

#####
# Copy to backup storage
#####
REMOTE_FILE_DAILY=backup-daily-`date +%A`.tar.gz
REMOTE_FILE_WEEKLY=backup-weekly-$((($(date +%-d)-1)/7+1)).tar.gz
REMOTE_FILE_MONTHLY=backup-monthly-`date +%B`.tar.gz

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

if [ -n "$FILES_TO_DELETE" ]; then
     rm -rf $FILES_TO_DELETE
fi
