import Foundation
func L(_ key: String) -> String {
    let language = UserDefaults.standard.string(forKey: "language") ?? "ja"
    let bundle = language == "system" ? Bundle.main : Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main
    return bundle.localizedString(forKey: key, value: key, table: nil)
}
