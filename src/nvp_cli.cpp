// Standalone CLI: nvp_validator --selftest | --validate <dir>
// Host-only (no Android HAL headers). Builds with clang++ -std=c++17.
#include "nvp_validator.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <sys/stat.h>

// Authoritative values extracted from gen_nvp_binary.sh — must match the
// property info table parsed from libizmproperties.so (offset 0x00cbd0).
static const Case kAuthoritative[] = {
    {   0, 1u,         "version"},
    {   7, 0x310000u,  "ro.product.model_id"},
    {  12, 0x3u,       "ro.product.destination (CEW)"},
    {  18, 0x31000000u,"_MODEL_ID_ NW-ZX507 CEW"},
    {  22, 0x00000103u,"shp destination CEW"},
    { 129, 1u,         "ro.safe_volume.enabled"},
    { 130, 0x50u,      "ro.safe_volume.default"},
    { 137, 1u,         "ro.effect.clear_phase.enabled"},
    { 138, 1u,         "ro.effect.dsee_ai.enabled"},
    { 139, 1u,         "ro.effect.dynamic_normalizer.enabled"},
    { 140, 1u,         "ro.effect.equalizer_10.enabled"},
    { 147, 1u,         "ro.effect.clear_audio_plus.enabled"},
    { 148, 1u,         "ro.nc_ambient.enabled"},
};

static void gen_nodes(const std::string& dir) {
    mkdir("build", 0755);
    mkdir(dir.c_str(), 0755);
    for (int i = 0; i < 243; ++i) nvp_write_node4(dir, i, 0);
    for (const auto& c : kAuthoritative) nvp_write_node4(dir, c.node, c.expected);
}

static int run_selftest() {
    std::string dir = "build/selftest_nvp";
    gen_nodes(dir);
    int fail = 0;
    int cnt = nvp_count_nodes(dir);
    if (cnt != 243) { printf("FAIL count=%d want 243\n", cnt); fail++; }
    else             { printf("ok   count=243\n"); }
    for (const auto& c : kAuthoritative) {
        int sz = nvp_node_size(dir, c.node);
        if (sz != 4) { printf("FAIL %03d size=%d\n", c.node, sz); fail++; continue; }
        uint32_t g = nvp_read_node_le4(dir, c.node);
        if (g != c.expected) {
            printf("FAIL %03d %s: got %08x want %08x\n", c.node, c.label, g, c.expected);
            fail++;
        } else {
            printf("ok   %03d=%08x (%s)\n", c.node, g, c.label);
        }
    }
    printf("\nselftest: %d failures\n", fail);
    return fail ? 1 : 0;
}

static int run_validate(const std::string& dir) {
    int fail = 0;
    int cnt = nvp_count_nodes(dir);
    if (cnt != 243) { printf("FAIL count=%d want 243\n", cnt); fail++; }
    else             { printf("ok   count=243\n"); }
    for (const auto& c : kAuthoritative) {
        int sz = nvp_node_size(dir, c.node);
        if (sz != 4) { printf("FAIL %03d size=%d\n", c.node, sz); fail++; continue; }
        uint32_t g = nvp_read_node_le4(dir, c.node);
        if (g != c.expected) {
            printf("FAIL %03d %s: got %08x want %08x\n", c.node, c.label, g, c.expected);
            fail++;
        } else {
            printf("ok   %03d=%08x (%s)\n", c.node, g, c.label);
        }
    }
    nvp_stats s = nvp_validate_dir(dir);
    printf("\nvalidate [%s]: count=%d 4byte=%d nonzero=%d failures=%d\n",
           dir.c_str(), s.count, s.four_byte, s.nonzero, fail);
    return fail ? 1 : 0;
}

int main(int argc, char** argv) {
    if (argc < 2 || argv[1] == std::string("--help") || argv[1] == std::string("-h")) {
        printf("usage: nvp_validator --selftest | --validate <dir>\n");
        return 2;
    }
    std::string arg = argv[1];
    if (arg == "--selftest")       return run_selftest();
    if (arg == "--validate") {
        if (argc < 3) { printf("usage: --validate <dir>\n"); return 2; }
        return run_validate(argv[2]);
    }
    printf("unknown arg: %s\n", arg.c_str());
    return 2;
}
