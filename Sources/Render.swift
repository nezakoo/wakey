import AppKit

// One line of wakey.sh output: "text | key=value key='quoted value'", nested with leading "--".
struct Line {
    let depth: Int
    let text: String
    let params: [String: String]
}

let separator = "---"

func parseLine(_ raw: String) -> Line {
    var body = Substring(raw)
    var depth = 0
    while body.hasPrefix("--") {
        depth += 1
        body = body.dropFirst(2)
    }
    guard let bar = body.range(of: " | ") else {
        return Line(depth: depth, text: String(body), params: [:])
    }
    return Line(depth: depth, text: String(body[..<bar.lowerBound]), params: parseParams(String(body[bar.upperBound...])))
}

func parseParams(_ s: String) -> [String: String] {
    var out: [String: String] = [:]
    var key = "", value = ""
    var inKey = true, quoted = false
    for c in s + " " {
        if inKey {
            if c == "=" { inKey = false } else if c != " " { key.append(c) }
        } else if c == "'" {
            quoted.toggle()
        } else if c == " " && !quoted {
            out[key] = value
            key = ""; value = ""; inKey = true
        } else {
            value.append(c)
        }
    }
    return out
}

private let symbolToken = try! NSRegularExpression(pattern: ":([a-z0-9.]+):")

// ":name:" tokens become SF Symbols; drawn in black so the caller can use the result as a template.
func styled(_ text: String, font: NSFont, color: NSColor = .black) -> NSAttributedString {
    let out = NSMutableAttributedString()
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    var last = text.startIndex
    for m in symbolToken.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        let whole = Range(m.range, in: text)!
        let name = String(text[Range(m.range(at: 1), in: text)!])
        let config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: name)?.withSymbolConfiguration(config) else { continue }
        out.append(NSAttributedString(string: String(text[last..<whole.lowerBound]), attributes: attrs))
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - image.size.height) / 2, width: image.size.width, height: image.size.height)
        out.append(NSAttributedString(attachment: attachment))
        last = whole.upperBound
    }
    out.append(NSAttributedString(string: String(text[last...]), attributes: attrs))
    return out
}

func titleImage(_ line: Line) -> NSImage {
    var text = line.text
    if let symbol = line.params["sfimage"] { text = ":\(symbol):" + (text.isEmpty ? "" : " " + text) }
    let attr = styled(text, font: .menuBarFont(ofSize: 0))
    let size = attr.size()
    let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { _ in
        attr.draw(at: .zero)
        return true
    }
    image.isTemplate = true
    return image
}
