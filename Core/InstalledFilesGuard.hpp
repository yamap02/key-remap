#pragma once
#include <array>
#include <filesystem>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <utility>

namespace rekey {
// The privileged process must not keep capturing after its installed code has
// been removed, replaced, made writable, or modified in place. Once a change
// is seen, only a new process can establish a new trusted snapshot.
class InstalledFilesGuard {
    struct Identity {
        dev_t device{};
        ino_t inode{};
        off_t size{};
        timespec modified{};
        timespec changed{};
    };
    std::array<std::string, 3> paths;
    std::array<Identity, 3> original{};
    uid_t owner;
    std::filesystem::path root;
    bool valid = true;

    bool trustedParents(const std::filesystem::path& file) const {
        auto parent = file.parent_path();
        while (!parent.empty()) {
            struct stat directory{};
            if (lstat(parent.c_str(), &directory) != 0 || !S_ISDIR(directory.st_mode) ||
                directory.st_uid != owner || (directory.st_mode & 022) != 0) return false;
            if (parent == root) return true;
            auto next = parent.parent_path();
            if (next == parent) break;
            parent = std::move(next);
        }
        return false;
    }
    bool read(size_t i, Identity& result) const {
        if (!trustedParents(paths[i])) return false;
        struct stat st{};
        if (lstat(paths[i].c_str(), &st) != 0 || !S_ISREG(st.st_mode) ||
            st.st_uid != owner || (st.st_mode & 022) != 0) return false;
        result = {st.st_dev, st.st_ino, st.st_size, st.st_mtimespec, st.st_ctimespec};
        return true;
    }
    static bool equal(const Identity& a, const Identity& b) {
        return a.device == b.device && a.inode == b.inode && a.size == b.size &&
            a.modified.tv_sec == b.modified.tv_sec && a.modified.tv_nsec == b.modified.tv_nsec &&
            a.changed.tv_sec == b.changed.tv_sec && a.changed.tv_nsec == b.changed.tv_nsec;
    }
public:
    InstalledFilesGuard(std::array<std::string, 3> files, uid_t expectedOwner, std::filesystem::path bundleRoot)
        : paths(std::move(files)), owner(expectedOwner), root(std::move(bundleRoot)) {
        for (size_t i = 0; i < paths.size(); ++i) if (!read(i, original[i])) valid = false;
    }
    bool unchanged() {
        if (!valid) return false;
        for (size_t i = 0; i < paths.size(); ++i) {
            Identity current;
            if (!read(i, current) || !equal(original[i], current)) { valid = false; break; }
        }
        return valid;
    }
};
}
