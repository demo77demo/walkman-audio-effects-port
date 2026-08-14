// TDD test for nvp_validator — run AFTER building build/nvp_validator.
// Verifikuje: 4-byte LE parse, count, a authoritativní node hodnoty podle
// gen_nvp_binary.sh (libizmproperties.so property info table, offset 0x00cbd0).
//
// FIX B1: nvp_read "cmp w0,#4" -> 4 bytes; IzmPropertiesHelper LE getInt().
//
// Build (host):  clang++ -std=c++17 -O2 -Isrc \
//                -o build/test_nvp_validator tests/test_nvp_validator.cpp
// Run:           ./build/test_nvp_validator <nvp_data_dir>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <sys/stat.h>

#include "nvp_validator.h"

// Case defined in src/nvp_validator.h (shared with nvp_cli/nvp_validator.cpp)

// Authoritative values extracted from gen_nvp_binary.sh — these MUST match
// the property info table parsed from libizmproperties.so.
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

static int failures = 0;
static int checks  = 0;

static void check(bool ok, const char* msg) {
    checks++;
    if (!ok) { failures++; printf("FAIL: %s\n", msg); }
    else      { printf("ok:   %s\n", msg); }
}

static std::string fmt_node(int n) {
    char buf[8];
    snprintf(buf, sizeof buf, "%03d", n);
    return std::string(buf);
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("usage: %s <nvp_data_dir>\n", argv[0]);
        return 2;
    }
    std::string dir = argv[1];

    // 1) count=243, každý 4-byte
    int count = nvp_count_nodes(dir);
    check(count == 243, "exactly 243 nodes present");

    // 2) size check na reprezentativních
    for (int n : {0, 22, 138, 242}) {
        int sz = nvp_node_size(dir, n);
        char msg[64]; snprintf(msg, sizeof msg, "node %s is 4-byte", fmt_node(n).c_str());
        check(sz == 4, msg);
    }

    // 3) authoritativní hodnoty
    for (const auto& c : kAuthoritative) {
        uint32_t got = nvp_read_node_le4(dir, c.node);
        char msg[96]; snprintf(msg, sizeof msg, "node %03d=%08x (%s) == %08x",
                               c.node, got, c.label, c.expected);
        check(got == c.expected, msg);
    }

    printf("\n%d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
