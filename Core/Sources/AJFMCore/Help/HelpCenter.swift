import Foundation

/// Monchik Help: частые вопросы и поиск по ним.
///
/// Большинство вопросов в поддержку — одни и те же: где взять слова, почему
/// нет карточек, как отменить подписку. Ответ на них есть сразу и без сети;
/// до ИИ и письма человек доходит, только если здесь ответа нет.
public enum HelpCenter {

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String
        public var question: String
        public var answer: String

        public init(id: String, question: String, answer: String) {
            self.id = id
            self.question = question
            self.answer = answer
        }
    }

    public static var entries: [Entry] {
        [
            Entry(id: "add-words",
                  question: tr("Как добавить слова?", "Como junto palavras?", "How do I add words?"),
                  answer: tr("Проще всего — вкладка «Сериалы»: найди сериал, открой серию и возьми слова. "
                                + "Ещё можно попросить набор у ИИ на «Сегодня», вставить готовый набор "
                                + "на вкладке «Наборы» или взять стартовый набор.",
                             "O mais simples é o separador «Séries»: procura a série, abre o episódio e "
                                + "obtém as palavras. Também podes pedir um baralho à IA em «Hoje», colar "
                                + "um baralho em «Baralhos» ou usar o baralho inicial.",
                             "The easiest way is the Shows tab: find a show, open an episode and get its "
                                + "words. You can also ask the AI for a deck on Today, paste a deck on the "
                                + "Decks tab or take the starter deck.")),
            Entry(id: "no-cards",
                  question: tr("Почему сегодня нет карточек?", "Porque não há cartões hoje?",
                               "Why are there no cards today?"),
                  answer: tr("Интервальное повторение показывает слово тогда, когда ты начинаешь его "
                                + "забывать. Если всё повторено вовремя, карточек нет — это хороший знак. "
                                + "Добавь новые слова или загляни завтра.",
                             "A repetição espaçada mostra a palavra quando a começas a esquecer. Se "
                                + "reviste tudo a tempo, não há cartões — é bom sinal. Junta palavras novas "
                                + "ou volta amanhã.",
                             "Spaced repetition shows a word right when you start forgetting it. If "
                                + "everything is reviewed on time, there are no cards — a good sign. Add "
                                + "new words or come back tomorrow.")),
            Entry(id: "grades",
                  question: tr("Что значат «Забыл», «Трудно», «Хорошо», «Легко»?",
                               "O que significam «Esqueci», «Difícil», «Bem», «Fácil»?",
                               "What do Again, Hard, Good and Easy mean?"),
                  answer: tr("Это то, насколько легко ты вспомнил. От оценки зависит, когда слово "
                                + "вернётся: срок написан прямо на кнопке. Честное «Забыл» полезнее "
                                + "угаданного «Хорошо».",
                             "É o quão fácil te lembraste. A avaliação decide quando a palavra volta: "
                                + "o prazo está escrito no botão. Um «Esqueci» honesto vale mais do que "
                                + "um «Bem» à sorte.",
                             "It's how easily you remembered. Your grade decides when the word comes "
                                + "back — the interval is on the button. An honest Again beats a lucky Good.")),
            Entry(id: "monchik-chat",
                  question: tr("Как поговорить с Мончиком о серии?", "Como converso com o Monchik sobre um episódio?",
                               "How do I chat with Monchik about an episode?"),
                  answer: tr("Отметь серию просмотренной во вкладке «Сериалы», возьми к ней слова и "
                                + "нажми «Поговорить с Мончиком». Нужен Recap Plus или свой ключ ИИ.",
                             "Marca o episódio como visto em «Séries», obtém as palavras e toca em "
                                + "«Conversar com o Monchik». É preciso o Recap Plus ou uma chave de IA própria.",
                             "Mark the episode as watched on the Shows tab, get its words and tap "
                                + "“Chat with Monchik”. You need Recap Plus or your own AI key.")),
            Entry(id: "retell",
                  question: tr("Как работает пересказ?", "Como funciona o reconto?", "How does retelling work?"),
                  answer: tr("Расскажи серию голосом или текстом — ИИ сверит пересказ с описанием или "
                                + "субтитрами и покажет, что сказать точнее. Нужен свой ключ ИИ.",
                             "Conta o episódio por voz ou texto — a IA compara com a sinopse ou as "
                                + "legendas e mostra o que dizer melhor. É preciso uma chave de IA própria.",
                             "Retell the episode by voice or text — the AI checks it against the synopsis "
                                + "or subtitles and shows what to say better. You need your own AI key.")),
            Entry(id: "plus",
                  question: tr("Что даёт Recap Plus и как его отменить?", "O que dá o Recap Plus e como o cancelo?",
                               "What is Recap Plus and how do I cancel it?"),
                  answer: tr("Слова к любой серии и разговоры с Мончиком без своего ключа. Отменить — "
                                + "Профиль → Управлять подпиской или настройки Apple ID. Возврат — через Apple.",
                             "Palavras para qualquer episódio e conversas com o Monchik sem chave própria. "
                                + "Para cancelar: Perfil → Gerir subscrição ou definições do Apple ID. "
                                + "Reembolsos — pela Apple.",
                             "Words for any episode and chats with Monchik without your own key. Cancel in "
                                + "Profile → Manage subscription or in Apple ID settings. Refunds go through Apple.")),
            Entry(id: "ai-key",
                  question: tr("Как подключить свой ключ ИИ?", "Como ligo a minha chave de IA?",
                               "How do I add my own AI key?"),
                  answer: tr("Профиль → Ключи ИИ. Подходят Claude, Gemini, ChatGPT, Kimi, DeepSeek, "
                                + "Mistral, Grok и Qwen. У каждого есть ссылка «Где взять ключ» и кнопка "
                                + "проверки. Ключ хранится только в Keychain телефона.",
                             "Perfil → Chaves de IA. Servem Claude, Gemini, ChatGPT, Kimi, DeepSeek, "
                                + "Mistral, Grok e Qwen. Cada um tem «Onde obter a chave» e um botão de "
                                + "verificação. A chave fica só no Keychain do telemóvel.",
                             "Profile → AI keys. Claude, Gemini, ChatGPT, Kimi, DeepSeek, Mistral, Grok and "
                                + "Qwen work. Each has “Where to get a key” and a check button. The key "
                                + "stays in the phone's Keychain only.")),
            Entry(id: "new-phone",
                  question: tr("Как перенести слова на новый телефон?", "Como passo as palavras para um telemóvel novo?",
                               "How do I move my words to a new phone?"),
                  answer: tr("Вкладка «Наборы» → бэкап: сохрани файл и открой его на новом телефоне. "
                                + "Подписка вернётся через «Восстановить покупки» или вход через Apple.",
                             "Separador «Baralhos» → cópia de segurança: guarda o ficheiro e abre-o no "
                                + "telemóvel novo. A subscrição volta com «Restaurar compras» ou com a "
                                + "sessão da Apple.",
                             "Decks tab → backup: save the file and open it on the new phone. Your "
                                + "subscription comes back with Restore purchases or Sign in with Apple.")),
            Entry(id: "delete",
                  question: tr("Как удалить свои данные?", "Como apago os meus dados?", "How do I delete my data?"),
                  answer: tr("Профиль → Конфиденциальность и удаление данных → «Удалить все данные». "
                                + "Удалится всё на телефоне, аккаунт и запись на сервере.",
                             "Perfil → Privacidade e apagar dados → «Apagar todos os dados». Apaga tudo "
                                + "no telemóvel, a conta e o registo no servidor.",
                             "Profile → Privacy and data deletion → Delete all data. Everything on the "
                                + "phone, your account and the server record are removed.")),
            Entry(id: "pronunciation",
                  question: tr("Произношение не распознаётся", "A pronúncia não é reconhecida",
                               "Pronunciation isn't recognised"),
                  answer: tr("Проверь, что у приложения есть доступ к микрофону и распознаванию речи "
                                + "(Настройки iOS → Recap). Говори в тишине, на обычном расстоянии.",
                             "Confirma que a aplicação tem acesso ao microfone e ao reconhecimento de "
                                + "fala (Definições do iOS → Recap). Fala num sítio calmo, à distância normal.",
                             "Make sure the app can use the microphone and speech recognition (iOS "
                                + "Settings → Recap). Speak somewhere quiet, at a normal distance.")),
            Entry(id: "motion",
                  question: tr("Как выключить анимации?", "Como desligo as animações?", "How do I turn off animations?"),
                  answer: tr("Включи «Уменьшение движения» в Настройках iOS → Универсальный доступ → "
                                + "Движение. Конфетти, сияние и тряска пропадут.",
                             "Ativa «Reduzir movimento» em Definições do iOS → Acessibilidade → Movimento. "
                                + "Confetes, auroras e abanões desaparecem.",
                             "Turn on Reduce Motion in iOS Settings → Accessibility → Motion. Confetti, "
                                + "aurora and shakes go away.")),
            Entry(id: "hot",
                  question: tr("Телефон греется", "O telemóvel aquece", "My phone gets warm"),
                  answer: tr("Сборка из Xcode с отладчиком греет телефон заметно сильнее обычной — "
                                + "проверяй на версии из TestFlight. Если греется и она, напиши нам и "
                                + "приложи журнал (Настройки → Для продвинутых → Журнал событий).",
                             "Uma versão do Xcode com o depurador aquece muito mais do que a normal — "
                                + "experimenta a do TestFlight. Se também aquecer, escreve-nos com o "
                                + "registo (Definições → Avançado → Registo de eventos).",
                             "A build from Xcode with the debugger heats the phone far more than a normal "
                                + "one — try the TestFlight version. If that heats too, write to us with the "
                                + "log (Settings → Advanced → Event log).")),
        ]
    }

    /// Поиск: вопросы, где встречаются все слова запроса, выше тех, где
    /// часть; совпадение в вопросе весит больше, чем в ответе. Регистр и
    /// диакритика не важны («acoes» находит «ações»).
    public static func search(_ query: String, in entries: [Entry] = entries) -> [Entry] {
        let words = normalize(query).split(separator: " ").map(String.init).filter { $0.count >= 2 }
        guard !words.isEmpty else { return entries }
        let scored = entries.compactMap { entry -> (Entry, Int)? in
            let question = normalize(entry.question)
            let answer = normalize(entry.answer)
            var score = 0
            for word in words {
                if question.contains(word) { score += 3 } else if answer.contains(word) { score += 1 }
            }
            return score > 0 ? (entry, score) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    static func normalize(_ text: String) -> String {
        // Без диакритики «ё» становится «е», а «ações» — «acoes».
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
