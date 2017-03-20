#!/bin/ash

if [ -n "$DEBUG" ]; then
  set -x
fi

CONFIG_TEMPLATES="/templates"
CONFIG_DEST="/storm/conf"

ZOOKEEPER_WAIT=${ZOOKEEPER_WAIT:-"true"}
ZOOKEEPER_WAIT_TIMEOUT=${ZOOKEEPER_WAIT_TIMEOUT:-"3"}
ZOOKEEPER_WAIT_DELAY=${ZOOKEEPER_WAIT_DELAY:-"10"}
ZOOKEEPER_WAIT_RETRIES=${ZOOKEEPER_WAIT_RETRIES:-"20"}

if [ -n "$ZOOKEEPER_SERVERS" ]; then
  if [ -z "$STORM_ZOOKEEPER_SERVERS" ]; then
    export STORM_ZOOKEEPER_SERVERS="$ZOOKEEPER_SERVERS"
  fi

  if [ -z "$TRANSACTIONAL_ZOOKEEPER_SERVERS" ]; then
    export TRANSACTIONAL_ZOOKEEPER_SERVERS="$ZOOKEEPER_SERVERS"
  fi
fi

if [ -n "$ZOOKEEPER_PORT" ]; then
  if [ -z "$STORM_ZOOKEEPER_PORT" ]; then
    export STORM_ZOOKEEPER_PORT="$ZOOKEEPER_PORT"
  fi

  if [ -z "$TRANSACTIONAL_ZOOKEEPER_PORT" ]; then
    export TRANSACTIONAL_ZOOKEEPER_PORT="$ZOOKEEPER_PORT"
  fi
fi

first_zk=$(echo $STORM_ZOOKEEPER_SERVERS | cut -d, -f1)

# wait for zookeeper to become available
if [ "$ZOOKEEPER_WAIT" = "true" ]; then
  success="false"
  for i in $(seq $ZOOKEEPER_WAIT_RETRIES); do
    ok=$(echo ruok | nc $first_zk $STORM_ZOOKEEPER_PORT -w $ZOOKEEPER_WAIT_TIMEOUT)
    if [ $? -eq 0 -a "$ok" = "imok" ]; then
      success="true"
      break
    else
      echo "Connect attempt $i of $ZOOKEEPER_WAIT_RETRIES failed, retrying..."
      sleep $ZOOKEEPER_WAIT_DELAY
    fi
  done

  if [ "$success" != "true" ]; then
    echo "Could not connect to $first_zk after $i attempts, exiting..."
    sleep 1
    exit 1
  fi
fi

if [ "$STORM_HOSTNAME_FROM_IP" = "true" ]; then
  # see also: http://stackoverflow.com/a/21336679
  ip=$(ip route get 8.8.8.8 | awk 'NR==1 {print $NF}')
  echo "Using autodetected IP as advertised hostname: $ip"
  export STORM_LOCAL_HOSTNAME=$ip
fi

if [ -z "$SUPERVISOR_CHILDOPTS" ]; then
  SUPERVISOR_CHILDOPTS="-Xmx$(python /heap.py $SUPERVISOR_MAX_HEAP_MB)"
  export SUPERVISOR_CHILDOPTS
fi

if [ -z "$WORKER_CHILDOPTS" ]; then
  WORKER_CHILDOPTS="-Xmx$(python /heap.py $WORKER_MAX_HEAP_MB)"
  WORKER_CHILDOPTS="$WORKER_CHILDOPTS -XX:+UseConcMarkSweepGC"
  if [ "$WORKER_REMOTE_JMX" = "true" ]; then
    WORKER_CHILDOPTS="$WORKER_CHILDOPTS -Dcom.sun.management.jmxremote"
  fi

  export WORKER_CHILDOPTS
fi

if [ -z "$NIMBUS_CHILDOPTS" ]; then
  NIMBUS_CHILDOPTS="-Xmx$(python /heap.py $NIMBUS_MAX_HEAP_MB)"
  export NIMBUS_CHILDOPTS
fi

if [ -z "$UI_CHILDOPTS" ]; then
  UI_CHILDOPTS="-Xmx$(python /heap.py $UI_MAX_HEAP_MB)"
  export UI_CHILDOPTS
fi

# apply all config templates
for f in $CONFIG_TEMPLATES/*; do
  if [ ! -e "$f" ]; then
    continue
  fi

  name=$(basename "$f")
  dest=$(basename "$f" .j2)
  if [ "$dest" = "$name" ]; then
    # file does not end in .j2
    cp "$f" "$CONFIG_DEST/$dest"
  else
    # file ends in .j2, apply template
    python /template.py "$f" "$CONFIG_DEST/$dest"
  fi
done

exec "$@"