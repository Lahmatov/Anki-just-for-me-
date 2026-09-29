import Foundation
import SwiftData
import UIKit
import Observation
import AJFMCore

/// «Спросить Мончика» в Monchik Help.
///
/// Вопрос уходит на сервер Recap (бесплатно для всех, с лимитами), а без
/// сервера — провайдеру по своему ключу. Если человек свернул приложение,
/// запрос не бросается: iOS даёт фоновое время дописать ответ, а сам ответ
/// приходит уведомлением. История хранится на телефоне.
@Observable
@MainActor
final class HelpService {
    static let shared = HelpService()

    private(set) var messages: [HelpChat.Message] = []
    private(set) var waiting = false
    var error: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    /// Можно ли спросить ИИ: есть сервер или свой ключ.
    var canAsk: Bool { RecapBackend.isConfigured || AIKeys.hasActiveKey }

    func ask(_ raw: String, context: ModelContext) async {
        guard !waiting, let question = HelpChat.cleanQuestion(raw) else { return }
        append(HelpChat.Message(author: .user, text: question))
        waiting = true
        error = nil
        await NotificationService.requestIfUndetermined()

        // Держим запрос живым, если приложение свернули посреди ответа.
        let background = BackgroundTask(name: "monchik-help")
        defer {
            waiting = false
            background.end()
        }

        do {
            let reply = try await fetch(question, context: context)
            append(HelpChat.Message(author: .monchik, text: reply.answer, suggestEmail: reply.suggestEmail))
            if UIApplication.shared.applicationState != .active {
                await NotificationService.notifyHelpReply(reply.answer)
            }
        } catch {
            self.error = error.localizedDescription
            Log.failure(.network, "Monchik Help не ответил", error)
        }
    }

    func clear() {
        messages = []
        defaults.removeObject(forKey: SettingsKey.helpHistory)
    }

    /// После «Удалить все данные» — забыть и то, что в памяти.
    func reload() {
        messages = defaults.data(forKey: SettingsKey.helpHistory)
            .flatMap { try? JSONDecoder().decode([HelpChat.Message].self, from: $0) } ?? []
    }

    private func append(_ message: HelpChat.Message) {
        messages = HelpChat.trimmed(messages + [message])
        if let data = try? JSONEncoder().encode(messages) {
            defaults.set(data, forKey: SettingsKey.helpHistory)
        }
    }

    private func fetch(_ question: String, context: ModelContext) async throws -> HelpChat.Reply {
        if RecapBackend.isConfigured {
            return try await RecapBackend.shared.help(
                BackendAPI.HelpBody(question: question, language: Loc.language)).asReply
        }
        guard let client = AIClient.current() else { throw ClaudeClientError.noAPIKey }
        let completion = try await client.complete(ClaudeRequest(
            model: ClaudeModel.haiku45, system: HelpChat.system(language: Loc.language),
            userMessage: question, maxTokens: HelpChat.maxTokens, effort: .low,
            outputSchemaJSON: HelpChat.outputSchemaJSON))
        ClaudeBudget(context: context).record(completion.usage, purpose: "Monchik Help")
        if let problem = ClaudeClient.problem(with: completion) {
            throw AIService.AIError.message(problem)
        }
        return try HelpChat.parseReply(completion.text ?? "")
    }
}

/// Фоновое время iOS для одного запроса: свернул приложение — запрос
/// дописывается, а не обрывается. Закрывается один раз, кто бы ни успел
/// первым: сам запрос или iOS, когда время вышло.
@MainActor
final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
