//
//  MirrorControls.swift
//  ggumirror
//
//  탭하면 나타나는 Mirror 컨트롤. 액션은 "홈으로"와 "촬영" 둘뿐이다.
//

import SwiftUI

struct MirrorControls: View {
    /// 컨트롤을 건드릴 때마다 호출 — auto-hide 타이머를 다시 시작한다.
    var onInteraction: () -> Void
    var onGoHome: () -> Void
    var onCapture: () -> Void
    /// 카메라가 살아 있을 때만 촬영 버튼을 보여준다. 홈으로는 항상 필요하다.
    var showsCapture: Bool = true

    /// Claude Design(Mirror App v2, 402 x 874 기준)의 배치를 0...1 normalized로 옮긴 값.
    /// 기기 크기가 달라져도 같은 비율로 놓인다.
    private enum Layout {
        static let shutterBottom = 118.0 / 874.0
        static let homeLeading = 60.0 / 402.0
        static let homeTop = 96.0 / 874.0
        static let scrimHeight = 58.0
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.06).opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Layout.scrimHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

                homeButton
                    .padding(.leading, width * Layout.homeLeading)
                    .padding(.top, height * Layout.homeTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if showsCapture {
                    captureButton
                        .padding(.bottom, height * Layout.shutterBottom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var homeButton: some View {
        Button {
            onInteraction()
            onGoHome()
        } label: {
            HStack(spacing: 6) {
                // iOS 기본 back처럼 보이지 않게 chevron 대신 집 아이콘을 쓴다.
                Image(systemName: "house")
                    .font(.system(size: 14, weight: .semibold))
                Text("홈으로")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.leading, 9)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .background(Color(white: 0.11).opacity(0.5), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private var captureButton: some View {
        Button {
            onInteraction()
            onCapture()
        } label: {
            Circle()
                .fill(.white)
                .frame(width: 64, height: 64)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.18), lineWidth: 2)
                        .padding(6)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("촬영")
    }
}

#Preview {
    ZStack {
        Color.gray
        MirrorControls(onInteraction: {}, onGoHome: {}, onCapture: {})
    }
    .ignoresSafeArea()
}
