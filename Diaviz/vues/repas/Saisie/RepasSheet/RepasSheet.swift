//
//  RepasSheet.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI
import SwiftData

/// Sheet "Repas en cours" présentée plein écran (`.large`) au-dessus de
/// `AjouterRepasVue` quand l'utilisateur tape ou drag-up sur la bulle
/// (`BulleRepasEnCours` rendue en overlay sur le parent).
///
/// La sheet est purement le mode complet : en-tête, liste d'aliments,
/// section insuline, alertes, détails d'injection, et bouton de validation.
/// Elle peut empiler des sheets enfants (`DetailAlimentSheet` pour l'édition
/// d'un aliment, `AjustementSheet` pour les ajustements intentionnels).
/// Réglages du repas portés par la sheet, hors aliments. Sert à la préremplir
/// quand on modifie un repas enregistré, et à conserver ce qui a été retouché
/// si la sheet se ferme le temps d'ajouter un aliment.
struct ValeursRepasEnCours {
    var ajustements: [Ajustement]
    var correctionHyper: Double
    var evenements: [EvenementRepas]
    var exclusionManuelle: Bool?
    var siteInjection: SiteInjection
    var doseGlobale: Double?
    var heureRepas: Date
    var momentChoisi: SectionRepas?

    init(depuis repas: Repas, site: SiteInjection) {
        ajustements = repas.ajustements
        correctionHyper = repas.doseCorrection ?? 0
        evenements = repas.evenementsAffiches
        // Exclu faute d'insuline : c'était un constat, pas un choix. Il ne doit
        // pas survivre à l'ajout d'une dose.
        exclusionManuelle = repas.exclureDesAnalyses ? (repas.aUneInjection ? true : nil) : false
        siteInjection = site
        doseGlobale = repas.doseGlobale
        heureRepas = repas.heure
        momentChoisi = repas.momentChoisi.flatMap(SectionRepas.init(rawValue:))
    }

    init(
        ajustements: [Ajustement], correctionHyper: Double, evenements: [EvenementRepas],
        exclusionManuelle: Bool?, siteInjection: SiteInjection, doseGlobale: Double?, heureRepas: Date,
        momentChoisi: SectionRepas?
    ) {
        self.ajustements = ajustements
        self.correctionHyper = correctionHyper
        self.evenements = evenements
        self.exclusionManuelle = exclusionManuelle
        self.siteInjection = siteInjection
        self.doseGlobale = doseGlobale
        self.heureRepas = heureRepas
        self.momentChoisi = momentChoisi
    }
}

struct RepasSheet: View {

    // MARK: - Bindings

    @Binding var aliments: [EntreeAliment]

    // MARK: - Closures

    /// "Ajouter un aliment" depuis la sheet : remonte au parent qui ferme
    /// la sheet et active la barre de recherche.
    let onAjouterUnAliment: () -> Void

    /// Validation finale du repas. Transmet la **dose réellement injectée**
    /// (aliments ou dose globale + ajustements + correction), le **site**,
    /// l'**heure** (réglable, préremplie à l'heure actuelle) et la **dose
    /// globale** (`nil` = mode par aliment), pour que le parent crée le repas
    /// et son bolus dans le hub. Le parent reset l'état.
    let onValiderRepas: (
        _ doseInjectee: Double,
        _ site: SiteInjection,
        _ heure: Date,
        _ doseGlobale: Double?,
        _ doseCorrection: Double,
        _ ajustements: [Ajustement],
        _ evenements: [EvenementRepas],
        _ exclureDesAnalyses: Bool,
        _ momentChoisi: SectionRepas?
    ) -> Void

    /// Appelé à la fermeture avec les réglages courants — seulement en
    /// modification, où le parent les rend à la réouverture.
    private let onFermeture: ((ValeursRepasEnCours) -> Void)?

    /// Libellé du bouton final, `nil` pour celui de la saisie.
    private let libelleValidation: String?

    /// Repas en cours de modification : son propre bolus ne compte pas dans
    /// l'insuline active affichée, qui décrit l'état avant ce repas.
    private let idRepasModifie: UUID?

    init(
        aliments: Binding<[EntreeAliment]>,
        valeursInitiales: ValeursRepasEnCours? = nil,
        idRepasModifie: UUID? = nil,
        libelleValidation: String? = nil,
        onFermeture: ((ValeursRepasEnCours) -> Void)? = nil,
        onAjouterUnAliment: @escaping () -> Void,
        onValiderRepas: @escaping (
            _ doseInjectee: Double, _ site: SiteInjection, _ heure: Date, _ doseGlobale: Double?,
            _ doseCorrection: Double, _ ajustements: [Ajustement], _ evenements: [EvenementRepas],
            _ exclureDesAnalyses: Bool, _ momentChoisi: SectionRepas?
        ) -> Void
    ) {
        _aliments = aliments
        self.idRepasModifie = idRepasModifie
        self.libelleValidation = libelleValidation
        self.onFermeture = onFermeture
        self.onAjouterUnAliment = onAjouterUnAliment
        self.onValiderRepas = onValiderRepas
        if let valeursInitiales {
            _ajustements = State(initialValue: valeursInitiales.ajustements)
            _correctionHyper = State(initialValue: valeursInitiales.correctionHyper)
            _evenements = State(initialValue: valeursInitiales.evenements)
            _exclusionManuelle = State(initialValue: valeursInitiales.exclusionManuelle)
            _siteInjection = State(initialValue: valeursInitiales.siteInjection)
            _doseGlobale = State(initialValue: valeursInitiales.doseGlobale)
            _heureRepas = State(initialValue: valeursInitiales.heureRepas)
            _momentChoisi = State(initialValue: valeursInitiales.momentChoisi)
        }
    }

    // MARK: - État interne

    @State private var ajustements: [Ajustement] = []
    @State private var correctionHyper: Double = 0
    /// Événements de vie du repas, édités via `SheetEvenementsRepas` — même
    /// sheet qu'après enregistrement, pour ne pas maintenir deux UI de la
    /// même donnée.
    @State private var evenements: [EvenementRepas] = []
    @State private var afficherEvenements = false
    /// Choix **explicite** de l'utilisateur sur l'exclusion des analyses.
    /// `nil` = jamais touché (décoché par défaut).
    @State private var exclusionManuelle: Bool? = nil
    @State private var siteInjection: SiteInjection = .parDefaut

    /// Mode « dose globale » : une seule dose pour tout le repas au lieu
    /// d'une ventilation par aliment. `nil` = mode classique. Activé via le
    /// toggle de `InsulineSection`, qui préremplit avec la somme des doses
    /// par aliment.
    @State private var doseGlobale: Double? = nil

    /// Heure du repas — préremplie à l'heure actuelle, réglable pour les
    /// saisies rétroactives (ex. repas oublié, saisi plus tard). Alimente
    /// aussi `contexteInsights` : les insights et le snapshot d'IOB doivent
    /// être calculés à l'heure du repas, pas à l'heure de saisie si elles
    /// diffèrent.
    @State private var heureRepas: Date = Date()

    /// Moment choisi à la main, `nil` = classement automatique selon l'heure.
    @State private var momentChoisi: SectionRepas? = nil

    /// Entrée actuellement en cours d'édition (déclenche la sheet enfant).
    @State private var entreeEnEdition: EntreeAliment? = nil

    /// Routage unifié pour la sheet d'ajustement (ajout ou édition).
    @State private var sheetAjustement: SheetAjustement? = nil

    /// Présentation de la sheet de sélection de site d'injection. Présentée
    /// à la racine du body (et non dans `DetailsSection`) pour éviter que
    /// SwiftUI ne démonte la sheet au 1er tap quand le `Form` rebuild — bug
    /// connu des `.sheet` attachés à une `Section` à l'intérieur d'un Form.
    @State private var afficherSitePicker: Bool = false

    /// Service hub des repas — expose la dérivation `derniereZoneRapide()` pour
    /// l'avertissement anti-lipodystrophie du sélecteur de site.
    @Environment(RepasService.self) private var repasService

    /// Mining R1 (ratio observé) — cache déjà calculé, lu tel quel (pas de
    /// recalcul à chaque frappe de saisie, voir `AnalyseRatioService`).
    @Environment(AnalyseRatioService.self) private var analyseRatioService

    /// Contexte du hub — alimente les insights réels (sport récent, IOB).
    @Environment(\.modelContext) private var modelContext

    /// Ferme la sheet automatiquement au dernier aliment supprimé — sans ça
    /// le bouton "Enregistrer" est bien désactivé à 0 aliment, mais la sheet
    /// reste ouverte sur un repas vide, ce qui n'a pas de sens.
    @Environment(\.dismiss) private var dismiss

    /// Zone de la dernière injection rapide enregistrée, lue depuis le hub
    /// (bolus repas ou correction). `nil` si aucune — pas d'avertissement.
    private var derniereZoneRapide: ZoneInjection? {
        repasService.derniereZoneRapide()
    }

    // MARK: - Calculs

    private var doseTotaleRepas: Double {
        aliments.reduce(0) { $0 + ($1.doseInsuline ?? 0) }
    }

    private var glucidesTotal: Double {
        aliments.reduce(0) { $0 + $1.glucides }
    }

    private var totalAjustements: Double {
        ajustements.reduce(0) { $0 + $1.valeur }
    }

    /// Dose de base du repas selon le mode actif : dose globale si le toggle
    /// est activé, sinon somme des doses par aliment.
    private var doseBaseRepas: Double {
        doseGlobale ?? doseTotaleRepas
    }

    private var totalInjecte: Double {
        max(0, doseBaseRepas + totalAjustements + correctionHyper)
    }

    /// Dose confrontée au ratio — **la seule part du repas qui prétend
    /// couvrir les glucides**, donc ni les ajustements ni la correction.
    ///
    /// - `correctionHyper` répond à la glycémie du moment, pas aux glucides.
    /// - `ajustements` (`[Ajustement]`, ex. « sport récent ») sont des
    ///   déviations **volontaires** au ratio : les inclure ici garantissait un
    ///   écart mécanique, et la carte annonçait « dose faible vs ratio » alors
    ///   que le ratio était scrupuleusement respecté sur la part repas. Ils
    ///   sont désormais rapportés à part par `ValidationRatioCard` (badge
    ///   ambre + ratio effectif), sans verdict — l'app n'a aucune base pour
    ///   juger une déviation décidée par l'utilisateur.
    ///
    /// Même définition que la dose du mining R1
    /// (`AnalyseRatioService.mapperEntrees`, `totalInsuline - doseCorrection`),
    /// qui lui non plus ne compte pas les ajustements : saisie et analyse
    /// parlent enfin de la même dose.
    ///
    /// En mode dose globale, la base est la dose globale — la validation du
    /// ratio fonctionne à l'identique (glucides totaux vs dose unique).
    private var doseCouvrantGlucides: Double {
        max(0, doseBaseRepas)
    }

    // MARK: - Exclusion des analyses

    /// Repas sans aucune insuline : la réponse glycémique n'est pas
    /// interprétable (c'est exactement le cas `EtatAnalyse.sansInjection` de
    /// l'assembleur), donc l'exclure des analyses n'est pas un choix mais un
    /// constat — le toggle est forcé et désactivé.
    private var exclusionForcee: Bool {
        !aliments.isEmpty && totalInjecte == 0
    }

    /// Valeur effective du toggle : le forçage prime, puis le choix manuel.
    private var exclureDesAnalyses: Bool {
        if exclusionForcee { return true }
        return exclusionManuelle ?? false
    }

    /// Explication affichée sous le toggle — `nil` quand l'état courant n'a
    /// rien d'automatique à justifier.
    private var raisonExclusionAuto: String? {
        if exclusionForcee {
            return "Ce repas n'a aucune dose d'insuline : sa réponse glycémique n'est pas analysable."
        }
        return nil
    }

    private var momentAutomatique: SectionRepas {
        SectionRepas(heure: heureRepas, horaires: ProfilService.shared.profil.horairesRepas)
    }

    private var contexteInsights: ContexteInsights {
        // T0 = heure du repas (réglable, préremplie à l'heure actuelle), et la
        // section (pour le ratio par moment) en découle via les horaires du profil.
        let section = momentChoisi ?? momentAutomatique
        return InsightsService.contexte(
            doseSaisie: doseCouvrantGlucides,
            glucides: glucidesTotal,
            ajustements: totalAjustements,
            heure: heureRepas,
            section: section,
            contexte: modelContext,
            repasIgnore: idRepasModifie,
            analyseRatioObserve: analyseRatioService.analyse,
            repartitions: analyseRatioService.repartitions
        )
    }

    // MARK: - Corps

    var body: some View {
        let insights = contexteInsights
        // Architecture : un seul `Form` contient toutes les sections, y
        // compris la section "Alertes". Les cartes ont une cornerRadius
        // qui matche le clip arrondi des sections de `Form.grouped` (~10pt)
        // pour que leurs bordures ne soient pas coupées aux coins.
        //
        // Ordre voulu : ce qu'on saisit (date, aliments, contexte), puis la
        // dose, puis ce qui la commente (alertes), puis le site d'injection.
        VStack(spacing: 0) {
            EnTeteSheet(
                nombreAliments: aliments.count,
                totalGlucides: glucidesTotal
            )

            Form {
                SectionDateHeure(date: $heureRepas) {
                    Picker(selection: $momentChoisi) {
                        Text("Automatique (\(momentAutomatique.titre))").tag(SectionRepas?.none)
                        ForEach(SectionRepas.allCases, id: \.self) { moment in
                            Text(moment.titre).tag(SectionRepas?.some(moment))
                        }
                    } label: {
                        Label("Moment", systemImage: "fork.knife")
                    }
                    .pickerStyle(.menu)
                }

                ListeAlimentsSection(
                    aliments: $aliments,
                    onEditer: { entreeEnEdition = $0 },
                    onAjouterUnAliment: onAjouterUnAliment
                )

                SectionContexteRepas(
                    evenements: evenements,
                    onEditer: { afficherEvenements = true }
                )

                sectionExclusionAnalyses

                InsulineSection(
                    doseRepas: doseTotaleRepas,
                    ajustements: $ajustements,
                    correctionHyper: $correctionHyper,
                    doseGlobale: $doseGlobale,
                    totalInjecte: totalInjecte,
                    onAjouterAjustement: { sheetAjustement = .ajout },
                    onEditerAjustement: { sheetAjustement = .edition($0) }
                )

                // Alertes placées juste **après** la section insuline : elles
                // commentent la dose (écart au ratio, sport récent, IOB), et
                // en haut du formulaire elles étaient hors écran au moment
                // précis où on saisit cette dose — donc invisibles quand
                // elles comptent le plus.
                if glucidesTotal > 0 {
                    SectionRatiosRepas(
                        glucides: glucidesTotal,
                        doseCouvrante: doseBaseRepas + totalAjustements,
                        avecAjustement: totalAjustements != 0,
                        ratioConfigure: insights.validation?.profil
                    )
                }

                InsightsSection(contexte: insights, iobAvantRepas: idRepasModifie != nil)

                // Site d'injection : visible seulement si une dose effective
                // est prévue. Sans injection, la zone n'a pas de sens.
                if totalInjecte > 0 {
                    DetailsSection(
                        siteInjection: $siteInjection,
                        derniereZoneRapide: derniereZoneRapide,
                        onOuvrirSitePicker: { afficherSitePicker = true }
                    )
                }
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            BoutonValiderRepas(
                nombreAliments: aliments.count,
                libelleForce: libelleValidation,
                onValider: {
                    onValiderRepas(
                        totalInjecte, siteInjection, heureRepas, doseGlobale, correctionHyper,
                        ajustements, evenements, exclureDesAnalyses, momentChoisi
                    )
                }
            )
        }
        .onDisappear {
            onFermeture?(ValeursRepasEnCours(
                ajustements: ajustements, correctionHyper: correctionHyper, evenements: evenements,
                exclusionManuelle: exclusionManuelle, siteInjection: siteInjection,
                doseGlobale: doseGlobale, heureRepas: heureRepas, momentChoisi: momentChoisi
            ))
        }
        // Dernier aliment supprimé (swipe dans ListeAlimentsSection) → plus
        // rien à composer, on referme au lieu de laisser la sheet ouverte
        // sur un repas vide avec juste un bouton désactivé.
        .onChange(of: aliments.isEmpty) { _, videMaintenant in
            if videMaintenant { dismiss() }
        }
        // Événements de vie — même sheet qu'après enregistrement (voir
        // `DetailRepasVue`). Ici la sélection n'est pas persistée à la
        // fermeture : elle voyage avec le repas jusqu'à sa validation.
        .sheet(isPresented: $afficherEvenements) {
            SheetEvenementsRepas(evenements: evenements) { nouveaux in
                evenements = nouveaux
            }
        }
        // Sheet enfant — édition d'une entrée existante (tap sur une row).
        .sheet(item: $entreeEnEdition) { entree in
            DetailAlimentSheet(
                aliment: entree.aliment,
                entreeExistante: entree
            ) { entreeMaj in
                remplacerEntree(entreeMaj)
            }
        }
        // Sheet d'ajustement intentionnel — ajout ou édition selon l'item.
        .sheet(item: $sheetAjustement) { item in
            switch item {
            case .ajout:
                AjustementSheet(
                    ajustementInitial: Ajustement(
                        raison: .sportRecent, valeur: -0.5,
                        typeSportDetecte: contexteInsights.sport?.typeSport
                    ),
                    onValider: { nouveau in
                        ajustements.append(nouveau)
                    }
                )
            case .edition(let existante):
                AjustementSheet(
                    ajustementInitial: existante,
                    onValider: { maj in
                        if let idx = ajustements.firstIndex(where: { $0.id == maj.id }) {
                            ajustements[idx] = maj
                        }
                    },
                    onSupprimer: {
                        ajustements.removeAll { $0.id == existante.id }
                    }
                )
            }
        }
        // Sheet de sélection du site d'injection — hostée ici (et pas dans
        // DetailsSection) pour rester sur la racine stable du body, à côté
        // des deux autres sheets enfants.
        .sheet(isPresented: $afficherSitePicker) {
            SiteInjectionPicker(
                site: $siteInjection,
                derniereZoneRapide: derniereZoneRapide
            )
        }
    }

    // MARK: - Section exclusion des analyses

    /// Toggle d'exclusion + son explication quand l'état est automatique.
    /// Désactivé (et forcé à « oui ») quand le repas n'a aucune dose : il n'y
    /// a alors rien à analyser, laisser le choix serait trompeur.
    private var sectionExclusionAnalyses: some View {
        Section {
            Toggle(
                "Exclure des analyses",
                isOn: Binding(
                    get: { exclureDesAnalyses },
                    set: { exclusionManuelle = $0 }
                )
            )
            .disabled(exclusionForcee)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ignore ce repas dans les analyses statistiques (ratio observé, repas à revoir) — il reste visible partout ailleurs.")
                if let raison = raisonExclusionAuto {
                    Text(raison)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Actions

    private func remplacerEntree(_ entreeMaj: EntreeAliment) {
        if let idx = aliments.firstIndex(where: { $0.id == entreeMaj.id }) {
            aliments[idx] = entreeMaj
        }
    }
}

// MARK: - Routage de la sheet d'ajustement

/// Discrimine ajout vs édition pour la sheet d'ajustement, routé via un seul
/// `.sheet(item:)`.
private enum SheetAjustement: Identifiable {
    case ajout
    case edition(Ajustement)

    var id: String {
        switch self {
        case .ajout:                return "ajout"
        case .edition(let aj):      return aj.id.uuidString
        }
    }
}

// MARK: - Aperçu

private let _previewAlimentsRepas: [EntreeAliment] = [
    EntreeAliment(
        aliment: .ciqual(AlimentCiqual(id: 1, nom: "Pâtes complètes cuites", calories: 124, glucides: 25, sucres: 1, proteines: 5, lipides: 0.8, fibres: 3, emoji: "🍝")),
        quantiteGrammes: 200,
        quantiteApproximative: false,
        doseInsuline: 5.0,
        note: ""
    ),
    EntreeAliment(
        aliment: .ciqual(AlimentCiqual(id: 2, nom: "Poulet grillé", calories: 165, glucides: 0, sucres: 0, proteines: 31, lipides: 3.6, fibres: 0, emoji: "🍗")),
        quantiteGrammes: 150,
        quantiteApproximative: false,
        doseInsuline: 0.0,
        note: ""
    ),
    EntreeAliment(
        aliment: .ciqual(AlimentCiqual(id: 3, nom: "Yaourt nature", calories: 60, glucides: 5, sucres: 5, proteines: 4, lipides: 3, fibres: 0, emoji: "🥛")),
        quantiteGrammes: 125,
        quantiteApproximative: true,
        doseInsuline: 0.5,
        note: "Légère"
    ),
]

#if DEBUG
#Preview("Repas typique") {
    @Previewable @State var aliments = _previewAlimentsRepas
    RepasSheet(
        aliments: $aliments,
        onAjouterUnAliment: {},
        onValiderRepas: { _, _, _, _, _, _, _, _, _ in }
    )
    .environment(RepasService.apercu())
    .environment(AnalyseRatioService())
    .modelContainer(for: [Injection.self, ActiviteSportive.self], inMemory: true)
}

#Preview("Repas vide") {
    @Previewable @State var aliments: [EntreeAliment] = []
    RepasSheet(
        aliments: $aliments,
        onAjouterUnAliment: {},
        onValiderRepas: { _, _, _, _, _, _, _, _, _ in }
    )
    .environment(RepasService.apercu())
    .environment(AnalyseRatioService())
    .modelContainer(for: [Injection.self, ActiviteSportive.self], inMemory: true)
}
#endif
