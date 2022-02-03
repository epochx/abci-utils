set -l script_dir (realpath (dirname (status -f)))

cat "$script_dir"/resource_types.txt | while read -l -a rline
    complete -f -c qrsh -s l -o l -a "$rline[1]=" -d "$rline[2]"
end

if test -e "$HOME/.groups"
    cat "$HOME/.groups" | while read -l -a gline
        complete -f -c qrsh -s g -o g -a "$gline[1]" -d "$gline[2]"
    end
else
    complete -f -c qrsh -s g -o g -a "$GROUPS"
end