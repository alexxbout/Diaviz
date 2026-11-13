//
//  PageAvecBandeau.swift
//  diaviz
//

import SwiftUI

/// État partagé entre une page et son bandeau d'en-tête plein écran.
///
/// La page mesure la hauteur occupée par la barre d'état et la barre de
/// navigation (`margeHaute`) : le bandeau s'en sert pour remonter dessous
/// sans que son texte y passe. Le bandeau, lui, dit en retour s'il a
/// disparu sous la barre (`replie`), pour que la barre affiche le titre.
@Observable
final class EtatBandeau {
    var margeHaute: CGFloat = 0
    var replie = false
    /// Bord inférieur du bandeau, depuis le haut de l'écran. Sert aux
    /// contrôles posés sur le bandeau qui restent ensuite sous la barre.
    var basBandeau: CGFloat = 0
    /// Marges de la page que le bandeau annule pour aller bord à bord.
    let debordHorizontal: CGFloat
    let debordHaut: CGFloat

    init(debordHorizontal: CGFloat, debordHaut: CGFloat) {
        self.debordHorizontal = debordHorizontal
        self.debordHaut = debordHaut
    }
}

private struct PageAvecBandeau: ViewModifier {

    let titre: String
    @State private var etat: EtatBandeau

    init(titre: String, debordHorizontal: CGFloat, debordHaut: CGFloat) {
        self.titre = titre
        _etat = State(initialValue: EtatBandeau(debordHorizontal: debordHorizontal, debordHaut: debordHaut))
    }

    func body(content: Content) -> some View {
        content
            .environment(etat)
            // Le défilement commence sous la barre d'état : c'est le bandeau
            // qui réserve lui-même cette hauteur (`margeHaute`).
            .ignoresSafeArea(.container, edges: .top)
            // Le flou de bord d'iOS 26 voilait le haut du bandeau d'une bande
            // blanche : il ne revient qu'une fois le bandeau passé dessous,
            // quand du contenu défile réellement sous la barre.
            .scrollEdgeEffectHidden(!etat.replie, for: .top)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.safeAreaInsets.top, initial: true) { _, marge in
                            etat.margeHaute = marge
                        }
                }
            }
            .navigationTitle(titre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Le grand titre vit dans le bandeau ; la barre ne le reprend
                // qu'une fois le bandeau passé dessous.
                ToolbarItem(placement: .principal) {
                    Text(titre)
                        .font(.headline)
                        .opacity(etat.replie ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: etat.replie)
                }
            }
            // Heure, batterie et boutons en blanc tant qu'ils sont posés sur
            // le dégradé.
            .toolbarColorScheme(etat.replie ? nil : .dark, for: .navigationBar)
    }
}

extension View {

    /// Page dont l'`EnTeteAnalyse` devient un bandeau bord à bord, sous la
    /// barre d'état. À poser sur le `ScrollView` vertical de la page, avec
    /// les marges que son contenu applique (le bandeau les annule).
    func pageAvecBandeau(titre: String, debordHorizontal: CGFloat = 16, debordHaut: CGFloat = 16) -> some View {
        modifier(PageAvecBandeau(titre: titre, debordHorizontal: debordHorizontal, debordHaut: debordHaut))
    }
}
