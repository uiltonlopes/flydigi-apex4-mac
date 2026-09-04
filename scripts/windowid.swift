import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w["kCGWindowOwnerName"] as? String) == (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Space Station") && (w["kCGWindowLayer"] as? Int) == 0 {
    if let b = w["kCGWindowBounds"] as? [String: Any], let h = b["Height"] as? Double, h > 300, let n = w["kCGWindowNumber"] { print(n); break }
}
