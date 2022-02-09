# ABCI Utils (for fish)

Utils that are useful for abci, translated to fish shell (note that this is complementary to the [ABCI docs](https://docs.abci.ai/en/01/))

## Installation

ABCI does not natively support a shell other than bash or zsh, so we suggest you install fish using conda. For example:

```bash
conda create default python=3.8
conda activate default 
conda install fish
```

Then, you can load `fish` at the end of your `~/.profile` file, which could look as follows (assuming that you used miniconda and installed it in your home folder).

```bash
if [ -f ~/.bashrc ]; then
        . ~/.bashrc
fi

conda activate default
# path to your shell
export SHELL=$HOME/miniconda3/envs/default/bin/fish
[[ $- == *i*  ]] && exec $SHELL -l || :
```
This enables you to `sftp` into ABCI with no problems, and also to execute bash or sh scripts using the syntax `bash /path/to/script.sh` (this is possible because the `~/.profile` file is only parsed when starting a new login interactive session).

To install these `abci-utils` simply run `bash setup.sh`, which will add symlinks to the fish `functions` and `complete` folders, as well as append some content to the `config.fish` file so that the functions (and their tab completions) described below are auto-loaded and available everywhere.

## Configuration

First, create the following file `~/.groups` and add the following contents:

```bash
<group_id> <group_name>
...
```
Where `<group_id>` is the unique ID for a group your user belongs to, and `<group_name>` is an alias or nickname you wish to give to the group. Please keep in mind that **names can only contain letters, numbers and underscores**. Though creating this file is not necessary, it will improve the completions offered by fish when using the commands below.

Also, create the folder `~/preambles` and add your preamble files to it. Each preamble file is used to declare initial configurations for when using the `submit-job` command. For example, you might create a file called "cuda10" with the following contents:

```bash
source /etc/profile.d/modules.sh

module load cuda/10.1/10.1.243
module load cudnn/7.6/7.6.5
module load nccl/2.6/2.6.4-1
module load gcc/7.4.0
module load openmpi

export CUDA_HOME=/apps/cuda/10.1.243
export MKL_SERVICE_FORCE_INTEL=GNU
export MKL_THREADING_LAYER=1
```
Once created, a preamble named after the file (in this case, "cuda10") will be available in the auto-completions when you use the `submit-job` command.

## Features

### 1. The group variables

An environment variable named `$GROUPS` is created automatically upon login, containing the IDs of the groups your user belongs to, which are obtained from the output of `check_point`. Additionally, if you have created and populated the file `~/groups`, a global variable named after each group will be created, each one containing the ID of the respective group. This is useful for accessing storage folders for each group in an easy manner. Simply type `cd /groups/$<group_name>`.

### 2. Integration with the `module` command

We have added ad-hoc integration for `fish` with the the `module` command, which was not provided by ABCI. You can test this integration by typing `module` and hitting tab.

### 3. Launching interactive sessions with `request-gpus`

We have added a new command for requesting interactive nodes, as follows.
```bash
request-gpus -g <group> -r <resource> -t <time>
```
This will attempt to start an interactive session using `qrsh` for the specified time, which should be in the format of H:MM:SS.  

### 4. Executing Jobs using `submit-job`

A shortcut command to just run a regular script as a job with the given configuration. Usage is as follows (all parameters are required).

```bash
submit-job -g <group> -r <resource> -q <quantity> -t <time> -p <preamble> -n <name> -c "command/to/execute"
```
This command will create a temporary file where the contents of your selected preamble and command will be placed. A header for this file is created based on your provided `qsub` parameters, and this script then is passed as an argument to the `qsub` command to run as a batch job with the provided parameters. By default, the standard output and standard error are merged together, and this is streamed to a file in the same folder where you launched the command, following the naming convention `<name>.o<job-id>`. 

### 5. Deleting Jobs with `delete-job`

A better interface for the the `qdel` command, with fish completions. Use as follows:

```bash
delete-job -j <job>
```

Where `<job>` is the job-id provided by ABCI. 

### 6. Checking node availability with `avail-node-count`

```bash
$ avail-node-count
73
```
The `avail-node-count` functions prints the amount of available nodes (rt_F's - 4 V100 16GB GPUs) on the cluster.

### 5. Better Completions for default commands

I have added better completions to the following ABCI commands:
- `qrsh`: completions for the `-g <group>` and `-l <resource>` options.
- `qsub`: completions for the `-g <group>` and `-l <resource>` options.
- `qdel`: automatically searches for running jobs and autocompletes with their ids.


## Important Tips (that they don't tell you)

1. If you are saving checkpoints when running a job, make sure to run a `watch ls -lah` (in tmux) in that directory. Sometimes, if you don't do this the checkpoint may take forever to finish saving (presumably being put as a lower priority by the system) and you will end up wasting a lot of points (speaking from experience). 

## Useful Links
- https://cstmize.hatenablog.jp/entry/2019/04/18/ABCI%E3%82%B7%E3%82%B9%E3%83%86%E3%83%A0%E3%81%AE%E4%BD%BF%E3%81%84%E6%96%B9

- [Enviroment Modules](http://modules.sourceforge.net/) [On Github](https://github.com/cea-hpc/modules/tree/d94e637a6a9902b59fb19d6067fb16522d220792)

-