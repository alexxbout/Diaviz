//
//  GenerateurDemo.swift
//  diaviz
//
//  Jeu de données FICTIF de l'app « Diaviz Démo » (captures du README) et
//  des aperçus de développement. Aucune donnée réelle : une personne
//  inventée (Camille), ~3 mois simulés à partir d'un petit modèle
//  physiologique (glucides, insuline, lente, sport, bruit capteur).
//
//  Reproductible : même ancre → même jeu, octet pour octet. Le hasard est un
//  SplitMix64 seedé par jour (index relatif à l'ancre), jamais l'horloge.
//
//  L'histoire racontée (voir `docs/Mode démo.md`) :
//  - J-89 → J-35 : charge habituelle, lente 18 u adaptée, nuits stables ;
//  - J-34 → aujourd'hui : préparation d'un semi-marathon, charge haute,
//    sensibilité accrue → nuits qui descendent, une nuit avec hypo (J-31) ;
//  - J-28 : lente baissée 18 → 16 u ; J-21 : ratio du dîner 10 → 12 g/u ;
//  - petit-déjeuner un peu sous-dosé par le ratio configuré (écart R1),
//    déjeuner bien calibré, pizza du vendredi récurrente hors cible
//    (« Repas à revoir »), dessert pris 40 min après certains déjeuners
//    (repas rapprochés écartés), séances Apple Watch avec FC.
//

#if DEBUG
import Foundation

// MARK: - Hasard reproductible

/// SplitMix64 : petit, rapide, et surtout stable d'une version de Swift à
/// l'autre (contrairement à `SystemRandomNumberGenerator`, non seedable).
nonisolated struct HasardDemo {
    private var etat: UInt64

    init(graine: UInt64) { etat = graine }

    mutating func suivant() -> UInt64 {
        etat &+= 0x9E37_79B9_7F4A_7C15
        var z = etat
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniforme dans [0, 1).
    mutating func uniforme() -> Double { Double(suivant() >> 11) / Double(1 << 53) }

    mutating func entre(_ a: Double, _ b: Double) -> Double { a + (b - a) * uniforme() }

    mutating func chance(_ p: Double) -> Bool { uniforme() < p }

    /// Loi normale (Box-Muller).
    mutating func normale(_ moyenne: Double, _ ecart: Double) -> Double {
        let u1 = max(uniforme(), 1e-12), u2 = uniforme()
        return moyenne + ecart * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    mutating func choix<T>(_ options: [T]) -> T { options[Int(suivant() % UInt64(options.count))] }
}

// MARK: - Jeu de données

/// Faits bruts du jeu fictif, indépendants de SwiftData : testables tels
/// quels, puis insérés dans le hub par `JeuDemo.inserer(dans:)`.
struct JeuDemo {

    struct AlimentDemo: Equatable {
        let emoji: String
        let nom: String
        let quantite: Int
        let glucides: Int
    }

    enum Moment: CaseIterable { case petitDejeuner, dejeuner, gouter, diner }

    struct RepasDemo {
        let id: UUID
        let heure: Date
        let moment: Moment
        let aliments: [AlimentDemo]
        /// Bolus repas réellement injecté (u).
        let dose: Double
        /// Repas gras (pizza) : absorption lente et résistance transitoire.
        let gras: Bool
        /// Ratio sport appliqué (repas dans la fenêtre après une séance).
        let apresSport: TypeSport?
        var glucides: Int { aliments.reduce(0) { $0 + $1.glucides } }
    }

    struct InjectionDemo {
        let id: UUID
        let type: TypeInsuline
        let dose: Double
        let heure: Date
        let glycemie: Double?
        let repasId: UUID?
    }

    struct ResucrageDemo {
        let id: UUID
        let date: Date
        let aliment: AlimentDemo
        let glycemie: Double
    }

    struct SeanceDemo {
        let id: UUID
        let workoutUUID: UUID
        let type: TypeSport
        let debut: Date
        let dureeMinutes: Int
        let intensite: IntensiteSport
        let fcMoyenne: Double
        /// Pic soutenu de FC (60 s), ce que `CalculFCMax` retient.
        let fcPic: Double
        let calories: Double
        let distanceMetres: Double?
        /// `HKWorkoutActivityType.rawValue` (running 37, cycling 13,
        /// traditionalStrengthTraining 50).
        let typeActiviteHK: UInt
        var fin: Date { debut.addingTimeInterval(TimeInterval(dureeMinutes * 60)) }
    }

    struct MarcheDemo {
        let debut: Date
        let fin: Date
        /// Pas par minute pendant le bout.
        let cadence: Double
    }

    struct StadeSommeilDemo {
        let stade: SleepStage
        let debut: Date
        let fin: Date
    }

    struct ChangementRatioDemo {
        let date: Date
        let parametre: ParametreSuivi
        let ancien: Double
        let nouveau: Double
    }

    let ancre: Date
    let debut: Date
    var glycemies: [(date: Date, valeur: Int)] = []
    var repas: [RepasDemo] = []
    var injections: [InjectionDemo] = []
    var resucrages: [ResucrageDemo] = []
    var seances: [SeanceDemo] = []
    var marches: [MarcheDemo] = []
    var sommeil: [StadeSommeilDemo] = []
    var changements: [ChangementRatioDemo] = []

    // MARK: Profil fictif

    static let prenom = "Camille"
    static let ratiosConfigures = (petitDejeuner: 8.0, dejeuner: 12.0, gouter: 15.0, dinerAvant: 10.0, dinerApres: 12.0)
    static let ratioCorrection = 40.0
    static let ratioSportCourse = 15.0
    static let lenteAvant = 18.0
    static let lenteApres = 16.0

    /// Jours relatifs à l'ancre (0 = aujourd'hui).
    static let nombreJours = 90
    static let debutChargeHaute = -34
    static let jourChangementLente = -28
    static let jourChangementRatioDiner = -21
    static let jourNuitHypo = -31
}

// MARK: - Générateur

enum GenerateurDemo {

    static let graine: UInt64 = 0xD1A7_1200_5EED_0001

    /// Génère le jeu complet. `ancre` = « maintenant » : rien n'est produit
    /// après elle (le jour en cours s'arrête à l'heure de la génération).
    static func generer(ancre: Date, calendrier: Calendar = .current) -> JeuDemo {
        let cal = calendrier
        let aujourdhui = cal.startOfDay(for: ancre)
        let debut = cal.date(byAdding: .day, value: -(JeuDemo.nombreJours - 1), to: aujourdhui)!
        var jeu = JeuDemo(ancre: ancre, debut: debut)

        // 1. Événements planifiés, jour par jour.
        var planifies: [Planifie] = []
        var derives: [Int: Double] = [:]
        for j in -(JeuDemo.nombreJours - 1)...0 {
            let jour = cal.date(byAdding: .day, value: j, to: aujourdhui)!
            planifier(cal, jour: jour, index: j, dans: &jeu, planifies: &planifies, derives: &derives)
        }
        planifies.sort { $0.date < $1.date }
        let jourRatio = cal.date(byAdding: .day, value: JeuDemo.jourChangementRatioDiner, to: aujourdhui)!
        jeu.changements = [.init(
            date: jourRatio.addingTimeInterval(18 * 3600), parametre: .ratioDiner,
            ancien: JeuDemo.ratiosConfigures.dinerAvant, nouveau: JeuDemo.ratiosConfigures.dinerApres
        )]

        // 2. Simulation causale de la glycémie, pas de 5 min, avec les
        //    réactions (corrections, resucrages) qui en découlent.
        simuler(&jeu, planifies: planifies, derives: derives, calendrier: cal)

        // 3. Sommeil (après la simulation : les réveils de resucrage y
        //    figurent).
        genererSommeil(&jeu, calendrier: cal)

        // Rien après l'ancre.
        jeu.repas.removeAll { $0.heure > ancre }
        jeu.injections.removeAll { $0.heure > ancre }
        jeu.seances.removeAll { $0.fin > ancre }
        jeu.marches.removeAll { $0.fin > ancre }
        jeu.sommeil.removeAll { $0.fin > ancre }
        jeu.injections.sort { $0.heure < $1.heure }
        jeu.repas.sort { $0.heure < $1.heure }
        return jeu
    }

    // MARK: Planification

    /// Effet glycémique planifié, connu d'avance (repas, bolus, lente, sport).
    fileprivate struct Planifie {
        enum Nature {
            /// `persistance` : minutes avant que l'effet commence à s'éteindre.
            case repas(glucides: Double, csf: Double, tau: Double, persistance: Double)
            case insuline(dose: Double, isf: Double)
            case sport(amplitude: Double, duree: Double)
        }
        let date: Date
        let nature: Nature
    }

    fileprivate struct Physiologie {
        let isf: Double
        let ratioVrai: [JeuDemo.Moment: Double]
        let besoinLente: Double
    }

    fileprivate static func physiologie(index j: Int) -> Physiologie {
        let haute = j >= JeuDemo.debutChargeHaute
        return Physiologie(
            isf: haute ? 46 : 40,
            ratioVrai: [
                .petitDejeuner: haute ? 7.2 : 6.9,
                .dejeuner: haute ? 12.5 : 12,
                .gouter: haute ? 16 : 15,
                .diner: haute ? 12.4 : 10,
            ],
            besoinLente: haute ? 15.6 : 18
        )
    }

    static func ratioConfigure(_ moment: JeuDemo.Moment, index j: Int) -> Double {
        switch moment {
        case .petitDejeuner: JeuDemo.ratiosConfigures.petitDejeuner
        case .dejeuner: JeuDemo.ratiosConfigures.dejeuner
        case .gouter: JeuDemo.ratiosConfigures.gouter
        case .diner: j >= JeuDemo.jourChangementRatioDiner
            ? JeuDemo.ratiosConfigures.dinerApres : JeuDemo.ratiosConfigures.dinerAvant
        }
    }

    static func doseLente(index j: Int) -> Double {
        j >= JeuDemo.jourChangementLente ? JeuDemo.lenteApres : JeuDemo.lenteAvant
    }

    /// Heure murale `h` (décimale, peut dépasser 24) du jour `jour` : par le
    /// calendrier, pour rester juste les jours de changement d'heure.
    static func heure(_ cal: Calendar, _ jour: Date, _ h: Double) -> Date {
        let jours = Int(floor(h / 24))
        let reste = h - Double(jours) * 24
        let minutes = Int((reste * 60).rounded())
        let base = cal.date(byAdding: .day, value: jours, to: jour)!
        return cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: base)!
    }

    private static func arrondiDemi(_ x: Double) -> Double { max(0.5, (x * 2).rounded() / 2) }

    private static func varier(_ a: JeuDemo.AlimentDemo, _ h: inout HasardDemo, amplitude: Double = 0.1) -> JeuDemo.AlimentDemo {
        let f = 1 + h.entre(-amplitude, amplitude)
        return .init(emoji: a.emoji, nom: a.nom, quantite: Int((Double(a.quantite) * f).rounded()),
                     glucides: Int((Double(a.glucides) * f).rounded()))
    }

    // Menus (glucides pour la quantité indiquée).
    private static let petitsDejeuners: [[JeuDemo.AlimentDemo]] = [
        [.init(emoji: "🥖", nom: "Pain complet", quantite: 80, glucides: 34),
         .init(emoji: "🍓", nom: "Confiture de fraise", quantite: 20, glucides: 12),
         .init(emoji: "🧈", nom: "Beurre", quantite: 10, glucides: 0)],
        [.init(emoji: "🥣", nom: "Muesli", quantite: 60, glucides: 38),
         .init(emoji: "🥛", nom: "Lait demi-écrémé", quantite: 200, glucides: 10)],
        [.init(emoji: "🍞", nom: "Tartines de pain de mie", quantite: 60, glucides: 29),
         .init(emoji: "🍌", nom: "Banane", quantite: 110, glucides: 22)],
    ]

    private static let dejeuners: [[JeuDemo.AlimentDemo]] = [
        [.init(emoji: "🍚", nom: "Riz basmati cuit", quantite: 180, glucides: 50),
         .init(emoji: "🍗", nom: "Poulet rôti", quantite: 120, glucides: 0),
         .init(emoji: "🥦", nom: "Brocolis", quantite: 150, glucides: 4)],
        [.init(emoji: "🥗", nom: "Salade de lentilles", quantite: 250, glucides: 38),
         .init(emoji: "🥖", nom: "Baguette", quantite: 40, glucides: 22)],
        [.init(emoji: "🥪", nom: "Sandwich jambon-beurre", quantite: 200, glucides: 58),
         .init(emoji: "🍎", nom: "Pomme", quantite: 150, glucides: 18)],
        [.init(emoji: "🍝", nom: "Pâtes complètes cuites", quantite: 200, glucides: 52),
         .init(emoji: "🐟", nom: "Saumon", quantite: 120, glucides: 0)],
        [.init(emoji: "🍲", nom: "Chili con carne", quantite: 300, glucides: 42),
         .init(emoji: "🍚", nom: "Riz basmati cuit", quantite: 100, glucides: 28)],
    ]

    private static let diners: [[JeuDemo.AlimentDemo]] = [
        [.init(emoji: "🥔", nom: "Pommes de terre vapeur", quantite: 250, glucides: 42),
         .init(emoji: "🥩", nom: "Steak haché", quantite: 125, glucides: 0)],
        [.init(emoji: "🍜", nom: "Soupe de légumes", quantite: 350, glucides: 18),
         .init(emoji: "🥖", nom: "Baguette", quantite: 60, glucides: 33)],
        [.init(emoji: "🍛", nom: "Curry de pois chiches", quantite: 300, glucides: 40),
         .init(emoji: "🍚", nom: "Riz basmati cuit", quantite: 120, glucides: 33)],
        [.init(emoji: "🥚", nom: "Omelette", quantite: 150, glucides: 1),
         .init(emoji: "🍞", nom: "Pain complet", quantite: 80, glucides: 34),
         .init(emoji: "🥗", nom: "Salade verte", quantite: 80, glucides: 2)],
    ]

    static let pizza = JeuDemo.AlimentDemo(emoji: "🍕", nom: "Pizza margherita", quantite: 330, glucides: 92)
    static let dessert = JeuDemo.AlimentDemo(emoji: "🥧", nom: "Tarte aux pommes", quantite: 90, glucides: 28)
    private static let gouter: [JeuDemo.AlimentDemo] = [
        .init(emoji: "🍎", nom: "Pomme", quantite: 150, glucides: 18),
        .init(emoji: "🍪", nom: "Biscuits sablés", quantite: 25, glucides: 17),
    ]
    private static let resucrages: [JeuDemo.AlimentDemo] = [
        .init(emoji: "🧃", nom: "Jus d'orange", quantite: 150, glucides: 15),
        .init(emoji: "🍬", nom: "Morceaux de sucre", quantite: 15, glucides: 15),
    ]

    /// « Jour de la semaine » fictif, dérivé de l'index pour que le jeu ne
    /// dépende pas du jour réel de génération (5 et 6 = week-end).
    static func jourSemaine(_ j: Int) -> Int { ((j % 7) + 7) % 7 }

    private static func planifier(_ cal: Calendar, jour: Date, index j: Int, dans jeu: inout JeuDemo, planifies: inout [Planifie], derives: inout [Int: Double]) {
        var h = HasardDemo(graine: graine ^ UInt64(bitPattern: Int64(j + 1000)) &* 0x2545_F491_4F6C_DD1D)
        let phys = physiologie(index: j)
        let haute = j >= JeuDemo.debutChargeHaute
        let w = jourSemaine(j)
        let weekend = w >= 5
        let aujourdhui = j == 0

        // Séances (avant les repas : un repas dans les 3 h suivant une course
        // prend le ratio sport).
        var seancesDuJour: [JeuDemo.SeanceDemo] = []
        func seance(_ type: TypeSport, _ h0: Double, _ duree: Int, _ intensite: IntensiteSport) {
            let (fc, hk, vitesse): (Double, UInt, Double?) = switch type {
            case .course: (intensite == .intense ? 166 : 151, 37, 10.6)
            case .velo: (138, 13, 24)
            default: (118, 50, nil)
            }
            let fcMoy = (fc + h.normale(0, 3)).rounded()
            let pic = (fcMoy + (type == .musculation ? 30 : 20) + h.entre(-2, 4)).rounded()
            let s = JeuDemo.SeanceDemo(
                id: uuid(&h), workoutUUID: uuid(&h), type: type,
                debut: heure(cal, jour, h0 + h.entre(-0.15, 0.15)), dureeMinutes: duree, intensite: intensite,
                fcMoyenne: fcMoy, fcPic: min(pic, 189), calories: Double(duree) * (type == .musculation ? 6 : 10.5),
                distanceMetres: vitesse.map { ($0 * Double(duree) / 60 * 1000).rounded() }, typeActiviteHK: hk
            )
            seancesDuJour.append(s)
            let amplitude: Double = switch intensite { case .faible: 20; case .moderee: 38; case .intense: 55 }
            let facteurType = type == .musculation ? 0.3 : 1
            planifies.append(.init(date: s.debut, nature: .sport(
                amplitude: amplitude * facteurType * min(1.6, Double(duree) / 45), duree: Double(duree)
            )))
        }
        if !aujourdhui {
            if haute {
                if [1, 3].contains(w) { seance(.course, 18, 50, w == 3 ? .intense : .moderee) }
                if w == 6 { seance(.course, 9.5, j == -6 || j == -13 ? 105 : 80, .moderee) }
                if w == 2 { seance(.musculation, 18.25, 45, .moderee) }
                if w == 5 { seance(.velo, 10, 90, .moderee) }
            } else {
                if w == 1 { seance(.course, 18, 45, .moderee) }
                if w == 4, j % 14 != 0 { seance(.musculation, 18.25, 45, .moderee) }
                if w == 6, h.chance(0.5) { seance(.velo, 10, 75, .faible) }
            }
        }
        jeu.seances += seancesDuJour

        // Marche (bouts ≥ 10 min à ≥ 100 pas/min).
        func marche(_ h0: Double, _ minutes: Double) {
            let d = heure(cal, jour, h0 + h.entre(-0.1, 0.1))
            jeu.marches.append(.init(debut: d, fin: d.addingTimeInterval(minutes * 60), cadence: h.entre(106, 118)))
        }
        if weekend {
            marche(11, h.entre(35, 60))
        } else {
            marche(8.35, h.entre(15, 20))
            marche(17.6, h.entre(15, 22))
        }
        if haute { marche(13.2, h.entre(14, 20)) }

        // Lente, la veille au soir pour la nuit qui suit.
        let doseLente = doseLente(index: j)
        let heureLente = heure(cal, jour, 22.5 + h.entre(-0.25, 0.25))
        jeu.injections.append(.init(id: uuid(&h), type: .lente, dose: doseLente, heure: heureLente, glycemie: nil, repasId: nil))

        // Repas.
        func repas(_ moment: JeuDemo.Moment, _ h0: Double, _ aliments: [JeuDemo.AlimentDemo],
                   gras: Double? = nil, ecartDose: Double? = nil) {
            let date = heure(cal, jour, h0)
            let glucides = Double(aliments.reduce(0) { $0 + $1.glucides })
            let course = seancesDuJour.first { $0.type == .course && date > $0.fin && date.timeIntervalSince($0.fin) < 3 * 3600 }
            let ratio = course != nil ? JeuDemo.ratioSportCourse : ratioConfigure(moment, index: j)
            let ecart = ecartDose ?? h.normale(0, 0.13)
            let dose = arrondiDemi(glucides / ratio * (1 + ecart))
            let r = JeuDemo.RepasDemo(id: uuid(&h), heure: date, moment: moment, aliments: aliments,
                                      dose: dose, gras: gras != nil, apresSport: course?.type)
            jeu.repas.append(r)
            jeu.injections.append(.init(id: uuid(&h), type: .rapideRepas, dose: dose, heure: date, glycemie: nil, repasId: r.id))
            var ratioVrai = phys.ratioVrai[moment]!
            if course != nil { ratioVrai *= 1.25 }
            // Repas gras : absorption lente et résistance transitoire (`gras`
            // = multiplicateur de l'effet des glucides).
            let csf = phys.isf / ratioVrai * (gras ?? 1)
            planifies.append(.init(date: date, nature: .repas(
                glucides: glucides, csf: csf, tau: gras != nil ? 75 : 36, persistance: gras != nil ? 330 : 240
            )))
            planifies.append(.init(date: date, nature: .insuline(dose: dose, isf: phys.isf)))
        }

        let pdj = petitsDejeuners[j == 0 ? 1 : (abs(j) % 5 == 0 ? 2 : abs(j) % 2)].map { varier($0, &h) }
        repas(.petitDejeuner, (weekend ? 8.7 : 7.2) + h.entre(-0.3, 0.3), pdj,
              ecartDose: aujourdhui ? 0.12 : nil)

        let dej = dejeuners[Int(h.suivant() % UInt64(dejeuners.count))].map { varier($0, &h) }
        let heureDej = 12.5 + h.entre(-0.3, 0.3)
        repas(.dejeuner, heureDej, dej, ecartDose: aujourdhui ? 0.02 : nil)
        // Dessert pris à part 40 min plus tard : repas rapprochés, écartés.
        if w == 2, !aujourdhui {
            repas(.dejeuner, heureDej + 0.67, [varier(dessert, &h, amplitude: 0.05)])
        }

        if j % 4 == 0, !aujourdhui { repas(.gouter, 16.5 + h.entre(-0.2, 0.3), gouter.map { varier($0, &h) }) }

        // Pizza du vendredi : hors cible le plus souvent, toujours la dernière.
        if w == 4, !aujourdhui {
            // La dernière pizza (J-3) est franchement hors cible ; les
            // précédentes varient, pour un « N fois sur M » honnête.
            let resistance = j == -3 ? 1.65 : h.entre(1.0, 1.7)
            repas(.diner, 20 + h.entre(-0.2, 0.2), [varier(pizza, &h, amplitude: 0.04)],
                  gras: resistance, ecartDose: h.normale(0, 0.04))
        } else if !aujourdhui {
            let diner = diners[Int(h.suivant() % UInt64(diners.count))].map { varier($0, &h) }
            repas(.diner, 19.75 + h.entre(-0.3, 0.3), diner)
        } else {
            repas(.diner, 19.75, diners[0])
        }

        // Lente : effet de nuit = écart dose / besoin (simulé dans la
        // dérive de `simuler`), mémorisé par jour.
        // Dérive nocturne (mg/dL par heure) de la nuit qui suit : écart
        // entre la dose de lente et le besoin du moment. La nuit J-31 est
        // forcée plus raide (la nuit avec hypo de l'histoire).
        derives[j] = j == JeuDemo.jourNuitHypo ? -13 : (doseLente - phys.besoinLente) * -2.5
    }

    private static func uuid(_ h: inout HasardDemo) -> UUID {
        let a = h.suivant(), b = h.suivant()
        var octets = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { octets[i] = UInt8(truncatingIfNeeded: a >> (8 * UInt64(i))) }
        for i in 0..<8 { octets[8 + i] = UInt8(truncatingIfNeeded: b >> (8 * UInt64(i))) }
        octets[6] = (octets[6] & 0x0F) | 0x40
        octets[8] = (octets[8] & 0x3F) | 0x80
        return UUID(uuid: (octets[0], octets[1], octets[2], octets[3], octets[4], octets[5], octets[6], octets[7],
                           octets[8], octets[9], octets[10], octets[11], octets[12], octets[13], octets[14], octets[15]))
    }

    // MARK: Simulation glycémique

    /// Montée cumulée normalisée (0 → 1) d'une absorption de constante `tau`.
    private static func cumul(_ minutes: Double, tau: Double) -> Double {
        guard minutes > 0 else { return 0 }
        let x = minutes / tau
        return 1 - (1 + x) * exp(-x)
    }

    /// Après 4 h, l'effet résiduel d'un événement s'éteint (régulation non
    /// modélisée) : sans ça, chaque petit écart s'accumulerait sur des jours.
    private static func extinction(_ minutes: Double) -> Double {
        minutes <= 240 ? 1 : exp(-(minutes - 240) / 150)
    }

    private static func effet(_ p: Planifie, a t: Date) -> Double {
        let m = t.timeIntervalSince(p.date) / 60
        guard m > 0 else { return 0 }
        let e = extinction(m)
        switch p.nature {
        case let .repas(g, csf, tau, persistance):
            let eRepas = m <= persistance ? 1 : exp(-(m - persistance) / 150)
            return g * csf * cumul(m, tau: tau) * eRepas
        case let .insuline(dose, isf): return -dose * isf * cumul(m, tau: 55) * e
        case let .sport(amplitude, duree):
            let montee = min(1, m / duree)
            let apres = m > duree ? exp(-(m - duree) / 140) : 1
            return -amplitude * montee * apres
        }
    }

    private static func simuler(_ jeu: inout JeuDemo, planifies: [Planifie], derives: [Int: Double], calendrier cal: Calendar) {
        var h = HasardDemo(graine: graine ^ 0xC0FFEE)
        var actifs: [Planifie] = []
        var prochain = 0
        var bruit = 0.0
        var deriveCourante = 0.0
        var dernierRepasOuBolus = Date.distantPast
        var derniereCorrection = Date.distantPast
        var dernierResucrage = Date.distantPast
        let pas: TimeInterval = 300
        let fin = jeu.ancre.addingTimeInterval(-600)
        var t = jeu.debut
        let aujourdhui = cal.startOfDay(for: jeu.ancre)

        while t <= fin {
            while prochain < planifies.count, planifies[prochain].date <= t {
                let p = planifies[prochain]
                actifs.append(p)
                if case .insuline = p.nature { dernierRepasOuBolus = p.date }
                prochain += 1
            }
            actifs.removeAll { t.timeIntervalSince($0.date) > 14 * 3600 }

            // Index du jour dont la nuit est en cours (la nuit de J va de
            // J 23 h à J+1 7 h).
            let debutJour = cal.startOfDay(for: t)
            let comp = cal.dateComponents([.hour, .minute], from: t)
            let heureJ = Double(comp.hour ?? 0) + Double(comp.minute ?? 0) / 60
            let jour = cal.dateComponents([.day], from: aujourdhui, to: debutJour).day ?? 0
            let nuitDe = heureJ < 12 ? jour - 1 : jour
            let pente = derives[nuitDe] ?? 0
            let enNuit = heureJ >= 23 || heureJ < 7
            if enNuit {
                deriveCourante += pente * pas / 3600
            } else {
                deriveCourante -= deriveCourante * (pas / 3600) / 1.5
            }

            bruit = 0.9 * bruit + h.normale(0, jour == 0 ? 2.2 : 3.4)
            var g = 118 + deriveCourante + bruit + actifs.reduce(0) { $0 + effet($1, a: t) }
            // Phénomène de l'aube, léger.
            if heureJ >= 5, heureJ < 8 { g += 6 * sin((heureJ - 5) / 3 * .pi) }
            g = min(400, max(40, g))

            // Trou capteur (changement tous les 10 jours, 2 h).
            let trou = (((jour % 10) + 10) % 10 == 3) && heureJ >= 9 && heureJ < 11
            if !trou { jeu.glycemies.append((t, Int(g.rounded()))) }

            let eveille = heureJ >= 7 && heureJ < 23.25
            let phys = physiologie(index: jour)

            // Resucrage sous 70 (la nuit aussi : réveil).
            if g < 70, t.timeIntervalSince(dernierResucrage) > 40 * 60 {
                let aliment = h.choix(resucrages)
                jeu.resucrages.append(.init(id: uuid(&h), date: t, aliment: aliment, glycemie: g.rounded()))
                let p = Planifie(date: t, nature: .repas(glucides: Double(aliment.glucides), csf: phys.isf / 9, tau: 14, persistance: 240))
                actifs.append(p)
                dernierResucrage = t
            }

            // Correction : éveillé, > 240, loin du dernier bolus.
            if eveille, g > 240, jour != 0,
               t.timeIntervalSince(dernierRepasOuBolus) > 2.5 * 3600,
               t.timeIntervalSince(derniereCorrection) > 3 * 3600,
               h.chance(0.35) {
                let dose = arrondiDemi((g - 130) / JeuDemo.ratioCorrection)
                jeu.injections.append(.init(id: uuid(&h), type: .rapideCorrection, dose: dose, heure: t, glycemie: g.rounded(), repasId: nil))
                actifs.append(.init(date: t, nature: .insuline(dose: dose, isf: phys.isf)))
                derniereCorrection = t
                dernierRepasOuBolus = t
            }
            t = t.addingTimeInterval(pas)
        }
    }

    // MARK: Sommeil

    private static func genererSommeil(_ jeu: inout JeuDemo, calendrier cal: Calendar) {
        let lentes = jeu.injections.filter { $0.type == .lente }
        for lente in lentes {
            let jour = cal.startOfDay(for: lente.heure)
            let j = cal.dateComponents([.day], from: cal.startOfDay(for: jeu.ancre), to: jour).day ?? 0
            var h = HasardDemo(graine: graine ^ UInt64(bitPattern: Int64(j + 5000)) &* 0x9E37)
            let coucher = lente.heure.addingTimeInterval(h.entre(20, 45) * 60)
            let weekendLendemain = jourSemaine(j + 1) >= 5
            let lever = heure(cal, jour, 24 + (weekendLendemain ? 8.25 : 6.85) + h.entre(-0.25, 0.25))
            let reveils = jeu.resucrages.filter { $0.date > coucher && $0.date < lever }.map(\.date)

            var stades: [JeuDemo.StadeSommeilDemo] = []
            var t = coucher
            func ajouter(_ s: SleepStage, _ minutes: Double) {
                let f = min(lever, t.addingTimeInterval(minutes * 60))
                guard f > t else { return }
                stades.append(.init(stade: s, debut: t, fin: f))
                t = f
            }
            ajouter(.awake, h.entre(6, 15))
            var cycle = 0
            while t < lever {
                if let r = reveils.first(where: { $0 >= t.addingTimeInterval(-300) && $0 < t.addingTimeInterval(95 * 60) }), r > t {
                    // Réveil du resucrage : on dort jusqu'à 5 min avant.
                    ajouter(.core, max(0, r.timeIntervalSince(t) / 60 - 5))
                    ajouter(.awake, h.entre(18, 28))
                    continue
                }
                let profondeur = max(5, 32 - Double(cycle) * 7)
                ajouter(.core, h.entre(20, 30))
                ajouter(.deep, profondeur + h.entre(-4, 4))
                ajouter(.core, h.entre(15, 25))
                ajouter(.rem, 12 + Double(cycle) * 5 + h.entre(-3, 3))
                if h.chance(0.25) { ajouter(.awake, h.entre(2, 6)) }
                cycle += 1
            }
            jeu.sommeil += stades
        }
    }
}

// MARK: - Lectures de remplacement (sommeil, charge)

extension JeuDemo {

    /// Stades de sommeil chevauchant `plage` (marge d'1 h, comme la lecture
    /// Apple Santé).
    func stades(sur plage: ClosedRange<Date>) -> [SleepStageInterval] {
        let debut = plage.lowerBound.addingTimeInterval(-3600)
        let fin = plage.upperBound.addingTimeInterval(3600)
        return sommeil
            .filter { $0.fin > debut && $0.debut < fin }
            .map { SleepStageInterval(stage: $0.stade, debut: $0.debut, fin: $0.fin) }
    }
}

/// Faits « Apple Santé » du jeu démo, figés en types `Sendable` pour les
/// lecteurs de remplacement (appelés hors du MainActor).
nonisolated struct FaitsSanteDemo: Sendable {
    let debut: Date
    let workouts: [WorkoutPourCharge]
    let pics: [UUID: Double]
    let marches: [DateInterval]
    let cadences: [Double]
    let sommeil: [(stade: SleepStage, debut: Date, fin: Date)]

    func pas(minute: Date) -> Double {
        if let i = marches.firstIndex(where: { $0.start <= minute && minute < $0.end }) { return cadences[i] }
        let s = Int(minute.timeIntervalSince1970 / 60)
        let heureJ = Double(((s % 1440) + 1440) % 1440) / 60
        guard heureJ >= 7.5, heureJ < 22 else { return 0 }
        let bruit = (s &* 2_654_435_761) & 0xFF
        return bruit < 40 ? Double(bruit % 35) : 0
    }
}

extension JeuDemo {
    var faitsSante: FaitsSanteDemo {
        FaitsSanteDemo(
            debut: debut,
            workouts: seances.map {
                WorkoutPourCharge(uuid: $0.workoutUUID, intervalle: DateInterval(start: $0.debut, end: $0.fin),
                                  typeActiviteHK: $0.typeActiviteHK, fcMoyenne: $0.fcMoyenne)
            },
            pics: Dictionary(uniqueKeysWithValues: seances.map { ($0.workoutUUID, $0.fcPic) }),
            marches: marches.map { DateInterval(start: $0.debut, end: $0.fin) },
            cadences: marches.map(\.cadence),
            sommeil: sommeil.map { ($0.stade, $0.debut, $0.fin) }
        )
    }
}
#endif
