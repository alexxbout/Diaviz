//
//  BulleRepasEnCours.swift
//  insulog
//
//  Created by Alexandre on 27/04/2026.
//

import SwiftUI
import Combine

/// Rendu compact du repas en cours, présenté en `.overlay(alignment: .bottom)`
/// au-dessus de `AjouterRepasVue` tant qu'au moins un aliment est ajouté.
///
/// Capsule en Liquid Glass avec ombre douce — donne à la bulle son identité
/// visuelle distincte. Conserve l'animation d'alternance d'emojis quand le
/// repas contient plusieurs aliments, et l'animation "bump" du compteur de
/// glucides à chaque ajout.
///
/// Deux interactions possibles déclenchent `onOuvrir` (le parent présente
/// alors la `RepasSheet` plein écran) :
/// - **Tap** simple sur la capsule
/// - **Drag** vers le haut (>30pt) — geste plus naturel, façon "place card"
struct BulleRepasEnCours: View {
    @Binding var aliments: [EntreeAliment]

    /// Action déclenchée au tap ou au drag-up. Le parent présente la sheet.
    let onOuvrir: () -> Void

    /// Index de l'emoji actuellement affiché lors de l'alternance.
    @State private var emojiActuelIndex: Int = 0

    /// Timer qui pilote l'alternance des emojis toutes les 1.5 secondes
    /// quand le repas contient plus d'un aliment.
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    /// Init explicite pour éviter que l'init memberwise synthétisé n'inclue
    /// `timer` (let + valeur par défaut) dans sa signature, ce qui casserait
    /// la résolution de la trailing closure pour `onOuvrir`.
    init(aliments: Binding<[EntreeAliment]>, onOuvrir: @escaping () -> Void) {
        self._aliments = aliments
        self.onOuvrir = onOuvrir
    }

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
        contenuBulle
            // Tap simple — ouvre la sheet.
            .onTapGesture(perform: onOuvrir)
            // Drag vers le haut — ouvre aussi la sheet quand le geste
            // dépasse 30pt vers le haut. Cohabite avec le tap car
            // SwiftUI route les taps simples vers `onTapGesture` et
            // les mouvements significatifs vers la `DragGesture`.
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        if value.translation.height < -30 {
                            onOuvrir()
                        }
                    }
            )
            .onReceive(timer) { _ in
                alternerEmoji()
            }
            .onChange(of: aliments.count) { _, nouveauCount in
                ajusterIndexEmoji(nouveauCount: nouveauCount)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Repas en cours, \(aliments.count) aliments, \(totalGlucides) grammes de glucides")
            .accessibilityHint("Touchez deux fois ou faites glisser vers le haut pour ouvrir le détail du repas")
    }

    /// Contenu visuel de la bulle (emoji + résumé + glucides).
    /// Capsule en Liquid Glass avec ombre douce. Le padding horizontal
    /// externe évite que la capsule touche les bords de l'écran.
    private var contenuBulle: some View {
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
                    .foregroundStyle(.primary)
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
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: totalGlucides)
                Text("glucides")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(in: RoundedRectangle(cornerRadius: 100, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 4)
        // Padding externe pour que la capsule ne touche pas les bords
        // de la sheet et conserve son identité visuelle.
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
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
        BulleRepasEnCours(aliments: $alimentsRepas) {
            print("Bulle ouverte")
        }
    }
}
