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
///
/// **Liquid Glass (iOS 26)** — l'écran est construit en profondeur : un fond
/// teinté par l'état (vert en cours / orange en pause) sert de matière que le
/// verre réfracte, le contenu défile *derrière* un pied d'actions flottant, et
/// le chrono morphe d'une capsule de verre à l'autre au changement d'état.
/// Le chrono et les libellés d'action restent pleinement opaques : cet écran
/// se lit en plein effort, parfois en plein soleil — le verre habille le
/// chrome, jamais l'information critique.
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

    /// Espace réservé sous le contenu défilant pour que la dernière ligne ne
    /// finisse jamais masquée par le pied flottant.
    private let hauteurPiedFlottant: CGFloat = 148

    /// Namespace du morphing Liquid Glass — le chrono et le badge de statut
    /// changent de forme d'un état à l'autre en conservant leur identité de
    /// verre (`glassEffectID`), au lieu d'un remplacement sec.
    @Namespace private var verre

    /// Teinte ambiante de l'écran, dérivée de l'état de la séance. C'est elle
    /// que le verre du pied et des cartes réfracte — sans cette matière
    /// derrière, le Liquid Glass ne se verrait pas sur un fond uni.
    private var teinteEtat: Color {
        session.enPause ? .orange : .green
    }

    var body: some View {
        ZStack {
            fondAmbiant

            VStack(spacing: 0) {
                barreHaut

                ScrollView {
                    VStack(spacing: 32) {
                        contenuCentral
                        sectionHistorique
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 20)
                    .padding(.bottom, hauteurPiedFlottant)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            // Pied flottant : le contenu défile *dessous*, ce qui donne au
            // verre quelque chose à réfracter en continu.
            VStack {
                Spacer()
                piedActions
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.45), value: session.enPause)
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

    // MARK: - Fond ambiant
    //
    // Halo teinté par l'état, posé sur le fond groupé standard. Sert deux
    // rôles : feedback d'état ambiant (vert → orange au passage en pause,
    // animé) et matière réfractée par le verre du pied et des cartes.

    private var fondAmbiant: some View {
        ZStack {
            Color(.systemGroupedBackground)

            RadialGradient(
                colors: [teinteEtat.opacity(0.28), teinteEtat.opacity(0.04), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )

            RadialGradient(
                colors: [teinteEtat.opacity(0.20), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Barre du haut

    private var barreHaut: some View {
        HStack {
            Button("Annuler") { afficherConfirmationAnnuler = true }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Contenu central (chrono)

    private var contenuCentral: some View {
        GlassEffectContainer(spacing: 18) {
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
    }

    /// Badge d'état en verre teinté — c'est l'élément qui change de sens au
    /// tap sur Pause, le verre teinté le rend vivant sans le rendre criard.
    private var badgeStatut: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(teinteEtat)
                .frame(width: 7, height: 7)
            Text(session.enPause ? "En pause" : "En cours")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(teinteEtat)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular.tint(teinteEtat.opacity(0.22)), in: Capsule())
        .glassEffectID("statut", in: verre)
    }

    /// Chrono central, posé sur une capsule de verre teintée par l'état.
    /// `glassEffectID` fait **morpher** la capsule entre les deux états
    /// (timer système ↔ valeur figée) au lieu d'un remplacement sec.
    ///
    /// Le texte lui-même reste `.primary` plein : c'est l'information la plus
    /// consultée de l'écran, elle ne doit rien perdre en contraste.
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
        .foregroundStyle(.primary)
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .glassEffect(
            .regular.tint(teinteEtat.opacity(0.14)),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .glassEffectID("chrono", in: verre)
    }

    // MARK: - Historique de la séance
    //
    // Bandeau de 3 stats (dernière correction, IOB active, dernier resucrage)
    // dans une carte unique — colonnes de largeur égale séparées par des
    // filets, plutôt que 3 cartes indépendantes de hauteurs inégales. Suivi
    // de la liste des événements survenus depuis le début de la séance.
    // Lecture seule : la saisie passe par les boutons du pied.
    //
    // Les deux cartes sont en verre, groupées dans un `GlassEffectContainer`
    // pour que leurs matières se fondent de façon cohérente.

    private var sectionHistorique: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pendant la séance")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 10) {
                    bandeauStats

                    if evenements.isEmpty {
                        messageAucunEvenement
                    } else {
                        listeEvenements
                    }
                }
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
        .surfaceCarteVerre()
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
            .surfaceCarteVerre()
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
        .surfaceCarteVerre()
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

    // MARK: - Pied — actions flottantes
    //
    // Deux registres séparés visuellement : saisie d'événements
    // (correction / resucrage) au-dessus, contrôle du chrono en dessous.
    // Le bouton correction était initialement dans la barre du haut —
    // descendu ici (2026-08-06) : trop peu accessible au pouce pendant
    // l'effort.
    //
    // Le pied **flotte** au-dessus du `ScrollView` : c'est ce qui donne au
    // verre du contenu à réfracter quand on fait défiler l'historique.

    private var piedActions: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 10) {
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
                            teinte: .green
                        ) { service.reprendre() }
                    } else {
                        boutonPrincipal(
                            titre: "Pause",
                            systemImage: "pause.fill",
                            teinte: .primary
                        ) { service.pause() }
                    }

                    boutonPrincipal(
                        titre: "Terminer",
                        systemImage: "stop.fill",
                        teinte: .red
                    ) {
                        if let brouillon = service.terminer() {
                            onTerminer(brouillon)
                        }
                    }
                }
            }
            .padding(14)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    /// Bouton de saisie — verre teinté, registre secondaire : on enregistre
    /// un fait, on ne pilote pas la séance.
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
                .glassEffect(
                    .regular.tint(couleur.opacity(0.18)).interactive(),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    /// Contrôle du chrono — verre interactif, libellé plein contraste.
    private func boutonPrincipal(
        titre: String,
        systemImage: String,
        teinte: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(titre, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(teinte)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .glassEffect(
                    .regular.tint(teinte == .primary ? .clear : teinte.opacity(0.20)).interactive(),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
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

#if DEBUG
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
#endif
