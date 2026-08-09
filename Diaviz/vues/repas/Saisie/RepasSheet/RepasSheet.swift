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
        _ contexteLibre: String?,
        _ exclureDesAnalyses: Bool
    ) -> Void

    // MARK: - État interne

    @State private var ajustements: [Ajustement] = []
    @State private var correctionHyper: Double = 0
    /// Événement contextuel en texte libre — saisie ajoutée en lot 2 (section
    /// UI dédiée) ; câblé dès maintenant pour ne toucher la signature de
    /// validation qu'une seule fois.
    @State private var contexteLibre: String = ""
    /// Choix **explicite** de l'utilisateur sur l'exclusion des analyses.
    /// `nil` = jamais touché, la valeur suit alors la suggestion automatique
    /// (`exclusionSuggeree`). Un `Bool` simple ne suffit pas : il faut
    /// distinguer « décoché parce que l'utilisateur l'a décoché » de
    /// « décoché par défaut », sinon la suggestion automatique écraserait le
    /// choix manuel à chaque changement d'aliment.
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

    /// Dose couvrant les glucides du repas — c'est elle qu'on confronte au
    /// ratio, pas `totalInjecte`. Le repas peut porter **deux ajustements
    /// distincts**, à traiter différemment vis-à-vis du ratio :
    /// - `ajustements` (`[Ajustement]`, ex. "sport récent") : modulent la
    ///   dose *pour les glucides* (le repas en nécessite moins/plus dans ce
    ///   contexte) → **inclus** ici.
    /// - `correctionHyper` : répond à la glycémie du moment, pas aux
    ///   glucides du repas ; **exclu**, positif ou négatif. L'inclure
    ///   faussait le constat de cohérence dès qu'on ajoutait une correction
    ///   (la dose totale ne respectait alors plus le ratio, alors que la
    ///   part "repas" le respectait toujours).
    /// En mode dose globale, la base est la dose globale — la validation du
    /// ratio fonctionne à l'identique (glucides totaux vs dose unique).
    private var doseCouvrantGlucides: Double {
        max(0, doseBaseRepas + totalAjustements)
    }

    // MARK: - Exclusion des analyses

    /// Repas sans aucune insuline : la réponse glycémique n'est pas
    /// interprétable (c'est exactement le cas `EtatAnalyse.sansInjection` de
    /// l'assembleur), donc l'exclure des analyses n'est pas un choix mais un
    /// constat — le toggle est forcé et désactivé.
    private var exclusionForcee: Bool {
        !aliments.isEmpty && totalInjecte == 0
    }

    /// Repas de pur resucrage : tous les aliments sont marqués « pris pour
    /// traiter une hypoglycémie » et aucun ne porte de dose. Ce n'est pas un
    /// repas ordinaire, sa réponse glycémique polluerait le mining du ratio —
    /// on le pré-coche, mais l'utilisateur reste libre de décocher.
    /// La condition « aucune insuline par aliment » est explicite : un
    /// resucrage bolusé (rare mais possible) reste un repas analysable.
    private var exclusionSuggeree: Bool {
        !aliments.isEmpty
            && aliments.allSatisfy { $0.resucrage }
            && aliments.allSatisfy { ($0.doseInsuline ?? 0) == 0 }
    }

    /// Valeur effective du toggle : le forçage prime, puis le choix manuel,
    /// puis la suggestion automatique.
    private var exclureDesAnalyses: Bool {
        if exclusionForcee { return true }
        return exclusionManuelle ?? exclusionSuggeree
    }

    /// Explication affichée sous le toggle — `nil` quand l'état courant n'a
    /// rien d'automatique à justifier.
    private var raisonExclusionAuto: String? {
        if exclusionForcee {
            return "Ce repas n'a aucune dose d'insuline : sa réponse glycémique n'est pas analysable."
        }
        if exclusionManuelle == nil && exclusionSuggeree {
            return "Tous les aliments sont marqués comme resucrage — pré-coché, décochable si besoin."
        }
        return nil
    }

    private var contexteInsights: ContexteInsights {
        // T0 = heure du repas (réglable, préremplie à l'heure actuelle), et la
        // section (pour le ratio par moment) en découle via les horaires du profil.
        let section = SectionRepas(
            heure: heureRepas,
            horaires: ProfilService.shared.profil.horairesRepas
        )
        return InsightsService.contexte(
            doseSaisie: doseCouvrantGlucides,
            glucides: glucidesTotal,
            heure: heureRepas,
            section: section,
            contexte: modelContext,
            analyseRatioObserve: analyseRatioService.analyse
        )
    }

    // MARK: - Corps

    var body: some View {
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
                SectionDateHeure(date: $heureRepas)

                ListeAlimentsSection(
                    aliments: $aliments,
                    onEditer: { entreeEnEdition = $0 },
                    onAjouterUnAliment: onAjouterUnAliment
                )

                SectionContexteRepas(contexteLibre: $contexteLibre)

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
                InsightsSection(contexte: contexteInsights)

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
                onValider: {
                    onValiderRepas(
                        totalInjecte, siteInjection, heureRepas, doseGlobale, correctionHyper,
                        ajustements, contexteLibre.isEmpty ? nil : contexteLibre, exclureDesAnalyses
                    )
                }
            )
        }
        // Dernier aliment supprimé (swipe dans ListeAlimentsSection) → plus
        // rien à composer, on referme au lieu de laisser la sheet ouverte
        // sur un repas vide avec juste un bouton désactivé.
        .onChange(of: aliments.isEmpty) { _, videMaintenant in
            if videMaintenant { dismiss() }
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
        onValiderRepas: { _, _, _, _, _, _, _, _ in }
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
        onValiderRepas: { _, _, _, _, _, _, _, _ in }
    )
    .environment(RepasService.apercu())
    .environment(AnalyseRatioService())
    .modelContainer(for: [Injection.self, ActiviteSportive.self], inMemory: true)
}
#endif
