set -l script_dir (realpath (dirname (status -f)))

cat "$script_dir"/resource_types.txt | while read -l -a rline
    complete -f --command qsub -s q -o q -a "$rline[1]" -d "$rline[2]"
end

if test -e "$HOME/.groups"
    cat "$HOME/.groups" | while read -l -a gline
        complete -f -c qsub -s P -o P -a "$gline[1]" -d "$gline[2]"
    end
else
    complete -f -c qsub -s P -o P -a "$GROUPS"
end

complete -f -c qsub -s m -o m -a "n" -d "Specify not to send emails"
complete -f -c qsub -s m -o m -a "a" -d "Mail is sent when job is aborted"
complete -f -c qsub -s m -o m -a "b" -d "Mail is sent when job is started"
complete -f -c qsub -s m -o m -a "e" -d "Mail is sent when job is finished"
