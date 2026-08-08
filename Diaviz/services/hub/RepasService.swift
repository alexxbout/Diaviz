//
//  RepasService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service du domaine Repas, branché sur le hub SwiftData. Lit et écrit
/// réellement les `Repas` (fait brut horodaté + ses `Aliment`).
///
/// Pattern de démarrage aligné sur `InjectionsService` : la vue crée le
/// service vide puis lui passe le `ModelContext` de l'environnement via `.task`.
/// Le service garde le contexte, recharge `repas` après chaque mutation et
/// l'expose en `@Observable` pour rafraîchir la vue.
///
/// « Un hub, des dérivations » : le service ne persiste que des faits bruts.
/// La réponse glycémique d'un repas (`Repas.etatAnalyse`) est une dérivation
/// `@Transient` — laissée à `nil` côté hub (aucun assembleur CGM branché pour
/// l'instant).
@Observable
@MainActor
final class RepasService {

    /// Contexte du hub, fourni au démarrage. `nil` tant que `demarrer` n'a pas
    /// été appelé — toutes les opérations sont alors des no-op (dégradation
    /// gracieuse plutôt que crash).
    private var contexte: ModelContext?

    /// Tous les repas du hub, triés par heure ascendante. Rechargé depuis le
    /// store après chaque écriture.
    private(set) var repas: [Repas] = []

    // MARK: - Démarrage

    /// Branche le service sur le contexte du hub et charge les données. Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    // MARK: - Lecture par jour

    /// Repas d'un jour donné, triés par heure ascendante.
    func repasDuJour(_ jour: Date) -> [Repas] {
        let cal = Calendar.current
        return repas
            .filter { cal.isDate($0.heure, inSameDayAs: jour) }
            .sorted { $0.heure < $1.heure }
    }

    /// Regroupe les repas d'un jour donné dans les 4 sections canoniques du
    /// journal (« Petit déjeuner », « Déjeuner », « En-cas », « Dîner »), dans
    /// l'ordre attendu par `ListeRepasParSection`. Les sections vides sont
    /// conservées (la vue affiche un état « Aucun repas enregistré »).
    ///
    /// Format identique au tuple historique `[(titre:, repas:)]` consommé par
    /// `JournalVue` / `ListeRepasParSection`, pour brancher la lecture sans
    /// toucher à la signature de ces vues.
    func sectionsDuJour(_ jour: Date) -> [(titre: String, repas: [Repas])] {
        let duJour = repasDuJour(jour)
        let horaires = horairesRepas
        return SectionRepas.allCases.map { section in
            (titre: section.titre, repas: duJour.filter { SectionRepas(heure: $0.heure, horaires: horaires) == section })
        }
    }

    /// Horaires de repas configurés dans le profil — sert à classer un repas
    /// dans sa section (« Déjeuner »…) selon les heures de début réglées,
    /// plutôt que des seuils fixes en dur.
    private var horairesRepas: HorairesRepas {
        ProfilService.shared.profil.horairesRepas
    }

    // MARK: - Dérivations pour l'UI d'injection
    //
    // Le hub stocke le site d'injection sur l'`Injection`, jamais sur le
    // `Repas`. Ces deux lectures rapatrient l'info côté repas au lieu de la
    // dupliquer ou de la mocker.

    /// Zone de la dernière injection **rapide** (bolus repas ou correction)
    /// enregistrée dans le hub. Alimente l'avertissement anti-lipodystrophie du
    /// sélecteur de site. `nil` si aucune injection rapide connue.
    func derniereZoneRapide() -> ZoneInjection? {
        guard let contexte else { return nil }
        let descripteur = FetchDescriptor<Injection>(
            sortBy: [SortDescriptor(\.heure, order: .reverse)]
        )
        let injections = (try? contexte.fetch(descripteur)) ?? []
        return injections.first {
            $0.type == .rapideRepas || $0.type == .rapideCorrection
        }?.zoneInjection
    }

    /// Site (zone + côté) du bolus repas lié à un repas, s'il existe. Permet à
    /// `DetailRepasVue` d'afficher le vrai site plutôt qu'un « — » permanent.
    func siteBolus(repasId: UUID) -> SiteInjection? {
        guard let contexte else { return nil }
        let descripteur = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.repasAssocieId == repasId }
        )
        guard let bolus = try? contexte.fetch(descripteur).first else { return nil }
        return SiteInjection(zone: bolus.zoneInjection, cote: bolus.coteInjection)
    }

    /// Nombre de repas (non vides) enregistrés aujourd'hui — alimente le
    /// sous-titre de la carte « Repas » du journal.
    var nombreRepasAujourdhui: Int {
        repasDuJour(Date()).filter { !$0.aliments.isEmpty }.count
    }

    // MARK: - Écriture

    /// Enregistre un repas (création ou édition). **Upsert par `id`** : si un
    /// repas de même `id` existe déjà, il est supprimé puis remplacé (la
    /// relation cascade nettoie ses anciens `Aliment`).
    func enregistrer(_ unRepas: Repas) {
        guard let contexte else { return }
        let cible = unRepas.id
        let descripteur = FetchDescriptor<Repas>(predicate: #Predicate { $0.id == cible })
        if let existant = try? contexte.fetch(descripteur).first, existant !== unRepas {
            contexte.delete(existant)
        }
        contexte.insert(unRepas)
        try? contexte.save()
        recharger()
    }

    /// Construit puis enregistre un repas depuis les entrées de saisie. Point
    /// d'entrée appelé à la validation de `RepasSheet`. Les `EntreeAliment`
    /// (saisie, en grammes, liées à `AlimentCiqual`) sont mappées en `Aliment`
    /// du hub (voir `Aliment.init(depuis:)`).
    ///
    /// Les entrées sans aliment ne produisent rien : on n'enregistre pas un
    /// repas vide.
    @discardableResult
    func enregistrerDepuisSaisie(
        entrees: [EntreeAliment],
        heure: Date = Date(),
        doseInjectee: Double = 0,
        site: SiteInjection = .parDefaut,
        doseGlobale: Double? = nil,
        doseCorrection: Double = 0,
        ajustements: [Ajustement] = [],
        contexteLibre: String? = nil,
        exclureDesAnalyses: Bool = false
    ) -> Repas? {
        let alimentsHub = entrees.map(Aliment.init(depuis:))
        guard !alimentsHub.isEmpty else { return nil }
        // Mode « dose globale » : la dose vit sur le repas, pas sur les
        // aliments — on neutralise d'éventuelles doses par aliment saisies
        // avant la bascule, sinon `CarteAlimentEnregistre` afficherait une
        // ventilation qui ne correspond plus à rien.
        if doseGlobale != nil {
            for aliment in alimentsHub { aliment.insuline = 0 }
        }
        let nouveau = Repas(
            heure: heure, aliments: alimentsHub, doseGlobale: doseGlobale,
            doseCorrection: doseCorrection > 0 ? doseCorrection : nil,
            ajustements: ajustements,
            contexteLibre: (contexteLibre?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 },
            exclureDesAnalyses: exclureDesAnalyses
        )
        // IOB actif juste avant le repas — snapshot figé du contexte insuline
        // (dérivé du hub à la saisie, donc avant le bolus de ce repas). `nil` si
        // négligeable, pour ne pas afficher un badge « 0u ».
        if let contexte {
            let iob = IOBService.iobDuHub(a: heure, contexte: contexte)
            nouveau.iobAuDebut = iob > 0.05 ? iob : nil
        }
        enregistrer(nouveau)

        // Normalisation différée du contexte libre — jamais bloquante pour la
        // validation du repas (la sheet peut déjà être fermée). Rien si
        // `contexteLibre` est nil. Si la résolution échoue (modèle
        // indisponible, erreur de génération), le badge reste sur le texte
        // brut indéfiniment — dégradation gracieuse, pas de retry
        // automatique. `nouveau` est un `@Model` (référence) déjà inséré
        // dans `contexte` : le muter ici suffit, SwiftData notifie la vue
        // automatiquement (pas de `recharger()` requis).
        if let texteContexte = nouveau.contexteLibre {
            Task {
                guard let resultat = await ReferentielContextesService.shared.resoudre(texte: texteContexte) else { return }
                nouveau.contexteNormalise = resultat.affichage
                try? contexte?.save()
            }
        }

        // Bolus repas → `Injection` rapide liée au repas dans le hub. C'est elle
        // que lisent l'IOB et la section « Bolus repas » de Médications (le hub
        // ne déduit pas l'insuline depuis les aliments). Rien créé sans dose.
        if doseInjectee > 0, let contexte {
            let bolus = Injection(
                type: .rapideRepas,
                dose: doseInjectee,
                heure: heure,
                zoneInjection: site.zone,
                coteInjection: site.cote,
                repasAssocieId: nouveau.id,
                labelRepas: SectionRepas(heure: heure, horaires: horairesRepas).titre,
                emojiRepas: nouveau.emojiPrincipal,
                motif: .repas,
                source: .manuel
            )
            contexte.insert(bolus)
            try? contexte.save()
        }
        return nouveau
    }

    /// Supprime un repas du hub (ses aliments suivent via la cascade), ainsi que
    /// son bolus `Injection` lié — sinon l'IOB compterait une dose fantôme.
    func supprimer(_ unRepas: Repas) {
        guard let contexte else { return }
        supprimerBolusLie(repasId: unRepas.id, contexte: contexte)
        contexte.delete(unRepas)
        try? contexte.save()
        recharger()
    }

    /// Supprime un aliment isolé d'un repas. Si c'était le dernier, le repas
    /// devenu vide est retiré aussi (avec son bolus lié) — un repas sans aliment
    /// n'a pas de sens.
    func supprimerAliment(_ aliment: Aliment, de unRepas: Repas) {
        guard let contexte else { return }
        let deviendraitVide = unRepas.aliments.filter { $0.id != aliment.id }.isEmpty
        contexte.delete(aliment)
        if deviendraitVide {
            supprimerBolusLie(repasId: unRepas.id, contexte: contexte)
            contexte.delete(unRepas)
        }
        try? contexte.save()
        recharger()
    }

    /// Supprime les injections bolus liées à un repas (via `repasAssocieId`).
    /// La dose d'un aliment retiré sans vider le repas n'est PAS recalculée :
    /// le bolus est un fait déjà injecté, pas un dérivé des aliments.
    private func supprimerBolusLie(repasId: UUID, contexte: ModelContext) {
        let descripteur = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.repasAssocieId == repasId }
        )
        for bolus in (try? contexte.fetch(descripteur)) ?? [] {
            contexte.delete(bolus)
        }
    }

    /// Recalcule les réponses glycémiques des repas depuis le CGM du hub, sans
    /// re-fetch des repas. À appeler quand de nouvelles `GlucoseReading` sont
    /// arrivées (sync HealthKit) — au démarrage, le CGM n'est pas encore
    /// synchronisé, donc les analyses seraient toutes en attente sinon.
    func rafraichirAnalyses() {
        annoterReponsesGlycemiques()
    }

    // MARK: - Privé

    private func recharger() {
        guard let contexte else { return }
        let descripteur = FetchDescriptor<Repas>(sortBy: [SortDescriptor(\.heure)])
        repas = (try? contexte.fetch(descripteur)) ?? []
        annoterReponsesGlycemiques()
    }

    /// Fenêtre au-delà de laquelle on ne calcule plus la réponse glycémique
    /// d'un repas : sans CGM aussi ancien (backfill Dexcom borné à 7 jours),
    /// l'analyse serait de toute façon `donneesManquantes`. Borne aussi le
    /// volume du fetch CGM au rechargement.
    private static let fenetreAnalyseJours = 45

    /// Calcule et pose l'`EtatAnalyse` (`@Transient`) de chaque repas récent à
    /// partir des `GlucoseReading` du hub. Un seul fetch CGM borné, puis
    /// découpage en mémoire par repas via `AssembleurReponseRepas` (pur).
    private func annoterReponsesGlycemiques() {
        guard let contexte else { return }
        let maintenant = Date()
        let borneAnalyse = Calendar.current.date(
            byAdding: .day, value: -Self.fenetreAnalyseJours, to: maintenant
        ) ?? maintenant

        let recents = repas.filter { $0.heure >= borneAnalyse }
        guard let premier = recents.first?.heure, let dernier = recents.last?.heure else { return }

        // Fetch unique sur [T-1h du premier repas, T+4h du dernier].
        let borneBasse = premier.addingTimeInterval(AssembleurReponseRepas.debutFenetre)
        let borneHaute = dernier.addingTimeInterval(AssembleurReponseRepas.finFenetre)
        var descripteur = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.date >= borneBasse && $0.date <= borneHaute },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        descripteur.propertiesToFetch = [\.date, \.valeur]
        let echantillons = ((try? contexte.fetch(descripteur)) ?? [])
            .map { (date: $0.date, valeur: $0.valeur) }

        // Seuils du profil — « hypo » / « hors cible » doivent vouloir dire la
        // même chose ici que dans les graphes et les analyses du coucher.
        let seuils = ProfilService.shared.profil.seuilsGlycemiques

        var doseASauvegarder = false
        for unRepas in recents {
            let etat = AssembleurReponseRepas.analyser(
                heureRepas: unRepas.heure,
                aUneInjection: unRepas.aUneInjection,
                echantillons: echantillons,
                maintenant: maintenant,
                seuils: seuils
            )
            unRepas.etatAnalyse = etat

            // Persiste le verdict + ratio effectif dès qu'ils sont connus —
            // contrairement à `etatAnalyse` (transient, courbe non stockable),
            // ces deux valeurs survivent au relancement de l'app et alimentent
            // le mining R1 (CalculRatioObserve) sur tout l'historique, pas
            // seulement la fenêtre récente gardée en mémoire ici.
            guard case .disponible(let reponse) = etat else { continue }
            let doseCouvrante = unRepas.totalInsuline - (unRepas.doseCorrection ?? 0)
            let ratio = unRepas.totalGlucides > 0 && doseCouvrante > 0
                ? Double(unRepas.totalGlucides) / doseCouvrante : nil
            if unRepas.verdictPersiste != reponse.verdict || unRepas.ratioEffectifPersiste != ratio {
                unRepas.verdictPersiste = reponse.verdict
                unRepas.ratioEffectifPersiste = ratio
                doseASauvegarder = true
            }
        }
        if doseASauvegarder { try? contexte.save() }
    }
}

// MARK: - Mapping EntreeAliment -> Aliment

extension Aliment {

    /// Mappe une entrée de saisie (`EntreeAliment`, liée à `AlimentCiqual`,
    /// quantité en grammes, dose optionnelle) vers l'`Aliment` du hub (forme
    /// déjà résolue, glucides entiers, dose non optionnelle).
    ///
    /// Choix de conversion :
    /// - `emoji` : celui de l'`AlimentCiqual`, ou 🍽 par défaut (le réf. CIQUAL
    ///   a un emoji optionnel).
    /// - `nom` : repris tel quel de l'`AlimentCiqual`.
    /// - `quantite` : grammes consommés, **arrondis** à l'entier le plus proche.
    /// - `glucides` : glucides calculés (proportionnels à la quantité),
    ///   **arrondis** à l'entier le plus proche — l'`Aliment` du hub stocke des
    ///   glucides entiers (précision suffisante, cohérente avec l'affichage).
    /// - `insuline` : `doseInsuline ?? 0` (un aliment logué pour mémoire, sans
    ///   bolus, vaut 0 u).
    convenience init(depuis entree: EntreeAliment) {
        var idCiqualSource: Int?
        if case .ciqual(let a) = entree.aliment { idCiqualSource = a.id }

        self.init(
            emoji: entree.aliment.emoji ?? "🍽",
            nom: entree.aliment.nom,
            quantite: Int(entree.quantiteGrammes.rounded()),
            glucides: Int(entree.glucides.rounded()),
            insuline: entree.doseInsuline ?? 0,
            // Miniature 200 px : suffisante pour les rows du journal.
            imageURL: entree.aliment.imagePetiteURL,
            resucrage: entree.resucrage,
            idCiqualSource: idCiqualSource
        )
    }
}

// MARK: - Sections de repas (dérivation d'affichage)

/// Les 5 tranches canoniques du journal. Reste une dérivation d'affichage :
/// le hub ne stocke pas la section, seulement l'heure absolue du repas.
enum SectionRepas: CaseIterable {
    case petitDejeuner
    case dejeuner
    case enCas
    case diner
    /// Fenêtre nocturne entre la fin du dîner et le début du petit-déjeuner
    /// — évite qu'un repas de milieu de nuit soit classé à tort dans
    /// « Dîner » (nearest-anchor le ferait si le dîner est tardif).
    case nuit

    /// Libellé exact attendu par `ListeRepasParSection` (mêmes chaînes).
    var titre: String {
        switch self {
        case .petitDejeuner: return "Petit déjeuner"
        case .dejeuner:      return "Déjeuner"
        case .enCas:         return "En-cas"
        case .diner:         return "Dîner"
        case .nuit:          return "Nuit"
        }
    }

    /// Délai après le **début** du dîner marquant le passage à la section
    /// « Nuit » — fixe (pas un réglage utilisateur séparé), pour ne pas
    /// ajouter un 5ᵉ champ dans les réglages horaires du profil.
    private static let delaiNuitApresDinerMinutes = 180 // 3h

    /// Classe une heure de repas dans une section selon les **heures de
    /// début du profil** (`HorairesRepas`) : chaque horaire marque le
    /// **début** de sa section (pas un point de référence le plus proche),
    /// la section retenue est celle dont le début est le dernier atteint
    /// avant l'heure du repas — journée traitée en cercle (24h), donc le
    /// passage minuit est géré sans cas particulier. Le goûter du profil
    /// correspond à la section « En-cas » ; « Nuit » démarre automatiquement
    /// `delaiNuitApresDinerMinutes` après le début du dîner.
    init(heure: Date, horaires: HorairesRepas) {
        let cal = Calendar.current
        func minuteDuJour(_ date: Date) -> Int {
            let c = cal.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        let cible = minuteDuJour(heure)
        let debutDiner = minuteDuJour(horaires.diner)
        let debutNuit = (debutDiner + Self.delaiNuitApresDinerMinutes) % (24 * 60)

        let bornes: [(section: SectionRepas, debut: Int)] = [
            (.petitDejeuner, minuteDuJour(horaires.petitDejeuner)),
            (.dejeuner,      minuteDuJour(horaires.dejeuner)),
            (.enCas,         minuteDuJour(horaires.gouter)),
            (.diner,         debutDiner),
            (.nuit,          debutNuit),
        ]
        self = Self.section(pour: cible, bornes: bornes)
    }

    /// Trouve la section dont le début est le **dernier atteint avant**
    /// `cible`, bornes traitées de façon circulaire (24h). Si `cible` est
    /// avant toutes les bornes du jour (ex. 00h30 alors que la plus petite
    /// borne est à 01h), la section active est celle qui a commencé la
    /// veille — la dernière borne une fois triées.
    private static func section(
        pour cible: Int,
        bornes: [(section: SectionRepas, debut: Int)]
    ) -> SectionRepas {
        let triees = bornes.sorted { $0.debut < $1.debut }
        if let trouvee = triees.last(where: { $0.debut <= cible }) {
            return trouvee.section
        }
        return triees.last?.section ?? .petitDejeuner
    }
}

#if DEBUG
extension RepasService {

    /// Container in-memory peuplé pour les `#Preview` — remplace l'ancien jeu
    /// mock du journal. Hors `DEBUG`, l'app démarre sur un hub vide
    /// (dégradation gracieuse → état vide honnête).
    @MainActor
    static var conteneurApercu: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Repas.self, configurations: config)
        for unRepas in echantillonsApercu() {
            container.mainContext.insert(unRepas)
        }
        return container
    }

    /// Instance de service **démarrée** sur un container de démo — pour les
    /// previews qui consomment `RepasService` via `@Environment`.
    @MainActor
    static func apercu() -> RepasService {
        let service = RepasService()
        service.demarrer(contexte: conteneurApercu.mainContext)
        return service
    }

    /// Jeu de repas de démonstration sur la journée courante (un par section).
    /// Uniquement pour previews / captures. `etatAnalyse` laissé à `nil`
    /// (dérivation non persistée, pas d'assembleur CGM branché).
    static func echantillonsApercu() -> [Repas] {
        let cal = Calendar.current
        func aujourdhui(_ h: Int, _ m: Int = 0) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
        }

        return [
            Repas(
                heure: aujourdhui(7, 30),
                aliments: [
                    Aliment(emoji: "🥣", nom: "Flocons d'avoine", quantite: 80, glucides: 54, insuline: 3.0),
                    Aliment(emoji: "🍌", nom: "Banane", quantite: 120, glucides: 27, insuline: 1.5),
                ]
            ),
            Repas(
                heure: aujourdhui(12, 30),
                aliments: [
                    Aliment(emoji: "🍝", nom: "Pâtes complètes", quantite: 90, glucides: 60, insuline: 3.5),
                    Aliment(emoji: "🥦", nom: "Brocolis vapeur", quantite: 200, glucides: 8, insuline: 0.0),
                ]
            ),
            Repas(
                heure: aujourdhui(16, 0),
                aliments: [
                    Aliment(emoji: "🍪", nom: "Cookie", quantite: 30, glucides: 18, insuline: 0.0),
                ]
            ),
            Repas(
                heure: aujourdhui(19, 45),
                aliments: [
                    Aliment(emoji: "🍚", nom: "Riz basmati", quantite: 70, glucides: 56, insuline: 3.0),
                    Aliment(emoji: "🐟", nom: "Saumon grillé", quantite: 130, glucides: 0, insuline: 0.0),
                ]
            ),
        ]
    }

    /// Historique synthétique dédié au mining R1 (`CalculRatioObserve`), placé
    /// **au-delà** de `fenetreAnalyseJours` (45 jours) — hors de cette fenêtre,
    /// `annoterReponsesGlycemiques()` ne recalcule jamais le verdict d'un repas
    /// depuis le CGM, donc le `verdictPersiste` posé ici à la construction
    /// reste stable (la courbe CGM synthétique du preview ne matcherait de
    /// toute façon aucun repas précis). Objectif : illustrer tous les états
    /// possibles de la carte de progression / de la sheet « Écart de ratio »
    /// sans dépendre d'un vrai calcul CGM — chaque tranche est peuplée
    /// directement avec le verdict voulu, en réutilisant les mêmes constantes
    /// (`effectifMinimalBucket`, `toleranceRatio`) que `CalculRatioObserve`
    /// pour rester cohérent si elles changent.
    ///
    /// - Déjeuner : écart net (les repas sous-dosés marchent mieux — ratio
    ///   actuel probablement trop fort).
    /// - Petit-déjeuner : bien calibré, pas d'écart.
    /// - Goûter : tranches trop peu fournies, taux brut seulement.
    /// - Dîner : volontairement pas touché, reste sur le seul repas du jour
    ///   (`echantillonsApercu()`) pour illustrer l'état quasi vide.
    static func echantillonsApercuR1() -> [Repas] {
        let cal = Calendar.current

        func repasType(joursAvant: Int, heure: (h: Int, m: Int), glucides: Int, dose: Double, verdict: VerdictGlycemique) -> Repas {
            let jour = cal.date(byAdding: .day, value: -joursAvant, to: Date()) ?? Date()
            let date = cal.date(bySettingHour: heure.h, minute: heure.m, second: 0, of: jour) ?? jour
            return Repas(
                heure: date,
                aliments: [Aliment(emoji: "🍽", nom: "Repas type", quantite: 1, glucides: glucides, insuline: 0)],
                doseGlobale: dose,
                verdictPersiste: verdict,
                ratioEffectifPersiste: Double(glucides) / dose
            )
        }

        /// Génère un lot réparti en 3 tranches (faible / proche / forte du
        /// ratio configuré), chacune avec le nombre de bons verdicts demandé
        /// — les non-bons alternent moyen/mauvais. Le ratio varie sur toute
        /// la plage de la tranche (pas une valeur fixe) : sinon tous les
        /// repas d'une tranche tombent au même x et s'empilent en une seule
        /// colonne sur le graphique — même plages que les autres previews
        /// de la sheet (`GraphiqueZonesRatio`/`SheetEcartRatio`).
        func lot(
            departJours: Int, glucides: Int, doseSuggeree: Double, heure: (h: Int, m: Int),
            faible: (bon: Int, total: Int), proche: (bon: Int, total: Int), forte: (bon: Int, total: Int)
        ) -> [Repas] {
            var jour = departJours
            var resultat: [Repas] = []
            func ajouter(_ compte: (bon: Int, total: Int), plage: ClosedRange<Double>) {
                for i in 0..<compte.total {
                    let ratio = plage.lowerBound + (plage.upperBound - plage.lowerBound) * Double(i) / Double(max(1, compte.total - 1))
                    let verdict: VerdictGlycemique = i < compte.bon ? .bon : (i.isMultiple(of: 2) ? .moyen : .mauvais)
                    resultat.append(repasType(joursAvant: jour, heure: heure, glucides: glucides, dose: doseSuggeree * ratio, verdict: verdict))
                    jour += 1
                }
            }
            ajouter(faible, plage: 0.55...0.78)
            ajouter(proche, plage: 0.85...1.15)
            ajouter(forte, plage: 1.22...1.55)
            return resultat
        }

        let dejeuner = lot(
            departJours: 50, glucides: 100, doseSuggeree: 100.0 / 12, heure: (12, 30),
            faible: (8, 10), proche: (7, 15), forte: (2, 10)
        )
        let petitDejeuner = lot(
            departJours: 90, glucides: 50, doseSuggeree: 50.0 / 8, heure: (7, 30),
            faible: (3, 6), proche: (14, 20), forte: (3, 6)
        )
        let gouter = lot(
            departJours: 130, glucides: 40, doseSuggeree: 40.0 / 15, heure: (16, 30),
            faible: (2, 4), proche: (7, 10), forte: (1, 3)
        )

        return dejeuner + petitDejeuner + gouter
    }
}
#endif
