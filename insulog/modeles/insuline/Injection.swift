//
//  Injection.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import Foundation

/// Une injection d'insuline enregistrée. Englobe les trois flux possibles :
/// insuline lente quotidienne, correction rapide hors repas, et bolus repas
/// (saisi via la page Repas, exposé ici en lecture seule).
///
/// Le champ `repasAssocieId` permet de remonter au repas d'origine pour
/// les bolus ; `labelRepas` et `emojiRepas` sont des dénormalisations
/// pratiques pour l'affichage en liste sans avoir à rejoindre la table
/// repas. Dans la version branchée à Prisma, ces deux champs seront
/// remplacés par un join côté API.
struct Injection: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let type: TypeInsuline
    let dose: Double
    let heure: Date

    /// Site d'injection — décomposé en zone × côté pour rester compatible
    /// avec le `SiteInjectionPicker` existant et faciliter la statistique
    /// future (rotation des sites, alerte lipodystrophie).
    let zoneInjection: ZoneInjection
    let coteInjection: CoteInjection

    let note: String?

    /// Glycémie capillaire saisie manuellement — `nil` pour la lente et
    /// les bolus repas. Utile aux corrections vu le délai de 3h du CGM
    /// Dexcom UE (l'utilisateur peut renseigner sa valeur capillaire).
    let glycemieAuMoment: Double?

    /// `nil` sauf pour les bolus repas : pointe vers `Repas.id`.
    let repasAssocieId: UUID?

    /// Marque commerciale renseignée pour la lente (Lantus, Tresiba…)
    /// et éventuellement pour la rapide (NovoRapid, Humalog…).
    let nomMedicament: String?

    /// Libellé du repas associé (« Petit-déjeuner », « Déjeuner »…).
    /// Dénormalisation de confort — sera dérivée du repas joint en prod.
    let labelRepas: String?

    /// Emoji du repas associé. Idem : dénormalisation pour l'affichage.
    let emojiRepas: String?

    init(
        id: UUID = UUID(),
        type: TypeInsuline,
        dose: Double,
        heure: Date,
        zoneInjection: ZoneInjection,
        coteInjection: CoteInjection,
        note: String? = nil,
        glycemieAuMoment: Double? = nil,
        repasAssocieId: UUID? = nil,
        nomMedicament: String? = nil,
        labelRepas: String? = nil,
        emojiRepas: String? = nil
    ) {
        self.id = id
        self.type = type
        self.dose = dose
        self.heure = heure
        self.zoneInjection = zoneInjection
        self.coteInjection = coteInjection
        self.note = note
        self.glycemieAuMoment = glycemieAuMoment
        self.repasAssocieId = repasAssocieId
        self.nomMedicament = nomMedicament
        self.labelRepas = labelRepas
        self.emojiRepas = emojiRepas
    }
}

extension Injection {
    /// Site d'injection composé, formaté « Cuisse gauche ».
    var libelleSite: String {
        SiteInjection(zone: zoneInjection, cote: coteInjection).libelle
    }
}

// MARK: - Conformances rétro-ajoutées sur le modèle de site

// `ZoneInjection` et `CoteInjection` vivent dans `SiteInjectionPicker.swift`
// (ressources partagées avec la page Repas). On y ajoute Codable + Sendable
// ici sans toucher au fichier source : Codable est synthétisé pour les
// `enum: String`, et Sendable est trivialement vérifié pour ces énumérations
// sans valeurs associées.
extension ZoneInjection: Codable, Sendable {}
extension CoteInjection: Codable, Sendable {}
