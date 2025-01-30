#!/bin/sh
#PBS -q rt_HF
#PBS -l select=1
#PBS -l walltime=01:00:00
#PBS -j oe
#PBS -k o

source /etc/profile.d/modules.sh

module load cuda/12.4
module load hpcx-debug/2.20 
module list

source $HOME/miniforge3/bin/activate test

cd ~/abci-utils/jobs

export OMP_NUM_THREADS=1
export NUM_GPUS_PER_NODE=`nvidia-smi -L | wc -l`

export HOSTFILE="hostfile_${PBS_JOBID}"
cat ${PBS_NODEFILE} > ${HOSTFILE}
export MASTER_ADDR=`cat ${PBS_NODEFILE} | head -n 1`
export MASTER_PORT=12345

export NCCL_DEBUG=DEBUG
export NCCL_SOCKET_IFNAME=bond0
export TORCH_DISTRIBUTED_DEBUG=DETAIL
export LOGLEVEL=DEBUG

# export TORCHELASTIC_ENABLE_FILE_TIMER=12345
# export TORCHELASTIC_HEALTH_CHECK_PORT=12345

export CUDA_LAUNCH_BLOCKING=1

echo "OMP_NUM_THREADS" $OMP_NUM_THREADS
echo "NUM_GPUS_PER_NODE" $NUM_GPUS_PER_NODE

echo "HOSTFILE" $HOSTFILE
echo "MASTER_ADDR" $MASTER_ADDR
echo "MASTER_PORT" $MASTER_PORT

echo "NCCL_DEBUG" $NCCL_DEBUG
echo "NCCL_SOCKET_IFNAME" $NCCL_SOCKET_IFNAME
echo "TORCH_DISTRIBUTED_DEBUG" $TORCH_DISTRIBUTED_DEBUG
echo "LOGLEVEL" $LOGLEVEL

export NUM_NODES=`cat ${PBS_NODEFILE} | wc -l`
export NUM_PROCESSES=$((${NUM_GPUS_PER_NODE}*${NUM_NODES}))

echo "NUM_NODES" $NUM_NODES
echo "NUM_PROCESSES" $NUM_PROCESSES


# Helper script will select the right config file for each node
mpirun -npernode 1 -hostfile $PBS_NODEFILE ./train_multi.sh 