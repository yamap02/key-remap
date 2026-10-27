#include "Engine.hpp"
#include <iostream>

// Offline diagnostic: never opens a device or sends operating-system input.
int main() {
    auto config = rekey::JSON::parse(R"({
        "schema_version": 1,
        "global": {"thresholds_ms": {"alone": 200, "held_down": 500, "simultaneous": 50}},
        "profiles": [{"name": "Default", "selected": true,
            "simple": [{"from": {"key": "international2"},
                        "to": [{"key": "return_or_enter"}]}],
            "rules": [], "layers": [], "devices": []}]
    })");
    auto make = [&] { return rekey::Engine(rekey::Program::compile(config, {})); };
    auto is_return = [](const rekey::Outputs& output, bool down) {
        return output.size == 1 && output.values[0].key == 40 &&
               output.values[0].down == down;
    };

    auto idle = make();
    size_t idle_events = 0;
    for (uint64_t t = 0; t <= 60000; t += 5) idle_events += idle.tick(t).size;

    auto missing_up = make();
    auto down = missing_up.process({136, true, 1});
    size_t timer_events = 0;
    for (uint64_t t = 5; t <= 60000; t += 5) timer_events += missing_up.tick(t).size;
    auto forced_up = missing_up.release_all(60001);

    auto normal = make();
    auto normal_down = normal.process({136, true, 1});
    auto normal_up = normal.process({136, false, 2});
    auto duplicate = make();
    auto first = duplicate.process({136, true, 1});
    auto again = duplicate.process({136, true, 2});
    auto last = duplicate.process({136, false, 3});

    bool ok = idle_events == 0 && is_return(down, true) && timer_events == 0 &&
              is_return(forced_up, false) && is_return(normal_down, true) &&
              is_return(normal_up, false) && is_return(first, true) &&
              again.size == 0 && is_return(last, false);
    std::cout << "idle simulated 60s: " << idle_events << " events\n"
              << "missing up: Return down=" << down.size
              << ", simulated 60s timer events=" << timer_events
              << ", release_all Return up=" << forced_up.size << '\n'
              << "normal down/up and duplicate down: " << (ok ? "PASS" : "FAIL") << '\n';
    return ok ? 0 : 1;
}
