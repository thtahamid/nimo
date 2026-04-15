import Foundation
import os

enum NimoLogger {
    static let subsystem = "com.nimo.installer"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let installer = Logger(subsystem: subsystem, category: "installer")
    static let detector = Logger(subsystem: subsystem, category: "detector")
}
