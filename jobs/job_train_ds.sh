#!/bin/sh
#PBS -q rt_HF
#PBS -l select=1
#PBS -l walltime=01:00:00
#PBS -j oe
#PBS -k o

source /etc/profile.d/modules.sh

module load cuda/12.4
module load hpcx/2.20
module list

source $HOME/miniforge3/bin/activate test

export OMP_NUM_THREADS=1
export NUM_GPUS_PER_NODE=`nvidia-smi -L | wc -l`

export HOSTFILE="hostfile_${JOB_ID}"
#cat ${SGE_JOB_HOSTLIST} > ${HOSTFILE}
# NOTE slots = number of GPUs
cat ${SGE_JOB_HOSTLIST} | awk '{print $0, "slots=4"}' > ${HOSTFILE}
export MASTER_ADDR=`cat ${SGE_JOB_HOSTLIST} | head -n 1`
export MASTER_PORT=12345

export NCCL_DEBUG=DEBUG
export NCCL_SOCKET_IFNAME=eno
export TORCH_DISTRIBUTED_DEBUG=DETAIL
export LOGLEVEL=DEBUG

export NUM_NODES=$NHOSTS
export NUM_PROCESSES=$((${NUM_GPUS_PER_NODE}*${NUM_NODES}))

# Template
BASE_CONFIG_FILE=ds_config.yaml

export PATH_PREFIX=`echo ${BASE_CONFIG_FILE} | cut -d'.' -f1`
for ((i = 1 ; i <= $NUM_NODES ; i++ ))
do
    # Copy base config file
    NODE_CONFIG_FILE="${PATH_PREFIX}.${i}_${NUM_NODES}.yaml"
    # Delete old if it exists
    rm -f $NODE_CONFIG_FILE
    cp -f $BASE_CONFIG_FILE $NODE_CONFIG_FILE

    # Modify config file
    export DEEPSPEED_HOSTFILE="${PWD}/${HOSTFILE}"
    export MAIN_PROCESS_IP=${MASTER_ADDR}
    export MAIN_PROCESS_PORT=${MASTER_PORT}
    export NUM_MACHINES=${NUM_NODES}
    export NUM_PROCESSES=${NUM_PROCESSES}
    envsubst < ${BASE_CONFIG_FILE} > ${NODE_CONFIG_FILE}
    
    # Rank starts from 0
    sed -i "s/machine_rank: 0/machine_rank: $(( i-1 ))/g" ${NODE_CONFIG_FILE}
done

# Helper script will select the right config file for each node
mpirun -npernode 1 -hostfile $SGE_JOB_HOSTLIST train_ds.sh
