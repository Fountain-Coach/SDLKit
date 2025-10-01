import Foundation
import SDLKit

@main
struct SDLKitSettingsCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else { return printUsage() }
        var key: String?
        var value: String?
        var it = args.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--key", "-k": key = it.next()
            case "--value", "-v": value = it.next()
            default: break
            }
        }
        switch cmd {
        case "get":
            guard let k = key else { return printUsage() }
            if let s = SettingsStore.getString(k) { print(s) } else { print("") }
        case "set":
            guard let k = key, let v = value else { return printUsage() }
            SettingsStore.setString(k, v)
            print("OK")
        case "set-bool":
            guard let k = key, let v = value else { return printUsage() }
            let b = ["1","true","yes","on"].contains(v.lowercased())
            SettingsStore.setBool(k, b)
            print("OK")
        default:
            printUsage()
        }
    }

    static func printUsage() {
        print("""
        Usage: sdlkit-settings <get|set|set-bool> --key KEY [--value VALUE]
        Examples:
          sdlkit-settings set --key render.backend.override --value metal
          sdlkit-settings set-bool --key vk.validation --value true
        """)
    }
}

