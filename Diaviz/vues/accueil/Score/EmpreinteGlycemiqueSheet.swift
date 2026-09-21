//
//  EmpreinteGlycemiqueSheet.swift
//  diaviz
//
//  Extrait de EmpreinteGlycemiqueVue.swift — couplé à ScoreService, donc
//  hors du périmètre partagé avec l'extension widget.
//

import SwiftUI

/// Sheet ouverte par tap sur `CercleScoreDetail` — empreinte en grand
/// (280pt), navigable jour par jour (chevrons) pour comparer les empreintes
/// précédentes. `.id(jour)` sur `EmpreinteGlycemiqueVue` force une nouvelle
/// identité de vue à chaque changement de jour, ce qui rejoue l'animation
/// d'apparition centre → bord sans état à réinitialiser manuellement.
///
/// Deux détentes : `.medium` montre uniquement l'empreinte sélectionnée ;
/// glisser vers `.large` révèle en dessous un historique des empreintes
/// des jours précédents, en petit, pour comparer d'un coup d'œil.
struct EmpreinteGlycemiqueSheet: View {
    let service: ScoreService
    @State private var jour: Date
    @State private var detente: PresentationDetent = .medium

    @Environment(\.dismiss) private var dismiss

    init(service: ScoreService, jourInitial: Date) {
        self.service = service
        self._jour = State(initialValue: jourInitial)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(spacing: 28) {
                    navigationJour
                    EmpreinteGlycemiqueVue(anneaux: anneaux(pour: jour), score: score(pour: jour), diametre: 260, anime: true, vivante: true, plaqueElevee: true)
                        .id(jour)
                    if detente == .large {
                        historique
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Empreinte du jour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detente)
        .presentationDragIndicator(.visible)
    }

    /// Grille 3 colonnes des jours précédents (petites empreintes,
    /// statiques) — pensée pour comparer d'un coup d'œil, sans avoir à
    /// sélectionner chaque jour un par un. Le tap reste possible pour
    /// afficher un jour en grand au-dessus.
    ///
    /// `Grid` (non paresseuse) plutôt que `LazyVGrid` : sur 21 cellules, le
    /// coût de tout instancier d'un coup est négligeable, et ça évite le
    /// bug visuel d'un `LazyVGrid` dont les lignes s'instancient au fil du
    /// scroll — chacune captait alors l'animation ambiante du conteneur et
    /// « tombait » depuis le haut de la sheet au lieu d'être simplement là.
    private var historique: some View {
        Grid(horizontalSpacing: 20, verticalSpacing: 20) {
            ForEach(lignesHistorique, id: \.self) { ligne in
                GridRow {
                    ForEach(ligne, id: \.self) { j in
                        Button {
                            jour = j
                        } label: {
                            VStack(spacing: 6) {
                                EmpreinteGlycemiqueVue(anneaux: anneaux(pour: j), score: score(pour: j), diametre: 92)
                                    .overlay(
                                        Circle().strokeBorder(
                                            Color.accentColor,
                                            lineWidth: calendrierFrancais.isDate(j, inSameDayAs: jour) ? 2 : 0
                                        )
                                    )
                                Text(libelleCourt(j))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 28)
    }

    /// `joursHistorique` regroupé par lignes de 3 pour `Grid`/`GridRow`.
    private var lignesHistorique: [[Date]] {
        stride(from: 0, to: joursHistorique.count, by: 3).map { debut in
            Array(joursHistorique[debut..<min(debut + 3, joursHistorique.count)])
        }
    }

    /// 21 derniers jours métaboliques (3 semaines) se terminant au jour en
    /// cours — assez de recul pour repérer un pattern en un coup d'œil sur
    /// la grille, sans remonter jusqu'à la limite des 30 jours du hub.
    private var joursHistorique: [Date] {
        let cal = Calendar.current
        return (0..<21).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: service.jourCourant)
        }
    }

    /// « Lun 12 » — plus précis que la seule initiale du jour, utile sur 21
    /// jours où plusieurs lundis se répètent dans la grille.
    private func libelleCourt(_ jour: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "E d"
        return formatter.string(from: jour).capitalizedFirst
    }

    private var navigationJour: some View {
        HStack {
            Button { changerJour(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .disabled(!peutReculer)
            .opacity(peutReculer ? 1 : 0.3)

            Spacer()

            VStack(spacing: 4) {
                Text(libelleDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(score(pour: jour).map { "\($0) / 100" } ?? "—")
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }

            Spacer()

            Button { changerJour(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .disabled(!peutAvancer)
            .opacity(peutAvancer ? 1 : 0.3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 28)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: jour)
    }

    // MARK: Données d'un jour donné (grand format + historique)

    private func score(pour jour: Date) -> Int? { service.scoreAffiche(pour: jour) }

    private func anneaux(pour jour: Date) -> [CalculEmpreinteGlycemique.Anneau] {
        CalculEmpreinteGlycemique.anneaux(
            depuis: service.echantillonsPourJour(jour),
            fenetre: service.fenetreMetabolique(pourJourCalendaire: jour)
        )
    }

    // MARK: Navigation jour par jour

    /// Fenêtre du hub (30 derniers jours) — même borne que `ScoreService`.
    private var borneBasse: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: service.jourCourant) ?? service.jourCourant
    }
    private var peutReculer: Bool { jour > borneBasse }
    private var peutAvancer: Bool { jour < service.jourCourant }

    private func changerJour(_ delta: Int) {
        guard let cible = Calendar.current.date(byAdding: .day, value: delta, to: jour) else { return }
        jour = cible
    }

    private var libelleDate: String {
        let cal = calendrierFrancais
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        let texte = formatter.string(from: jour).capitalizedFirst
        if cal.isDateInYesterday(jour) { return "Hier · \(texte)" }
        return texte
    }
}
