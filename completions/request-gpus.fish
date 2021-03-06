set -l script_dir (realpath (dirname (status -f)))

cat "$script_dir"/resource_types.txt | while read -l -a rline
    complete -f -c request-gpus -s r -o r -l resource -a "$rline[1]" -d "$rline[2]"
end

if test -e "$HOME/.groups"
    cat "$HOME/.groups" | while read -l -a gline
        complete -f -c request-gpus -s g -o g -l group -a "$gline[1]" -d "$gline[2]"
    end
else
    complete -f -c request-gpus -s g -o g -l group -a "$GROUPS"
end