set -l script_dir (realpath (dirname (status -f)))

cat "$script_dir"/resource_types.txt | while read -l -a rline
    complete -f -c qsub -s r -o r -l resource -a "$rline[1]" -d "$rline[2]"
end

if test -e "$script_dir/groups.txt"
    cat "$script_dir"/groups.txt | while read -l -a gline
        complete -f -c qsub -s g -o g -l group -a "$gline[1]" -d "$gline[2]"
    end
else
    complete -f -c qsub -s g -o g -l group -a "$GROUPS"
end