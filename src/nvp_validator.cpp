// Implementation: host-side NVP node reader (4-byte LE) for Walkman port.
// See FIX B1 in src/nvp_validator.h and gen_nvp_binary.sh comment block.
#include "nvp_validator.h"

#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <sys/stat.h>
#include <string>

static std::string node_path(const std::string& dir, int n) {
    char p[256];
    snprintf(p, sizeof p, "%s/%03d", dir.c_str(), n);
    return std::string(p);
}

int nvp_node_size(const std::string& dir, int n) {
    struct stat st;
    if (stat(node_path(dir, n).c_str(), &st) != 0) return -1;
    return (int)st.st_size;
}

uint32_t nvp_read_node_le4(const std::string& dir, int n, bool* ok) {
    if (ok) *ok = false;
    FILE* f = fopen(node_path(dir, n).c_str(), "rb");
    if (!f) return 0;
    unsigned char b[4] = {0, 0, 0, 0};
    size_t r = fread(b, 1, 4, f);
    fclose(f);
    if (r != 4) return 0;           // short read -> treat as 0 (size-checked elsewhere)
    if (ok) *ok = true;
    return (uint32_t)b[0]
         | ((uint32_t)b[1] << 8)
         | ((uint32_t)b[2] << 16)
         | ((uint32_t)b[3] << 24);
}

uint32_t nvp_read_node_le4(const std::string& dir, int n) {
    bool ok;
    uint32_t v = nvp_read_node_le4(dir, n, &ok);
    return ok ? v : 0xFFFFFFFFu;    // sentinel: never a valid NVP value
}

bool nvp_write_node4(const std::string& dir, int n, uint32_t v) {
    unsigned char b[4] = {
        (unsigned char)(v & 0xFF),
        (unsigned char)((v >> 8) & 0xFF),
        (unsigned char)((v >> 16) & 0xFF),
        (unsigned char)((v >> 24) & 0xFF),
    };
    FILE* f = fopen(node_path(dir, n).c_str(), "wb");
    if (!f) return false;
    bool ok = fwrite(b, 1, 4, f) == 4;
    fclose(f);
    return ok;
}

int nvp_count_nodes(const std::string& dir) {
    DIR* d = opendir(dir.c_str());
    if (!d) return -1;
    int c = 0;
    struct dirent* e;
    while ((e = readdir(d))) {
        const char* name = e->d_name;
        if (name[0] == '.') continue;
        if (strlen(name) == 3
            && name[0] >= '0' && name[0] <= '9'
            && name[1] >= '0' && name[1] <= '9'
            && name[2] >= '0' && name[2] <= '9')
            c++;
    }
    closedir(d);
    return c;
}

nvp_stats nvp_validate_dir(const std::string& dir) {
    nvp_stats s{};
    s.count = nvp_count_nodes(dir);
    s.four_byte = 0;
    s.nonzero = 0;
    for (int i = 0; i < 243; ++i) {
        int sz = nvp_node_size(dir, i);
        if (sz == 4) s.four_byte++;
        if (nvp_read_node_le4(dir, i) != 0) s.nonzero++;
    }
    return s;
}
