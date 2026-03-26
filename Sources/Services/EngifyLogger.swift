import Foundation

enum EngifyLogger {
    static func debug(_ message: @autoclosure () -> String) {
#if DEBUG
        print(message())
#endif
    }
}
