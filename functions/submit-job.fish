function submit-job -d "Run a command as a job using qsub"
   # set group
    set -l options (fish_opt -s g -l group --required-val)
    
    # set resource
    set options $options (fish_opt -s r -l resource --required-val)

    # set resource quantity
    set options $options (fish_opt -s q -l quantity --required-val)

    # set time
    set options $options (fish_opt -s t -l time --required-val)

    # set preamble
    set options $options (fish_opt -s p -l preamble --required-val)

    # set command
    set options $options (fish_opt -s c -l command --required-val)

    # set name
    set options $options (fish_opt -s n -l name --required-val)

    argparse $options -- $argv

    set -l path (pwd)
    set -l filename (mktemp)
    
    echo "#!/bin/bash" > $filename 
    echo "#\$ -l $_flag_resource=$_flag_quantity" >> $filename
    echo "#\$ -l h_rt=$_flag_time" >> $filename 
    echo "#\$ -j y" >> $filename 
    echo "#\$ -cwd" >> $filename 
    echo "#\$ -m ea" >> $filename  
    echo "" >> $filename
    cat "$HOME/preambles/$_flag_preamble" >> $filename
    echo "cd $path" >> $filename  
    echo "$_flag_command" >> $filename

    echo "Temp script containing command available at $filename"
       
    echo "Running command: qsub -g $_flag_group -l $_flag_resource=$_flag_quantity -l h_rt=$_flag_time -N $_flag_name $filename"
      
    qsub -g $_flag_group -l $_flag_resource=$_flag_quantity -l h_rt=$_flag_time -N $_flag_name $filename
    
end


