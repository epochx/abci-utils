set -l script_dir (realpath (dirname (status -f)))

cat "$script_dir"/resource_types.txt | while read -l -a rline
    complete -f -c qrsh -s r -o r -l resource -a "$rline[1]" -d "$rline[2]"
end
