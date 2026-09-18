//
//  EmpreinteGlycemiqueVue.swift
//  diaviz
//
//  Created by Alexandre on 18/09/2026.
//

import SwiftUI

/// Cercles parfaitement concentriques — un par tranche de temps
/// (`CalculEmpreinteGlycemique.Anneau`). Toujours ronds, jamais déformés :
/// seul le motif de tirets change d'un anneau à l'autre (fragmenté = tranche
/// agitée, quasi continu = tranche stable), ainsi que sa rotation de départ
/// (déterministe). Encre unique — la teinte du score, comme un tampon gravé.
///
/// Ouverte depuis `CercleScoreDetail` (tap → sheet, cf. `EmpreinteGlycemiqueSheet`).
/// Ne remplace rien en place — le cercle du score à l'accueil comme dans le
/// détail reste inchangé.
///
/// Jour sans CGM : anneaux neutres en pointillés réguliers, jamais vide/plat
/// (même convention que le reste du module score).
struct EmpreinteGlycemiqueVue: View {
    let anneaux: [CalculEmpreinteGlycemique.Anneau]
    let score: Int?
    let diametre: CGFloat
    /// `true` → les anneaux se dessinent du centre vers le bord, chacun
    /// révélé le long de sa longueur (`.trim`). `false` → rendu statique.
    var anime: Bool = false
    /// `true` → dérive continue (chaque anneau tourne lentement à sa
    /// propre vitesse) + cœur qui respire, même principe que la dérive de
    /// `MeshScore`. Réservé à l'empreinte sélectionnée en grand — jamais
    /// aux miniatures (calendrier, historique), qui doivent rester lisibles
    /// et stables au premier coup d'œil.
    var vivante: Bool = false
    /// `true` → disque légèrement surélevé (ombre portée), réservé au grand
    /// cercle sélectionné. Un vrai `.glassEffect()` sur tout le disque
    /// noyait les anneaux dans le flou du matériau ; une bordure de glass
    /// seule demanderait une shape en anneau dédiée — l'ombre donne un
    /// relief comparable sans ce coût. Sur une miniature (calendrier,
    /// grille d'historique), pas d'ombre : fond plat adaptatif.
    var plaqueElevee: Bool = false

    @State private var apparue = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rayonMin: CGFloat { diametre * 0.09 }
    private var rayonMax: CGFloat { diametre * 0.46 }

    private var couleurEncre: Color {
        guard let score else { return Color.secondary }
        return CouleurScore.couleur(pour: score)
    }

    private var vivanteActive: Bool { vivante && !reduceMotion }

    var body: some View {
        TimelineView(.animation(paused: !vivanteActive)) { contexte in
            let phase = vivanteActive ? contexte.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                plaqueVerre
                if anneaux.isEmpty {
                    contenuVide
                } else {
                    ForEach(anneaux, id: \.index) { anneau in
                        anneauVue(pour: anneau, phase: phase)
                    }
                    Circle()
                        .fill(couleurEncre)
                        .frame(width: diametre * 0.04, height: diametre * 0.04)
                        .scaleEffect(1 + (vivanteActive ? 0.1 * sin(phase * 0.7) : 0))
                }
            }
        }
        .frame(width: diametre, height: diametre)
        .onAppear {
            guard anime else { apparue = true; return }
            apparue = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleAccessibilite)
    }

    /// Fond du disque — purement décoratif, aucune donnée n'y est encodée.
    /// Les anneaux restent des traits plats par-dessus dans les deux cas :
    /// un `.glassEffect()` sur un tiret de 0.85pt le noierait dans le flou
    /// (cf. skill `liquid-glass`).
    @ViewBuilder
    private var plaqueVerre: some View {
        Circle()
            .fill(Color(.secondarySystemGroupedBackground))
            .frame(width: diametre, height: diametre)
            .shadow(
                color: .black.opacity(plaqueElevee ? 0.20 : 0),
                radius: diametre * 0.045,
                x: 0,
                y: diametre * 0.02
            )
    }

    private var contenuVide: some View {
        ForEach(0..<6, id: \.self) { i in
            let r = rayonMin + CGFloat(i) * (rayonMax - rayonMin) / 5
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .frame(width: r * 2, height: r * 2)
        }
    }

    @ViewBuilder
    private func anneauVue(pour anneau: CalculEmpreinteGlycemique.Anneau, phase: Double) -> some View {
        let rayon = rayonMin + CGFloat(anneau.index) * (rayonMax - rayonMin) / CGFloat(anneau.total - 1)
        let circonference = 2 * Double.pi * rayon
        let nbTirets = Int((2 + anneau.agitation * 8).rounded())
        let fractionPleine = 0.72 - anneau.agitation * 0.42
        let pas = circonference / Double(nbTirets * 2)
        let longueurTiret = pas * fractionPleine * 2
        let longueurEspace = pas * 2 - longueurTiret
        let opacite = 0.55 + 0.35 * Double(anneau.index) / Double(anneau.total - 1)
        let couleurAnneau = CouleurScore.couleur(pourValeurGlycemie: anneau.valeurMoyenne)
        let epaisseurTrait = max(0.6, diametre * 0.0123)

        // Dérive continue : vitesse et sens propres à chaque anneau (pair =
        // horaire, impair = antihoraire), comme des rouages — jamais la
        // même vitesse deux anneaux de suite, pour éviter l'effet "roue qui
        // tourne" en bloc.
        let vitesse = 2.0 + Double(anneau.index % 3) * 1.4
        let sens = anneau.index % 2 == 0 ? 1.0 : -1.0
        let derive = phase * vitesse * sens

        Circle()
            .trim(from: 0, to: apparue ? 1 : 0)
            .stroke(
                couleurAnneau.opacity(opacite),
                style: StrokeStyle(lineWidth: epaisseurTrait, lineCap: .round, dash: [longueurTiret, longueurEspace])
            )
            .frame(width: rayon * 2, height: rayon * 2)
            .rotationEffect(.degrees(anneau.rotationDeg + derive))
            .animation(
                anime
                    ? .easeOut(duration: 1.1).delay(Double(anneau.index) * 0.09)
                    : nil,
                value: apparue
            )
    }

    private var libelleAccessibilite: String {
        guard !anneaux.isEmpty else {
            return "Empreinte glycémique indisponible, pas assez de données"
        }
        return "Empreinte glycémique du jour, \(anneaux.count) tranches de temps"
    }
}

// MARK: - Sheet détail (grand format, navigable)

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
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: detente)
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
    private var historique: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            ForEach(joursHistorique, id: \.self) { j in
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
        .padding(.horizontal, 28)
        .transition(.opacity.combined(with: .move(edge: .top)))
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
