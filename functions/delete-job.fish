function delete-job -d "Delete a running job using qsub"
    set options $options (fish_opt -s j -l job --required-val)
    argparse $options -- $argv
    echo "Running qdel $_flag_job"
    qdel "$_flag_job"
end