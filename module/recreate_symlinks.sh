#!/system/bin/sh
# Recreate symlinks that are lost when the module is zipped (zip stores them as
# empty/broken files). Run from post-fs-data.sh after module extraction.
# Format: <module-relative-path>|<absolute-target>
MODDIR=${0%/*}

SYMLINKS='system/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1|/system/bin/ld-2.25.so
system/lib/aarch64-linux-gnu/libc.so.6|/system/lib/aarch64-linux-gnu/libc-2.25.so
system/lib/aarch64-linux-gnu/libdl.so.2|/system/lib/aarch64-linux-gnu/libdl-2.25.so
system/lib/aarch64-linux-gnu/libfuse.so.2|/system/lib/aarch64-linux-gnu/libfuse.so.2.9.7
system/lib/aarch64-linux-gnu/libfuse.so|/system/lib/aarch64-linux-gnu/libfuse.so.2.9.7
system/lib/aarch64-linux-gnu/libl10n.so.7|/system/lib/aarch64-linux-gnu/libl10n.so.7.0
system/lib/aarch64-linux-gnu/libl10n.so|/system/lib/aarch64-linux-gnu/libl10n.so.7.0
system/lib/aarch64-linux-gnu/libnss_compat.so.2|/system/lib/aarch64-linux-gnu/libnss_compat-2.25.so
system/lib/aarch64-linux-gnu/libnss_files.so.2|/system/lib/aarch64-linux-gnu/libnss_files-2.25.so
system/lib/aarch64-linux-gnu/libpthread.so.0|/system/lib/aarch64-linux-gnu/libpthread-2.25.so
system/lib/aarch64-linux-gnu/librt.so.1|/system/lib/aarch64-linux-gnu/librt-2.25.so
system/lib/lib_wma10_dec.so|/system/lib/lib_wma10_dec_v2_arm12_elinux.so
system/lib64/lib_wma10_dec.so|/system/lib64/lib_wma10_dec_v2_arm12_elinux.so
system/priv-app/DefaultContainerService/lib/arm64/libdefcontainer_jni.so|/system/lib64/libdefcontainer_jni.so
system/vendor/lib/lib_aac_dec.so|/vendor/lib/lib_aac_dec_v2_arm12_elinux.so
system/vendor/lib/lib_aacplus_dec.so|/vendor/lib/lib_aacplus_dec_v2_arm11_elinux.so
system/vendor/lib/lib_flac_dec.so|/vendor/lib/lib_flac_dec_v2_arm11_elinux.so
system/vendor/lib/lib_mp3_dec.so|/vendor/lib/lib_mp3_dec_v2_arm12_elinux.so
system/vendor/lib/lib_nb_amr_dec.so|/vendor/lib/lib_nb_amr_dec_v2_arm9_elinux.so
system/vendor/lib/lib_oggvorbis_dec.so|/vendor/lib/lib_oggvorbis_dec_v2_arm11_elinux.so
system/vendor/lib/lib_wb_amr_dec.so|/vendor/lib/lib_wb_amr_dec_arm9_elinux.so
system/vendor/lib64/lib_aac_dec.so|/vendor/lib64/lib_aac_dec_v2_arm12_elinux.so
system/vendor/lib64/lib_aacplus_dec.so|/vendor/lib64/lib_aacplus_dec_v2_arm11_elinux.so
system/vendor/lib64/lib_flac_dec.so|/vendor/lib64/lib_flac_dec_v2_arm11_elinux.so
system/vendor/lib64/lib_mp3_dec.so|/vendor/lib64/lib_mp3_dec_v2_arm12_elinux.so
system/vendor/lib64/lib_nb_amr_dec.so|/vendor/lib64/lib_nb_amr_dec_v2_arm9_elinux.so
system/vendor/lib64/lib_oggvorbis_dec.so|/vendor/lib64/lib_oggvorbis_dec_v2_arm11_elinux.so
system/vendor/lib64/lib_wb_amr_dec.so|/vendor/lib64/lib_wb_amr_dec_arm9_elinux.so'

echo "$SYMLINKS" | while IFS='|' read -r link tgt; do
    [ -z "$link" ] && continue
    lpath="$MODDIR/$link"
    # remove broken/empty file from zip, then create symlink
    rm -f "$lpath" 2>/dev/null
    ln -sf "$tgt" "$lpath" 2>/dev/null
done
echo "$(date '+%Y-%m-%d %H:%M:%S') recreate_symlinks: done"
