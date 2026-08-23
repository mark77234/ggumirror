//
//  ButtonHitAreaTests.swift
//  ggumirrorTests
//
//  **보이는 만큼 눌린다.**
//
//  실기기에서 `저장`이 글자를 정확히 눌러야만 반응했다. 테두리와 여백은 보이는데
//  그 자리는 죽어 있었다. SwiftUI에서 **Button의 tap 영역은 label이 정한다** —
//  밖에 붙인 `.padding` · `.background` · `.frame`은 보이기만 하고 눌리지 않는다.
//  밖에서 `.contentShape`을 걸어도 마찬가지다.
//

import Testing
import Foundation
@testable import ggumirror

@Suite("버튼은 보이는 만큼 눌린다")
struct ButtonHitAreaTests {

    /// `Button(...)` 뒤에 겉모습 modifier가 붙은 자리를 전부 찾는다.
    private func offenders() throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "ggumirror")
        let chrome = ["padding", "background", "frame", "overlay"]
        var found: [String] = []

        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }

        for case let url as URL in files where url.pathExtension == "swift" {
            let lines = (try String(contentsOf: url, encoding: .utf8)).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let text = line.trimmingCharacters(in: .whitespaces)
                // 짧은 형태(`Button("저장") { … }`)만 위험하다.
                // `label:`이 있으면 겉모습이 label 안에 있다는 뜻이다.
                guard text.hasPrefix("Button("), !text.contains("label:") else { continue }
                for next in (index + 1)..<min(index + 8, lines.count) {
                    let modifier = lines[next].trimmingCharacters(in: .whitespaces)
                    guard modifier.hasPrefix(".") else { break }
                    if chrome.contains(where: { modifier.hasPrefix(".\($0)(") || modifier.hasPrefix(".\($0) {") }) {
                        found.append("\(url.lastPathComponent):\(index + 1)")
                        break
                    }
                }
            }
        }
        return found
    }

    @Test("겉모습이 Button 밖에 붙은 곳이 없다")
    func noChromeOutsideButtonLabel() throws {
        let found = try offenders()
        #expect(found.isEmpty, "글자만 눌리는 버튼이 남아 있다: \(found)")
    }

    @Test("공통 잉크 버튼은 label 안에서 모양을 만든다")
    func sharedButtonsShapeInsideTheLabel() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "ggumirror/Shared/InkButtons.swift")
        let source = codeWithoutComments(try String(contentsOf: root, encoding: .utf8))

        // 모양과 44pt가 label 안에 있다.
        #expect(source.contains("frame(minHeight: InkTapTarget.minimum)"))
        #expect(source.contains(".contentShape(.rect)"))
        #expect(InkTapTarget.minimum == 44)
        // 이중 이벤트로 때우지 않는다.
        #expect(!source.contains("onTapGesture"))
    }

    @Test("CTA를 onTapGesture로 만들지 않는다")
    func ctasAreRealButtons() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "ggumirror")
        var suspicious: [String] = []
        if let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in files where url.pathExtension == "swift" {
                let source = codeWithoutComments(
                    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                )
                if source.contains("onTapGesture") { suspicious.append(url.lastPathComponent) }
            }
        }
        // 남아도 되는 것: 화면 전체 탭(컨트롤 토글) · 키보드 닫기 층 · dim 배경.
        // **버튼처럼 보이는 것**에는 쓰지 않는다.
        #expect(Set(suspicious) == ["MirrorView.swift", "InkKeyboard.swift", "InkModal.swift"],
                "CTA에 onTapGesture를 썼을 수 있다: \(suspicious)")
    }
}
