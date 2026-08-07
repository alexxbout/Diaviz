//
//  DetailActiviteVue.swift
//  diaviz
//
//  Created by Alexandre on 02/05/2026.
//

import SwiftUI

// MARK: - DetailActiviteVue
//
// Page de détail d'une activité sportive, pushée depuis la
// `LigneActiviteSport` via un `NavigationLink` :
//
// 1. **Frise** — courbe parcourable + liste des événements corrélés
//    (`FriseSeanceSportive`). Sa barre de contexte porte le bilan
//    glycémique de la séance.
// 2. **Chiffres clés** — bilan sur l'effort, IOB au départ, glucides
//    pré-sport, en trois colonnes.
// 3. **Données santé** — uniquement si source = HealthKit (FC, calories,
//    distance).
// 4. **Détails** — quand, intensité, structure d'effort, source, note.
//
// La page portait auparavant deux redondances, supprimées le 2026-08-07 :
// le type de sport en gros titre alors qu'il est déjà dans la barre de
// navigation, et une carte « Glycémie début / fin / variation » qui
// répétait la barre de contexte du graphique juste au-dessus.
//
// Le menu ⋯ bifurque selon `source` : sheet d'édition complète pour le
// manuel, sheet allégée `SheetEditionActiviteHealthKit` pour le HealthKit.
struct DetailActiviteVue: View {

    // MARK: - Paramètres

    let activite: ActiviteSportive

    /// Réponse glycémique pré-calculée pour cette activité — passée par
    /// le parent (la liste qui ouvre le détail). `nil` = données CGM
    /// insuffisantes, l'écran affichera l'état dégradé approprié.
    let reponse: ReponseGlycemiqueSport?

    /// Délai restant avant que l'analyse devienne disponible (en minutes).
    /// `nil` ou ≤ 0 = pas dans l'état « en attente ». Permet d'afficher
    /// le rendu horloge avec le bon délai depuis l'extérieur — la page
    /// elle-même ne calcule pas la fenêtre temporelle.
    var minutesAttenteRestantes: Int? = nil

    /// Persiste une activité éditée (upsert hub). Fourni par le parent qui
    /// détient le service ; `nil` dans les previews isolées.
    var onEnregistrer: ((ActiviteSportive) -> Void)? = nil

    var onSupprimer: (() -> Void)? = nil

    /// Corrections et resucrages corrélés à cette activité par fenêtre
    /// temporelle — fournis par le parent qui détient le service. Vide dans
    /// les previews isolées.
    var evenements: [EvenementActivite] = []

    // MARK: - Environnement

    @Environment(\.dismiss) private var dismiss

    // MARK: - État local

    @State private var afficherConfirmationSuppression = false
    @State private var sheetActive: SheetEdition?

    // MARK: - Corps

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Graphique en vedette : pleine largeur, sans carte, tout
                // en haut. Sa barre de contexte porte déjà le bilan
                // glycémique (départ → fin, variation) — inutile de le
                // répéter dans une carte de métriques en dessous.
                sectionGraphique

                // Les trois chiffres qui expliquent la séance, d'un coup
                // d'œil : ce qu'a donné l'effort, ce qui était actif au
                // départ, ce qui avait été mangé avant.
                sectionChiffresCles

                if activite.source == .healthKit {
                    sectionDonneesSante
                }
                // Doublonnerait la liste de la frise quand celle-ci s'affiche.
                if friseIndisponible && !activite.alimentsPreSport.isEmpty {
                    sectionAlimentsPreSport
                }
                sectionDetails
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(activite.type.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { menuActions }
        .alert(
            "Supprimer cette activité ?",
            isPresented: $afficherConfirmationSuppression
        ) {
            Button("Supprimer", role: .destructive) { confirmerSuppression() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(messageConfirmationSuppression)
        }
        .sheet(item: $sheetActive) { sheet in
            vueSheet(pour: sheet)
        }
    }

    /// Le message de confirmation diffère selon la source — pour
    /// rassurer l'utilisateur HealthKit que la donnée d'origine reste
    /// dans Apple Santé après suppression côté Diaviz.
    private var messageConfirmationSuppression: String {
        if activite.source == .healthKit {
            return "Cette action est irréversible. L'activité restera disponible dans Apple Santé."
        }
        return "Cette action est irréversible."
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var menuActions: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    sheetActive = (activite.source == .healthKit) ? .editionHealthKit : .editionManuelle
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    afficherConfirmationSuppression = true
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Actions sur l'activité")
            }
        }
    }
    /// Sous-ligne de l'en-tête : « Aujourd'hui à 7h15 · 45min » /
    /// « Hier à 17h30 · 1h » / « Jeudi 30 avr. à 18h45 · 50min ».
    /// Locale `fr_FR` forcée systématiquement — sinon le formatter par
    /// défaut suit la locale du device et affiche par exemple
    /// « Thursday 30 Apr at 6:45 PM ». L'heure est en notation
    /// française usuelle « 7h15 » plutôt que « 07:15 ».
    private var sousLigneEntete: String {
        let cal = Calendar.current
        let jourTexte: String
        if cal.isDateInToday(activite.dateDebut) {
            jourTexte = "Aujourd'hui"
        } else if cal.isDateInYesterday(activite.dateDebut) {
            jourTexte = "Hier"
        } else {
            jourTexte = Self.formatterDateLongue
                .string(from: activite.dateDebut)
                .capitalizedFirstLetter
        }
        let heureTexte = Self.formatterHeure.string(from: activite.dateDebut)
        return "\(jourTexte) à \(heureTexte) · \(formaterDuree(activite.dureeMinutes))"
    }

    /// Formatter du jour long — « jeudi 30 avr. ». Locale française
    /// fixe pour ne pas dépendre du device.
    private static let formatterDateLongue: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMM"
        return f
    }()

    /// Formatter de l'heure — « 7h15 », « 18h45 ». Pattern `H'h'mm`.
    private static let formatterHeure: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "H'h'mm"
        return f
    }()

    // MARK: - Section 2 — Graphique (pleine largeur, sans carte)

    /// Courbe parcourable + liste d'événements dès qu'une réponse CGM est
    /// disponible. Sinon on retombe sur le composant partagé, qui sait
    /// afficher les états dégradés (attente, données manquantes).
    /// `true` quand la frise ne peut pas être rendue (pas de courbe CGM, ou
    /// fenêtre d'analyse encore incomplète).
    private var friseIndisponible: Bool {
        reponse == nil || (minutesAttenteRestantes ?? 0) > 0
    }

    @ViewBuilder
    private var sectionGraphique: some View {
        if let reponse, !friseIndisponible {
            FriseSeanceSportive(
                reponse: reponse,
                activite: activite,
                evenements: evenements
            )
            .padding(.horizontal, 16)
        } else {
            GraphiqueGlycemique.pourSport(
                etat: etatGraphique,
                dureeMinutes: activite.dureeMinutes
            )
            .padding(.horizontal, 16)
        }
    }

    /// Mappe `(reponse, minutesAttenteRestantes)` sur l'état attendu par
    /// `GraphiqueGlycemiqueSport`. Priorité à l'attente : si l'analyse
    /// n'est pas prête, on n'affiche pas une courbe partielle.
    private var etatGraphique: EtatMiniCourbeSport {
        if let minutes = minutesAttenteRestantes, minutes > 0 {
            return .enAttente(minutesRestantes: minutes)
        }
        if let reponse {
            return .disponible(reponse)
        }
        return .donneesManquantes
    }

    // MARK: - Section 3 — Chiffres clés
    //
    // Trois colonnes de largeur égale dans une seule carte de verre, même
    // grammaire que le bandeau de stats de l'écran de séance live.
    //
    // Remplace l'ancienne carte « Glycémie début / fin / variation » :
    // celle-ci répétait mot pour mot ce que la barre de contexte du
    // graphique affiche déjà au repos, à quelques centimètres au-dessus.
    // L'IOB au départ et les glucides pré-sport, eux, n'étaient visibles
    // qu'en fouillant — ce sont pourtant les deux facteurs qui expliquent
    // la variation.

    private var sectionChiffresCles: some View {
        HStack(spacing: 0) {
            colonneChiffre(
                icone: "arrow.left.arrow.right",
                couleur: .secondary,
                titre: "Sur l'effort",
                valeur: bilanGlycemique,
                couleurValeur: reponse.map { couleurVariation(reponse: $0) } ?? .primary
            )
            Divider().frame(height: 42)
            colonneChiffre(
                icone: "drop.fill",
                couleur: .purple,
                titre: "IOB au départ",
                valeur: activite.iobAuDebut.map { $0.doseInsulineFormatee } ?? "—"
            )
            Divider().frame(height: 42)
            colonneChiffre(
                icone: "fork.knife",
                couleur: .green,
                titre: "Pré-sport",
                valeur: glucidesFormate
            )
        }
        .padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func colonneChiffre(
        icone: String,
        couleur: Color,
        titre: String,
        valeur: String,
        couleurValeur: Color = .primary
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icone)
                .font(.footnote)
                .foregroundStyle(couleur)
            Text(titre)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(valeur)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(couleurValeur)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre) : \(valeur)")
    }

    /// « 149 → 147 » quand la courbe est disponible, « — » sinon.
    private var bilanGlycemique: String {
        guard let reponse else { return "—" }
        return "\(Int(reponse.glycemieDebut)) → \(Int(reponse.glycemieFin))"
    }
    /// Couleur du delta selon les seuils de la spec.
    private func couleurVariation(reponse: ReponseGlycemiqueSport) -> Color {
        if reponse.glycemieFin < 70 { return .red }
        if abs(reponse.deltaMgDl) <= 10 { return .green }
        if reponse.deltaMgDl >= -40 && reponse.deltaMgDl <= -10 { return .blue }
        if reponse.deltaMgDl < -40 { return .orange }
        return .primary
    }

    // MARK: - Section 4 — Données santé (HealthKit uniquement)

    @ViewBuilder
    private var sectionDonneesSante: some View {
        if let hk = activite.healthKitData {
            VStack(alignment: .leading, spacing: 8) {
                Text("DONNÉES SANTÉ")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)

                CarteRegroupee {
                    if let fc = hk.fcMoyenne {
                        LigneMetrique(
                            libelle: "FC moyenne",
                            valeur: "\(Int(fc)) bpm",
                            couleur: nil
                        )
                        Divider().padding(.leading, 16)
                    }
                    if let fcMax = hk.fcMax {
                        LigneMetrique(
                            libelle: "FC max",
                            valeur: "\(Int(fcMax)) bpm",
                            couleur: nil
                        )
                        Divider().padding(.leading, 16)
                    }
                    if let cal = hk.caloriesActives {
                        LigneMetrique(
                            libelle: "Calories actives",
                            valeur: "\(Int(cal)) kcal",
                            couleur: nil
                        )
                    }
                    if let dist = hk.distanceMetres {
                        Divider().padding(.leading, 16)
                        LigneMetrique(
                            libelle: "Distance",
                            valeur: distanceFormatee(dist),
                            couleur: nil
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    // MARK: - Section 4ter — Glucides pré-sport (détail par aliment)
    //
    // Conservée pour les cas où la frise n'est pas rendue (pas de réponse
    // CGM, ou analyse encore en attente) — la frise reprend cette liste dans
    // son propre récapitulatif dès qu'elle s'affiche, inutile de la doubler.

    private var sectionAlimentsPreSport: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GLUCIDES PRÉ-SPORT")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            CarteRegroupee {
                ForEach(Array(activite.alimentsPreSport.enumerated()), id: \.element.id) { index, aliment in
                    if index > 0 {
                        Divider().padding(.leading, 16)
                    }
                    CarteAlimentEnregistre(
                        emoji: aliment.emojiAffiche,
                        nom: aliment.nomAffiche,
                        quantite: aliment.quantite,
                        glucides: aliment.glucides,
                        insuline: 0
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Section 5 — Détails
    //
    // Fusionne l'ancien en-tête (type, date, durée, source) et l'ancien
    // bloc « Contexte » en une seule carte.
    //
    // Le type de sport était affiché deux fois — en titre de barre de
    // navigation *et* en gros titre ici. La ligne « Glucides pré-sport »
    // a migré vers les chiffres clés. La structure d'effort, elle, était
    // absente de la page alors qu'elle est obligatoire à la saisie pour
    // les sports cardio.

    private var sectionDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DÉTAILS")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            CarteRegroupee {
                LigneMetrique(libelle: "Quand", valeur: sousLigneEntete, couleur: nil)
                Divider().padding(.leading, 16)
                LigneMetrique(
                    libelle: "Intensité",
                    valeur: activite.intensite.rawValue,
                    couleur: nil
                )
                if let structure = activite.structureEffort {
                    Divider().padding(.leading, 16)
                    LigneMetrique(libelle: "Effort", valeur: structure.rawValue, couleur: nil)
                }
                if activite.source == .healthKit {
                    Divider().padding(.leading, 16)
                    LigneMetrique(libelle: "Source", valeur: "Apple Santé", couleur: nil)
                }
                Divider().padding(.leading, 16)
                ligneNote
            }
            .padding(.horizontal, 16)
        }
    }

    /// Ligne note avec rendu spécial : si vide on affiche « Pas de note »
    /// en `.secondary`. Différent des autres lignes, donc inline plutôt
    /// que `LigneMetrique`.
    private var ligneNote: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Note")
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(noteAffichee)
                .font(.body.weight(noteVide ? .regular : .semibold))
                .foregroundStyle(noteVide ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func formaterDuree(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }

    private func distanceFormatee(_ metres: Double) -> String {
        if metres >= 1000 {
            return String(format: "%.1f km", metres / 1000)
                .replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int(metres)) m"
    }

    private var glucidesFormate: String {
        let g = activite.glucidesPreSportTotal
        guard g > 0 else { return "—" }
        return g == floor(g) ? "\(Int(g)) g" : String(format: "%.1f g", g)
    }

    private var noteVide: Bool {
        (activite.note?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    private var noteAffichee: String {
        noteVide ? "Pas de note" : (activite.note ?? "")
    }

    // MARK: - Sheets

    @ViewBuilder
    private func vueSheet(pour sheet: SheetEdition) -> some View {
        switch sheet {
        case .editionManuelle:
            SheetNouvelleActivite(
                activiteExistante: activite,
                onValider: { nouvelle in
                    // Upsert hub par `id` : la sheet réémet l'activité avec
                    // l'`id` d'origine, donc `enregistrer` remplace l'existante
                    // plutôt que de doublonner. On revient en arrière pour que
                    // l'utilisateur voie la liste rafraîchie.
                    onEnregistrer?(nouvelle)
                    dismiss()
                }
            )
        case .editionHealthKit:
            SheetEditionActiviteHealthKit(
                activite: activite,
                onValider: { nouvelle in
                    onEnregistrer?(nouvelle)
                    dismiss()
                }
            )
        }
    }

    // MARK: - Actions

    private func confirmerSuppression() {
        onSupprimer?()
        dismiss()
    }
}

// MARK: - SheetEdition (routage interne)

private enum SheetEdition: Identifiable {
    case editionManuelle
    case editionHealthKit

    var id: String {
        switch self {
        case .editionManuelle:    "manuelle"
        case .editionHealthKit:   "healthkit"
        }
    }
}

// MARK: - Mocks pour previews
//
// Trois variantes pour exercer les différents rendus de la page :
// activité manuelle simple, activité HealthKit avec FC/cal/distance,
// activité avec hypoglycémie en fin de séance (variation rouge).

extension ActiviteSportive {

    /// Activité saisie à la main — pas de section « Données santé »,
    /// la sheet d'édition complète s'ouvre depuis le menu ⋯. IOB
    /// faible (0.5u) pour exercer le rendu orange « Modéré » de la
    /// section IOB.
    static var mockManuel: ActiviteSportive {
        let heure = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: Date()) ?? Date()
        return ActiviteSportive(
            type: .musculation,
            dateDebut: heure,
            dureeMinutes: 50,
            intensite: .intense,
            alimentsPreSport: [],
            note: "Séance jambes",
            source: .manuel,
            iobAuDebut: 0.5
        )
    }

    /// Activité importée depuis HealthKit — déclenche l'affichage de la
    /// section « Données santé » et oriente le menu ⋯ vers la sheet
    /// d'édition allégée. IOB moyen (1.2u → niveau « Élevé », rouge).
    static var mockHealthKit: ActiviteSportive {
        let heure = Calendar.current.date(bySettingHour: 7, minute: 15, second: 0, of: Date()) ?? Date()
        return ActiviteSportive(
            type: .course,
            dateDebut: heure,
            dureeMinutes: 45,
            intensite: .moderee,
            alimentsPreSport: [.collationGenerique(glucidesGrammes: 15)],
            note: "Footing matinal au parc",
            source: .healthKit,
            healthKitData: HealthKitWorkoutData(
                workoutUUID: UUID(),
                fcMoyenne: 145,
                fcMax: 168,
                caloriesActives: 420,
                distanceMetres: 7200,
                sourceAppareil: "Apple Watch Series 9"
            ),
            iobAuDebut: 1.2
        )
    }

    /// Activité avec hypoglycémie en fin de séance — pour valider le
    /// rendu rouge de la ligne « Variation » et la couleur du marqueur
    /// de fin sur le graphique. IOB élevé (2.5u) cohérent avec le
    /// risque hypo : démarrer une longue sortie vélo intense avec
    /// 2.5u d'IOB est typiquement le scénario qui produit l'hypo.
    static var mockAvecHypo: ActiviteSportive {
        let heure = Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: Date()) ?? Date()
        return ActiviteSportive(
            type: .velo,
            dateDebut: heure,
            dureeMinutes: 90,
            intensite: .intense,
            alimentsPreSport: [],
            note: "Sortie longue sans collation pré-sport",
            source: .manuel,
            iobAuDebut: 2.5
        )
    }

    // MARK: Mocks dédiés au test du badge IOB
    //
    // Les trois suivants existent pour exercer chaque branche du
    // `couleurIOB` / `libelleNiveauIOB` indépendamment des cas
    // ci-dessus. Pas de note ni de glucides pour rester focalisé.

    /// IOB modéré — 0.5u, rendu orange « Modéré ».
    static var mockAvecIOBModere: ActiviteSportive {
        let heure = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
        return ActiviteSportive(
            type: .yoga,
            dateDebut: heure,
            dureeMinutes: 30,
            intensite: .faible,
            iobAuDebut: 0.5
        )
    }

    /// IOB élevé — 2.5u, rendu rouge « Très élevé ». Démarrer une
    /// séance avec 2.5u d'IOB est cliniquement risqué : la card
    /// rouge doit attirer l'œil immédiatement.
    static var mockAvecIOBEleve: ActiviteSportive {
        let heure = Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: Date()) ?? Date()
        return ActiviteSportive(
            type: .course,
            dateDebut: heure,
            dureeMinutes: 45,
            intensite: .moderee,
            iobAuDebut: 2.5
        )
    }

    /// Aucun IOB — la section « Insuline active » doit être
    /// totalement masquée (et non remplie d'un placeholder).
    static var mockSansIOB: ActiviteSportive {
        let heure = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        return ActiviteSportive(
            type: .marche,
            dateDebut: heure,
            dureeMinutes: 60,
            intensite: .faible,
            iobAuDebut: nil
        )
    }
}

// MARK: - String helper
//
// Capitalise uniquement la première lettre. `String.capitalized`
// capitalise CHAQUE mot et transformerait « jeudi 30 avr. » en
// « Jeudi 30 Avr. ». Ici on veut juste la majuscule en début de phrase.
private extension String {
    var capitalizedFirstLetter: String {
        guard let premiere = first else { return self }
        return String(premiere).uppercased() + dropFirst()
    }
}

// MARK: - Aperçu

#Preview("Activité manuelle") {
    NavigationStack {
        DetailActiviteVue(
            activite: .mockManuel,
            reponse: ActivitesSportService.genererReponse(pour: .mockManuel)
        )
    }
}

#Preview("Activité Apple Health") {
    NavigationStack {
        DetailActiviteVue(
            activite: .mockHealthKit,
            reponse: ActivitesSportService.genererReponse(pour: .mockHealthKit)
        )
    }
}

#Preview("Activité avec hypo") {
    // On force une réponse synthétique avec hypo en fin de séance pour
    // exercer la coloration rouge de la ligne « Variation ». Construite
    // à la main parce que le générateur mock du service ne descend pas
    // toujours en hypo selon le type/intensité passés.
    let reponseHypo = ReponseGlycemiqueSport(
        pointsCgm: pointsAvecHypo(dureeMinutes: ActiviteSportive.mockAvecHypo.dureeMinutes),
        glycemieDebut: 130,
        glycemieFin: 62,
        deltaMgDl: -68
    )
    NavigationStack {
        DetailActiviteVue(
            activite: .mockAvecHypo,
            reponse: reponseHypo
        )
    }
}

#Preview("Activité - IOB modéré") {
    NavigationStack {
        DetailActiviteVue(
            activite: .mockAvecIOBModere,
            reponse: ActivitesSportService.genererReponse(pour: .mockAvecIOBModere)
        )
    }
}

#Preview("Activité - IOB élevé") {
    NavigationStack {
        DetailActiviteVue(
            activite: .mockAvecIOBEleve,
            reponse: ActivitesSportService.genererReponse(pour: .mockAvecIOBEleve)
        )
    }
}

#Preview("Activité - Pas d'IOB") {
    NavigationStack {
        DetailActiviteVue(
            activite: .mockSansIOB,
            reponse: ActivitesSportService.genererReponse(pour: .mockSansIOB)
        )
    }
}

/// Génère une courbe synthétique partant de 130 mg/dL et descendant en
/// hypoglycémie (62 mg/dL) en fin de séance. Utilisée uniquement par le
/// preview « Activité avec hypo » — extrait en fonction libre pour ne
/// pas alourdir le `#Preview` lui-même.
private func pointsAvecHypo(dureeMinutes: Int) -> [PointCgmSport] {
    let pas: TimeInterval = 5 * 60
    let dureeSec = TimeInterval(dureeMinutes * 60)
    let debut: TimeInterval = -30 * 60
    let fin: TimeInterval = dureeSec + 30 * 60
    var points: [PointCgmSport] = []
    var t = debut
    while t <= fin {
        let valeur: Double
        if t <= 0 {
            valeur = 130
        } else if t <= dureeSec {
            // Descente linéaire 130 → 62 sur la durée d'effort
            let progression = t / dureeSec
            valeur = 130 - 68 * progression
        } else {
            // Léger rebond après la fin
            let dt = (t - dureeSec) / (30 * 60)
            valeur = 62 + 8 * dt
        }
        points.append(PointCgmSport(secondesDepuisDebut: t, valeur: valeur))
        t += pas
    }
    return points
}
