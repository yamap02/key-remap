import Foundation
public enum KeyCatalog {
    public static let usages: [String: UInt32] = {
        var v: [String: UInt32] = [:]
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() { v[String(c)] = UInt32(i + 4) }
        for (i, c) in "1234567890".enumerated() { v[String(c)] = UInt32(i + 30) }
        let standard = ["return_or_enter", "escape", "delete_or_backspace", "tab", "spacebar", "hyphen", "equal_sign", "open_bracket", "close_bracket", "backslash", "non_us_pound", "semicolon", "quote", "grave_accent_and_tilde", "comma", "period", "slash", "caps_lock"]
        for (i, s) in standard.enumerated() { v[s] = UInt32(i + 40) }
        for i in 1...12 { v["f\(i)"] = UInt32(i + 57) }
        for (i, s) in ["print_screen", "scroll_lock", "pause", "insert", "home", "page_up", "delete_forward", "end", "page_down", "right_arrow", "left_arrow", "down_arrow", "up_arrow", "keypad_num_lock", "keypad_slash", "keypad_asterisk", "keypad_hyphen", "keypad_plus", "keypad_enter", "keypad_1", "keypad_2", "keypad_3", "keypad_4", "keypad_5", "keypad_6", "keypad_7", "keypad_8", "keypad_9", "keypad_0", "keypad_period", "non_us_backslash", "application", "power", "keypad_equal_sign"].enumerated() { v[s] = UInt32(i + 70) }
        for i in 13...24 { v["f\(i)"] = UInt32(i + 91) }
        v["international1"] = 135; v["japanese_kana"] = 144; v["japanese_eisuu"] = 145
        for (i, s) in ["left_control", "left_shift", "left_option", "left_command", "right_control", "right_shift", "right_option", "right_command"].enumerated() { v[s] = UInt32(i + 224) }
        // Consumer-page identifiers are encoded with page in the upper 16 bits.
        v["mute"] = 0xC00E2; v["volume_increment"] = 0xC00E9; v["volume_decrement"] = 0xC00EA
        v["play_or_pause"] = 0xC00CD; v["fastforward"] = 0xC00B3; v["rewind"] = 0xC00B4
        v["display_brightness_increment"] = 0xC006F; v["display_brightness_decrement"] = 0xC0070
        v["mission_control"] = 0xFF010010; v["launchpad"] = 0xFF010004; v["spotlight"] = 0xFF010001
        v["illumination_decrement"] = 0xFF0009; v["illumination_increment"] = 0xFF0008; v["fn"] = 0xFF0003
        return v
    }()
    public static let names = usages.keys.sorted()

    public enum Category: String, CaseIterable, Identifiable, Sendable {
        case letters, numbers, symbols, modifiers, editing, navigation, function, keypad, japanese, media, system

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .letters: "英字"
            case .numbers: "数字"
            case .symbols: "記号"
            case .modifiers: "修飾キー"
            case .editing: "入力・編集"
            case .navigation: "矢印・移動"
            case .function: "ファンクションキー"
            case .keypad: "テンキー"
            case .japanese: "日本語・国際キー"
            case .media: "メディア・明るさ"
            case .system: "システム"
            }
        }

        /// Keyboard order within each group, rather than lexicographic order (F1, F10, F11…).
        public var keys: [String] {
            switch self {
            case .letters: "abcdefghijklmnopqrstuvwxyz".map(String.init)
            case .numbers: "1234567890".map(String.init)
            case .symbols: ["hyphen", "equal_sign", "open_bracket", "close_bracket", "backslash", "semicolon", "quote", "grave_accent_and_tilde", "comma", "period", "slash"]
            case .modifiers: ["left_command", "right_command", "left_control", "right_control", "left_option", "right_option", "left_shift", "right_shift", "caps_lock", "fn"]
            case .editing: ["return_or_enter", "escape", "delete_or_backspace", "delete_forward", "tab", "spacebar", "insert"]
            case .navigation: ["up_arrow", "down_arrow", "left_arrow", "right_arrow", "home", "end", "page_up", "page_down"]
            case .function: (1...24).map { "f\($0)" }
            case .keypad: ["keypad_num_lock"] + (0...9).map { "keypad_\($0)" } + ["keypad_period", "keypad_plus", "keypad_hyphen", "keypad_asterisk", "keypad_slash", "keypad_equal_sign", "keypad_enter"]
            case .japanese: ["japanese_eisuu", "japanese_kana", "international1", "non_us_pound", "non_us_backslash"]
            case .media: ["mute", "volume_decrement", "volume_increment", "play_or_pause", "rewind", "fastforward", "display_brightness_decrement", "display_brightness_increment", "illumination_decrement", "illumination_increment"]
            case .system: ["mission_control", "launchpad", "spotlight", "print_screen", "scroll_lock", "pause", "application", "power"]
            }
        }
    }
    public static func name(page: UInt32, usage: UInt32) -> String {
        let code = page == 7 ? usage : (page << 16) | usage
        return usages.first(where: { $0.value == code })?.key ?? String(format: "0x%02X:0x%02X", page, usage)
    }
    public static func label(_ name: String) -> String {
        let labels = ["caps_lock": "⇪ Caps Lock", "left_control": "⌃ Left Control", "left_shift": "⇧ Left Shift", "left_option": "⌥ Left Option", "left_command": "⌘ Left Command", "right_control": "⌃ Right Control", "right_shift": "⇧ Right Shift", "right_option": "⌥ Right Option", "right_command": "⌘ Right Command", "spacebar": "Space", "return_or_enter": "↩ Return", "escape": "⎋ Escape", "delete_or_backspace": "⌫ Delete", "tab": "⇥ Tab", "japanese_eisuu": "英数", "japanese_kana": "かな", "left_arrow": "←", "right_arrow": "→", "up_arrow": "↑", "down_arrow": "↓"]
        return labels[name] ?? (name.count == 1 ? name.uppercased() : name.replacingOccurrences(of: "_", with: " ").capitalized)
    }
    public static let macKeyCodes: [UInt16: String] = [0:"a",1:"s",2:"d",3:"f",4:"h",5:"g",6:"z",7:"x",8:"c",9:"v",11:"b",12:"q",13:"w",14:"e",15:"r",16:"y",17:"t",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"equal_sign",25:"9",26:"7",27:"hyphen",28:"8",29:"0",30:"close_bracket",31:"o",32:"u",33:"open_bracket",34:"i",35:"p",36:"return_or_enter",37:"l",38:"j",39:"quote",40:"k",41:"semicolon",42:"backslash",43:"comma",44:"slash",45:"n",46:"m",47:"period",48:"tab",49:"spacebar",50:"grave_accent_and_tilde",51:"delete_or_backspace",53:"escape",54:"right_command",55:"left_command",56:"left_shift",57:"caps_lock",58:"left_option",59:"left_control",60:"right_shift",61:"right_option",62:"right_control",96:"f5",97:"f6",98:"f7",99:"f3",100:"f8",101:"f9",102:"japanese_eisuu",103:"f11",104:"japanese_kana",109:"f10",111:"f12",115:"home",116:"page_up",117:"delete_forward",118:"f4",119:"end",120:"f2",121:"page_down",122:"f1",123:"left_arrow",124:"right_arrow",125:"down_arrow",126:"up_arrow"]
}
