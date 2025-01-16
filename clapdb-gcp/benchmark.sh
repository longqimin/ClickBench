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
CLAPDB_HTTP_PORT=8000
./clap_node --config ./stdb.toml --proxy-port ${CLAPDB_HTTP_PORT} -c 16 &>/tmp/null &
sleep 2

echo "do create table hits"
CREATE_SQL=$(<create.sql)
# clapctl -n $DEPLOYMENT sql --local -s "$CREATE_SQL" -v
echo "Query: $CREATE_SQL"
curl -X POST -d "${CREATE_SQL}" -u "${USERNAME}.${TENANT}:${PASSWORD}" "http://localhost:${CLAPDB_HTTP_PORT}/psql?database=${DATABASE}"
# check create table success

# COPY_SQL="copy hits from '$HITS_TSV' DELIMITER E'\t' CSV;"
# # clapctl -n $DEPLOYMENT sql --local -v -s "${COPY_SQL}"
# echo "Query: $COPY_SQL"
# curl -X POST -d "${COPY_SQL}" -u "${USERNAME}.${TENANT}:${PASSWORD}" "http://localhost:${CLAPDB_HTTP_PORT}/psql?database=${DATABASE}"

echo ""
COUNT_SQL="select count(*) from hits"
# clapctl -n $DEPLOYMENT sql --local -v -s "${COUNT_SQL}"
echo "Query: $COUNT_SQL"
curl -X POST -d "${COUNT_SQL}" -u "${USERNAME}.${TENANT}:${PASSWORD}" "http://localhost:${CLAPDB_HTTP_PORT}/psql?database=${DATABASE}"

pkill clap_node

# Run the queries
USERNAME=${USERNAME} TENANT=${TENANT} PASSWORD=${PASSWORD} DATABASE=${DATABASE} ./run.sh
