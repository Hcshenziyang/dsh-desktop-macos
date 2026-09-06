import Foundation

package func expandedUserPath(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

/// 把常见的命令行参数文本拆成 Process.arguments。
/// 支持单双引号与反斜杠，但不会执行 shell、管道、重定向或命令替换。
package func parseCommandArguments(_ input: String) -> [String]? {
    var arguments: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false
    var tokenStarted = false

    for character in input {
        if escaping {
            current.append(character)
            escaping = false
            tokenStarted = true
        } else if character == "\\" && quote != "'" {
            escaping = true
            tokenStarted = true
        } else if let activeQuote = quote {
            if character == activeQuote {
                quote = nil
            } else {
                current.append(character)
            }
            tokenStarted = true
        } else if character == "\"" || character == "'" {
            quote = character
            tokenStarted = true
        } else if character.isWhitespace {
            if tokenStarted {
                arguments.append(current)
                current = ""
                tokenStarted = false
            }
        } else {
            current.append(character)
            tokenStarted = true
        }
    }

    guard quote == nil, !escaping else { return nil }
    if tokenStarted { arguments.append(current) }
    return arguments
}
