#!/bin/bash

TRIES=3

QUERY_NUM=1
echo "query_num,try,execution_time" >result.csv
cat queries.sql | while read query; do
    cd ../../stdb/build.enum-empty-rows/ && ./clap_node/clap_node --config ../stdb-dev.toml &>/tmp/null &
    sleep 1

    # echo "${QUERY_NUM} ${query}"
    echo -n "["
    for i in $(seq 1 $TRIES); do
        RES=$(clapctl -n ${deployment} sql -v -s "$query" | grep 'x-process-time' | awk '{print $3}')
        if [[ -n "$RES" ]]; then
            echo -n "${RES}"
            echo "${QUERY_NUM},${i},${RES}" >>result.csv
        else
            echo -n "null"
            echo "${QUERY_NUM},${i},null" >>result.csv
        fi
        [[ "$i" != $TRIES ]] && echo -n ", "
    done
    echo "],"
    QUERY_NUM=$((QUERY_NUM + 1))
    pkill clap_node
done
