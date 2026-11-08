//
//  PileToasts.swift
//  diaviz
//

import SwiftUI

/// Pile de pilules Liquid Glass posée en haut de l'écran, qui confirme les
/// enregistrements (repas, insuline, sport, resucrage) puis s'efface seule.
///
/// **Sous la Dynamic Island, jamais dedans** : cette zone appartient au
/// système, une app n'y accède que par une Live Activity (ActivityKit) — un
/// objet persistant, à démarrer et arrêter explicitement, qui apparaît aussi
/// sur l'écran verrouillé. Pour un accusé de réception de deux secondes, ce
/// serait le mauvais outil. La pile se pose donc juste sous la zone système,
/// dans la safe area.
///
/// Glass et non `surfaceCarte` : c'est une couche de chrome qui flotte
/// au-dessus du contenu, exactement l'usage pour lequel le matériau existe.
/// Un seul `GlassEffectContainer` réunit les pilules — plusieurs
/// `.glassEffect()` indépendants ne se mélangent pas et coûtent plus cher.
struct PileToasts: View {

    @Environment(ToastsService.self) private var service
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Réduction appliquée à chaque rang derrière le premier.
    private static let reductionParRang: CGFloat = 0.06
    /// Décalage vertical entre deux rangs — la pile reste visible en
    /// « épaisseur » sans qu'aucune pilule ne se lise en entier.
    private static let decalageParRang: CGFloat = 9

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ZStack(alignment: .top) {
                ForEach(Array(service.toasts.enumerated()), id: \.element.id) { rang, toast in
                    // Seule la pilule de tête porte son texte : les suivantes
                    // ne gardent que leur capsule. Deux libellés visibles en
                    // même temps se lisaient l'un par-dessus l'autre et
                    // rendaient le plus récent — celui qui compte —
                    // illisible. La pile garde son épaisseur, pas son bruit.
                    PilluleToast(toast: toast, contenuMasque: rang > 0)
                        .scaleEffect(1 - Self.reductionParRang * CGFloat(rang), anchor: .top)
                        .offset(y: Self.decalageParRang * CGFloat(rang))
                        .opacity(rang == 0 ? 1 : 0.55)
                        // Le plus récent devant : il porte l'information
                        // qu'on vient de produire.
                        .zIndex(Double(service.toasts.count - rang))
                        // Une pilule porteuse d'une action ne se referme pas
                        // au tap : le geste viserait « Annuler » et détruirait
                        // au passage la seule occasion de l'utiliser.
                        .onTapGesture { if toast.action == nil { service.retirer(toast.id) } }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.top, 8)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82),
            value: service.toasts
        )
        // Laisse passer les gestes vers le contenu : seule la pilule elle-même
        // est tappable (`onTapGesture`), pas la bande transparente autour.
        .allowsHitTesting(!service.toasts.isEmpty)
    }
}

// MARK: - Pilule

private struct PilluleToast: View {

    @Environment(ToastsService.self) private var service

    let toast: ToastEvenement
    /// Pilule d'arrière-plan : la capsule de verre reste, son contenu
    /// s'efface. `.opacity(0)` et non une vue absente — la capsule garde
    /// ainsi exactement la taille qu'elle aurait avec son texte, donc la pile
    /// ne se déforme pas quand la pilule de tête disparaît.
    var contenuMasque: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.categorie.icone)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(teinte)
                .frame(width: 26, height: 26)
                .background(teinte.opacity(0.18), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(toast.titre)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detail = toast.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .lineLimit(1)

            if let action = toast.action {
                Button(action.libelle) {
                    action.executer()
                    service.retirer(toast.id)
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(teinte)
                .padding(.leading, 4)
            }
        }
        .opacity(contenuMasque ? 0 : 1)
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        // Teinte seulement pour un ajout ou une suppression, verre nu sinon.
        .glassEffect(.regular.tint(estNeutre ? nil : teinte.opacity(0.12)), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([toast.titre, toast.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isStaticText)
        // Les capsules d'arrière-plan sont décoratives : VoiceOver ne doit
        // annoncer que l'événement lisible.
        .accessibilityHidden(contenuMasque)
    }

    /// La couleur dit la nature de l'action, jamais le domaine : vert pour un
    /// ajout, rouge pour une suppression, neutre pour le reste.
    private var teinte: Color {
        switch toast.categorie {
        case .repas, .insuline, .sport, .resucrage: .green
        // Rouge pour une suppression : ce n'est pas une alerte mais un fait
        // irréversible, et c'est la couleur que porte déjà l'action qui l'a
        // produite (bouton « Supprimer », swipe destructif).
        case .suppression: .red
        case .reglage, .donnees, .modification: .primary
        }
    }

    private var estNeutre: Bool {
        switch toast.categorie {
        case .reglage, .donnees, .modification: true
        default: false
        }
    }
}

// MARK: - Aperçus

#if DEBUG
private func _toasts() -> [ToastEvenement] {
    [
        ToastEvenement(categorie: .repas, titre: "Repas enregistré", detail: "62 g · 6u"),
        ToastEvenement(categorie: .insuline, titre: "Insuline lente enregistrée", detail: "22u"),
        ToastEvenement(categorie: .sport, titre: "Séance enregistrée", detail: "Musculation · 1h05"),
    ]
}

private func _toastSuppression() -> ToastEvenement {
    ToastEvenement(
        categorie: .suppression, titre: "Repas supprimé", detail: "62 g · 6u",
        action: ActionToast(libelle: "Annuler", executer: {})
    )
}

#Preview("Pile de trois") {
    ZStack(alignment: .top) {
        LinearGradient(colors: [.indigo, .pink], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        PileToasts()
    }
    .environment(ToastsService.apercu(_toasts()))
}

#Preview("Suppression annulable") {
    ZStack(alignment: .top) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        PileToasts()
    }
    .environment(ToastsService.apercu([_toastSuppression()]))
}

#Preview("Une seule") {
    ZStack(alignment: .top) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        PileToasts()
    }
    .environment(ToastsService.apercu([_toasts()[0]]))
}

#Preview("Texte agrandi") {
    ZStack(alignment: .top) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        PileToasts()
    }
    .environment(ToastsService.apercu(_toasts()))
    .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
