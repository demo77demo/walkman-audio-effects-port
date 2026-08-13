# Magisk module customization script
# Runs AFTER file extraction, BEFORE module is activated
# NVP data files are generated HERE (not at boot) for reliability

ui_print "- Setting up NVP emulator..."

# Set executable permissions for scripts
set_perm $MODPATH/nvp_emulator/gen_nvp_binary.sh 0 0 0755
set_perm $MODPATH/nvp_emulator/init_nvp.sh 0 0 0755
set_perm $MODPATH/nvp_emulator/nvp_fuse.sh 0 0 0755
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/post-fs-data.sh 0 0 0755
set_perm $MODPATH/recreate_symlinks.sh 0 0 0755

# Generate NVP data files NOW (during installation, not at boot)
ui_print "- Generating NVP data files..."
mkdir -p $MODPATH/nvp_emulator/nvp_data
sh $MODPATH/nvp_emulator/gen_nvp_binary.sh $MODPATH/nvp_emulator/nvp_data

# Verify
NODE0=$(cat $MODPATH/nvp_emulator/nvp_data/000 2>/dev/null | od -A n -t x1 | tr -d ' ')
NODE22=$(cat $MODPATH/nvp_emulator/nvp_data/022 2>/dev/null | od -A n -t x1 | tr -d ' ')
NODE138=$(cat $MODPATH/nvp_emulator/nvp_data/138 2>/dev/null | od -A n -t x1 | tr -d ' ')
ui_print "- NVP data: 000=$NODE0 022=$NODE22 138=$NODE138"

ui_print "- Module installation complete"
