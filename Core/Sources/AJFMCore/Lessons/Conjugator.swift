import Foundation

/// Время для тренажёра спряжения: настоящее и одно прошедшее — те, что
/// проходят первыми. У португальского прошедшее — pretérito perfeito,
/// у итальянского — passato prossimo, у английского — past simple.
public enum Tense: String, CaseIterable, Codable, Sendable {
    case present, past

    public func title(for language: StudyLanguage) -> String {
        switch (self, language) {
        case (.present, .english): return "Present simple"
        case (.past, .english): return "Past simple"
        case (.present, .portuguese): return "Presente"
        case (.past, .portuguese): return "Pretérito perfeito"
        case (.present, .italian): return "Presente"
        case (.past, .italian): return "Passato prossimo"
        }
    }
}

/// Одна строка таблицы: «eu — como».
public struct ConjugatedForm: Equatable, Sendable {
    public var person: String
    public var form: String

    public init(person: String, form: String) {
        self.person = person
        self.form = form
    }
}

public struct Conjugation: Equatable, Sendable {
    public var verb: String
    public var tense: Tense
    public var forms: [ConjugatedForm]

    public init(verb: String, tense: Tense, forms: [ConjugatedForm]) {
        self.verb = verb
        self.tense = tense
        self.forms = forms
    }
}

/// Спряжение по правилам плюс таблицы самых частых неправильных глаголов.
///
/// Глаголы берутся из карточек урока, поэтому правило должно честно
/// отказываться: незнакомое окончание — `nil`, и тренажёр такой глагол
/// пропускает. Неправильная форма в тренажёре хуже, чем её отсутствие:
/// человек выучит ошибку.
///
/// Португальский — европейский: «falámos» в прошедшем (в Бразилии
/// «falamos»), возвратные — с местоимением после глагола («levanto-me»).
/// Лица — те, что учат в Португалии: eu, tu, ele/ela, nós, eles/elas.
public enum Conjugator {

    public static func persons(for language: StudyLanguage) -> [String] {
        switch language {
        case .english: return ["I", "you", "he/she", "we", "they"]
        case .portuguese: return ["eu", "tu", "ele/ela", "nós", "eles/elas"]
        case .italian: return ["io", "tu", "lui/lei", "noi", "voi", "loro"]
        }
    }

    /// Спряжение словарной формы. Фраза («ter saudades», «get up») —
    /// спрягается первое слово, остальное остаётся как есть.
    public static func conjugate(_ term: String, language: StudyLanguage, tense: Tense) -> Conjugation? {
        var words = term.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        if language == .english, words.first == "to" { words.removeFirst() }
        guard let verb = words.first, verb.count >= 2,
              verb.allSatisfy({ $0.isLetter || $0 == "-" }) else { return nil }
        let rest = words.dropFirst().joined(separator: " ")

        let forms: [String]?
        switch language {
        case .portuguese: forms = Portuguese.forms(verb, tense: tense)
        case .italian: forms = Italian.forms(verb, tense: tense)
        case .english: forms = English.forms(verb, tense: tense)
        }
        guard let forms else { return nil }
        let people = persons(for: language)
        guard forms.count == people.count else { return nil }
        let full = rest.isEmpty ? forms : forms.map { "\($0) \(rest)" }
        let dictionary = ([verb] + (rest.isEmpty ? [] : [rest])).joined(separator: " ")
        return Conjugation(
            verb: dictionary, tense: tense,
            forms: zip(people, full).map { ConjugatedForm(person: $0, form: $1) })
    }

    /// Можно ли тренировать спряжение этого слова.
    public static func canConjugate(_ term: String, language: StudyLanguage) -> Bool {
        conjugate(term, language: language, tense: .present) != nil
    }
}

// MARK: - Португальский (Португалия)

private enum Portuguese {
    static let clitics = ["me", "te", "se", "nos", "se"]

    static func forms(_ verb: String, tense: Tense) -> [String]? {
        if verb.hasSuffix("-se") {
            let base = String(verb.dropLast(3))
            guard !base.contains("-"), let plain = forms(base, tense: tense) else { return nil }
            // Энклиза: «levantamos» + «nos» → «levantamo-nos» — конечное s выпадает.
            return zip(plain, clitics).enumerated().map { index, pair in
                let (form, clitic) = pair
                let stem = index == 3 && form.hasSuffix("s") ? String(form.dropLast()) : form
                return "\(stem)-\(clitic)"
            }
        }
        guard !verb.contains("-") else { return nil }
        switch tense {
        case .present: return present(verb)
        case .past: return past(verb)
        }
    }

    static let irregularPresent: [String: [String]] = [
        "ser": ["sou", "és", "é", "somos", "são"],
        "estar": ["estou", "estás", "está", "estamos", "estão"],
        "ter": ["tenho", "tens", "tem", "temos", "têm"],
        "ir": ["vou", "vais", "vai", "vamos", "vão"],
        "fazer": ["faço", "fazes", "faz", "fazemos", "fazem"],
        "poder": ["posso", "podes", "pode", "podemos", "podem"],
        "querer": ["quero", "queres", "quer", "queremos", "querem"],
        "dizer": ["digo", "dizes", "diz", "dizemos", "dizem"],
        "ver": ["vejo", "vês", "vê", "vemos", "veem"],
        "dar": ["dou", "dás", "dá", "damos", "dão"],
        "saber": ["sei", "sabes", "sabe", "sabemos", "sabem"],
        "vir": ["venho", "vens", "vem", "vimos", "vêm"],
        "haver": ["hei", "hás", "há", "havemos", "hão"],
        "pôr": ["ponho", "pões", "põe", "pomos", "põem"],
        "trazer": ["trago", "trazes", "traz", "trazemos", "trazem"],
        "ler": ["leio", "lês", "lê", "lemos", "leem"],
        "crer": ["creio", "crês", "crê", "cremos", "creem"],
        "ouvir": ["ouço", "ouves", "ouve", "ouvimos", "ouvem"],
        "pedir": ["peço", "pedes", "pede", "pedimos", "pedem"],
        "medir": ["meço", "medes", "mede", "medimos", "medem"],
        "perder": ["perco", "perdes", "perde", "perdemos", "perdem"],
        "valer": ["valho", "vales", "vale", "valemos", "valem"],
        "sair": ["saio", "sais", "sai", "saímos", "saem"],
        "cair": ["caio", "cais", "cai", "caímos", "caem"],
        "rir": ["rio", "ris", "ri", "rimos", "riem"],
        "sorrir": ["sorrio", "sorris", "sorri", "sorrimos", "sorriem"],
        "subir": ["subo", "sobes", "sobe", "subimos", "sobem"],
        "fugir": ["fujo", "foges", "foge", "fugimos", "fogem"],
        "odiar": ["odeio", "odeias", "odeia", "odiamos", "odeiam"],
        "construir": ["construo", "constróis", "constrói", "construímos", "constroem"],
        "destruir": ["destruo", "destróis", "destrói", "destruímos", "destroem"],
    ]

    /// Глаголы на -ir, у которых меняется только первое лицо: dormir → durmo.
    static let firstPersonPresent: [String: String] = [
        "dormir": "durmo", "sentir": "sinto", "preferir": "prefiro", "vestir": "visto",
        "servir": "sirvo", "repetir": "repito", "seguir": "sigo", "conseguir": "consigo",
        "mentir": "minto", "divertir": "divirto", "despir": "dispo", "tossir": "tusso",
        "cobrir": "cubro", "descobrir": "descubro", "competir": "compito", "sugerir": "sugiro",
    ]

    static let irregularPast: [String: [String]] = [
        "ser": ["fui", "foste", "foi", "fomos", "foram"],
        "ir": ["fui", "foste", "foi", "fomos", "foram"],
        "estar": ["estive", "estiveste", "esteve", "estivemos", "estiveram"],
        "ter": ["tive", "tiveste", "teve", "tivemos", "tiveram"],
        "fazer": ["fiz", "fizeste", "fez", "fizemos", "fizeram"],
        "poder": ["pude", "pudeste", "pôde", "pudemos", "puderam"],
        "querer": ["quis", "quiseste", "quis", "quisemos", "quiseram"],
        "dizer": ["disse", "disseste", "disse", "dissemos", "disseram"],
        "ver": ["vi", "viste", "viu", "vimos", "viram"],
        "dar": ["dei", "deste", "deu", "demos", "deram"],
        "saber": ["soube", "soubeste", "soube", "soubemos", "souberam"],
        "vir": ["vim", "vieste", "veio", "viemos", "vieram"],
        "haver": ["houve", "houveste", "houve", "houvemos", "houveram"],
        "pôr": ["pus", "puseste", "pôs", "pusemos", "puseram"],
        "trazer": ["trouxe", "trouxeste", "trouxe", "trouxemos", "trouxeram"],
        "sair": ["saí", "saíste", "saiu", "saímos", "saíram"],
        "cair": ["caí", "caíste", "caiu", "caímos", "caíram"],
        "construir": ["construí", "construíste", "construiu", "construímos", "construíram"],
        "destruir": ["destruí", "destruíste", "destruiu", "destruímos", "destruíram"],
    ]

    static func present(_ verb: String) -> [String]? {
        if let forms = irregularPresent[verb] { return forms }
        guard let (stem, ending) = split(verb) else { return nil }
        var forms: [String]
        switch ending {
        case "ar":
            // passear → passeio, passeias: в ударных формах e → ei.
            if stem.hasSuffix("e") {
                let root = stem + "i"
                return [root + "o", root + "as", root + "a", stem + "amos", root + "am"]
            }
            forms = [stem + "o", stem + "as", stem + "a", stem + "amos", stem + "am"]
        case "er":
            forms = [stem + "o", stem + "es", stem + "e", stem + "emos", stem + "em"]
        case "ir":
            // incluir → incluo, incluis, inclui, incluímos, incluem.
            if isUir(stem) {
                return [stem + "o", stem + "is", stem + "i", stem + "ímos", stem + "em"]
            }
            forms = [stem + "o", stem + "es", stem + "e", stem + "imos", stem + "em"]
        default:
            return nil
        }
        if let first = firstPersonPresent[verb] {
            forms[0] = first
        } else if stem.hasSuffix("gu") || stem.hasSuffix("qu") {
            // distinguir → distingo: u только сохраняет звук перед e и i.
            forms[0] = String(stem.dropLast()) + "o"
        } else if ending != "ar" {
            // Орфография первого лица: conhecer → conheço, proteger → protejo.
            if stem.hasSuffix("c") {
                forms[0] = String(stem.dropLast()) + "ço"
            } else if stem.hasSuffix("g") {
                forms[0] = String(stem.dropLast()) + "jo"
            }
        }
        return forms
    }

    static func past(_ verb: String) -> [String]? {
        if let forms = irregularPast[verb] { return forms }
        guard let (stem, ending) = split(verb) else { return nil }
        switch ending {
        case "ar":
            // Первое лицо: ficar → fiquei, chegar → cheguei, começar → comecei.
            var first = stem + "ei"
            if stem.hasSuffix("c") { first = String(stem.dropLast()) + "quei" }
            if stem.hasSuffix("g") { first = stem + "uei" }
            if stem.hasSuffix("ç") { first = String(stem.dropLast()) + "cei" }
            return [first, stem + "aste", stem + "ou", stem + "ámos", stem + "aram"]
        case "er":
            return [stem + "i", stem + "este", stem + "eu", stem + "emos", stem + "eram"]
        case "ir":
            if isUir(stem) {
                return [stem + "í", stem + "íste", stem + "iu", stem + "ímos", stem + "íram"]
            }
            return [stem + "i", stem + "iste", stem + "iu", stem + "imos", stem + "iram"]
        default:
            return nil
        }
    }

    /// -uir (incluir), но не -guir/-quir (seguir): там u — часть буквы.
    static func isUir(_ stem: String) -> Bool {
        stem.hasSuffix("u") && !stem.hasSuffix("gu") && !stem.hasSuffix("qu")
    }

    static func split(_ verb: String) -> (String, String)? {
        guard verb.count >= 3 else { return nil }
        let ending = String(verb.suffix(2))
        guard ["ar", "er", "ir"].contains(ending) else { return nil }
        let stem = String(verb.dropLast(2))
        // atrair, doer, moer — свои формы, которых нет в таблицах: лучше
        // промолчать, чем научить «atrao».
        if ending != "ar", let last = stem.last, "aoe".contains(last) { return nil }
        return (stem, ending)
    }
}

// MARK: - Итальянский

private enum Italian {
    static let reflexivePronouns = ["mi", "ti", "si", "ci", "vi", "si"]
    static let avere = ["ho", "hai", "ha", "abbiamo", "avete", "hanno"]
    static let essere = ["sono", "sei", "è", "siamo", "siete", "sono"]

    static func forms(_ verb: String, tense: Tense) -> [String]? {
        // alzarsi → alzare, mettersi → mettere, divertirsi → divertire.
        if verb.hasSuffix("si"), verb.count > 5 {
            let base = String(verb.dropLast(2)) + "e"
            guard split(base) != nil || irregularPresent[base] != nil else { return nil }
            switch tense {
            case .present:
                guard let plain = present(base) else { return nil }
                return zip(reflexivePronouns, plain).map { "\($0) \($1)" }
            case .past:
                guard let participle = participle(base) else { return nil }
                return zip(reflexivePronouns, agreeing(participle)).map { "\($0) \($1)" }
            }
        }
        switch tense {
        case .present: return present(verb)
        case .past:
            guard let participle = participle(verb) else { return nil }
            if takesEssere.contains(verb) { return agreeing(participle) }
            return avere.map { "\($0) \(participle)" }
        }
    }

    /// С essere причастие согласуется: «sono andato», «siamo andati».
    /// Мужской род — как в словаре и учебнике.
    static func agreeing(_ participle: String) -> [String] {
        let plural = String(participle.dropLast()) + "i"
        return essere.enumerated().map { index, aux in
            "\(aux) \(index < 3 ? participle : plural)"
        }
    }

    static let irregularPresent: [String: [String]] = [
        "essere": ["sono", "sei", "è", "siamo", "siete", "sono"],
        "avere": ["ho", "hai", "ha", "abbiamo", "avete", "hanno"],
        "andare": ["vado", "vai", "va", "andiamo", "andate", "vanno"],
        "fare": ["faccio", "fai", "fa", "facciamo", "fate", "fanno"],
        "dire": ["dico", "dici", "dice", "diciamo", "dite", "dicono"],
        "dare": ["do", "dai", "dà", "diamo", "date", "danno"],
        "stare": ["sto", "stai", "sta", "stiamo", "state", "stanno"],
        "potere": ["posso", "puoi", "può", "possiamo", "potete", "possono"],
        "volere": ["voglio", "vuoi", "vuole", "vogliamo", "volete", "vogliono"],
        "dovere": ["devo", "devi", "deve", "dobbiamo", "dovete", "devono"],
        "venire": ["vengo", "vieni", "viene", "veniamo", "venite", "vengono"],
        "sapere": ["so", "sai", "sa", "sappiamo", "sapete", "sanno"],
        "uscire": ["esco", "esci", "esce", "usciamo", "uscite", "escono"],
        "bere": ["bevo", "bevi", "beve", "beviamo", "bevete", "bevono"],
        "tenere": ["tengo", "tieni", "tiene", "teniamo", "tenete", "tengono"],
        "rimanere": ["rimango", "rimani", "rimane", "rimaniamo", "rimanete", "rimangono"],
        "salire": ["salgo", "sali", "sale", "saliamo", "salite", "salgono"],
        "scegliere": ["scelgo", "scegli", "sceglie", "scegliamo", "scegliete", "scelgono"],
        "togliere": ["tolgo", "togli", "toglie", "togliamo", "togliete", "tolgono"],
        "tradurre": ["traduco", "traduci", "traduce", "traduciamo", "traducete", "traducono"],
        "morire": ["muoio", "muori", "muore", "moriamo", "morite", "muoiono"],
        "piacere": ["piaccio", "piaci", "piace", "piacciamo", "piacete", "piacciono"],
        "sedere": ["siedo", "siedi", "siede", "sediamo", "sedete", "siedono"],
        "porre": ["pongo", "poni", "pone", "poniamo", "ponete", "pongono"],
    ]

    /// -ire с вставкой -isc- в ударных формах: capire → capisco, capiamo.
    static let iscVerbs: Set<String> = [
        "capire", "finire", "preferire", "pulire", "spedire", "costruire", "restituire",
        "suggerire", "colpire", "fornire", "garantire", "gestire", "impedire", "inserire",
        "obbedire", "ubbidire", "proibire", "punire", "sparire", "sostituire", "stabilire",
        "tradire", "unire", "reagire", "agire", "chiarire", "definire", "diminuire",
        "distribuire", "favorire", "ferire", "guarire", "istruire", "riferire", "riunire",
        "trasferire", "contribuire", "attribuire", "digerire", "demolire", "condire",
        "arrossire", "dimagrire", "impazzire", "ingrandire", "approfondire", "abolire",
    ]

    static let irregularParticiples: [String: String] = [
        "essere": "stato", "stare": "stato", "fare": "fatto", "dire": "detto",
        "vedere": "visto", "prendere": "preso", "mettere": "messo", "scrivere": "scritto",
        "leggere": "letto", "aprire": "aperto", "bere": "bevuto", "venire": "venuto",
        "rimanere": "rimasto", "chiedere": "chiesto", "rispondere": "risposto",
        "chiudere": "chiuso", "decidere": "deciso", "perdere": "perso", "vivere": "vissuto",
        "morire": "morto", "nascere": "nato", "offrire": "offerto", "scegliere": "scelto",
        "spendere": "speso", "correre": "corso", "accendere": "acceso", "spegnere": "spento",
        "piangere": "pianto", "ridere": "riso", "rompere": "rotto", "scendere": "sceso",
        "succedere": "successo", "tradurre": "tradotto", "vincere": "vinto",
        "conoscere": "conosciuto", "piacere": "piaciuto", "dipingere": "dipinto",
        "discutere": "discusso", "muovere": "mosso", "nascondere": "nascosto",
        "togliere": "tolto", "cuocere": "cotto", "coprire": "coperto", "scoprire": "scoperto",
        "soffrire": "sofferto", "apparire": "apparso", "crescere": "cresciuto",
        "permettere": "permesso", "promettere": "promesso", "comprendere": "compreso",
        "sorprendere": "sorpreso", "produrre": "prodotto", "condurre": "condotto",
        "porre": "posto", "proporre": "proposto", "esprimere": "espresso",
        "raggiungere": "raggiunto", "dividere": "diviso", "convincere": "convinto",
        "assumere": "assunto", "mordere": "morso", "distruggere": "distrutto",
        "friggere": "fritto", "correggere": "corretto", "proteggere": "protetto",
        "sedere": "seduto", "tenere": "tenuto", "parere": "parso",
    ]

    /// Глаголы движения и состояния — с essere.
    static let takesEssere: Set<String> = [
        "andare", "venire", "arrivare", "partire", "tornare", "ritornare", "entrare",
        "uscire", "stare", "essere", "restare", "rimanere", "nascere", "morire",
        "diventare", "cadere", "salire", "scendere", "succedere", "piacere", "sembrare",
        "bastare", "costare", "durare", "riuscire", "apparire", "crescere", "sparire",
        "scappare", "fuggire", "accadere", "invecchiare", "dimagrire", "ingrassare",
    ]

    static func present(_ verb: String) -> [String]? {
        if let forms = irregularPresent[verb] { return forms }
        guard let (stem, ending) = split(verb) else { return nil }
        switch ending {
        case "are":
            // cercare → cerchi, cerchiamo: звук [k]/[g] сохраняется буквой h.
            let soft = stem.hasSuffix("c") || stem.hasSuffix("g") ? stem + "h" : stem
            // mangiare → mangi, mangiamo: двойное i не пишется.
            func withI(_ tail: String) -> String {
                stem.hasSuffix("i") ? stem + String(tail.dropFirst()) : soft + tail
            }
            return [stem + "o", withI("i"), stem + "a", withI("iamo"), stem + "ate", stem + "ano"]
        case "ere":
            return [stem + "o", stem + "i", stem + "e", stem + "iamo", stem + "ete", stem + "ono"]
        case "ire":
            if iscVerbs.contains(verb) {
                return [stem + "isco", stem + "isci", stem + "isce", stem + "iamo",
                        stem + "ite", stem + "iscono"]
            }
            return [stem + "o", stem + "i", stem + "e", stem + "iamo", stem + "ite", stem + "ono"]
        default:
            return nil
        }
    }

    static func participle(_ verb: String) -> String? {
        if let irregular = irregularParticiples[verb] { return irregular }
        guard let (stem, ending) = split(verb) else { return nil }
        switch ending {
        case "are": return stem + "ato"
        case "ere": return stem + "uto"
        case "ire": return stem + "ito"
        default: return nil
        }
    }

    static func split(_ verb: String) -> (String, String)? {
        guard verb.count >= 4 else { return nil }
        let ending = String(verb.suffix(3))
        guard ["are", "ere", "ire"].contains(ending) else { return nil }
        return (String(verb.dropLast(3)), ending)
    }
}

// MARK: - Английский

private enum English {
    static let irregularPast: [String: String] = [
        "have": "had", "do": "did", "go": "went", "get": "got", "make": "made",
        "say": "said", "see": "saw", "take": "took", "come": "came", "know": "knew",
        "think": "thought", "give": "gave", "find": "found", "tell": "told", "become": "became",
        "leave": "left", "feel": "felt", "bring": "brought", "begin": "began", "keep": "kept",
        "hold": "held", "write": "wrote", "stand": "stood", "hear": "heard", "let": "let",
        "mean": "meant", "set": "set", "meet": "met", "run": "ran", "pay": "paid", "sit": "sat",
        "speak": "spoke", "lie": "lay", "lead": "led", "read": "read", "grow": "grew",
        "lose": "lost", "fall": "fell", "send": "sent", "build": "built", "understand": "understood",
        "draw": "drew", "break": "broke", "spend": "spent", "cut": "cut", "rise": "rose",
        "drive": "drove", "buy": "bought", "wear": "wore", "choose": "chose", "eat": "ate",
        "drink": "drank", "sleep": "slept", "sing": "sang", "swim": "swam", "fly": "flew",
        "forget": "forgot", "forgive": "forgave", "hide": "hid", "hit": "hit", "hurt": "hurt",
        "put": "put", "quit": "quit", "shut": "shut", "sell": "sold", "shoot": "shot",
        "show": "showed", "steal": "stole", "teach": "taught", "catch": "caught",
        "fight": "fought", "throw": "threw", "wake": "woke", "win": "won", "ride": "rode",
        "ring": "rang", "seek": "sought", "shake": "shook", "shine": "shone", "sink": "sank",
        "deal": "dealt", "dig": "dug", "feed": "fed", "freeze": "froze", "hang": "hung",
        "lend": "lent", "light": "lit", "bite": "bit", "blow": "blew", "bend": "bent",
        "bet": "bet", "bleed": "bled", "breed": "bred", "burst": "burst", "cost": "cost",
        "creep": "crept", "flee": "fled", "kneel": "knelt", "lay": "laid", "slide": "slid",
        "spin": "spun", "spit": "spat", "split": "split", "spread": "spread", "stick": "stuck",
        "sting": "stung", "strike": "struck", "swear": "swore", "sweep": "swept",
        "swing": "swung", "tear": "tore", "weep": "wept", "withdraw": "withdrew",
        "undertake": "undertook", "overcome": "overcame", "upset": "upset", "arise": "arose",
        "awake": "awoke", "bear": "bore", "bind": "bound", "forbid": "forbade",
    ]

    static func forms(_ verb: String, tense: Tense) -> [String]? {
        guard verb.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
        switch tense {
        case .present:
            if verb == "be" { return ["am", "are", "is", "are", "are"] }
            let third = verb == "have" ? "has" : thirdPerson(verb)
            return [verb, verb, third, verb, verb]
        case .past:
            if verb == "be" { return ["was", "were", "was", "were", "were"] }
            let past = irregularPast[verb] ?? regularPast(verb)
            return Array(repeating: past, count: 5)
        }
    }

    static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

    static func thirdPerson(_ verb: String) -> String {
        if ["s", "x", "z", "o"].contains(where: { verb.hasSuffix($0) })
            || verb.hasSuffix("ch") || verb.hasSuffix("sh") {
            return verb + "es"
        }
        if endsWithConsonantY(verb) { return String(verb.dropLast()) + "ies" }
        return verb + "s"
    }

    static func regularPast(_ verb: String) -> String {
        if verb.hasSuffix("e") { return verb + "d" }
        if endsWithConsonantY(verb) { return String(verb.dropLast()) + "ied" }
        // stop → stopped: один слог, согласная-гласная-согласная (кроме w, x, y).
        let letters = Array(verb)
        if letters.count >= 3, syllables(verb) == 1,
           let last = letters.last, !vowels.contains(last), !"wxy".contains(last),
           vowels.contains(letters[letters.count - 2]),
           !vowels.contains(letters[letters.count - 3]) {
            return verb + String(last) + "ed"
        }
        return verb + "ed"
    }

    static func endsWithConsonantY(_ verb: String) -> Bool {
        let letters = Array(verb)
        guard letters.count >= 2, letters.last == "y" else { return false }
        return !vowels.contains(letters[letters.count - 2])
    }

    /// Группы гласных — грубая, но достаточная оценка числа слогов.
    static func syllables(_ verb: String) -> Int {
        var count = 0
        var previousVowel = false
        for letter in verb {
            let vowel = vowels.contains(letter)
            if vowel && !previousVowel { count += 1 }
            previousVowel = vowel
        }
        return count
    }
}
