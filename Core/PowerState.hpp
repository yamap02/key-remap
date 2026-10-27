#pragma once

namespace rekey {
// Main-loop owned: display and system notifications may arrive in either order.
class PowerState {
    bool display_asleep_ = false, system_asleep_ = false;
public:
    bool suspended() const { return display_asleep_ || system_asleep_; }
    bool display(bool asleep) {
        if(display_asleep_ == asleep)return false;
        display_asleep_ = asleep;
        return true;
    }
    bool system(bool asleep) {
        if(system_asleep_ == asleep)return false;
        system_asleep_ = asleep;
        return true;
    }
};
}
