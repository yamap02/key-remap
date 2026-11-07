#include "InstalledFilesGuard.hpp"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <unistd.h>

namespace fs = std::filesystem;
static void write(const fs::path& p, const char* text = "original") { std::ofstream(p) << text; }
int main() {
    char temp[] = "/tmp/rekey-guard.XXXXXX";
    const auto directory = fs::path(mkdtemp(temp));
    const auto app = directory / "app", agent = directory / "agent", core = directory / "core";
    write(app); write(agent); write(core);
    auto paths = std::array<std::string, 3>{app.string(), agent.string(), core.string()};
    {
        rekey::InstalledFilesGuard guard(paths, getuid(), directory);
        assert(guard.unchanged());
        fs::rename(app, directory / "old");
        write(app, "replacement");
        assert(!guard.unchanged());
        fs::remove(app); fs::rename(directory / "old", app);
        assert(!guard.unchanged()); // A replacement cannot be undone in this process.
    }
    {
        rekey::InstalledFilesGuard guard(paths, getuid(), directory);
        assert(guard.unchanged());
        write(agent, "modified-in-place");
        assert(!guard.unchanged());
    }
    {
        rekey::InstalledFilesGuard guard(paths, getuid(), directory);
        assert(guard.unchanged());
        fs::permissions(core, fs::perms::group_write, fs::perm_options::add);
        assert(!guard.unchanged());
    }
    {
        rekey::InstalledFilesGuard guard(paths, getuid(), directory);
        assert(!guard.unchanged()); // A writable file is never accepted at startup.
    }
    fs::permissions(core, fs::perms::group_write, fs::perm_options::remove);
    {
        rekey::InstalledFilesGuard guard(paths, getuid(), directory);
        assert(guard.unchanged());
        fs::remove(agent);
        assert(!guard.unchanged());
        write(agent);
        assert(!guard.unchanged());
    }
    {
        fs::remove(agent); fs::create_symlink(app, agent);
        rekey::InstalledFilesGuard guard(paths, getuid(), directory);
        assert(!guard.unchanged());
    }
    fs::remove(agent); write(agent);
    {
        rekey::InstalledFilesGuard guard(paths, getuid(), directory);
        assert(guard.unchanged());
        fs::permissions(directory, fs::perms::group_write, fs::perm_options::add);
        assert(!guard.unchanged());
    }
    fs::permissions(directory, fs::perms::group_write, fs::perm_options::remove);
    fs::remove_all(directory);
    std::cout << "PASS installed code replacement, mutation, permissions and latch\n";
}
