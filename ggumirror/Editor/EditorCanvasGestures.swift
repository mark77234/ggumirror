//
//  EditorCanvasGestures.swift
//  ggumirror
//
//  한 손가락 = 그리기 / 지우기, 두 손가락 = Pan + Zoom.
//  SwiftUI DragGesture만으로는 터치 개수 구분과 취소 처리가 불안정해 UIKit recognizer를 쓴다.
//  ScrollView는 쓰지 않는다 — Drawing gesture를 가로채기 때문이다.
//

import SwiftUI
import UIKit

/// 한 손가락 입력의 생애주기. cancelled에서도 이미 그린 획은 살릴 수 있어야 한다.
enum CanvasTouchPhase {
    /// 움직이지 않고 떼는 짧은 터치. Pan recognizer는 이동 임계값을 넘어야 began이 되므로
    /// 제자리 tap은 여기로만 들어온다.
    case tapped(CGPoint)
    case began(CGPoint)
    case moved(CGPoint)
    case ended
    case cancelled
}

/// 두 손가락 입력. 화면 좌표 기준으로 그대로 전달한다.
struct CanvasNavigation {
    /// 직전 이벤트 대비 이동량.
    var translationDelta: CGSize = .zero
    /// 직전 이벤트 대비 배율 변화(1이면 변화 없음).
    var scaleDelta: CGFloat = 1
    /// 두 손가락의 중심. 이 지점을 기준으로 확대한다.
    var center: CGPoint = .zero
    var isEnded = false
}

struct EditorCanvasGestureOverlay: UIViewRepresentable {
    var onTouch: (CanvasTouchPhase) -> Void
    var onNavigate: (CanvasNavigation) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let draw = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDraw(_:))
        )
        draw.minimumNumberOfTouches = 1
        draw.maximumNumberOfTouches = 1
        // 손가락을 대자마자 점이 찍히도록 이동 임계값을 없앤다.
        draw.delaysTouchesBegan = false
        draw.cancelsTouchesInView = false
        draw.delegate = context.coordinator

        // Pan recognizer는 손가락이 일정 거리 움직여야 began이 된다.
        // 제자리 tap(= 스티커 재선택)은 절대 오지 않으므로 별도 tap recognizer가 필요하다.
        // 임계값은 UITapGestureRecognizer의 기본 allowableMovement를 그대로 쓴다 —
        // 손이 1~2pt 흔들려도 tap으로 남고, 진짜로 끌면 pan이 이긴다.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.numberOfTapsRequired = 1
        tap.numberOfTouchesRequired = 1
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator

        let navigate = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleNavigate(_:))
        )
        navigate.minimumNumberOfTouches = 2
        navigate.maximumNumberOfTouches = 2
        navigate.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.delegate = context.coordinator

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(draw)
        view.addGestureRecognizer(navigate)
        view.addGestureRecognizer(pinch)
        context.coordinator.drawRecognizer = draw
        context.coordinator.tapRecognizer = tap
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTouch = onTouch
        context.coordinator.onNavigate = onNavigate
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTouch: onTouch, onNavigate: onNavigate)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTouch: (CanvasTouchPhase) -> Void
        var onNavigate: (CanvasNavigation) -> Void
        weak var drawRecognizer: UIPanGestureRecognizer?
        weak var tapRecognizer: UITapGestureRecognizer?

        private var lastTranslation: CGPoint = .zero

        init(onTouch: @escaping (CanvasTouchPhase) -> Void, onNavigate: @escaping (CanvasNavigation) -> Void) {
            self.onTouch = onTouch
            self.onNavigate = onNavigate
        }

        // MARK: 한 손가락

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onTouch(.tapped(recognizer.location(in: recognizer.view)))
        }

        @objc func handleDraw(_ recognizer: UIPanGestureRecognizer) {
            let point = recognizer.location(in: recognizer.view)
            switch recognizer.state {
            case .began: onTouch(.began(point))
            case .changed: onTouch(.moved(point))
            case .ended: onTouch(.ended)
            case .cancelled, .failed: onTouch(.cancelled)
            default: break
            }
        }

        // MARK: 두 손가락

        @objc func handleNavigate(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                lastTranslation = .zero
                // 두 손가락이 들어오면 진행 중인 한 손가락 입력은 즉시 마무리한다.
                cancelDrawing()
            case .changed:
                let translation = recognizer.translation(in: recognizer.view)
                onNavigate(CanvasNavigation(
                    translationDelta: CGSize(
                        width: translation.x - lastTranslation.x,
                        height: translation.y - lastTranslation.y
                    ),
                    center: recognizer.location(in: recognizer.view)
                ))
                lastTranslation = translation
            case .ended, .cancelled, .failed:
                onNavigate(CanvasNavigation(isEnded: true))
                lastTranslation = .zero
            default:
                break
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                cancelDrawing()
                recognizer.scale = 1
            case .changed:
                guard recognizer.numberOfTouches >= 2 else { return }
                onNavigate(CanvasNavigation(
                    scaleDelta: recognizer.scale,
                    center: recognizer.location(in: recognizer.view)
                ))
                recognizer.scale = 1
            case .ended, .cancelled, .failed:
                onNavigate(CanvasNavigation(isEnded: true))
            default:
                break
            }
        }

        /// 두 손가락이 시작되면 한 손가락 recognizer를 강제 종료시킨다.
        /// 이때도 .cancelled로 전달되므로 이미 유효한 획은 저장된다.
        private func cancelDrawing() {
            guard let drawRecognizer, drawRecognizer.state == .began || drawRecognizer.state == .changed
            else { return }
            drawRecognizer.isEnabled = false
            drawRecognizer.isEnabled = true
        }

        // 두 손가락 pan과 pinch는 함께 인식한다. 한 손가락 그리기 / tap과는 섞이지 않는다.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            for recognizer in [gestureRecognizer, other] {
                if recognizer === drawRecognizer || recognizer === tapRecognizer { return false }
            }
            return true
        }
    }
}
