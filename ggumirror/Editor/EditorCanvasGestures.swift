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

        view.addGestureRecognizer(draw)
        view.addGestureRecognizer(navigate)
        view.addGestureRecognizer(pinch)
        context.coordinator.drawRecognizer = draw
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

        private var lastTranslation: CGPoint = .zero

        init(onTouch: @escaping (CanvasTouchPhase) -> Void, onNavigate: @escaping (CanvasNavigation) -> Void) {
            self.onTouch = onTouch
            self.onNavigate = onNavigate
        }

        // MARK: 한 손가락

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

        // 두 손가락 pan과 pinch는 함께 인식한다. 한 손가락 그리기와는 섞이지 않는다.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer !== drawRecognizer && other !== drawRecognizer
        }
    }
}
