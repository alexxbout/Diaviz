//
//  DiavizSportWidgetBundle.swift
//  DiavizSportWidget
//
//  Point d'entrée de la widget extension : Live Activity de séance sportive
//  + widget écran d'accueil "empreinte glycémique du jour". Pas de Control.
//

import WidgetKit
import SwiftUI

@main
struct DiavizSportWidgetBundle: WidgetBundle {
    var body: some Widget {
        SeanceSportiveLiveActivity()
        EmpreinteGlycemiqueWidget()
    }
}
