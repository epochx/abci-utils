set -l script_dir (realpath (dirname (status -f)))

cat "$script_dir"/resource_types.txt | while read -l -a rline
    complete -f -c submit-job -s r -o r -l resource -a "$rline[1]" -d "$rline[2]"
end

if test -e "$HOME/.groups"
    cat "$HOME/.groups" | while read -l -a gline
        complete -f -c submit-job -s g -o g -l group -a "$gline[1]" -d "$gline[2]"
    end
else
    complete -f -c submit-job -s g -o g -l group -a "$GROUPS"
end

set -l preambles (ls $HOME/preambles/)
 
# set preamble
complete -f -c submit-job -s p -o p -l preamble -a "$preambles"

