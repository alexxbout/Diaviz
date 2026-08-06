//
//  SeanceEnCoursVue.swift
//  diaviz
//

import SwiftUI

/// Écran plein écran d'une séance chronométrée en cours. Chrono central
/// animé, statut (en cours / en pause), historique des événements de la
/// séance, actions de saisie (correction / resucrage) et contrôles du
/// chrono (pause·reprendre / terminer).
///
/// Le chrono s'anime via `Text(_, style: .timer)` piloté par le système : le
/// temps affiché est recalculé depuis les horodatages de la `session` (pas de
/// `Timer` à gérer), donc reste juste après un passage en arrière-plan.
///
/// La vue ne détient pas la logique du chrono : elle lit
/// `SessionSportService.shared` et déclenche pause/reprise. « Terminer »
/// remonte le brouillon d'activité au parent (qui ouvre la sheet
/// d'enregistrement pré-remplie), « Annuler » abandonne la séance.
struct SeanceEnCoursVue: View {

    let session: SessionSportiveEnCours

    /// Remonte le brouillon (durée chronométrée) pour l'enregistrement.
    var onTerminer: (ActiviteSportive) -> Void
    /// Abandon sans enregistrer.
    var onAnnuler: () -> Void

    @State private var service = SessionSportService.shared
    @State private var afficherConfirmationAnnuler = false

    /// Services médications/resucrage **locaux** — même pattern que
    /// `SportVue`/`JournalVue` : pas de partage nécessaire, juste écrire et
    /// lire l'historique de la séance depuis cet écran.
    @Environment(\.modelContext) private var modelContext
    @State private var injectionsService = InjectionsService()
    @State private var resucragesService = ResucragesService()

    /// Sheet active — un seul `.sheet(item:)` plutôt que deux booléens,
    /// même pattern que `MedicationsVue` (évite les conflits de présentation).
    @State private var sheetActive: SheetSeance?

    var body: some View {
        VStack(spacing: 0) {
            barreHaut

            ScrollView {
                VStack(spacing: 32) {
                    contenuCentral
                    sectionHistorique
                }
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            piedActions
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .confirmationDialog(
            "Abandonner cette séance ?",
            isPresented: $afficherConfirmationAnnuler,
            titleVisibility: .visible
        ) {
            Button("Abandonner", role: .destructive) { onAnnuler() }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Le chrono en cours sera perdu, sans enregistrement.")
        }
        // Racine du body — jamais sur un fragment recalculé (Section, etc.),
        // sinon présentation instable (voir `SectionAlimentsAjoutes`).
        .sheet(item: $sheetActive) { sheet in
            vueSheet(pour: sheet)
        }
        .task { demarrerServices() }
        // Reflète un resucrage/correction ajouté ailleurs (Journal) pendant
        // que la séance tourne en arrière-plan.
        .onAppear { demarrerServices() }
    }

    // MARK: - Barre du haut

    private var barreHaut: some View {
        HStack {
            Button("Annuler") { afficherConfirmationAnnuler = true }
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 16)
    }

    // MARK: - Contenu central (chrono)

    private var contenuCentral: some View {
        VStack(spacing: 10) {
            badgeStatut
                .padding(.bottom, 14)

            Image(systemName: session.type.icone)
                .font(.system(size: 32))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(session.type.rawValue)
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            chrono

            Text("démarrée à \(heureDebut)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var badgeStatut: some View {
        let enPause = session.enPause
        return HStack(spacing: 6) {
            Circle()
                .fill(enPause ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
            Text(enPause ? "En pause" : "En cours")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(enPause ? .orange : .green)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background((enPause ? Color.orange : Color.green).opacity(0.15), in: Capsule())
    }

    /// Chrono central. En cours : `Text(_, style: .timer)` piloté par le
    /// système (fluide, sans redraw manuel). En pause : valeur figée.
    @ViewBuilder
    private var chrono: some View {
        Group {
            if session.enPause {
                Text(chronoFormate(session.secondesEcoulees()))
            } else {
                Text(session.dateReference, style: .timer)
                    .multilineTextAlignment(.center)
            }
        }
        .font(.system(size: 62, weight: .medium, design: .rounded))
        .monospacedDigit()
    }

    // MARK: - Historique de la séance
    //
    // Bandeau de 3 stats (dernière correction, IOB active, dernier resucrage)
    // dans une carte unique — colonnes de largeur égale séparées par des
    // filets, plutôt que 3 cartes indépendantes de hauteurs inégales. Suivi
    // de la liste des événements survenus depuis le début de la séance.
    // Lecture seule : la saisie passe par les boutons du pied.

    private var sectionHistorique: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pendant la séance")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            bandeauStats

            if evenements.isEmpty {
                messageAucunEvenement
            } else {
                listeEvenements
            }
        }
    }

    private var bandeauStats: some View {
        HStack(spacing: 0) {
            colonneStat(
                icone: "syringe",
                couleur: .blue,
                titre: "Correction",
                valeur: texteDerniereCorrection
            )
            Divider().frame(height: 42)
            colonneStat(
                icone: "drop.fill",
                couleur: .purple,
                titre: "IOB active",
                valeur: texteIOB
            )
            Divider().frame(height: 42)
            colonneStat(
                icone: "cross.case.fill",
                couleur: .red,
                titre: "Resucrage",
                valeur: texteDernierResucrage
            )
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func colonneStat(
        icone: String,
        couleur: Color,
        titre: String,
        valeur: String
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
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre) : \(valeur)")
    }

    private var messageAucunEvenement: some View {
        Text("Aucune correction ni resucrage depuis le début de la séance.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }

    private var listeEvenements: some View {
        VStack(spacing: 0) {
            ForEach(evenements) { evenement in
                ligneEvenement(evenement)
                if evenement.id != evenements.last?.id {
                    Divider().padding(.leading, 48)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func ligneEvenement(_ evenement: EvenementSeance) -> some View {
        HStack(spacing: 12) {
            Image(systemName: evenement.icone)
                .font(.subheadline)
                .foregroundStyle(evenement.couleur)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(evenement.titre)
                    .font(.subheadline)
                Text(Self.formatterHeure.string(from: evenement.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Text(evenement.detail)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pied — actions
    //
    // Deux registres séparés visuellement : saisie d'événements
    // (correction / resucrage) au-dessus, contrôle du chrono en dessous.
    // Le bouton correction était initialement dans la barre du haut —
    // remonté ici (2026-08-06) : trop peu accessible au pouce pendant
    // l'effort.

    private var piedActions: some View {
        VStack(spacing: 10) {
            Divider()
                .padding(.bottom, 4)

            HStack(spacing: 10) {
                boutonAction(
                    titre: "Correction",
                    systemImage: "syringe",
                    couleur: .blue
                ) { sheetActive = .correction }

                boutonAction(
                    titre: "Resucrage",
                    systemImage: "cross.case.fill",
                    couleur: .red
                ) { sheetActive = .resucrage }
            }

            HStack(spacing: 10) {
                if session.enPause {
                    boutonPrincipal(
                        titre: "Reprendre",
                        systemImage: "play.fill",
                        couleur: .green
                    ) { service.reprendre() }
                } else {
                    boutonPrincipal(
                        titre: "Pause",
                        systemImage: "pause.fill",
                        couleur: Color(.secondarySystemGroupedBackground),
                        teinteTexte: .primary
                    ) { service.pause() }
                }

                boutonPrincipal(
                    titre: "Terminer",
                    systemImage: "stop.fill",
                    couleur: Color(.secondarySystemGroupedBackground),
                    teinteTexte: .red
                ) {
                    if let brouillon = service.terminer() {
                        onTerminer(brouillon)
                    }
                }
            }
        }
    }

    /// Bouton de saisie — teinté, plus discret que les contrôles du chrono
    /// (registre secondaire : on enregistre un fait, on ne pilote pas la
    /// séance).
    private func boutonAction(
        titre: String,
        systemImage: String,
        couleur: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(titre, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(couleur)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(couleur.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func boutonPrincipal(
        titre: String,
        systemImage: String,
        couleur: Color,
        teinteTexte: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(titre, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(teinteTexte)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(couleur, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func vueSheet(pour sheet: SheetSeance) -> some View {
        switch sheet {
        case .correction:
            SheetCorrection(
                derniereZoneRapide: injectionsService.injections
                    .filter { $0.type != .lente }
                    .max { $0.heure < $1.heure }?
                    .zoneInjection,
                onValider: { injectionsService.enregistrer($0) }
            )
        case .resucrage:
            SheetNouveauResucrage(
                onValider: { resucragesService.enregistrer($0) }
            )
        }
    }

    // MARK: - Historique — données

    /// Corrections et resucrages survenus depuis le début de la séance,
    /// triés du plus récent au plus ancien.
    private var evenements: [EvenementSeance] {
        let corrections = injectionsService.injections
            .filter { $0.type != .lente && $0.heure >= session.dateDebut }
            .map { injection in
                EvenementSeance(
                    id: "correction-\(injection.id.uuidString)",
                    date: injection.heure,
                    icone: "syringe",
                    couleur: .blue,
                    titre: "Correction",
                    detail: injection.dose.doseInsulineFormatee
                )
            }
        let resucrages = resucragesService.resucrages
            .filter { $0.date >= session.dateDebut }
            .map { resucrage in
                EvenementSeance(
                    id: "resucrage-\(resucrage.id.uuidString)",
                    date: resucrage.date,
                    icone: resucrage.intention.icone,
                    couleur: resucrage.intention.couleur,
                    titre: resucrage.intention.rawValue,
                    detail: "\(resucrage.glucidesTotal)g"
                )
            }
        return (corrections + resucrages).sorted { $0.date > $1.date }
    }

    private var texteDerniereCorrection: String {
        injectionsService.injections
            .filter { $0.type != .lente && $0.heure >= session.dateDebut }
            .map(\.heure)
            .max()
            .map { texteDepuis($0) } ?? "Aucune"
    }

    private var texteDernierResucrage: String {
        resucragesService.resucrages
            .filter { $0.date >= session.dateDebut }
            .map(\.date)
            .max()
            .map { texteDepuis($0) } ?? "Aucun"
    }

    private var texteIOB: String {
        IOBService.iobDuHub(a: Date(), contexte: modelContext).doseInsulineFormatee
    }

    /// Durée écoulée, formulée court pour tenir dans une colonne de stat.
    private func texteDepuis(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "à l'instant" }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }

    // MARK: - Helpers

    private func demarrerServices() {
        injectionsService.demarrer(contexte: modelContext)
        resucragesService.demarrer(contexte: modelContext)
    }

    private var heureDebut: String {
        Self.formatterHeure.string(from: session.dateDebut)
    }

    private static let formatterHeure: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "H'h'mm"
        return f
    }()

    /// Format aligné sur `Text(_, style: .timer)` (utilisé quand la séance
    /// tourne) : « m:ss » sous une heure, « h:mm:ss » au-delà. Sans ça, le
    /// passage en pause changeait de format (« 0:32 » → « 00:00:33 »).
    private func chronoFormate(_ secondes: TimeInterval) -> String {
        let total = Int(secondes.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Routage des sheets

private enum SheetSeance: Identifiable {
    case correction
    case resucrage

    var id: String {
        switch self {
        case .correction: "correction"
        case .resucrage:  "resucrage"
        }
    }
}

// MARK: - EvenementSeance

/// Entrée d'historique affichée pendant la séance — correction ou
/// resucrage, unifiés pour un seul flux chronologique.
private struct EvenementSeance: Identifiable {
    let id: String
    let date: Date
    let icone: String
    let couleur: Color
    let titre: String
    let detail: String
}

#Preview("En cours") {
    SeanceEnCoursVue(
        session: SessionSportiveEnCours(type: .course, dateDebut: Date().addingTimeInterval(-754)),
        onTerminer: { _ in },
        onAnnuler: {}
    )
}

#Preview("En pause") {
    SeanceEnCoursVue(
        session: SessionSportiveEnCours(
            type: .velo,
            dateDebut: Date().addingTimeInterval(-1230),
            secondesPauseCumulees: 0,
            debutPauseCourante: Date().addingTimeInterval(-30)
        ),
        onTerminer: { _ in },
        onAnnuler: {}
    )
}
