//
//  DatesChangementRatio.swift
//  diaviz
//

import Foundation

/// Date du dernier changement de valeur pour chaque ratio glucides/insuline,
/// par moment de la journée — même structure que `RatiosParMoment`. `nil` =
/// jamais modifié depuis la première configuration.
///
/// Sert à borner le mining R1 (`AnalyseRatioService`) : un repas antérieur à
/// ce changement n'est plus comparé au ratio actuel, pour ne pas mélanger
/// deux régimes différents dans la même analyse. Stampée uniquement sur une
/// vraie transition valeur → valeur différente (jamais sur la configuration
/// initiale, `nil → valeur`) — voir `SectionRatios`.
nonisolated struct DatesChangementRatio: Codable, Equatable, Sendable {
    var unique: Date?
    var petitDejeuner: Date?
    var dejeuner: Date?
    var gouter: Date?
    var diner: Date?
}
