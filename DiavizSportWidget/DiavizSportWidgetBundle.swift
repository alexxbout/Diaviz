//
//  DiavizSportWidgetBundle.swift
//  DiavizSportWidget
//
//  Point d'entrée de la widget extension. Ne contient que la Live Activity
//  de séance sportive (pas de widget d'écran d'accueil ni de Control).
//

import WidgetKit
import SwiftUI

@main
struct DiavizSportWidgetBundle: WidgetBundle {
    var body: some Widget {
        SeanceSportiveLiveActivity()
    }
}
