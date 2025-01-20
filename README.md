# ABCI 3.0 Utils (for fish)

Utils that are useful for abci, translated to fish shell (complementary to [ABCI docs](https://docs.abci.ai/v3/en))

## Installation

As of January 2025, ABCI 3.0 does not natively support a shell other than bash, so we suggest you install fish using mamba/conda, or linuxbrew. Please use at least version `3.7.1`, as currently we do not know if older version are also supported. 

If you decide to use `conda` the below command is an example of how to install.
```bash
conda create -n default python=3.10
conda activate default 
conda install fish=3.7.1
```

ABCI 3.0 run Red Hat on the login nodes, so when using the conda installation mode, you can load `fish` at the end of your `~/.profile` file as follows, because this file is only parsed when starting a new login interactive session.

```bash

# optionally, run the contents of .bashrc if exists
if [ -f ~/.bashrc ]; then
        . ~/.bashrc
fi

# discover CONDA install path from env var
CONDA_PATH=$(echo $CONDA_EXE | sed 's\/bin/conda\\g')

# add binaries from the `default` conda env to PATH
export PATH="$CONDA_PATH/envs/default/bin:$PATH"

# change shell
export SHELL=$CONDA_PATH/envs/default/bin/fish
[[ $- == *i*  ]] && exec $SHELL -l || :
```
This enables you to do things like `sftp` into ABCI with no problems, and also to execute bash or sh scripts using the syntax `bash /path/to/script.sh`. 

Finally, to install `abci-utils` simply run `bash setup.sh`. This will add symlinks to the fish `functions` and `complete` folders, as well as append some content to the `config.fish` file so that the functions (and their tab completions) described below are auto-loaded and available everywhere.

## Configuration

First, create the following file `~/.groups` and add the following contents:

```bash
<group_id> <group_name>
...
```
Where `<group_id>` is the unique ID for a group your user belongs to, and `<group_name>` is an alias or nickname you wish to give to the group. Please keep in mind that **names can only contain letters, numbers and underscores**. Though creating this file is not necessary, it will improve the completions offered by fish when using the commands below.

<!-- Also, create the folder `~/preambles` and add your preamble files to it. Each preamble file is used to declare initial configurations for when using the `submit-job` command. For example, you might create a file called "cuda10" with the following contents:

```bash
source /etc/profile.d/modules.sh

module load cuda/10.1/10.1.243
module load cudnn/7.6/7.6.5
```
Once created, a preamble named after the file (in this case, "cuda10") will be available in the auto-completions when you use the `submit-job` command. -->

## Features

### 1. The group variables

An environment variable named `$GROUPS` is created automatically upon login, containing the IDs of the groups your user belongs to, which are obtained from the output of `check_point`. Additionally, if you have created and populated the file `~/groups`, a global variable named after each group will be created, each one containing the ID of the respective group. This is useful for accessing storage folders for each group in an easy manner. Simply type `cd /groups/$<group_name>`.

### 2. Integration with the `module` command

We have added ad-hoc integration for `fish` with the the `module` command. This was not originally provided by ABCI, and our integration is not guaranteed to work in every case. You can test this integration by typing `module` and hitting tab.

### 3. Launching interactive sessions with `request-interactive`

We have added a new command for requesting interactive sessions, as follows.
```bash
request-interactive -g <group> -r <resource> -n <nresources>
```
This will attempt to start an interactive session using the `qsub -I`. The parameter -n is optional, and `nresources` is set to 1 as default.

<!-- ### 4. Executing Jobs using `submit-job`

A shortcut command to just run a regular script as a job with the given configuration. Usage is as follows (all parameters are required).

```bash
submit-job -g <group> -r <resource> -q <quantity> -t <time> -p <preamble> -n <name> -c "command/to/execute"
```
This command will create a temporary file where the contents of your selected preamble and command will be placed. A header for this file is created based on your provided `qsub` parameters, and this script then is passed as an argument to the `qsub` command to run as a batch job with the provided parameters. By default, the standard output and standard error are merged together, and this is streamed to a file in the same folder where you launched the command, following the naming convention `<name>.o<job-id>`.  -->

### 4. Deleting Jobs with `delete-job`

A slightly better interface for the `qdel` command, with fish completions. Use as follows:

```bash
delete-job -j <job>
```

Where `<job>` is the job-id of your batch jobs, as provided by ABCI. 

<!-- ### 5. Checking node availability with `avail-node-count`

```bash
$ avail-node-count
73
```
The `avail-node-count` functions prints the amount of available nodes (rt_F's - 4 V100 16GB GPUs) on the cluster. -->

### 5. Better Completions for default commands

These tools add better completions to the following ABCI commands:
- `qsub`: completions for the `-g <group>`, `-q <resource>` and mailing options.
- `qdel`: prevents paths for being auto-completed, and automatically searches for running jobs, suggesting job ids for autocompletions.


## Important Tips

1. If you are saving checkpoints when running a job, make sure to run a `watch ls -lah` (in tmux) in that directory. Sometimes, if you don't do this the checkpoint may take forever to finish saving (presumably being put as a lower priority by the system) and you will end up wasting a lot of points (speaking from experience). 

## Useful Links

- [Enviroment Modules](http://modules.sourceforge.net/) [On Github](https://github.com/envmodules/modules)
