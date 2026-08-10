//
//  ggumirrorApp.swift
//  ggumirror
//
//  Created by 이병찬 on 8/8/26.
//

import SwiftUI
import UIKit

@main
struct ggumirrorApp: App {
    init() {
        MirrorFontLibrary.registerIfNeeded()
        Self.applyBrandNavigationBar()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }

    /// UIKit이 그리는 네비게이션 제목도 같은 손글씨 서체로 맞춘다.
    /// 시스템이 통째로 제공하는 UI(공유 시트 · 사진 선택 · 권한 알림)는 건드리지 않는다.
    @MainActor
    private static func applyBrandNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        let ink = UIColor(PaperTheme.ink)
        appearance.titleTextAttributes = [
            .font: MirrorFontLibrary.uiFont(resource: BrandFont.bold, size: 19, fallbackWeight: .semibold),
            .foregroundColor: ink,
        ]
        appearance.largeTitleTextAttributes = [
            .font: MirrorFontLibrary.uiFont(resource: BrandFont.bold, size: 32, fallbackWeight: .bold),
            .foregroundColor: ink,
        ]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [
            .font: MirrorFontLibrary.uiFont(resource: BrandFont.regular, size: 18),
            .foregroundColor: ink,
        ]
        appearance.buttonAppearance = button
        appearance.backButtonAppearance = button

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
}
