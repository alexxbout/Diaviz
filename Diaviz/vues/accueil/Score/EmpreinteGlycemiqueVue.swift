//
//  EmpreinteGlycemiqueVue.swift
//  diaviz
//
//  Created by Alexandre on 18/09/2026.
//

import SwiftUI
import WidgetKit

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
    /// `false` → aucun disque de fond, seuls les anneaux et le point central
    /// sont dessinés (widget en mode teinté/transparent : le disque blanc
    /// masquerait le fond système). `true` partout ailleurs (app, widget en
    /// mode couleur normale).
    var plaqueVisible: Bool = true

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
                if plaqueVisible {
                    plaqueVerre
                }
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
                        .widgetAccentable(true)
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
            .widgetAccentable(true)
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
