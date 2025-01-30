#!/bin/bash

HOSTNAME=`hostname -s`
NODE_NUMBER=`cat -n ${HOSTFILE} | grep $HOSTNAME | awk '{print $1}'`

echo "[${HOSTNAME}] OMPI_COMM_WORLD_SIZE=${OMPI_COMM_WORLD_SIZE}"
echo "[${HOSTNAME}] OMPI_COMM_WORLD_RANK=${OMPI_COMM_WORLD_RANK}"
echo "[${HOSTNAME}] OMPI_COMM_WORLD_LOCAL_SIZE=${OMPI_COMM_WORLD_LOCAL_SIZE}"
echo "[${HOSTNAME}] OMPI_COMM_WORLD_LOCAL_RANK=${OMPI_COMM_WORLD_LOCAL_RANK}"
echo "[${HOSTNAME}] OMPI_COMM_WORLD_NODE_RANK=${OMPI_COMM_WORLD_NODE_RANK}"

export MACHINE_RANK=$((NODE_NUMBER-1))
echo "[${HOSTNAME}] MACHINE_RANK=$MACHINE_RANK"

accelerate launch \
    --multi_gpu \
    --mixed_precision "no" \
    --num_processes $NUM_PROCESSES \
    --num_machines $NUM_NODES \
    --same_network \
    --machine_rank $MACHINE_RANK \
    --main_process_ip $MASTER_ADDR \
    --main_process_port $MASTER_PORT \
    --rdzv_backend "static" \
    --dynamo_backend "no" \
    nlp_example.py
