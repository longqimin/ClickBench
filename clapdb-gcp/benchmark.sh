#!/bin/bash

# download data

HITS_TSV_GZ=/data/apps/hits.tsv.gz
if [[ ! -f "$HITS_TSV_GZ" ]]; then
    echo "wget --continue 'https://datasets.clickhouse.com/hits_compatible/hits.tsv.gz'"
    wget --continue 'https://datasets.clickhouse.com/hits_compatible/hits.tsv.gz' -O $HITS_TSV_GZ
fi

HITS_TSV=/data/apps/hits.tsv
if [[ ! -f "$HITS_TSV" ]]; then
    echo "pv -cN source $HITS_TSV_GZ | gzip -d > $HITS_TSV"
    pv -cN source $HITS_TSV_GZ | gzip -d > "$HITS_TSV"
    if [ $? -ne 0 ]; then
        exit 1
    fi
    # gunzip -vc "$HITS_TSV_GZ" > "$HITS_TSV"
    # gzip -dc "$HITS_TSV_GZ" > "$HITS_TSV"
fi

# install

# CLAPDB_DIR=/data/apps/clapdb/build.dev
cp ${CLAPDB_DIR}/clap_node/createdb ${CLAPDB_DIR}/clap_node/clap_node ${CLAPDB_DIR}/../stdb.toml .
if [ $? -ne 0 ]; then
    exit 1
fi

# prepare clapdb/credentials
TENANT=benchmark
DATABASE=local
USERNAME=admin
PASSWORD=admin

DEPLOYMENT="clapdb-clickbench"

CLAPDB_CREDENTIALS_FILE="$HOME/.clapdb/credentials"
if [[ ! -f "$CLAPDB_CREDENTIALS_FILE" ]]; then
    touch "$CLAPDB_CREDENTIALS_FILE"  # Create the file if it doesn't exist
fi

./createdb --config stdb.toml --tenant $TENANT --database $DATABASE --user $USERNAME --passwd $PASSWORD &
if [ $? -eq 0 ]; then
    echo "createdb success"
else
    echo "createdb failed"
    exit 1
fi

CLAPDB_CREDENTIALS=$(<$CLAPDB_CREDENTIALS_FILE)
if [[ "$CLAPDB_CREDENTIALS" == *"[$DEPLOYMENT]"* ]]; then
    echo "skip update $CLAPDB_CREDENTIALS_FILE"
else
    echo "update $CLAPDB_CREDENTIALS_FILE"
cat >> $CLAPDB_CREDENTIALS_FILE <<EOL
[${DEPLOYMENT}]
data_api_url_endpoint    = http://localhost:8000
license_api_url_endpoint = ""
tenant                   = ${TENANT}
database                 = ${DATABASE}
username                 = ${USERNAME}
password                 = ${PASSWORD}

EOL
fi

# Load the data

./clap_node --config ./stdb.toml -c 16 &>/tmp/null &
sleep 2

echo "do create table hits"
CREATE_SQL=$(<create.sql)
clapctl -n $DEPLOYMENT sql --local -s "$CREATE_SQL" -v

clapctl -n $DEPLOYMENT sql --local -v -s "copy hits from '$HITS_TSV' DELIMITER E'\t' CSV;"
echo ""
clapctl -n $DEPLOYMENT sql --local -v -s "select count(*) from hits"

pkill clap_node

# Run the queries
deployment=${DEPLOYMENT} ./run.sh
