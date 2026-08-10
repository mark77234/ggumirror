//
//  MirrorFonts.swift
//  ggumirror
//
//  번들에 들어 있는 손글씨 폰트 등록과 이름 해석.
//
//  두 군데서 쓴다. 서로 **별개**다:
//    1. 앱 UI — 개구(Gaegu) 하나로 고정된 브랜드 서체. `InkFont`가 여기서 가져간다.
//    2. 거울 텍스트 — 사용자가 고르는 서체 목록. `TextFontStyle`이 가져간다.
//  사용자가 거울 글씨를 "나눔붓"으로 골라도 앱 버튼 글씨는 바뀌지 않는다.
//
//  PostScript 이름은 파일 이름에서 추측하지 않는다 — 실제로 다르다.
//  (NanumBrushScript-Regular.ttf → "NanumBrush", NanumPenScript-Regular.ttf → "NanumPen-Regular")
//  그래서 번들 파일을 열어 직접 읽고, 그 값으로만 폰트를 만든다.
//

import CoreGraphics
import CoreText
import SwiftUI
import UIKit

// MARK: - 번들 폰트

enum MirrorFontLibrary {
    /// 번들에 넣어 둔 파일 이름(확장자 제외).
    static let bundledResources = [
        "Gaegu-Light", "Gaegu-Regular", "Gaegu-Bold",
        "GamjaFlower-Regular", "HiMelody-Regular", "Jua-Regular",
        "NanumBrushScript-Regular", "NanumPenScript-Regular",
        "PoorStory-Regular", "SingleDay-Regular",
    ]

    /// 파일 이름 → 실제 PostScript 이름.
    /// 전역 `let`이라 처음 읽을 때 **한 번만** 만들어지고, 그 뒤로는 읽기 전용이다.
    /// 덕분에 어느 스레드에서 글꼴을 물어도 안전하다(렌더러는 MainActor 밖에서도 돈다).
    private static let resolved: [String: String] = registerAll()

    /// Info.plist(UIAppFonts) 대신 런타임 등록을 쓴다 — 번들이 폴더를 평탄화해도 안전하고,
    /// 등록하면서 PostScript 이름을 그 자리에서 확인할 수 있다.
    private static func registerAll() -> [String: String] {
        var names: [String: String] = [:]
        for resource in bundledResources {
            guard let url = url(for: resource) else { continue }
            // 이미 등록돼 있어도(테스트에서 두 번 도는 경우) 이름은 읽을 수 있다.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)

            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let descriptor = descriptors.first,
                  let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
            else { continue }
            names[resource] = name
        }
        return names
    }

    /// 앱 시작 때 한 번 불러 준비시킨다. 안 불러도 처음 쓰는 순간 알아서 등록된다.
    static func registerIfNeeded() { _ = resolved }

    private static func url(for resource: String) -> URL? {
        Bundle.main.url(forResource: resource, withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: resource, withExtension: "ttf")
    }

    /// 실제 PostScript 이름. 파일이 없으면 nil.
    static func postScriptName(for resource: String) -> String? { resolved[resource] }

    /// 번들 폰트. 못 찾으면 **시스템 한글 폰트로 떨어진다** — 글씨가 사라지거나 죽지 않는다.
    static func uiFont(resource: String?, size: CGFloat, fallbackWeight: UIFont.Weight = .regular) -> UIFont {
        guard let resource,
              let name = postScriptName(for: resource),
              let font = UIFont(name: name, size: size)
        else { return .systemFont(ofSize: size, weight: fallbackWeight) }
        return font
    }

    /// SwiftUI용. Dynamic Type을 따라가도록 `relativeTo`를 함께 준다.
    static func font(
        resource: String?,
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        fallbackWeight: Font.Weight = .regular
    ) -> Font {
        guard let resource, let name = postScriptName(for: resource) else {
            return .system(textStyle, weight: fallbackWeight)
        }
        return .custom(name, size: size, relativeTo: textStyle)
    }
}

// MARK: - 앱 UI 브랜드 서체

/// 꾸미러 UI의 글씨. **개구(Gaegu) 하나로 고정**이다.
/// 화면마다 `.font(.custom(...))`을 직접 쓰지 않고 여기 semantic 이름만 쓴다.
enum BrandFont {
    static let light = "Gaegu-Light"
    static let regular = "Gaegu-Regular"
    static let bold = "Gaegu-Bold"

    /// 개구는 시스템 폰트보다 작게 나오므로 기준 크기를 조금 키워 잡았다.
    static func scaled(
        _ resource: String,
        _ size: CGFloat,
        _ style: Font.TextStyle,
        fallback: Font.Weight = .regular
    ) -> Font {
        MirrorFontLibrary.font(resource: resource, size: size, relativeTo: style, fallbackWeight: fallback)
    }
}
