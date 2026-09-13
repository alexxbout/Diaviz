//
//  VueGrilleAliments.swift
//  diaviz
//

import SwiftUI

/// Bascule liste/grille disponible partout où une **recherche** d'aliments
/// s'affiche (résultats, aliments récents, mes aliments). Persistée par
/// appareil (`@AppStorage`) : préférence d'affichage, pas une donnée saisie
/// par l'utilisateur — n'a pas sa place dans le hub SwiftData.
///
/// Volontairement absente des rows d'un repas en cours ou déjà enregistré
/// (`LigneAlimentEnCours`, `CarteAlimentEnregistre`) : ces rows portent une
/// dose et une quantité éditables que le carré n'a pas la place d'afficher.
enum ModeAffichageRecherche: String {
    case liste
    case grille
}

/// Grille 3 colonnes des résultats d'une recherche d'aliments — équivalent
/// visuel de `LigneResultatRecherche`/`List`, pour l'onglet grille.
///
/// Chaque case : vignette carrée (`VignetteAliment`, agrandie), nom sur deux
/// lignes maximum, puis glucides/100g ou « non renseignés » en rouge — même
/// contenu que la row, réarrangé en colonne plutôt qu'en ligne.
struct VueGrilleAliments: View {
    let aliments: [ResultatRechercheAliment]
    let onSelection: (ResultatRechercheAliment) -> Void
    /// `nil` : pas de swipe/masquage possible (produits OFF, aliments récents
    /// non-CIQUAL) — même règle que `ligneAvecMasquage` en vue liste.
    var onMasquer: ((AlimentCiqual) -> Void)? = nil

    private let colonnes = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: colonnes, spacing: 12) {
                ForEach(aliments) { aliment in
                    CarteAlimentGrille(aliment: aliment)
                        .onTapGesture { onSelection(aliment) }
                        .contextMenu {
                            if case .ciqual(let a) = aliment, let onMasquer {
                                Button(role: .destructive) {
                                    onMasquer(a)
                                } label: {
                                    Label("Masquer", systemImage: "eye.slash")
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

/// Une case de la grille — vignette + nom + glucides, fond de carte standard.
private struct CarteAlimentGrille: View {
    let aliment: ResultatRechercheAliment

    var body: some View {
        VStack(spacing: 6) {
            // Vignette dimensionnée à la largeur réelle de la case (pas une
            // taille fixe) : une taille fixe laissait un reliquat de largeur
            // dans les colonnes plus larges, poussant la vignette centrée à
            // paraître davantage retirée des bords latéraux que du bord haut.
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    VignetteAliment(aliment: aliment, taille: geo.size.width, coinArrondi: 12, echelleEmoji: 0.5)
                    if AlimentsRecentsService.shared.estRecent(aliment) {
                        Text("Récent")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(6)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            // Hauteur fixe (2 lignes) même pour un nom court : sinon les
            // cartes d'une même rangée n'ont pas toutes la même hauteur.
            Text(aliment.nom)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28, alignment: .top)

            if aliment.glucidesRenseignes {
                Text("\(Int(aliment.glucides))g/100g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Non renseignés")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .surfaceCarte()
    }
}

#if DEBUG
#Preview {
    let pomme = AlimentCiqual(id: 1, nom: "Pomme, pulpe et peau, crue", calories: 52, glucides: 12.6, sucres: 10.4, proteines: 0.3, lipides: 0.2, fibres: 2.4, emoji: "🍎")
    let nutella = AlimentOFF(code: "3017620422003", nom: "Nutella", marque: "Ferrero", calories: 539, glucides: 57.5, sucres: 56.3, proteines: 6.3, lipides: 30.9, fibres: nil, imagePetiteURL: nil, imageURL: nil)
    let mystere = AlimentOFF(code: "123", nom: "Produit sans nutriments trouvé sur OFF", marque: nil, calories: nil, glucides: nil, sucres: nil, proteines: nil, lipides: nil, fibres: nil, imagePetiteURL: nil, imageURL: nil)

    VueGrilleAliments(
        aliments: [.ciqual(pomme), .off(nutella), .off(mystere)],
        onSelection: { _ in }
    )
    .background(Color(.systemGroupedBackground))
}
#endif
