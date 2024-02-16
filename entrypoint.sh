#!/bin/sh

NC="\033[0m"
INFO="\033[0;34m"
SUCCESS="\033[0;32m"
WARNING="\033[0;33m"

running=false

echo_line() {
    echo -e "$1"
}

echo_info() {
    echo -e "${INFO}$1${NC}"
}

echo_success() {
    echo -e "${SUCCESS}$1${NC}"
}

echo_warning() {
    echo -e "${WARNING}$1${NC}"
}

start_tunnel() {
    echo_line "Starting tunnel on port ${GAME_PORT} to ${CONTAINER_NAME}..."
    socat TCP4-LISTEN:$GAME_PORT,fork,reuseaddr TCP4:$CONTAINER_NAME:$GAME_PORT &

    if [ -n "$RCON_PORT" ]; then
        echo_line "Starting rcon tunnel on port ${RCON_PORT} to ${CONTAINER_NAME}..."
        socat TCP4-LISTEN:$RCON_PORT,fork,reuseaddr TCP4:$CONTAINER_NAME:$RCON_PORT &
    fi
}

check_for_start() {
    echo_line "Listening for connection attempts on port ${GAME_PORT}..."

    # Command to trigger locally: nc -vu localhost 8211
    tcpdump -n -c 1 -i any port $GAME_PORT 2> /dev/null

    echo_line "Connection attempt detected on port ${GAME_PORT}."
    
    echo_info "***STARTING SERVER***"
    docker start "${CONTAINER_NAME}"
    
    max_attempts=10
    attempt=0
    until [ $attempt -ge $max_attempts ] || docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q "healthy"; do
        echo_line "Waiting for the server to be healthy..."
        sleep 5
        attempt=$(( attempt + 1 ))
    done

    if [ $attempt -ge $max_attempts ]; then
        echo_warning "Server did not become healthy after ${max_attempts} attempts. Please check the server logs."
    else
        running=true
        echo_success "Server is healthy."
        echo_line "Allowing users ${CONNECT_GRACE_SECONDS} seconds to connect..."
        sleep "${CONNECT_GRACE_SECONDS}"
    fi
}

check_for_stop() {
    echo_line "Checking for players..."

    players_output=$(docker exec -i "${CONTAINER_NAME}" rcon-cli ShowPlayers)

    if [ "$players_output" = "name,playeruid,steamid" ]; then
        echo_line "No players found. Server will be shut down."
        echo_info "***STOPPING SERVER***"

        docker stop "${CONTAINER_NAME}"

        running=false
    fi
}

run() {
    echo_success "***STARTING MONITOR***"

    start_tunnel

    echo_line "Waiting 5 seconds..."
    sleep 5

    if [ "$( docker container inspect -f '{{.State.Status}}' ${CONTAINER_NAME} )" = "running" ]; then
        echo_line "Server is already running."
        running=true
        echo_line "Allowing users ${CONNECT_GRACE_SECONDS} seconds to connect..."
        sleep "${CONNECT_GRACE_SECONDS}"
    else
        echo_line "Server is not running."
        running=false
    fi

    while true; do
        if [ "$running" = false ]; then
            check_for_start
        else
            check_for_stop
        fi

        echo_line "Sleeping for ${LOOP_SLEEP_SECONDS} seconds..."
        sleep "${LOOP_SLEEP_SECONDS}"
    done
}

run