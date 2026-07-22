//
//  DiavizSportWidgetBundle.swift
//  DiavizSportWidget
//
//  Point d'entrée de la widget extension. Ne contient que la Live Activity
//  de séance sportive (pas de widget d'écran d'accueil). Si Xcode a généré
//  un widget statique `DiavizSportWidget()` et un `…Control`, supprime-les
//  du bundle et de la cible.
//

import SwiftUI
import WidgetKit

@main
struct DiavizSportWidgetBundle: WidgetBundle {
    var body: some Widget {
        SeanceSportiveLiveActivity()
    }
}
