#!/bin/bash

# Unified script for starting and stopping BioSoundsLab environment

# Log file
LOGFILE="/tmp/biosoundslab.log"

# Base directory
BIOSOUNDSLAB_DIR=~/Workspace/biosoundslab

# Export all variables from .env
set -a
source "$BIOSOUNDSLAB_DIR/.env"
set +a

# Function to start all services
start_services() {
    echo "Starting BioSoundsLab environment at $(date)" > "$LOGFILE"

    # Activate conda environment
    source ~/miniconda3/etc/profile.d/conda.sh
    conda activate biosoundslab >> "$LOGFILE" 2>&1

    # Start Docker containers
    cd "$BIOSOUNDSLAB_DIR"
    docker compose -f docker-compose.yaml up -d >> "$LOGFILE" 2>&1

    # Start backend dev.sh
    cd "$BIOSOUNDSLAB_DIR/backend/"
    /bin/bash dev.sh -d >> "$LOGFILE" 2>&1 &

    # Start frontend npm
    cd "$BIOSOUNDSLAB_DIR/frontend/"
    /usr/bin/npm start >> "$LOGFILE" 2>&1 &

    echo "All services started. Logging to $LOGFILE"
}

# Function to stop all services
stop_services() {
    echo "Stopping BioSoundsLab environment at $(date)" >> "$LOGFILE"

    # Stop frontend npm process
    echo "Stopping frontend (npm start)..." >> "$LOGFILE"
    pkill -f "npm start" >> "$LOGFILE" 2>&1

    # Stop backend dev.sh process
    echo "Stopping backend (dev.sh)..." >> "$LOGFILE"
    pkill -f "dev.sh -d" >> "$LOGFILE" 2>&1

    # Stop Docker containers
    echo "Stopping Docker containers..." >> "$LOGFILE"
    cd "$BIOSOUNDSLAB_DIR"
    docker compose -f docker-compose.yaml down >> "$LOGFILE" 2>&1

    pkill -f celery

    echo "All services stopped. Logging to $LOGFILE"
}

# Check the argument
case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac
