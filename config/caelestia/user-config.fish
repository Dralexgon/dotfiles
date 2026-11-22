# Switch rice: rice <name> | next (the files in config/caelestia/rices, see "Rices" in hypr-user.lua)
function rice
    hyprctl eval "set_rice('$argv[1]')"
end
