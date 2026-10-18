import Foundation

/// Когда прятать панель вкладок на время сессии повторения.
///
/// Раньше хватало пары «появилась — спрятать, исчезла — показать». Но SwiftUI
/// в стеке на пути вызывает события экрана не строго парой: уходящий назад экран
/// может ещё раз получить «появился», когда родитель перерисовывается посреди
/// анимации, а «исчез» иногда не приходит вовсе. Тогда панель пропадала до
/// перезапуска (Devices, iPhone 17, после «Назад» из сессии). Поэтому правило
/// смотрит ещё и на путь стека: сессия лежит на своей глубине, и если путь стал
/// короче — её уже закрыли, что бы ни пришло потом.
///
/// `Stack` — кто владеет путём (в приложении — идентификатор роутера).
public struct SessionBarRule<Stack: Hashable & Sendable>: Equatable, Sendable {
    /// Стек и глубина пути, на которой открыта сессия.
    public private(set) var owner: Owner?
    /// Сессия открыта вне стека (лист, превью): прятать по событиям экрана.
    private var hiddenOutsideStack = false

    public struct Owner: Equatable, Sendable {
        public let stack: Stack
        public let depth: Int

        public init(stack: Stack, depth: Int) {
            self.stack = stack
            self.depth = depth
        }
    }

    public init() {}

    public var isBarHidden: Bool { owner != nil || hiddenOutsideStack }

    /// Экран сессии появился. `depth` — глубина пути, запомненная экраном при
    /// первом появлении; `currentDepth` — глубина сейчас.
    public mutating func sessionAppeared(stack: Stack?, depth: Int?, currentDepth: Int?) {
        guard let stack, let depth, let currentDepth else {
            hiddenOutsideStack = true
            return
        }
        // Путь уже короче — это запоздалое «появился» у закрытой сессии.
        // Глубина 0 — корень стека, а сессия корнем вкладки не бывает.
        guard depth > 0, currentDepth >= depth else { return }
        owner = Owner(stack: stack, depth: depth)
    }

    public mutating func sessionDisappeared() {
        owner = nil
        hiddenOutsideStack = false
    }

    /// Путь стека изменился (в том числе кнопкой «Назад» и жестом).
    public mutating func pathChanged(stack: Stack, depth: Int) {
        guard let owner, owner.stack == stack, depth < owner.depth else { return }
        self.owner = nil
    }
}
