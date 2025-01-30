#!/bin/sh
#PBS -q rt_HF
#PBS -l select=1
#PBS -l walltime=1:00:00
#PBS -j oe

source /etc/profile.d/modules.sh

module load cuda/12.4
module load hpcx/2.20 
module list

source $HOME/miniforge3/bin/activate test

export OMP_NUM_THREADS=1
export NUM_GPUS_PER_NODE=`nvidia-smi -L | wc -l`

train_single.sh