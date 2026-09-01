//
//  SportDetecteCard.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Carte affichée quand une séance sportive est terminée (ou en cours) dans
/// la fenêtre d'effet réglée au profil.
///
/// Purement **factuelle** : elle dit ce qui s'est passé et quel ratio en
/// découle, jamais un chiffre de ratio — celui-ci vit dans la carte de
/// validation de la dose, seule à le confronter à la dose saisie.
///
/// Design aligné sur les autres cartes : icône en cercle bleu à gauche,
/// titre + détail à droite, fond uni à `0.10` d'opacité.
struct SportDetecteCard: View {

    let sport: SportDetecte

    @State private var afficherExplication: Bool = false

    private let couleurAccent: Color = .blue

    var body: some View {
        Button {
            afficherExplication = true
        } label: {
            HStack(alignment: .top, spacing: 14) {
                iconeCirculaire
                contenu
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .surfaceCarte(fond: couleurAccent.opacity(0.10))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $afficherExplication) {
            FeuilleDetailSport(sport: sport)
        }
    }

    private var iconeCirculaire: some View {
        ZStack {
            Circle()
                .fill(couleurAccent.opacity(0.18))
                .frame(width: 40, height: 40)
            Image(systemName: "bolt.fill")
                .font(.title3.bold())
                .foregroundStyle(couleurAccent)
        }
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(titre, systemImage: sport.icone)
                .font(.body.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Text(messageContextuel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    /// Le temps écoulé se compte depuis la **fin** de la séance : c'est de là
    /// que court l'effet sur la sensibilité, et c'est cette référence qu'utilise
    /// la fenêtre du profil.
    private var titre: String {
        sport.enCours
            ? "\(sport.typeSport) en cours"
            : "\(sport.typeSport) terminé il y a \(FormatDureeSport.libelle(minutes: sport.minutesDepuisFin))"
    }

    /// Dit d'où vient le ratio en vigueur, sans répéter son chiffre — il est
    /// affiché une seule fois, dans la carte de validation de la dose.
    /// L'ancien message (« basé sur N séances ») attribuait à un historique
    /// inexistant un ratio qui venait du profil : le décompte était figé à 0
    /// et le mining par type de sport n'existe pas encore (S1/R2).
    private var messageContextuel: String {
        sport.ratioAjuste != nil
            ? "Votre ratio post-\(sport.typeSport.lowercased()) est appliqué à la dose de ce repas."
            : "Aucun ratio post-\(sport.typeSport.lowercased()) configuré : le ratio du moment reste appliqué."
    }
}

// MARK: - Format partagé

/// Durées en minutes rendues en « 45min » / « 2h » / « 1h20 » — partagé par la
/// carte et sa sheet pour que le même délai ne s'écrive pas de deux façons.
enum FormatDureeSport {
    static func libelle(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)min" }
        let h = minutes / 60
        let r = minutes % 60
        return r == 0 ? "\(h)h" : "\(h)h\(r)"
    }
}

// MARK: - Sheet de détail

/// Détail de la séance et de son effet sur le ratio.
///
/// L'ancienne version n'affichait que le type et un délai, plus un décompte de
/// séances toujours nul et une phrase promettant une analyse d'historique qui
/// n'existe pas. Elle montre désormais les faits réellement disponibles dans
/// le hub — horaires, durée, intensité — et ce qui en découle concrètement :
/// quel ratio s'applique, d'où il vient, et pendant combien de temps encore.
private struct FeuilleDetailSport: View {
    let sport: SportDetecte
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Séance") {
                    // `LabeledContent(_:value:)` et non une content view
                    // portant un `Label` : cette forme réservait une hauteur
                    // de ligne démesurée dans le `Form` (gros bloc vide sous
                    // la première row). L'icône vit dans le libellé de gauche,
                    // où elle ne perturbe pas la mesure de la row.
                    LabeledContent {
                        Text(sport.typeSport)
                    } label: {
                        Label("Type", systemImage: sport.icone)
                    }
                    LabeledContent("Intensité", value: sport.intensite)
                    LabeledContent("Durée", value: FormatDureeSport.libelle(minutes: sport.dureeMinutes))
                    LabeledContent("Horaires", value: horaires)
                    LabeledContent(
                        sport.enCours ? "État" : "Terminée",
                        value: sport.enCours
                            ? "En cours"
                            : "il y a \(FormatDureeSport.libelle(minutes: sport.minutesDepuisFin))"
                    )
                }

                if let ratio = sport.ratioAjuste {
                    Section("Ratio appliqué à ce repas") {
                        LabeledContent("Ratio", value: ratio.description)
                        if let restant = sport.minutesRestantesEffet {
                            LabeledContent(
                                "Encore actif",
                                value: restant > 0 ? FormatDureeSport.libelle(minutes: restant) : "expire maintenant"
                            )
                        }
                        Text("Ratio saisi dans votre profil, section Ratios sport. Il remplace celui du moment de la journée tant que la fenêtre d'effet court.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Ratio appliqué à ce repas") {
                        Text("Aucun ratio post-\(sport.typeSport.lowercased()) configuré : c'est le ratio du moment de la journée qui s'applique.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Le sport peut modifier la sensibilité à l'insuline pendant plusieurs heures. Le ratio appliqué ici est celui que vous avez renseigné pour ce type d'activité — Diaviz ne le déduit pas de votre historique de séances.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Activité récente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private var horaires: String {
        let debut = sport.debut.formatted(date: .omitted, time: .shortened)
        let fin = sport.fin.formatted(date: .omitted, time: .shortened)
        return "\(debut) → \(fin)"
    }
}

#if DEBUG
private func _sport(
    ratio: ProfilRatio? = ProfilRatio(grammesParUnite: 14, libelle: "post-yoga"),
    minutesDepuisFin: Int = 45,
    enCours: Bool = false,
    restant: Int? = 135
) -> SportDetecte {
    let fin = Date().addingTimeInterval(-Double(minutesDepuisFin) * 60)
    return SportDetecte(
        typeSport: "Yoga", icone: "figure.yoga", intensite: "Modérée", dureeMinutes: 75,
        debut: fin.addingTimeInterval(-75 * 60), fin: fin,
        minutesDepuisFin: minutesDepuisFin, enCours: enCours,
        ratioAjuste: ratio, minutesRestantesEffet: ratio == nil ? nil : restant
    )
}

#Preview("Cartes") {
    VStack(spacing: 12) {
        SportDetecteCard(sport: _sport())
        SportDetecteCard(sport: _sport(ratio: nil))
        SportDetecteCard(sport: _sport(minutesDepuisFin: 0, enCours: true, restant: 180))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Sheet — ratio configuré") {
    FeuilleDetailSport(sport: _sport())
}

#Preview("Sheet — sans ratio") {
    FeuilleDetailSport(sport: _sport(ratio: nil))
}
#endif
