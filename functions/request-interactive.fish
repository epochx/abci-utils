function request-interactive -d "Request an interactive session"
   # set group
    set -l options (fish_opt --short=g --long=group --required-val)
    
    # set resource
    set options $options (fish_opt --short=r --long=resource --required-val)

    # set num_resources
    set options $options (fish_opt --short n --long=nresources --optional-val)

    # set time
    # set options $options (fish_opt --short=t --long=time --optional-val)

    argparse $options -- $argv

    if not set -q _flag_nresources
        set _flag_nresources 1
    end

    # if not set -q _flag_time
    #     set _flag_time "12:00:00"
    # end

    echo "Running qsub -I -P $_flag_group -q $_flag_resource -l select=$_flag_nresources" 
    # walltime=$_flag_time"

    qsub -I -P $_flag_group -q $_flag_resource -l select=$_flag_nresources
    # walltime=$_flag_time

end