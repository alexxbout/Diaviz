//
//  BulleRepasEnCours.swift
//  insulog
//
//  Created by Alexandre on 27/04/2026.
//

import SwiftUI
import Combine

/// Bulle persistante ancrée en bas de l'écran résumant le repas en cours
/// de composition. Apparaît dès qu'un aliment est ajouté, disparaît
/// quand on la tape (vide le repas).
struct BulleRepasEnCours: View {
    @Binding var aliments: [EntreeAliment]

    /// Index de l'emoji actuellement affiché lors de l'alternance.
    @State private var emojiActuelIndex: Int = 0

    /// Échelle utilisée pour le bump visuel à chaque ajout d'aliment.
    @State private var echelle: CGFloat = 1.0

    /// Timer qui pilote l'alternance des emojis toutes les 1.5 secondes
    /// quand le repas contient plus d'un aliment.
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    /// Total glucides calculé réellement à partir de la quantité de chaque entrée.
    private var totalGlucides: Int {
        aliments.reduce(0) { $0 + Int($1.aliment.glucides * $1.quantiteGrammes / 100) }
    }

    /// Emoji courant à afficher selon l'index actif.
    /// Fallback sur 🍽️ si la liste est vide ou l'aliment n'a pas d'emoji.
    private var emojiCourant: String {
        guard !aliments.isEmpty else { return "🍽️" }
        let index = min(emojiActuelIndex, aliments.count - 1)
        return aliments[index].aliment.emoji ?? "🍽️"
    }

    var body: some View {
        VStack(spacing: 6) {
            poignee
            bulle
        }
        .padding(.horizontal, 16)
        // Toute la zone de la bulle (padding inclus) absorbe les touches
        // pour que le tap fonctionne aussi sur les bords externes.
        .contentShape(Rectangle())
        .onTapGesture {
            // L'animation est gérée au niveau parent via `.animation(value:)`.
            // On modifie juste l'état ici, sans wrapper avec withAnimation
            // pour ne pas propager l'animation à d'autres vues.
            aliments.removeAll()
        }
        .onReceive(timer) { _ in
            alternerEmoji()
        }
        .onChange(of: aliments.count) { ancienCount, nouveauCount in
            ajusterIndexEmoji(nouveauCount: nouveauCount)
            if nouveauCount > ancienCount {
                bumpVisuel()
            }
        }
    }

    /// Petite barre horizontale au-dessus de la bulle, indicateur visuel
    /// que la bulle pourra à terme être tirée pour s'expand en sheet.
    private var poignee: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color(.systemGray3))
            .frame(width: 36, height: 5)
    }

    /// Bulle principale avec emoji, résumé textuel et total glucides.
    private var bulle: some View {
        HStack(spacing: 16) {
            // Emoji animé — alterne entre les aliments si plusieurs.
            // L'`.id(emojiActuelIndex)` force SwiftUI à recréer la vue
            // lors du changement, déclenchant la transition .scale + .opacity.
            Text(emojiCourant)
                .font(.title2)
                .id(emojiActuelIndex)
                .transition(.scale(scale: 0.5).combined(with: .opacity))

            // Résumé textuel du repas.
            VStack(alignment: .leading, spacing: 2) {
                Text(aliments.count == 1 ? "1 aliment" : "\(aliments.count) aliments")
                    .font(.body.bold())
                Text("Repas en cours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Total glucides mis en avant à droite.
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(totalGlucides)g")
                    .font(.title2.bold())
                    .foregroundStyle(.green)
                    // Anime le changement de chiffre comme un compteur
                    // plutôt qu'un fade brutal.
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: totalGlucides)
                Text("glucides")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(in: RoundedRectangle(cornerRadius: 100, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 4)
        .scaleEffect(echelle)
    }

    /// Avance d'un cran l'index de l'emoji affiché, en boucle.
    /// Ne fait rien si le repas contient un seul aliment.
    private func alternerEmoji() {
        guard aliments.count > 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            emojiActuelIndex = (emojiActuelIndex + 1) % aliments.count
        }
    }

    /// Remet l'index dans les bornes si des aliments ont été retirés
    /// pendant que l'index pointait vers un index désormais hors limites.
    private func ajusterIndexEmoji(nouveauCount: Int) {
        if nouveauCount > 0 && emojiActuelIndex >= nouveauCount {
            emojiActuelIndex = 0
        }
    }

    /// Bump visuel rapide (scale 1.0 → 1.05 → 1.0) pour donner
    /// un retour tactile lors de l'ajout d'un nouvel aliment.
    private func bumpVisuel() {
        Task { @MainActor in
            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                echelle = 1.05
            }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
                echelle = 1.0
            }
        }
    }
}

#Preview {
    @Previewable @State var alimentsRepas: [EntreeAliment] = [
        EntreeAliment(
            aliment: AlimentCiqual(id: 1, nom: "Pomme", calories: 52, glucides: 14, sucres: 10, proteines: 0.3, lipides: 0.2, fibres: 2.4, emoji: "🍎"),
            quantiteGrammes: 150, quantiteApproximative: false, doseInsuline: nil, note: ""
        ),
        EntreeAliment(
            aliment: AlimentCiqual(id: 2, nom: "Pain complet", calories: 247, glucides: 45, sucres: 3, proteines: 9, lipides: 3, fibres: 6, emoji: "🍞"),
            quantiteGrammes: 60, quantiteApproximative: true, doseInsuline: 2.0, note: ""
        ),
    ]

    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        BulleRepasEnCours(aliments: $alimentsRepas)
    }
}
