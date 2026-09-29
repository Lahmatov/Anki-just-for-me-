import Foundation

/// Статьи о том, почему английский по сериалам работает. Только проверенные
/// источники — British Council, Cambridge и исследование в рецензируемом
/// журнале, — а не блоги, которые продают курсы.
public enum LearningArticles {

    public struct Article: Equatable, Sendable, Identifiable {
        /// Заголовок статьи как есть — статьи англоязычные.
        public var title: String
        public var source: String
        /// Одна фраза на языке приложения: зачем читать.
        public var summary: String
        public var url: URL

        public var id: URL { url }

        public init(title: String, source: String, summary: String, url: URL) {
            self.title = title
            self.source = source
            self.summary = summary
            self.url = url
        }
    }

    public static var all: [Article] {
        [
            Article(
                title: "How to use TV series, trailers and films in language class",
                source: "British Council",
                summary: tr("Почему сериалы полезнее фильмов: короткие серии, те же герои и живая речь.",
                            "Porque as séries ajudam mais do que os filmes: episódios curtos, as mesmas "
                                + "personagens e fala real.",
                            "Why series beat films: short episodes, the same characters, real speech."),
                url: URL(string: "https://www.britishcouncil.org/voices-magazine/how-to-use-tv-series-trailers-films-language-class")!),
            Article(
                title: "Netflix and learn – six ways to teach English language skills with television",
                source: "British Council",
                summary: tr("Шесть приёмов преподавателя: как выжать из серии слушание, слова и речь.",
                            "Seis técnicas de uma professora para tirar de um episódio audição, "
                                + "vocabulário e fala.",
                            "Six teacher-tested ways to get listening, vocabulary and speaking out of an episode."),
                url: URL(string: "https://www.britishcouncil.org/voices-magazine/teach-english-language-skills-television")!),
            Article(
                title: "Learn English through videos and TV",
                source: "Cambridge English",
                summary: tr("Как смотреть с субтитрами и без, чтобы слух рос быстрее.",
                            "Como ver com e sem legendas para a compreensão oral crescer mais depressa.",
                            "How to watch with and without subtitles so your listening grows faster."),
                url: URL(string: "https://www.cambridgeenglish.org/learning-english/parents-and-children/your-childs-interests/learn-english-through-videos-and-tv/")!),
            Article(
                title: "Incidental vocabulary acquisition through viewing L2 television and factors that affect learning",
                source: "Peters & Webb, Studies in Second Language Acquisition (2018)",
                summary: tr("Исследование: одна серия — и часть незнакомых слов уже узнаётся. "
                                + "Лучше всего запоминаются те, что звучат чаще.",
                            "Estudo: um só episódio e já se reconhece parte das palavras novas. "
                                + "Ficam melhor as que se ouvem mais vezes.",
                            "Research: after one episode learners already recognise some new words — "
                                + "the ones heard most often stick best."),
                url: URL(string: "https://www.semanticscholar.org/paper/INCIDENTAL-VOCABULARY-ACQUISITION-THROUGH-VIEWING-Peters-Webb/bceee3922d5103b9ef2f81143b7a7733481d0801")!),
        ]
    }
}
