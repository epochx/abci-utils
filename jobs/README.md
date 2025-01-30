# Running jobs on ABCI 3.0

## Findings

- It seems both rt_HG and rt_HF job requests have SSH access from the login node enabled by default. In order to find out which node you were assigned try `qstat -f | grep host`. Then simply do `ssh <host>`.
- By default, jobs seem to be lazy-flushing to stdou and sterr, with the job log file(s) showing up only after the job has finished. Writing content to files also comes with a massive delay, at least from python. For the former issue, I have been able to go around the problem by appending `#PBS -k o` to the batch job header [source](https://stackoverflow.com/questions/29701648/check-real-time-output-after-qsub-a-job-on-cluster). For the latter, so far things are beter by adding a `file.flush()` statement.
- There are now larger differences in terms of operating system between the login nodes (Red Hat) and the compute nodes (Rocky Linux). This means:
    - Fonts available OS-wide are now different (check `/usr/share/fonts` for details) 
    - I'm currently experiencing garbled input to the terminal inside interactive sessions with several key presses (specifically, up/down, left/right arrows) as well as with mouse clicks. A quick check to the output of `localectl` in the compute nodes shows:
    ```bash
    System Locale: LANG=en_US.UTF-8
    VC Keymap: (unset)
    X11 Layout: (unset)  
    ```
    Versus the login nodes, where everything is set:
    ```bash
    System Locale: LANG=en_US.UTF-8
    VC Keymap: jp
    X11 Layout: jp
    ```
## Multi-node jobs with pytorch, CUDA and accelerate

I have updated the helper scripts developed for ABCI 2.0 to work (at least partially). The key changes introduced were the following:
- The old environment variable `JOB_ID` has been replaced with `PBS_JOBID`
- The old environment variable `SGE_JOB_HOSTLIST` has been replaced with `PBS_NODEFILE`
- The variable `NHOSTS` does not seem to exist anymore. Using `cat ${PBS_NODEFILE} | wc -l` as a replacement for now.
- SSH access to nodes running jobs is now available by default, so job configuration parameters `#$ -l USE_SSH=1` and `#$ -v SSH_PORT=2299` are no longer needed.
- Added the `#PBS -k o` parameter for real-time flushing to stdout and stderr.
- Interface names changed a bit so for NCCL to work properly please set `export NCCL_SOCKET_IFNAME=bond0`.

Tested run alternatives:
 - [x] Multi-gpu training on a single node via mpi + accelerate
 - [x] Multi-gpu training on a multiple nodes via mpi + accelerate (tested with 2 nodes)
 - [] Multi-gpu training on a multiple nodes via mpi + accelerate + deepspeed

To test that things are working correctly I've used a example script from HuggingFace accelerate. First prepare the environment as follows.
```bash
wget "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
bash Miniforge3-$(uname)-$(uname -m).sh
conda create test python=3.12
conda activate test
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl
pip install transformers accelerate evaluate scikit-learn
```
Then, execute the job.
```bash
qsub -P <group> -N test job_train_multi.sh
```
