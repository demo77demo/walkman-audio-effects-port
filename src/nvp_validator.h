// Host-side NVP node reader for Walkman audio-effects port.
// Reads 4-byte LITTLE-ENDIAN node files (format libizmproperties.so expects).
//
// FIX B1 (verified live OP3 2026-07-16):
//   nvp_read (libizmproperties.so): "cmp w0,#4"  -> expects exactly 4 bytes
//   IzmPropertiesHelper.fromByteToInt: ByteBuffer.wrap(b).order(LE).getInt()
// Property info table base offset in libizmproperties.so: 0x00cbd0.
#pragma once
#include <cstdint>
#include <string>

struct Case { int node; uint32_t expected; const char* label; };

struct nvp_stats { int count; int four_byte; int nonzero; };

// Read node `n` (0..242) as little-endian uint32 from `dir/<NNN>`.
// Returns decoded value; sets *ok=false on I/O/size error.
uint32_t nvp_read_node_le4(const std::string& dir, int n, bool* ok);
// Convenience overload: returns 0xFFFFFFFFu sentinel on error (never valid).
uint32_t nvp_read_node_le4(const std::string& dir, int n);

// Write node `n` as 4-byte LE (replicates gen_nvp_binary.sh write_node).
bool nvp_write_node4(const std::string& dir, int n, uint32_t v);

// File size for node `n`; -1 if missing.
int nvp_node_size(const std::string& dir, int n);

// Count 3-digit-padded node files in `dir`.
int nvp_count_nodes(const std::string& dir);

// Aggregate stats: count | 4-byte files | nonzero values.
nvp_stats nvp_validate_dir(const std::string& dir);
