import SwiftUI
import Observation

/// Путь одного стека навигации. Живёт в `@State` корня вкладки или листа:
/// у каждой вкладки свой путь, и переходы в одной не трогают другую
/// (на iPad и открытом iPhone Duo — и в двух окнах сразу).
@Observable
@MainActor
final class Router {
    var path = NavigationPath()

    func push(_ route: AppRoute) {
        path.append(route)
    }

    /// Назад к корню — например, по окончании сессии.
    func popToRoot() {
        path = NavigationPath()
    }
}

extension View {
    /// Корень стека: `NavigationStack` на пути роутера, все маршруты
    /// приложения и роутер в окружении — экраны внутри переходят через него.
    func routedStack(_ router: Router) -> some View {
        NavigationStack(path: Bindable(router).path) {
            self.navigationDestination(for: AppRoute.self) { route in
                AppRouteView(route: route)
            }
        }
        .environment(router)
    }
}

/// Стек со своим роутером — для листов и превью, где корню не нужно
/// переходить самому.
struct RoutedStack<Root: View>: View {
    @State private var router = Router()
    @ViewBuilder let root: Root

    var body: some View {
        root.routedStack(router)
    }
}
