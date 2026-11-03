// SHA-256 (para conferir os dados da BVH com os golden files, que guardam o hash dos Float32Array).
#pragma once
#include <cstdint>
#include <string>

namespace tdi {
std::string sha256hex(const void *data, size_t len);
}
